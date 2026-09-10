defmodule KeeplingWeb.ProjectController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.Projects, as: PostgresProjects
  alias Keepling.Application.Projects

  def index(conn, params) do
    with {:ok, options} <- options(params),
         {:ok, page} <- Projects.list(context(conn), options, PostgresProjects) do
      json(conn, page)
    else
      {:error, :invalid_limit} -> invalid_query(conn)
      {:error, :invalid_cursor} -> invalid_query(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def tasks(conn, %{"organization_id" => organization_id} = params) do
    with {:ok, _uuid} <- Ecto.UUID.cast(organization_id),
         {:ok, options} <- options(Map.delete(params, "organization_id")),
         {:ok, page} <-
           Projects.tasks(context(conn), organization_id, options, PostgresProjects) do
      json(conn, page)
    else
      :error -> project_not_found(conn)
      {:error, :invalid_limit} -> invalid_query(conn)
      {:error, :invalid_cursor} -> invalid_query(conn)
      {:error, :not_found} -> project_not_found(conn)
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

  defp parse_limit(nil), do: {:ok, 20}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit >= 1 and limit <= 50 -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp parse_limit(_value), do: {:error, :invalid_limit}

  defp context(conn) do
    endpoint_config = Application.fetch_env!(:keepling, KeeplingWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_config, :secret_key_base)

    %{
      account_id: conn.assigns.current_account_id,
      cursor_secret: :crypto.mac(:hmac, :sha256, secret_key_base, "keepling-projects-cursor-v1")
    }
  end

  defp invalid_query(conn) do
    problem(
      conn,
      400,
      "invalid_project_query",
      "Invalid project query",
      "Use a server-issued cursor and a limit from 1 through 50.",
      false,
      "correct_project_query"
    )
  end

  defp project_not_found(conn) do
    problem(
      conn,
      404,
      "project_not_found",
      "Project not found",
      "This project is unavailable or belongs to a different account.",
      false,
      "return_to_project_list"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "Project results could not be loaded.",
      true,
      "retry_project_query"
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
