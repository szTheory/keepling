defmodule KeeplingWeb.MCP.Pipeline do
  @moduledoc """
  Authenticates an MCP bearer through the same device-grant credential every
  native adapter uses (D-05, `:device_grant_authenticated`), refuses a grant
  whose `client_kind` is not `mcp`, and assigns identity and scope from the
  loaded grant only -- never from the JSON-RPC body (D-24, T-05-01).

  On a missing or invalid bearer, responds 401 with a `WWW-Authenticate`
  header. Its `resource_metadata` parameter is filled in by plan 05-02.
  """

  import Plug.Conn

  alias Keepling.Accounts

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> credential] when credential != "" <-
           get_req_header(conn, "authorization"),
         {:ok, authenticated} <- Accounts.authenticate_device_access(credential),
         true <- authenticated.client_kind == "mcp" do
      conn
      |> assign(:current_account_id, authenticated.account_id)
      |> assign(:current_client_kind, authenticated.client_kind)
      |> assign(:current_device_grant_id, authenticated.grant_id)
      |> assign(:current_grant_label, authenticated.label)
      |> assign(:current_scope, authenticated.scope)
    else
      {:error, :infrastructure_failure} ->
        unauthorized(conn, "device_authentication_unavailable", "Device authentication unavailable")

      _reason ->
        unauthorized(conn, "device_authentication_required", "Device authentication required")
    end
  end

  defp unauthorized(conn, code, title) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
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
