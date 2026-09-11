defmodule Keepling.Adapters.Postgres.Export do
  @moduledoc """
  PostgreSQL implementation of `Keepling.Application.Ops.Port` for the
  `export` verb (06-04-PLAN.md Task 3).

  `execute/3` runs the ENTIRE export -- every entity read plus the bundle
  write -- inside one `Repo.transaction` at `REPEATABLE READ` isolation, so
  the whole bundle is one coherent snapshot rather than a smear across
  concurrent writes. Every entity is streamed with `Ecto.Adapters.SQL.
  stream/4` and an explicit `:max_rows` chunk size, bounding memory
  regardless of account size (T-06-04-05). This is new machinery: no other
  call site in `apps/server/lib` uses `SQL.stream/4`, so it carries its own
  test coverage rather than inheriting proof from a sibling.

  Every entity query is explicitly scoped by `account_id` and explicitly
  ordered (ascending by stable opaque id, or by feed sequence), even though
  the product is single-account today -- so two exports of an unchanged
  account are byte-identical, and so scoping is never accidentally implicit.
  """

  @behaviour Keepling.Application.Ops.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.SecurityAudit
  alias Keepling.Adapters.Postgres.OpsStore
  alias Keepling.Application.Export
  alias Keepling.Repo

  @impl true
  def inspect(options), do: OpsStore.inspect(options)

  @impl true
  def execute("export", input, options) when is_map(input) do
    destination_dir = Map.get(input, "destination_dir") || System.tmp_dir!()
    timeout = export_query_timeout()
    max_rows = export_max_rows()
    now = Map.get(options, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

    Repo.transaction(
      fn ->
        SQL.query!(Repo, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [])

        with {:ok, account_id} <- resolve_account_id(),
             sequence <- feed_high_water_sequence(account_id),
             epoch <- current_restore_epoch(),
             entity_streams <- entity_streams(account_id, max_rows, timeout),
             {:ok, result} <-
               Export.write_bundle(account_id, destination_dir, entity_streams, %{
                 "feed_high_water_sequence" => sequence,
                 "restore_epoch" => epoch
               }) do
          SecurityAudit.record_required!(Repo, "export_performed", now)
          result
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :database_unavailable}
  end

  def execute(_operation, _input, _options), do: {:error, :operation_adapter_unavailable}

  defp resolve_account_id do
    case SQL.query!(Repo, "SELECT id FROM accounts WHERE singleton_key = TRUE", []).rows do
      [[raw_id]] -> {:ok, Ecto.UUID.load!(raw_id)}
      [] -> {:error, :account_not_found}
    end
  end

  defp feed_high_water_sequence(account_id) do
    case SQL.query!(
           Repo,
           "SELECT high_sequence FROM sync_accounts WHERE account_id = $1",
           [Ecto.UUID.dump!(account_id)]
         ).rows do
      [[sequence]] -> sequence
      [] -> 0
    end
  end

  defp current_restore_epoch do
    case SQL.query!(
           Repo,
           "SELECT epoch FROM sync_epochs WHERE singleton_key = TRUE AND finalized = TRUE",
           []
         ).rows do
      [[epoch]] -> Ecto.UUID.load!(epoch)
      [] -> nil
    end
  end

  defp entity_streams(account_id, max_rows, timeout) do
    dumped = Ecto.UUID.dump!(account_id)
    opts = stream_opts(max_rows, timeout)

    %{
      "task" => task_stream(dumped, opts),
      "project" => organization_stream(dumped, "project", opts),
      "tag" => organization_stream(dumped, "tag", opts),
      "task-activity" => task_activity_stream(dumped, opts),
      "conflict" => conflict_stream(dumped, opts),
      "today-order" => today_order_stream(dumped, opts),
      "account-settings" => account_settings_stream(dumped, opts),
      "access-inventory" => access_inventory_stream(dumped, opts)
    }
  end

  defp stream_opts(max_rows, :infinity), do: [max_rows: max_rows]
  defp stream_opts(max_rows, timeout), do: [max_rows: max_rows, timeout: timeout]

  # `Ecto.Adapters.SQL.stream/4` yields one %Postgrex.Result{} PER CHUNK
  # (up to :max_rows rows each), never one element per row -- flatten here
  # so every entity helper below maps over individual row lists.
  defp stream_rows(sql, params, opts) do
    SQL.stream(Repo, sql, params, opts)
    |> Stream.flat_map(fn %Postgrex.Result{rows: rows} -> rows end)
  end

  defp task_stream(account_id, opts) do
    sql = """
    SELECT
      t.id, t.title, t.notes, t.inbox_state, t.project_id, t.planned_on,
      t.deadline_on, t.completed_at, t.trashed_at, t.captured_at, t.revision,
      COALESCE(
        (SELECT array_agg(tg.tag_id ORDER BY tg.tag_id)
         FROM task_tags tg
         WHERE tg.account_id = t.account_id AND tg.task_id = t.id),
        ARRAY[]::uuid[]
      ) AS tag_ids
    FROM tasks t
    WHERE t.account_id = $1
    ORDER BY t.id
    """

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [
                       id,
                       title,
                       notes,
                       inbox_state,
                       project_id,
                       planned_on,
                       deadline_on,
                       completed_at,
                       trashed_at,
                       captured_at,
                       revision,
                       tag_ids
                     ] ->
      %{
        "id" => load_uuid(id),
        "title" => title,
        "notes" => notes,
        "inbox_state" => inbox_state,
        "project_id" => optional_uuid(project_id),
        "planned_on" => civil_date(planned_on),
        "deadline_on" => civil_date(deadline_on),
        "completed_at" => instant(completed_at),
        "trashed_at" => instant(trashed_at),
        "captured_at" => instant(captured_at),
        "revision" => revision,
        "tag_ids" => Enum.map(tag_ids || [], &load_uuid/1)
      }
    end)
  end

  defp organization_stream(account_id, kind, opts) do
    sql = """
    SELECT id, display_name, archived_at
    FROM organizations
    WHERE account_id = $1 AND kind = $2
    ORDER BY id
    """

    stream_rows(sql, [account_id, kind], opts)
    |> Stream.map(fn [id, display_name, archived_at] ->
      %{
        "id" => load_uuid(id),
        "kind" => kind,
        "display_name" => display_name,
        "archived_at" => instant(archived_at)
      }
    end)
  end

  defp task_activity_stream(account_id, opts) do
    sql = """
    SELECT
      id, task_id, activity_type, activity_version, actor_type, client_kind,
      from_revision, to_revision, changed_fields, accepted_at
    FROM task_activities
    WHERE account_id = $1
    ORDER BY id
    """

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [
                       id,
                       task_id,
                       activity_type,
                       activity_version,
                       actor_type,
                       client_kind,
                       from_revision,
                       to_revision,
                       changed_fields,
                       accepted_at
                     ] ->
      %{
        "id" => id,
        "task_id" => load_uuid(task_id),
        "activity_type" => activity_type,
        "activity_version" => activity_version,
        "actor_type" => actor_type,
        "client_kind" => client_kind,
        "from_revision" => from_revision,
        "to_revision" => to_revision,
        "changed_fields" => changed_fields,
        "accepted_at" => instant(accepted_at)
      }
    end)
  end

  defp conflict_stream(account_id, opts) do
    sql = """
    SELECT
      id, task_id, original_mutation_id, command_type, expected_revision,
      latest_revision, affected_fields, base_values, requested_values,
      current_values, inserted_at
    FROM persisted_conflicts
    WHERE account_id = $1 AND resolved_at IS NULL
    ORDER BY id
    """

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [
                       id,
                       task_id,
                       original_mutation_id,
                       command_type,
                       expected_revision,
                       latest_revision,
                       affected_fields,
                       base_values,
                       requested_values,
                       current_values,
                       inserted_at
                     ] ->
      %{
        "id" => load_uuid(id),
        "task_id" => load_uuid(task_id),
        "original_mutation_id" => load_uuid(original_mutation_id),
        "command_type" => command_type,
        "expected_revision" => expected_revision,
        "latest_revision" => latest_revision,
        "affected_fields" => affected_fields,
        "base_values" => base_values,
        "requested_values" => requested_values,
        "current_values" => current_values,
        "inserted_at" => instant(inserted_at)
      }
    end)
  end

  defp today_order_stream(account_id, opts) do
    sql = """
    SELECT task_id, section, position
    FROM today_task_order
    WHERE account_id = $1
    ORDER BY section, position
    """

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [task_id, section, position] ->
      %{"task_id" => load_uuid(task_id), "section" => section, "position" => position}
    end)
  end

  defp account_settings_stream(account_id, opts) do
    sql = "SELECT timezone FROM accounts WHERE id = $1"

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [timezone] -> %{"timezone" => timezone} end)
  end

  defp access_inventory_stream(account_id, opts) do
    sql = """
    SELECT kind, id, client_kind, label, scope, inserted_at, revoked_at
    FROM (
      SELECT
        'device_grant' AS kind, id::text AS id, client_kind, label, scope,
        inserted_at, revoked_at
      FROM device_grants
      WHERE account_id = $1
      UNION ALL
      SELECT
        'mcp_registration' AS kind, client_id AS id, 'mcp' AS client_kind,
        client_name AS label, ARRAY[]::text[] AS scope, created_at AS inserted_at,
        revoked_at
      FROM mcp_client_registrations
      WHERE account_id = $1
    ) inventory
    ORDER BY kind, id
    """

    stream_rows(sql, [account_id], opts)
    |> Stream.map(fn [kind, id, client_kind, label, scope, inserted_at, revoked_at] ->
      %{
        "kind" => kind,
        "id" => id,
        "client_kind" => client_kind,
        "label" => label,
        "scope" => scope || [],
        "inserted_at" => instant(inserted_at),
        "revoked_at" => instant(revoked_at)
      }
    end)
  end

  defp load_uuid(nil), do: nil
  defp load_uuid(raw), do: Ecto.UUID.load!(raw)

  defp optional_uuid(nil), do: nil
  defp optional_uuid(raw), do: load_uuid(raw)

  defp civil_date(nil), do: nil
  defp civil_date(%Date{} = date), do: Date.to_iso8601(date)

  defp instant(nil), do: nil
  defp instant(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp instant(%NaiveDateTime{} = value) do
    value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp export_query_timeout do
    case Application.fetch_env!(:keepling, :export_query_timeout_ms) do
      :infinity ->
        :infinity

      ms when is_integer(ms) and ms > 0 ->
        ms

      other ->
        raise ArgumentError,
              "export query timeout must be :infinity or a positive integer, got: #{Kernel.inspect(other)}"
    end
  end

  defp export_max_rows do
    case Application.fetch_env!(:keepling, :export_max_rows) do
      rows when is_integer(rows) and rows > 0 ->
        rows

      other ->
        raise ArgumentError,
              "export max_rows must be a positive integer, got: #{Kernel.inspect(other)}"
    end
  end
end
