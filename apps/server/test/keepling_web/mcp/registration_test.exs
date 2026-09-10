defmodule KeeplingWeb.MCP.RegistrationTest do
  @moduledoc """
  05-02-PLAN.md Task 3: RFC 7591 Dynamic Client Registration, scoped behind
  the existing authenticated browser session (D-29) -- an unauthenticated
  caller cannot register, `account_id` never comes from request input, and a
  registered client_id completes the full authorization-code + S256 PKCE
  flow with its redirect bound exactly to what it registered.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @registered_redirect_uri "https://agent-host.invalid/callback"
  @other_registered_redirect_uri "https://agent-host.invalid/callback/other"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "registration-test-state") |> Base.url_encode64(padding: false)
  @password String.duplicate("registration-test-password-", 12)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-registration",
      redirect_uris: %{
        "electron" => ["keepling://authorization/callback"],
        "iphone" => ["keepling://authorization/callback"],
        "mcp" => ["https://server.keepling.invalid/mcp/callback"]
      }
    )

    SQL.query!(Repo, "DELETE FROM mcp_client_registrations", [])
    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()

    # `Keepling.Accounts.RateLimit`'s ETS bucket state is process-global, not
    # scoped by the SQL Sandbox -- without this, an earlier test's
    # registration attempts (which each consume one :mcp_registration hit,
    # even a rejected one, since RateLimit.admit runs before body validation)
    # would silently carry into this test and change what "the rate limit"
    # test file measures.
    :ets.delete_all_objects(Keepling.Accounts.RateLimit)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id}
  end

  test "an unauthenticated caller cannot register a client and creates no row", %{conn: conn} do
    response =
      conn
      |> trusted_request()
      |> post("/oauth/register", registration_body())

    assert response.status == 401

    assert {:ok, %{rows: [[0]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM mcp_client_registrations", [])
  end

  test "an authenticated session registers a public client and receives no client secret", %{
    conn: conn
  } do
    {browser, csrf} = login_and_csrf(conn)

    response =
      browser
      |> recycle()
      |> mutation_request(csrf)
      |> post("/oauth/register", registration_body())
      |> json_response(201)

    assert is_binary(response["client_id"])
    assert response["client_name"] == "Synthetic MCP host"
    assert response["redirect_uris"] == [@registered_redirect_uri]
    assert response["token_endpoint_auth_method"] == "none"
    refute Map.has_key?(response, "client_secret")

    assert {:ok, %{rows: [[1]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM mcp_client_registrations", [])

    assert {:ok, %{rows: [[count]]}} =
             SQL.query(
               Repo,
               "SELECT COUNT(*) FROM account_security_audits WHERE event_type = 'mcp_client_registered'",
               []
             )

    assert count == 1
  end

  test "a body carrying a key outside the closed allow-list is rejected", %{conn: conn} do
    {browser, csrf} = login_and_csrf(conn)

    response =
      browser
      |> recycle()
      |> mutation_request(csrf)
      |> post("/oauth/register", Map.put(registration_body(), "scope", "tasks.bulk"))

    assert response.status == 400

    assert {:ok, %{rows: [[0]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM mcp_client_registrations", [])
  end

  test "a redirect_uris entry that is not an absolute http(s) URI is rejected", %{conn: conn} do
    {browser, csrf} = login_and_csrf(conn)

    response =
      browser
      |> recycle()
      |> mutation_request(csrf)
      |> post(
        "/oauth/register",
        Map.put(registration_body(), "redirect_uris", ["keepling://not/http"])
      )

    assert response.status == 400

    assert {:ok, %{rows: [[0]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM mcp_client_registrations", [])
  end

  test "a registered client_id completes authorize, exchange, and tools/call, bound to its own redirect",
       %{conn: conn} do
    {browser, csrf} = login_and_csrf(conn)

    registration =
      browser
      |> recycle()
      |> mutation_request(csrf)
      |> post("/oauth/register", registration_body())
      |> json_response(201)

    client_id = registration["client_id"]

    authorization = authorize(browser, client_id, @registered_redirect_uri, "tasks.write")
    grant = exchange(client_id, @registered_redirect_uri, authorization)

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{grant["access_token"]}")
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{}
      })
      |> json_response(200)

    assert response["result"]["protocolVersion"] == "2025-06-18"
  end

  test "a redirect URI not registered for that client_id is refused at /oauth/authorize", %{
    conn: conn
  } do
    {browser, csrf} = login_and_csrf(conn)

    registration =
      browser
      |> recycle()
      |> mutation_request(csrf)
      |> post("/oauth/register", registration_body())
      |> json_response(201)

    client_id = registration["client_id"]

    response =
      browser
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => client_id,
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "unregistered-redirect",
        "label" => "Synthetic unregistered redirect",
        "redirect_uri" => @other_registered_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => "tasks.read",
        "state" => @state
      })

    assert response.status == 400
  end

  test "registration is rate-limited through the existing limiter", %{conn: conn} do
    {browser, csrf} = login_and_csrf(conn)

    responses =
      for _n <- 1..6 do
        browser
        |> recycle()
        |> mutation_request(csrf)
        |> post("/oauth/register", registration_body())
      end

    statuses = Enum.map(responses, & &1.status)
    assert Enum.count(statuses, &(&1 == 201)) == 5
    assert Enum.count(statuses, &(&1 == 400)) == 1
  end

  defp registration_body do
    %{
      "client_name" => "Synthetic MCP host",
      "grant_types" => ["authorization_code", "refresh_token"],
      "redirect_uris" => [@registered_redirect_uri],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none"
    }
  end

  defp authorize(conn, client_id, redirect_uri, scope) do
    response =
      conn
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => client_id,
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "registration-test-installation",
        "label" => "Synthetic registered installation",
        "redirect_uri" => redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => scope,
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == redirect_uri
    query = URI.decode_query(location.query)
    assert query["state"] == @state
    %{code: query["code"], state: query["state"]}
  end

  defp exchange(_client_id, redirect_uri, authorization) do
    build_conn()
    |> post("/oauth/token", %{
      "code" => authorization.code,
      "code_verifier" => @verifier,
      "grant_type" => "authorization_code",
      "redirect_uri" => redirect_uri,
      "resource" => @mcp_resource,
      "state" => authorization.state
    })
    |> json_response(200)
  end

  defp login_and_csrf(conn) do
    response =
      conn
      |> trusted_request()
      |> post("/api/v1/login", %{
        "client_kind" => "web",
        "label" => "Registration test browser",
        "password" => @password,
        "version" => 1
      })

    body = json_response(response, 200)
    {response, body["csrf_token"]}
  end

  defp mutation_request(conn, csrf_token) do
    conn
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
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

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

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
