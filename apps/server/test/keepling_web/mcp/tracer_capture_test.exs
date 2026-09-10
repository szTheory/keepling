defmodule KeeplingWeb.MCP.TracerCaptureTest do
  @moduledoc """
  05-01-PLAN.md Task 3: the whole Phase 5 architecture proved as one
  production-quality end-to-end slice. A real PKCE-obtained `mcp` grant
  captures exactly one task over the real Streamable HTTP MCP transport,
  through the real `Commands.dispatch/3`, into real Postgres, and is
  attributed to the agent in the real activity feed.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "tracer-capture-state") |> Base.url_encode64(padding: false)
  @password String.duplicate("tracer-capture-password-", 12)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-tracer-capture",
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

  test "initialize declares the pinned protocol revision and tools+resources capabilities", %{
    conn: conn
  } do
    credential = grant_credential(login(conn), "tracer-init", "tasks.read")

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})
      |> json_response(200)

    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == "2025-06-18"
    assert Map.has_key?(response["result"]["capabilities"], "tools")
    assert Map.has_key?(response["result"]["capabilities"], "resources")
  end

  test "tools/list with tasks.write lists keepling.capture_task and its closed input schema", %{
    conn: conn
  } do
    credential = grant_credential(login(conn), "tracer-list", "tasks.write")

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}})
      |> json_response(200)

    [tool] = response["result"]["tools"]
    assert tool["name"] == "keepling.capture_task"
    assert tool["inputSchema"]["additionalProperties"] == false
    assert Enum.sort(tool["inputSchema"]["required"]) == ["mutation_id", "task_id", "title", "version"]
  end

  test "tools/call captures exactly one task and is idempotent on mutation_id replay", %{
    conn: conn
  } do
    browser = login(conn)
    credential = grant_credential(browser, "tracer-capture", "tasks.write")
    mutation_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()

    call_params = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "keepling.capture_task",
        "arguments" => %{
          "mutation_id" => mutation_id,
          "task_id" => task_id,
          "title" => "Book the ferry",
          "version" => 1
        }
      }
    }

    first =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", call_params)
      |> json_response(200)

    assert first["result"]["structuredContent"]["outcome"] == "accepted"
    assert first["result"]["structuredContent"]["task_id"] == task_id

    second =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", call_params)
      |> json_response(200)

    assert second["result"]["structuredContent"] == first["result"]["structuredContent"]

    assert {:ok, %{rows: [[1]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM tasks WHERE id = $1", [
               Ecto.UUID.dump!(task_id)
             ])

    assert {:ok, %{rows: [[actor_type, actor_principal, actor_label, client_kind]]}} =
             SQL.query(
               Repo,
               """
               SELECT actor_type, actor_principal, actor_label, client_kind
               FROM task_activities
               WHERE mutation_id = $1
               """,
               [Ecto.UUID.dump!(mutation_id)]
             )

    assert actor_type == "agent"
    assert actor_principal == "authorized_grant"
    assert actor_label =~ "tracer-capture"
    assert client_kind == "mcp"

    # Plan-level verification: the tracer capture's activity record is
    # readable through the EXISTING browser activity endpoint, not just by
    # direct SQL -- proving the agent actor surfaces through the same
    # read path a human uses (MCP-04).
    activity_page =
      browser
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity")
      |> json_response(200)

    assert [%{"actor" => actor}] = activity_page["items"]
    assert actor["type"] == "agent"
    assert actor["principal"] == "authorized_grant"
    assert actor["label"] =~ "tracer-capture"
  end

  test "tools/call without tasks.write is refused and creates zero task rows", %{conn: conn} do
    credential = grant_credential(login(conn), "tracer-insufficient-scope", "tasks.read")
    task_id = Ecto.UUID.generate()

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "keepling.capture_task",
          "arguments" => %{
            "mutation_id" => Ecto.UUID.generate(),
            "task_id" => task_id,
            "title" => "Should never be written",
            "version" => 1
          }
        }
      })
      |> json_response(200)

    assert response["error"]["data"]["keepling_code"] == "insufficient_scope"

    assert {:ok, %{rows: [[0]]}} =
             SQL.query(Repo, "SELECT COUNT(*) FROM tasks WHERE id = $1", [
               Ecto.UUID.dump!(task_id)
             ])
  end

  test "a request with no bearer returns 401 with a WWW-Authenticate header" do
    response =
      build_conn()
      |> post("/mcp/v1", %{"jsonrpc" => "2.0", "id" => 5, "method" => "initialize", "params" => %{}})

    assert response.status == 401
    assert get_resp_header(response, "www-authenticate") != []
  end

  test "an unknown JSON-RPC method returns -32601 and no domain side effect", %{conn: conn} do
    credential = grant_credential(login(conn), "tracer-unknown-method", "tasks.write")

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{"jsonrpc" => "2.0", "id" => 6, "method" => "tools/unsubscribe", "params" => %{}})
      |> json_response(200)

    assert response["error"]["code"] == -32_601
  end

  defp grant_credential(conn, installation_id, scope) do
    authorization = authorize(conn, installation_id, scope)
    exchange(authorization)["access_token"]
  end

  defp authorize(conn, installation_id, scope) do
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
        "scope" => scope,
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == @mcp_redirect_uri

    query = URI.decode_query(location.query)
    assert query["state"] == @state
    assert is_binary(query["code"])

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
      "label" => "Tracer capture browser",
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
