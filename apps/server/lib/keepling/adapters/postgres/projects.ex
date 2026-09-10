defmodule Keepling.Adapters.Postgres.Projects do
  @moduledoc """
  PostgreSQL project list and per-project task reads, account-scoped in SQL.

  A project identity that does not belong to the calling account -- or does
  not exist, or is not a project -- returns `{:error, :not_found}` rather
  than an empty page, so a foreign but well-formed identity never confirms
  its own existence.
  """

  @behaviour Keepling.Application.Projects.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @impl true
  def list_projects(%{account_id: account_id}, options) do
    case transact(fn repo ->
           {items, next_keyset} = list_page(repo, account_id, options.cursor, options.limit)
           {:ok, %{items: items, next_keyset: next_keyset}}
         end) do
      {:ok, page} -> {:ok, page}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def list_project_tasks(%{account_id: account_id}, project_id, options) do
    case transact(fn repo ->
           with {:ok, _display_name} <- project_scope(repo, account_id, project_id) do
             {items, next_keyset} =
               tasks_page(repo, account_id, project_id, options.cursor, options.limit)

             {:ok, %{items: items, next_keyset: next_keyset}}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, page} -> {:ok, page}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  defp project_scope(repo, account_id, project_id) do
    case query(
           repo,
           """
           SELECT display_name
           FROM organizations
           WHERE account_id = $1 AND id = $2 AND kind = 'project'
           FOR SHARE
           """,
           [account_id, dump_uuid(project_id)]
         ) do
      {:ok, %{rows: [[display_name]]}} -> {:ok, display_name}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  defp list_page(repo, account_id, cursor, limit) do
    {predicate, keyset_params} =
      case cursor do
        nil ->
          {"", []}

        cursor ->
          {"AND (o.display_name > $2 OR (o.display_name = $2 AND o.id > $3))",
           [cursor.display_name, dump_uuid(cursor.id)]}
      end

    limit_parameter = 2 + length(keyset_params)

    rows =
      query!(
        repo,
        """
        SELECT o.id, o.display_name, o.revision,
               count(t.id) FILTER (WHERE t.id IS NOT NULL) AS task_count
        FROM organizations o
        LEFT JOIN tasks t
          ON t.account_id = o.account_id AND t.project_id = o.id AND t.trashed_at IS NULL
        WHERE o.account_id = $1 AND o.kind = 'project' AND o.archived_at IS NULL
        #{predicate}
        GROUP BY o.id, o.display_name, o.revision
        ORDER BY o.display_name ASC, o.id ASC
        LIMIT $#{limit_parameter}
        """,
        [account_id] ++ keyset_params ++ [limit + 1]
      ).rows

    {selected, extra} = Enum.split(rows, limit)
    items = Enum.map(selected, &project_item/1)

    next_keyset =
      case {selected, extra} do
        {[], _} -> nil
        {_, []} -> nil
        {page, [_ | _]} -> page |> List.last() |> project_keyset()
      end

    {items, next_keyset}
  end

  defp tasks_page(repo, account_id, project_id, cursor, limit) do
    {predicate, keyset_params} =
      case cursor do
        nil ->
          {"", []}

        cursor ->
          {"AND (captured_at < $3 OR (captured_at = $3 AND id < $4))",
           [cursor.captured_at, dump_uuid(cursor.id)]}
      end

    limit_parameter = 3 + length(keyset_params)

    rows =
      query!(
        repo,
        """
        SELECT id, title, revision, captured_at, planned_on, deadline_on, completed_at
        FROM tasks
        WHERE account_id = $1 AND project_id = $2 AND trashed_at IS NULL
        #{predicate}
        ORDER BY captured_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id, dump_uuid(project_id)] ++ keyset_params ++ [limit + 1]
      ).rows

    {selected, extra} = Enum.split(rows, limit)
    items = Enum.map(selected, &task_item/1)

    next_keyset =
      case {selected, extra} do
        {[], _} -> nil
        {_, []} -> nil
        {page, [_ | _]} -> page |> List.last() |> task_keyset()
      end

    {items, next_keyset}
  end

  defp project_item([id, display_name, revision, task_count]) do
    %{
      id: load_uuid(id),
      name: display_name,
      revision: revision,
      task_count: task_count
    }
  end

  defp project_keyset(row) do
    %{
      display_name: Enum.at(row, 1),
      id: row |> Enum.at(0) |> load_uuid()
    }
  end

  defp task_item([id, title, revision, captured_at, planned_on, deadline_on, completed_at]) do
    %{
      captured_at: captured_at |> to_datetime() |> DateTime.to_iso8601(),
      completed: not is_nil(completed_at),
      deadline_on: optional_date(deadline_on),
      id: load_uuid(id),
      planned_on: optional_date(planned_on),
      revision: revision,
      title: title
    }
  end

  defp task_keyset(row) do
    %{
      captured_at: row |> Enum.at(3) |> to_datetime(),
      id: row |> Enum.at(0) |> load_uuid()
    }
  end

  defp transact(fun), do: Repo.transact(fun, query_options())

  defp query(repo, statement, params),
    do: SQL.query(repo, statement, params, query_options())

  defp query!(repo, statement, params),
    do: SQL.query!(repo, statement, params, query_options())

  defp query_options do
    timeout = Application.fetch_env!(:keepling, :task_view_query_timeout_ms)

    if is_integer(timeout) and timeout > 0 do
      [timeout: timeout]
    else
      raise ArgumentError, "project read query timeout must be a positive integer"
    end
  end

  defp optional_date(nil), do: nil
  defp optional_date(%Date{} = date), do: Date.to_iso8601(date)

  defp dump_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, canonical} -> Ecto.UUID.dump!(canonical)
      :error -> uuid
    end
  end

  defp load_uuid(uuid), do: Ecto.UUID.load!(uuid)

  defp to_datetime(%DateTime{} = value), do: value

  defp to_datetime(%NaiveDateTime{} = value),
    do: DateTime.from_naive!(value, "Etc/UTC")
end
