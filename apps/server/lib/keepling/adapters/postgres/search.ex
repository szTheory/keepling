defmodule Keepling.Adapters.Postgres.Search do
  @moduledoc """
  PostgreSQL full-text search over `tasks.search_document`, account-scoped in
  SQL and ordered by `(captured_at DESC, id)` -- deliberately not by a
  computed relevance rank, which is not stable under a keyset cursor (D-35).
  """

  @behaviour Keepling.Application.Search.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @impl true
  def search_tasks(%{account_id: account_id}, term, options) do
    case transact(fn repo ->
           {items, next_keyset} = page(repo, account_id, term, options.cursor, options.limit)
           {:ok, %{items: items, next_keyset: next_keyset}}
         end) do
      {:ok, page} -> {:ok, page}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  defp page(repo, account_id, term, cursor, limit) do
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
        WHERE account_id = $1 AND trashed_at IS NULL
          AND search_document @@ websearch_to_tsquery('english', $2)
        #{predicate}
        ORDER BY captured_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id, term] ++ keyset_params ++ [limit + 1]
      ).rows

    {selected, extra} = Enum.split(rows, limit)
    items = Enum.map(selected, &item/1)

    next_keyset =
      case {selected, extra} do
        {[], _} -> nil
        {_, []} -> nil
        {page, [_ | _]} -> page |> List.last() |> keyset()
      end

    {items, next_keyset}
  end

  defp item([id, title, revision, captured_at, planned_on, deadline_on, completed_at]) do
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

  defp keyset(row) do
    %{
      captured_at: row |> Enum.at(3) |> to_datetime(),
      id: row |> Enum.at(0) |> load_uuid()
    }
  end

  defp transact(fun), do: Repo.transact(fun, query_options())

  defp query!(repo, statement, params),
    do: SQL.query!(repo, statement, params, query_options())

  defp query_options do
    timeout = Application.fetch_env!(:keepling, :task_view_query_timeout_ms)

    if is_integer(timeout) and timeout > 0 do
      [timeout: timeout]
    else
      raise ArgumentError, "search query timeout must be a positive integer"
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
