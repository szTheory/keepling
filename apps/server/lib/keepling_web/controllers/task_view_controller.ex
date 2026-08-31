defmodule KeeplingWeb.TaskViewController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.TaskViews, as: PostgresTaskViews
  alias Keepling.Application.TaskViews

  @default_limit 20

  def inbox(conn, params), do: list_view(conn, params, :inbox)
  def today(conn, params), do: list_view(conn, params, :today)
  def upcoming(conn, params), do: list_view(conn, params, :upcoming)
  def completed(conn, params), do: list_view(conn, params, :completed)

  def move_today(conn, params) do
    with {:ok, command} <- decode_move(params),
         {:ok, result} <-
           TaskViews.move_today(command, view_context(conn), PostgresTaskViews) do
      json(conn, result)
    else
      {:error, :invalid_move} -> invalid_query(conn)
      {:error, :not_found} -> task_not_found(conn)
      {:error, :order_stale} -> order_stale(conn)
      {:error, :today_section_too_large} -> section_too_large(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp list_view(conn, params, view) do
    with {:ok, options} <- options(params),
         {:ok, page} <- TaskViews.list(view, view_context(conn), options, PostgresTaskViews) do
      json(conn, page)
    else
      {:error, :invalid_cursor} -> invalid_query(conn)
      {:error, :invalid_limit} -> invalid_query(conn)
      {:error, :stale_cursor} -> stale_cursor(conn)
      {:error, :not_found} -> task_not_found(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp options(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["cursor", "limit"])),
         {:ok, limit} <- parse_limit(Map.get(params, "limit")) do
      {:ok, %{cursor: Map.get(params, "cursor"), limit: limit}}
    else
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp parse_limit(nil), do: {:ok, @default_limit}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit >= 1 and limit <= 50 -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp parse_limit(_value), do: {:error, :invalid_limit}

  defp decode_move(params) do
    allowed_keys = ["direction", "expected_order_revision", "mutation_id", "task_id", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "direction" => direction,
           "expected_order_revision" => revision,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- direction in ["earlier", "later"],
         true <- is_integer(revision) and revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         direction: String.to_existing_atom(direction),
         expected_order_revision: revision,
         mutation_id: mutation_id,
         task_id: task_id,
         version: 1
       }}
    else
      _invalid -> {:error, :invalid_move}
    end
  end

  defp view_context(conn) do
    endpoint_config = Application.fetch_env!(:keepling, KeeplingWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_config, :secret_key_base)

    %{
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      account_id: conn.assigns.current_account_id,
      cursor_secret: :crypto.mac(:hmac, :sha256, secret_key_base, "keepling-task-view-cursor-v1")
    }
  end

  defp invalid_query(conn) do
    problem(
      conn,
      400,
      "invalid_task_view_query",
      "Invalid task view query",
      "Use a server-issued cursor and a limit from 1 through 50.",
      false,
      "correct_task_view_query"
    )
  end

  defp stale_cursor(conn) do
    problem(
      conn,
      409,
      "task_view_cursor_stale",
      "Task view changed",
      "This view changed before more items could load.",
      false,
      "refresh_view"
    )
  end

  defp order_stale(conn) do
    problem(
      conn,
      409,
      "today_order_stale",
      "Today changed elsewhere",
      "Refresh the list before moving this task.",
      false,
      "refresh_today"
    )
  end

  defp task_not_found(conn) do
    problem(
      conn,
      404,
      "task_not_found",
      "Task not found",
      "Refresh the view before trying again.",
      false,
      "refresh_view"
    )
  end

  defp section_too_large(conn) do
    problem(
      conn,
      409,
      "today_section_too_large",
      "Today could not be reordered",
      "Narrow Today before moving this task.",
      false,
      "review_today"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "The last accepted task view could not be loaded.",
      true,
      "retry_view"
    )
  end

  defp problem(conn, status, code, title, detail, retryable, recovery_action) do
    conn
    |> put_status(status)
    |> put_resp_content_type("application/problem+json")
    |> json(%{
      code: code,
      detail: detail,
      recovery_action: recovery_action,
      retryable: retryable,
      status: status,
      title: title,
      type: "/problems/#{code}"
    })
  end
end
