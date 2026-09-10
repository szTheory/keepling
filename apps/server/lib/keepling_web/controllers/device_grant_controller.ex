defmodule KeeplingWeb.DeviceGrantController do
  use KeeplingWeb, :controller

  alias Keepling.Accounts
  alias KeeplingWeb.MCP.Metadata

  @authorize_keys ~w(client_id code_challenge code_challenge_method installation_id label redirect_uri response_type state)
  @exchange_keys ~w(code code_verifier grant_type redirect_uri state)
  @mcp_authorize_keys @authorize_keys ++ ~w(resource scope)
  @mcp_exchange_keys @exchange_keys ++ ~w(resource)
  @refresh_keys ~w(grant_type refresh_token)
  @client_ids ~w(electron iphone mcp)
  @access_ttl_seconds 15 * 60

  def authorize(%{assigns: %{current_account_id: account_id}} = conn, params) do
    authorize_keys = if params["client_id"] == "mcp", do: @mcp_authorize_keys, else: @authorize_keys

    with :ok <- exact_keys(params, authorize_keys),
         "code" <- params["response_type"],
         client_id when client_id in @client_ids <- params["client_id"],
         :ok <- validate_resource(params, client_id),
         {:ok, authorization} <-
           Accounts.issue_device_authorization(
             account_id,
             %{
               client_kind: client_id,
               code_challenge: params["code_challenge"],
               code_challenge_method: params["code_challenge_method"],
               installation_id: params["installation_id"],
               label: params["label"],
               redirect_uri: params["redirect_uri"],
               scope: params["scope"] || "",
               state: params["state"]
             }
             |> maybe_put_resource(client_id, params["resource"])
           ) do
      redirect(conn,
        external:
          append_query(params["redirect_uri"], %{
            "code" => authorization.code,
            "state" => authorization.state
          })
      )
    else
      _reason ->
        problem(
          conn,
          400,
          "invalid_authorization_request",
          "Invalid authorization request",
          "restart_authorization"
        )
    end
  end

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    exchange_keys = if Map.has_key?(params, "resource"), do: @mcp_exchange_keys, else: @exchange_keys

    with :ok <- exact_keys(params, exchange_keys),
         :ok <- validate_exchange_resource(params),
         {:ok, grant} <-
           Accounts.exchange_device_authorization(%{
             code: params["code"],
             code_verifier: params["code_verifier"],
             redirect_uri: params["redirect_uri"],
             state: params["state"]
           }) do
      json(conn, token_response(grant))
    else
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
      _reason -> invalid_credential_problem(conn, "invalid_authorization_code")
    end
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    with :ok <- exact_keys(params, @refresh_keys),
         {:ok, grant} <- Accounts.refresh_device_grant(params["refresh_token"]) do
      json(conn, token_response(grant))
    else
      {:error, :refresh_replay_detected} ->
        invalid_credential_problem(conn, "refresh_replay_detected")

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn)

      _reason ->
        invalid_credential_problem(conn, "invalid_refresh_token")
    end
  end

  def token(conn, _params),
    do:
      problem(
        conn,
        400,
        "invalid_grant_request",
        "Invalid grant request",
        "restart_authorization"
      )

  def list(%{assigns: %{device_grant_namespace: namespace}} = conn, _params) do
    grants =
      namespace.subject
      |> account_id!()
      |> Accounts.list_device_grants()
      |> Enum.map(&grant_response/1)

    json(conn, %{device_grants: grants})
  end

  def revoke(
        %{assigns: %{device_grant_namespace: namespace}} = conn,
        %{"installation_id" => installation_id}
      ) do
    with {:ok, result} <-
           Accounts.revoke_device_installation(
             account_id!(namespace.subject),
             installation_id
           ) do
      json(conn, Map.put(result, :installation_id, installation_id))
    else
      {:error, :device_grant_not_found} ->
        problem(conn, 404, "device_grant_not_found", "Device grant not found", "refresh_grants")

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn)
    end
  end

  defp token_response(grant) do
    %{
      access_token: grant.access_token,
      expires_in: @access_ttl_seconds,
      namespace: %{
        account_subject: grant.namespace.subject,
        generation: grant.namespace.generation,
        issuer: grant.namespace.issuer,
        origin: grant.namespace.origin,
        server_instance: grant.namespace.server_instance
      },
      refresh_token: grant.refresh_token,
      token_type: "Bearer"
    }
  end

  defp grant_response(grant) do
    %{
      client_kind: grant.client_kind,
      generation: grant.generation,
      id: grant.id,
      installation_id: grant.installation_id,
      label: grant.label,
      revoked: grant.revoked?
    }
  end

  # `resource` is only ever an `mcp` request key -- omitting it entirely for
  # electron/iphone (rather than including it as `nil`) matters because
  # `DeviceGrant.validate_authorization_request/1` checks the exact KEY SET
  # it receives, and a present-but-nil key is a different shape than an
  # absent one.
  defp maybe_put_resource(params, "mcp", resource), do: Map.put(params, :resource, resource)
  defp maybe_put_resource(params, _client_id, _resource), do: params

  defp exact_keys(params, keys) do
    if Enum.sort(Map.keys(params)) == Enum.sort(keys), do: :ok, else: {:error, :invalid_shape}
  end

  # D-33/RFC 8707: an `mcp` request must name this server's own canonical MCP
  # resource URI, and no other client kind may send `resource` at all --
  # `exact_keys/2` above already rejects a `resource` param for electron/
  # iphone before this function ever runs.
  defp validate_resource(params, "mcp") do
    if params["resource"] == canonical_mcp_resource(),
      do: :ok,
      else: {:error, :invalid_resource}
  end

  defp validate_resource(_params, _client_id), do: :ok

  defp validate_exchange_resource(%{"resource" => resource}) do
    if resource == canonical_mcp_resource(), do: :ok, else: {:error, :invalid_resource}
  end

  defp validate_exchange_resource(_params), do: :ok

  defp canonical_mcp_resource, do: Metadata.resource_uri()

  defp append_query(uri, values) do
    parsed = URI.parse(uri)
    query = parsed.query |> decode_query() |> Map.merge(values) |> URI.encode_query()
    %{parsed | query: query} |> URI.to_string()
  end

  defp decode_query(nil), do: %{}
  defp decode_query(query), do: URI.decode_query(query)

  defp account_id!(subject), do: Ecto.UUID.dump!(subject)

  defp invalid_credential_problem(conn, code),
    do:
      problem(
        conn,
        401,
        code,
        "Grant credential rejected",
        "restart_authorization"
      )

  defp infrastructure_problem(conn),
    do:
      problem(
        conn,
        503,
        "service_unavailable",
        "Service unavailable",
        "retry"
      )

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
