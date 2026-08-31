defmodule KeeplingWeb.CommandController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias KeeplingWeb.Auth

  def test_session(conn, _params) do
    case Auth.sign_in_test_account(conn) do
      {:ok, signed_in_conn, csrf_token} -> json(signed_in_conn, %{csrf_token: csrf_token})
      {:error, :fixture_unavailable} -> infrastructure_problem(conn)
    end
  end

  def session(conn, _params) do
    json(conn, %{csrf_token: Plug.CSRFProtection.get_csrf_token()})
  end

  def inbox(conn, _params) do
    case Commands.list_inbox(context(conn), CommandStore) do
      {:ok, tasks} -> json(conn, %{tasks: tasks})
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def capture_task(conn, params) do
    with {:ok, command} <- decode_capture(params),
         {:ok, result} <- Commands.dispatch(command, context(conn), CommandStore) do
      respond(conn, result)
    else
      {:error, :invalid_command} -> invalid_command(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def mutation(conn, %{"mutation_id" => mutation_id}) do
    with {:ok, _uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, result} <- Commands.lookup_result(context(conn), mutation_id, CommandStore) do
      respond(conn, result)
    else
      :error -> invalid_command(conn)
      {:error, :not_found} -> not_found_problem(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp decode_capture(params) do
    allowed_keys = ["mutation_id", "task_id", "title", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "title" => title,
           "version" => 1
         }
         when is_binary(title) <- params,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         mutation_id: mutation_id,
         task_id: task_id,
         title: title,
         type: :capture_task,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp context(conn) do
    %{
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      account_id: conn.assigns.current_account_id,
      actor_type: "user",
      client_kind: "web"
    }
  end

  defp respond(conn, %{status: status, body: body}) do
    conn
    |> put_status(status)
    |> maybe_problem_content_type(status)
    |> json(body)
  end

  defp maybe_problem_content_type(conn, status) when status >= 400,
    do: put_resp_content_type(conn, "application/problem+json")

  defp maybe_problem_content_type(conn, _status), do: conn

  defp invalid_command(conn) do
    problem(
      conn,
      400,
      "invalid_command",
      "Invalid command",
      "Send the closed version 1 capture command shape.",
      false,
      "correct_request"
    )
  end

  defp not_found_problem(conn) do
    problem(
      conn,
      404,
      "mutation_not_found",
      "Mutation not found",
      nil,
      true,
      "retry_original_mutation"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "Your request was not confirmed. Check again with the same mutation identity.",
      true,
      "check_mutation_result"
    )
  end

  defp problem(conn, status, code, title, detail, retryable, recovery_action) do
    body = %{
      code: code,
      recovery_action: recovery_action,
      retryable: retryable,
      status: status,
      title: title,
      type: "/problems/#{code}"
    }

    body = if detail, do: Map.put(body, :detail, detail), else: body

    conn
    |> put_status(status)
    |> put_resp_content_type("application/problem+json")
    |> json(body)
  end
end
