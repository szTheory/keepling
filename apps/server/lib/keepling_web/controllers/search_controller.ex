defmodule KeeplingWeb.SearchController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.Search, as: PostgresSearch
  alias Keepling.Application.Search

  def index(conn, params) do
    with {:ok, options} <- options(params),
         {:ok, page} <-
           Search.query(context(conn), Map.get(params, "q", ""), options, PostgresSearch) do
      json(conn, page)
    else
      {:error, :invalid_limit} -> invalid_query(conn)
      {:error, :invalid_cursor} -> invalid_query(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp options(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["cursor", "limit", "q"])),
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
      cursor_secret: :crypto.mac(:hmac, :sha256, secret_key_base, "keepling-search-cursor-v1")
    }
  end

  defp invalid_query(conn) do
    problem(
      conn,
      400,
      "invalid_search_query",
      "Invalid search query",
      "Use a server-issued cursor and a limit from 1 through 50.",
      false,
      "correct_search_query"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "Search results could not be loaded.",
      true,
      "retry_search"
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
