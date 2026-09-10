defmodule KeeplingWeb.MCP.Registration do
  @moduledoc """
  RFC 7591 Dynamic Client Registration, scoped behind the existing
  authenticated browser session (D-29). Registration succeeds only for a
  caller who has already proven ownership of the single Keepling account --
  `account_id` is read exclusively from `conn.assigns.current_account_id`
  (assigned by `KeeplingWeb.Auth` on the `:authenticated` pipeline), never
  from the request body, and neither scope nor client kind is ever
  request-supplied (T-05-09).

  A registered client_id is a public client: PKCE only, no client secret,
  `token_endpoint_auth_method: "none"`.
  """

  use KeeplingWeb, :controller

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.RateLimit
  alias Keepling.Accounts.SecurityAudit
  alias Keepling.Repo

  @allowed_keys ~w(client_name grant_types redirect_uris response_types token_endpoint_auth_method)
  @required_grant_types ~w(authorization_code refresh_token)
  @max_client_name_bytes 200
  @max_redirect_uris 5

  def create(%{assigns: %{current_account_id: account_id}} = conn, params) do
    with :ok <- RateLimit.admit(:mcp_registration, conn.remote_ip),
         :ok <- exact_keys(params, @allowed_keys),
         {:ok, client_name} <- valid_client_name(params["client_name"]),
         {:ok, redirect_uris} <- valid_redirect_uris(params["redirect_uris"]),
         :ok <- valid_grant_types(params["grant_types"]),
         :ok <- valid_response_types(params["response_types"]),
         :ok <- valid_auth_method(params["token_endpoint_auth_method"]),
         {:ok, client_id} <- insert_registration(account_id, client_name, redirect_uris) do
      RateLimit.emit_decision(:mcp_registration, :accepted)

      conn
      |> put_status(201)
      |> json(%{
        client_id: client_id,
        client_name: client_name,
        grant_types: @required_grant_types,
        redirect_uris: redirect_uris,
        response_types: ["code"],
        token_endpoint_auth_method: "none"
      })
    else
      {:error, :rate_limited, _retry_after_ms} ->
        RateLimit.emit_decision(:mcp_registration, :limited)
        invalid_client_metadata(conn)

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn)

      _reason ->
        RateLimit.emit_decision(:mcp_registration, :invalid)
        invalid_client_metadata(conn)
    end
  end

  defp exact_keys(params, keys) do
    if Enum.sort(Map.keys(params)) == Enum.sort(keys), do: :ok, else: {:error, :invalid_shape}
  end

  defp valid_client_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    if byte_size(trimmed) in 1..@max_client_name_bytes,
      do: {:ok, trimmed},
      else: {:error, :invalid_client_name}
  end

  defp valid_client_name(_name), do: {:error, :invalid_client_name}

  defp valid_redirect_uris(uris)
       when is_list(uris) and uris != [] and
              length(uris) <= @max_redirect_uris do
    if Enum.all?(uris, &valid_redirect_uri?/1),
      do: {:ok, uris},
      else: {:error, :invalid_redirect_uris}
  end

  defp valid_redirect_uris(_uris), do: {:error, :invalid_redirect_uris}

  defp valid_redirect_uri?(uri) when is_binary(uri) do
    case URI.new(uri) do
      {:ok, %URI{scheme: scheme, host: host, path: path}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             is_binary(path) and path != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_redirect_uri?(_uri), do: false

  # D-29: the registered client is a public MCP host -- always this exact
  # closed grant-type pair, in either order, never a subset and never a
  # client-credentials grant (D-07).
  defp valid_grant_types(grant_types) when is_list(grant_types) do
    if Enum.sort(grant_types) == Enum.sort(@required_grant_types),
      do: :ok,
      else: {:error, :invalid_grant_types}
  end

  defp valid_grant_types(_grant_types), do: {:error, :invalid_grant_types}

  defp valid_response_types(["code"]), do: :ok
  defp valid_response_types(_response_types), do: {:error, :invalid_response_types}

  defp valid_auth_method("none"), do: :ok
  defp valid_auth_method(_auth_method), do: {:error, :invalid_auth_method}

  defp insert_registration(account_id, client_name, redirect_uris) do
    client_id = "mcp_" <> (32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transact(fn repo ->
      SQL.query!(
        repo,
        """
        INSERT INTO mcp_client_registrations (
          client_id, account_id, client_name, redirect_uris, created_at
        )
        VALUES ($1, $2, $3, $4, $5)
        """,
        [client_id, account_id, client_name, redirect_uris, now]
      )

      SecurityAudit.record_required!(repo, "mcp_client_registered", now)

      {:ok, client_id}
    end)
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  defp invalid_client_metadata(conn) do
    problem(
      conn,
      400,
      "invalid_client_metadata",
      "Invalid client registration",
      "correct_request"
    )
  end

  defp infrastructure_problem(conn) do
    problem(conn, 503, "service_unavailable", "Service unavailable", "retry")
  end

  defp problem(conn, status, code, title, recovery_action) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> put_status(status)
    |> json(%{
      code: code,
      recovery_action: recovery_action,
      retryable: status == 503,
      status: status,
      title: title,
      type: "/problems/#{code}"
    })
  end
end
