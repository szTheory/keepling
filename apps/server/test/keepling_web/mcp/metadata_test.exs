defmodule KeeplingWeb.MCP.MetadataTest do
  @moduledoc """
  05-02-PLAN.md Task 2: the RFC 9728 / RFC 8414 discovery documents, the
  `WWW-Authenticate` challenge that names them, and the RFC 8707 audience
  check at `/mcp/v1`.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "metadata-test-state") |> Base.url_encode64(padding: false)
  @password String.duplicate("metadata-test-password-", 12)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-metadata",
      redirect_uris: %{
        "electron" => ["keepling://authorization/callback"],
        "iphone" => ["keepling://authorization/callback"],
        "mcp" => [@mcp_redirect_uri]
      }
    )

    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id}
  end

  test "GET /.well-known/oauth-protected-resource returns exactly the required keys and no account-specific value",
       %{conn: conn} do
    response = conn |> get("/.well-known/oauth-protected-resource") |> json_response(200)

    assert Enum.sort(Map.keys(response)) ==
             Enum.sort([
               "resource",
               "authorization_servers",
               "scopes_supported",
               "bearer_methods_supported"
             ])

    assert response["resource"] == @mcp_resource
    assert response["authorization_servers"] == ["https://server.keepling.invalid"]

    assert Enum.sort(response["scopes_supported"]) ==
             Enum.sort(["tasks.read", "tasks.write", "tasks.bulk"])

    assert response["bearer_methods_supported"] == ["header"]
  end

  test "GET /.well-known/oauth-authorization-server returns exactly the required keys", %{
    conn: conn
  } do
    response = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

    assert Enum.sort(Map.keys(response)) ==
             Enum.sort([
               "issuer",
               "authorization_endpoint",
               "token_endpoint",
               "registration_endpoint",
               "code_challenge_methods_supported",
               "response_types_supported"
             ])

    assert response["issuer"] == "https://server.keepling.invalid"
    assert response["authorization_endpoint"] == "https://server.keepling.invalid/oauth/authorize"
    assert response["token_endpoint"] == "https://server.keepling.invalid/oauth/token"
    assert response["registration_endpoint"] == "https://server.keepling.invalid/oauth/register"
    assert response["code_challenge_methods_supported"] == ["S256"]
    assert response["response_types_supported"] == ["code"]
  end

  test "both discovery documents are reachable without authentication", %{conn: conn} do
    assert conn |> get("/.well-known/oauth-protected-resource") |> then(& &1.status) == 200

    assert build_conn() |> get("/.well-known/oauth-authorization-server") |> then(& &1.status) ==
             200
  end

  test "an unauthenticated POST /mcp/v1 returns 401 with a WWW-Authenticate resource_metadata challenge",
       %{conn: conn} do
    response =
      conn
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{}
      })

    assert response.status == 401
    [challenge] = get_resp_header(response, "www-authenticate")

    assert challenge ==
             ~s(Bearer resource_metadata="https://server.keepling.invalid/.well-known/oauth-protected-resource")
  end

  test "a bearer whose grant's stored resource no longer matches the canonical MCP resource is refused and audited",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "metadata-audience-drift")

    # Simulate resource-configuration drift after the grant was minted: the
    # grant is real and was validated against the canonical resource at
    # issuance time, but its stored audience no longer matches what the
    # server currently enforces.
    %{num_rows: 1} =
      SQL.query!(
        Repo,
        "UPDATE device_grants SET resource = $1 WHERE access_token_hash = $2",
        [
          "https://server.keepling.invalid/mcp/v1-old",
          :crypto.hash(:sha256, credential)
        ]
      )

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "initialize",
        "params" => %{}
      })

    assert response.status == 401
    [challenge] = get_resp_header(response, "www-authenticate")
    assert challenge =~ "resource_metadata="

    assert {:ok, %{rows: [[count]]}} =
             SQL.query(
               Repo,
               "SELECT COUNT(*) FROM account_security_audits WHERE event_type = 'mcp_audience_rejected'",
               []
             )

    assert count == 1
  end

  test "a valid mcp bearer whose grant resource matches the canonical resource is admitted", %{
    conn: conn
  } do
    credential = grant_credential(login(conn), "metadata-audience-valid")

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "initialize",
        "params" => %{}
      })
      |> json_response(200)

    assert response["result"]["protocolVersion"] == "2025-06-18"
  end

  test "plain as code_challenge_method is refused on the MCP authorization path", %{conn: conn} do
    response =
      login(conn)
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "plain",
        "installation_id" => "metadata-plain-rejected",
        "label" => "Plain challenge rejected",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => "tasks.read",
        "state" => @state
      })

    assert response.status == 400
  end

  defp grant_credential(conn, installation_id) do
    authorization = authorize(conn, installation_id)
    exchange(authorization)["access_token"]
  end

  defp authorize(conn, installation_id) do
    response =
      conn
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => installation_id,
        "label" => "Synthetic mcp installation #{installation_id}",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => "tasks.read",
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    query = URI.decode_query(location.query)
    %{code: query["code"], state: query["state"]}
  end

  defp exchange(authorization) do
    build_conn()
    |> post("/oauth/token", %{
      "code" => authorization.code,
      "code_verifier" => @verifier,
      "grant_type" => "authorization_code",
      "redirect_uri" => @mcp_redirect_uri,
      "resource" => @mcp_resource,
      "state" => authorization.state
    })
    |> json_response(200)
  end

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Metadata test browser",
      "password" => @password,
      "version" => 1
    })
    |> tap(&json_response(&1, 200))
  end

  defp trusted_request(conn) do
    conn = %{
      conn
      | host: "www.example.com",
        req_headers: [
          {"host", "www.example.com"}
          | Enum.reject(conn.req_headers, fn {name, _value} -> name == "host" end)
        ]
    }

    put_req_header(conn, "origin", "http://www.example.com")
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, $2, 'Etc/UTC', $3, $3)
      """,
      [account_id, Argon2.hash_pwd_salt(@password), now]
    )

    account_id
  end
end
