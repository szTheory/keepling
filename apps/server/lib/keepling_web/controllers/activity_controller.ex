defmodule KeeplingWeb.ActivityController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Activity

  @default_limit 20

  def index(conn, %{"task_id" => task_id} = params) do
    with {:ok, _task_uuid} <- Ecto.UUID.cast(task_id),
         {:ok, options} <- options(params),
         {:ok, page} <-
           Activity.list_task(activity_context(conn), task_id, options, CommandStore) do
      json(conn, page)
    else
      :error -> invalid_query(conn)
      {:error, :invalid_cursor} -> invalid_query(conn)
      {:error, :invalid_limit} -> invalid_query(conn)
      {:error, :not_found} -> task_not_found(conn)
      {:error, :stale_cursor} -> stale_cursor(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp options(params) do
    allowed_keys = ["cursor", "limit", "task_id"]

    with true <- Enum.all?(Map.keys(params), &(&1 in allowed_keys)),
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

  defp activity_context(conn) do
    endpoint_config = Application.fetch_env!(:keepling, KeeplingWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_config, :secret_key_base)

    %{
      account_id: conn.assigns.current_account_id,
      cursor_secret: :crypto.mac(:hmac, :sha256, secret_key_base, "keepling-activity-cursor-v1")
    }
  end

  defp invalid_query(conn) do
    problem(
      conn,
      400,
      "invalid_activity_query",
      "Invalid activity query",
      "Use a server-issued cursor and a limit from 1 through 50.",
      false,
      "correct_activity_query"
    )
  end

  defp task_not_found(conn) do
    problem(
      conn,
      404,
      "task_not_found",
      "Task not found",
      "Refresh the task before trying again.",
      false,
      "refresh_task"
    )
  end

  defp stale_cursor(conn) do
    problem(
      conn,
      409,
      "activity_cursor_stale",
      "Task activity changed",
      "This task changed before earlier activity could load.",
      false,
      "refresh_activity"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "The last accepted activity could not be loaded.",
      true,
      "retry_activity"
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
