defmodule KeeplingWeb.MCP.Metadata do
  @moduledoc """
  RFC 9728 protected-resource metadata and RFC 8414 authorization-server
  metadata documents, and the single source of this server's canonical MCP
  resource URI (`resource_uri/0`).

  `KeeplingWeb.DeviceGrantController` validates the RFC 8707 `resource`
  parameter against this value at `/oauth/authorize` and `/oauth/token`, and
  `KeeplingWeb.MCP.Pipeline` re-checks a bearer's stored audience against it
  on every `/mcp/v1` request -- so the discovery documents below can never
  drift from what the authorization code actually enforces (05-02-PLAN.md
  Task 2).

  Both documents are reachable without authentication and every value is
  derived from `:keepling, :device_grants` configuration plus
  `Keepling.Application.AgentScope` -- never an account-specific value, a
  database identifier, or another internal detail (T-05-12).
  """

  use KeeplingWeb, :controller

  alias Keepling.Application.AgentScope

  @doc "This server's canonical MCP resource URI -- the RFC 8707 audience."
  @spec resource_uri() :: String.t()
  def resource_uri, do: origin() <> "/mcp/v1"

  @doc "The absolute URL of the RFC 9728 protected-resource metadata document."
  @spec protected_resource_metadata_url() :: String.t()
  def protected_resource_metadata_url, do: origin() <> "/.well-known/oauth-protected-resource"

  @spec protected_resource(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def protected_resource(conn, _params) do
    json(conn, %{
      resource: resource_uri(),
      authorization_servers: [origin()],
      scopes_supported: AgentScope.scopes(),
      bearer_methods_supported: ["header"]
    })
  end

  @spec authorization_server(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def authorization_server(conn, _params) do
    origin = origin()

    json(conn, %{
      issuer: origin,
      authorization_endpoint: origin <> "/oauth/authorize",
      token_endpoint: origin <> "/oauth/token",
      registration_endpoint: origin <> "/oauth/register",
      code_challenge_methods_supported: ["S256"],
      response_types_supported: ["code"]
    })
  end

  defp origin do
    :keepling
    |> Application.get_env(:device_grants, [])
    |> Keyword.get(:origin, "")
  end
end
