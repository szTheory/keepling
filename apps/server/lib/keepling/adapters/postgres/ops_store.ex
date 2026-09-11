defmodule Keepling.Adapters.Postgres.OpsStore do
  @moduledoc """
  PostgreSQL adapter for privacy-bounded operational inspection and restore proof.

  Only SHA-256 backup digests and closed proof metadata are persisted. Raw
  backup, host, account, task, credential, or provider identifiers are never
  returned through the inward operational contract.
  """

  @behaviour Keepling.Application.Ops.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @maximum_timeout_ms 5_000
  @rpo_seconds 300

  @impl true
  def inspect(options) do
    timeout = option(options, :timeout_ms, 1_000)
    now = option(options, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

    if not (is_integer(timeout) and timeout >= 1 and timeout <= @maximum_timeout_ms) do
      {:error, :invalid_timeout}
    else
      do_inspect(timeout, now)
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :database_unavailable}
  end

  # "export" is the one non-destructive verb this store already has a real,
  # transactionally-coherent port for (Keepling.Adapters.Postgres.Export,
  # 06-04-PLAN.md Task 3). Delegating here closes the `mix keepling.ops
  # export --destination-dir <dir>` CLI path without changing this store's
  # pre-existing, disclosed no-op behavior for backup/restore/deploy/
  # upgrade/replace-host, none of which this plan is scoped to wire.
  @impl true
  def execute("export", input, options), do: Keepling.Adapters.Postgres.Export.execute("export", input, options)
  def execute(_operation, _input, _options), do: {:error, :operation_adapter_unavailable}

  @spec record_restore_verification(map()) ::
          :ok | {:error, :invalid_restore_proof | :database_unavailable}
  def record_restore_verification(proof) when is_map(proof) do
    with :ok <- validate_proof(proof),
         {:ok, _result} <-
           SQL.query(
             Repo,
             """
             INSERT INTO restore_verifications (
               source_backup_digest, target_recovery_point, verifier_version,
               started_at, finished_at, result_code, inserted_at
             )
             VALUES ($1, $2, $3, $4, $5, $6, $5)
             """,
             [
               proof.source_backup_digest,
               proof.target_recovery_point,
               proof.verifier_version,
               proof.started_at,
               proof.finished_at,
               proof.result_code
             ]
           ) do
      :ok
    else
      {:error, :invalid_restore_proof} = error -> error
      {:error, _reason} -> {:error, :database_unavailable}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :database_unavailable}
  end

  def record_restore_verification(_proof), do: {:error, :invalid_restore_proof}

  defp do_inspect(timeout, now) do
    case SQL.query(Repo, inspection_sql(), [], timeout: timeout) do
      {:ok,
       %{
         rows: [
           [
             epoch_finalized,
             traffic_allowed,
             backup_at,
             wal_at,
             restore_at,
             restore_code,
             verifier_version
           ]
         ]
       }} ->
        compatibility = Application.fetch_env!(:keepling, :compatibility)
        migrations = migration_status()

        {:ok,
         %{
           "backup" => freshness("age_seconds", backup_at, now),
           "database" => "available",
           "last_restore_verification" =>
             restore_verification(restore_at, restore_code, verifier_version),
           "migrations" => migrations,
           "protocol_range" => protocol_range(compatibility),
           "release_revision" => compatibility["server_release"],
           "restore_epoch" => if(epoch_finalized, do: "finalized", else: "unfinalized"),
           "schema" => schema(compatibility),
           "tested_oci_digest" => compatibility["tested_oci_digest"],
           "traffic" => if(traffic_allowed, do: "accepting", else: "draining"),
           "wal" => freshness("lag_seconds", wal_at, now)
         }}

      _ ->
        {:error, :database_unavailable}
    end
  end

  defp inspection_sql do
    """
    SELECT
      COALESCE((SELECT finalized FROM sync_epochs WHERE singleton_key = TRUE), FALSE),
      COALESCE((SELECT traffic_allowed FROM operations_state WHERE singleton_key = TRUE), FALSE),
      (SELECT backup_completed_at FROM operations_state WHERE singleton_key = TRUE),
      (SELECT wal_archived_at FROM operations_state WHERE singleton_key = TRUE),
      proof.finished_at,
      proof.result_code,
      proof.verifier_version
    FROM (VALUES (TRUE)) AS singleton(key)
    LEFT JOIN LATERAL (
      SELECT finished_at, result_code, verifier_version
      FROM restore_verifications
      ORDER BY finished_at DESC
      LIMIT 1
    ) AS proof ON TRUE
    """
  end

  defp migration_status do
    migrations = Ecto.Migrator.migrations(Repo)
    pending_count = Enum.count(migrations, fn {status, _version, _name} -> status == :down end)

    %{
      "pending_count" => pending_count,
      "state" => if(pending_count == 0, do: "finalized", else: "pending")
    }
  end

  defp protocol_range(compatibility) do
    compatibility
    |> get_in(["supported_protocols", "sync"])
    |> Map.take(["minimum", "maximum"])
  end

  defp schema(compatibility) do
    range = Map.fetch!(compatibility, "schema_range")

    %{
      "current" => Map.fetch!(range, "maximum"),
      "minimum" => Map.fetch!(range, "minimum"),
      "maximum" => Map.fetch!(range, "maximum")
    }
  end

  defp freshness(label, nil, _now), do: %{"state" => "missing", label => nil}

  defp freshness(label, at, now) do
    at = utc_datetime(at)
    age = max(DateTime.diff(now, at, :second), 0)
    %{"state" => if(age <= @rpo_seconds, do: "current", else: "lagging"), label => age}
  end

  defp restore_verification(nil, _code, _version),
    do: %{"completed_at" => nil, "state" => "missing", "verifier_version" => nil}

  defp restore_verification(at, code, version) do
    %{
      "completed_at" =>
        at |> utc_datetime() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "state" => code,
      "verifier_version" => version
    }
  end

  defp utc_datetime(%DateTime{} = datetime), do: datetime

  defp utc_datetime(%NaiveDateTime{} = datetime) do
    DateTime.from_naive!(datetime, "Etc/UTC")
  end

  defp validate_proof(%{
         source_backup_digest: digest,
         target_recovery_point: %DateTime{} = recovery_point,
         verifier_version: version,
         started_at: %DateTime{} = started_at,
         finished_at: %DateTime{} = finished_at,
         result_code: result_code
       })
       when is_binary(digest) and byte_size(digest) == 32 and is_integer(version) and version >= 1 and
              result_code in ["passed", "failed"] do
    if DateTime.compare(recovery_point, finished_at) in [:lt, :eq] and
         DateTime.compare(started_at, finished_at) in [:lt, :eq] do
      :ok
    else
      {:error, :invalid_restore_proof}
    end
  end

  defp validate_proof(_proof), do: {:error, :invalid_restore_proof}

  defp option(options, key, default) when is_map(options), do: Map.get(options, key, default)
  defp option(options, key, default) when is_list(options), do: Keyword.get(options, key, default)
end
