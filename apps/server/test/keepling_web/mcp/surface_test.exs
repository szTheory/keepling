defmodule KeeplingWeb.MCP.SurfaceTest do
  @moduledoc """
  05-04-PLAN.md Task 3: binds `docs/architecture/MCP-SURFACE.md`'s
  implemented-method table to `KeeplingWeb.MCP.Dispatch`'s closed
  `@methods` list, and proves a named not-implemented method returns the
  standard method-not-found code with no domain side effect.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @surface_doc_path Path.join([
                       __DIR__,
                       "..",
                       "..",
                       "..",
                       "..",
                       "..",
                       "docs",
                       "architecture",
                       "MCP-SURFACE.md"
                     ])
                     |> Path.expand()

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("surface-test-password-", 12)

  test "docs/architecture/MCP-SURFACE.md is tracked" do
    assert File.exists?(@surface_doc_path)
  end

  test "the document's implemented-method set equals KeeplingWeb.MCP.Dispatch's closed @methods list exactly" do
    documented = implemented_methods_from_doc()

    assert documented != [],
           "expected at least one method marked \"implemented\" in #{@surface_doc_path}"

    assert Enum.sort(documented) == Enum.sort(KeeplingWeb.MCP.Dispatch.implemented_methods())
  end

  test "every method family listed in the document is marked implemented or deliberately not implemented, with a reason" do
    content = File.read!(@surface_doc_path)
    rows = coverage_table_rows(content)

    assert rows != [], "expected the Method and capability coverage table to have rows"

    for {status, reason} <- rows do
      assert status in ["implemented", "not_implemented", "not_implemented (client capability)"],
             "unexpected status #{inspect(status)}"

      assert String.trim(reason) != "", "every row must carry a non-empty reason"
    end

    for family <- [
          "initialize",
          "ping",
          "resources/list",
          "resources/read",
          "resources/templates/list",
          "resources/subscribe",
          "resources/unsubscribe",
          "tools/list",
          "tools/call",
          "prompts/list",
          "prompts/get",
          "completion/complete",
          "logging/setLevel",
          "roots",
          "sampling",
          "Notification families"
        ] do
      assert content =~ family, "expected #{@surface_doc_path} to cover #{inspect(family)}"
    end
  end

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-surface-test",
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

  test "calling a named not-implemented method returns the standard method-not-found code with no domain side effect",
       %{conn: conn} do
    credential = grant_credential(login(conn), "surface-not-implemented", "tasks.read tasks.write")

    response =
      build_conn()
      |> bearer(credential)
      |> post("/mcp/v1", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "resources/templates/list",
        "params" => %{}
      })
      |> json_response(200)

    assert response["error"]["code"] == -32_601

    assert {:ok, %{rows: [[0]]}} = SQL.query(Repo, "SELECT COUNT(*) FROM tasks", [])
  end

  # Parses the "Method and capability coverage" markdown table, returning
  # only the exact backtick-quoted method strings marked "implemented" --
  # `roots`/`sampling`/notification-family rows are never backtick-wrapped
  # single JSON-RPC method strings AND are always `not_implemented`, so
  # they never enter this set regardless of formatting.
  defp implemented_methods_from_doc do
    @surface_doc_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\|\s*`([a-zA-Z0-9_\/]+)`\s*\|\s*implemented\s*\|/, line) do
        [_full, method] -> [method]
        nil -> []
      end
    end)
  end

  defp coverage_table_rows(content) do
    content
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(
             ~r/^\|\s*(.+?)\s*\|\s*(implemented|not_implemented(?:\s*\(client capability\))?)\s*\|\s*(.+?)\s*\|$/,
             line
           ) do
        [_full, _method, status, reason] -> [{status, reason}]
        _no_match -> []
      end
    end)
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
        "state" => challenge_state(installation_id)
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == @mcp_redirect_uri

    query = URI.decode_query(location.query)
    assert query["state"] == challenge_state(installation_id)
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

  defp challenge_state(installation_id),
    do:
      :crypto.hash(:sha256, "surface-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Surface test browser",
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
