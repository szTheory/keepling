defmodule KeeplingWeb.MCP.Pipeline do
  @moduledoc """
  Authenticates an MCP bearer through the same device-grant credential every
  native adapter uses (D-05, `:device_grant_authenticated`), refuses a grant
  whose `client_kind` is not `mcp`, refuses a grant whose stored resource
  audience does not equal this server's canonical MCP resource URI (D-33,
  RFC 8707, T-05-10), and assigns identity and scope from the loaded grant
  only -- never from the JSON-RPC body (D-24, T-05-01).

  On a missing, invalid, or audience-mismatched bearer, responds 401 with a
  `WWW-Authenticate` header whose `resource_metadata` parameter is the
  absolute URL of the RFC 9728 protected-resource metadata document, so a
  spec-conformant client can discover the authorization server from the 401
  alone.
  """

  import Plug.Conn

  alias Keepling.Accounts
  alias Keepling.Accounts.SecurityAudit
  alias Keepling.Repo
  alias KeeplingWeb.MCP.Metadata

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> credential] when credential != "" <-
           get_req_header(conn, "authorization"),
         {:ok, authenticated} <- Accounts.authenticate_device_access(credential),
         true <- authenticated.client_kind == "mcp",
         :ok <- check_audience(authenticated) do
      conn
      |> assign(:current_account_id, authenticated.account_id)
      |> assign(:current_client_kind, authenticated.client_kind)
      |> assign(:current_device_grant_id, authenticated.grant_id)
      |> assign(:current_grant_label, authenticated.label)
      |> assign(:current_scope, authenticated.scope)
    else
      {:error, :infrastructure_failure} ->
        unauthorized(
          conn,
          "device_authentication_unavailable",
          "Device authentication unavailable"
        )

      {:error, :audience_rejected} ->
        record_audience_rejected()
        unauthorized(conn, "device_authentication_required", "Device authentication required")

      _reason ->
        unauthorized(conn, "device_authentication_required", "Device authentication required")
    end
  end

  defp check_audience(%{resource: resource}) do
    if resource == Metadata.resource_uri(), do: :ok, else: {:error, :audience_rejected}
  end

  defp record_audience_rejected do
    SecurityAudit.record_best_effort(
      Repo,
      "mcp_audience_rejected",
      DateTime.utc_now() |> DateTime.truncate(:microsecond)
    )
  end

  defp unauthorized(conn, code, title) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer resource_metadata="#{Metadata.protected_resource_metadata_url()}")
    )
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      401,
      Jason.encode!(%{
        code: code,
        recovery_action: "reauthorize_device",
        retryable: code == "device_authentication_unavailable",
        status: 401,
        title: title,
        type: "/problems/#{code}"
      })
    )
    |> halt()
  end
end
