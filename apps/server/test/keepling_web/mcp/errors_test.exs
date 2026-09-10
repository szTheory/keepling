defmodule KeeplingWeb.MCP.ErrorsTest do
  @moduledoc """
  05-05-PLAN.md Task 3: every error a model can receive is drawn from a
  closed vocabulary, is stable across runs, and is pinned by a golden
  vector. Iterates `KeeplingWeb.MCP.Errors.mcp_error_codes/0` against
  `packages/contracts/vectors/mcp-tools.json`'s `errors` map in both
  directions, so neither the code nor the vector can gain a member alone.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo
  alias KeeplingWeb.MCP.Errors

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "errors-test-state") |> Base.url_encode64(padding: false)
  @password String.duplicate("errors-test-password-", 12)

  @vectors_path Path.join([
                  __DIR__,
                  "..",
                  "..",
                  "..",
                  "..",
                  "..",
                  "packages",
                  "contracts",
                  "vectors",
                  "mcp-tools.json"
                ])
                |> Path.expand()

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-errors-test",
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

  test "every member of @mcp_error_codes has a vector entry, and every vector entry is a real member" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()
    vector_codes = vectors["errors"] |> Map.keys() |> Enum.sort()
    module_codes = Errors.mcp_error_codes() |> Enum.sort()

    assert module_codes == vector_codes
  end

  test "every closed error member renders byte-for-byte identical to the vector" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    for keepling_code <- Errors.mcp_error_codes() do
      expected = Map.fetch!(vectors["errors"], keepling_code)
      rendered = render(keepling_code, vectors)

      assert stringify(rendered) == Map.take(expected, ["code", "message", "data"]),
             "rendering for #{keepling_code} does not match the vector"
    end
  end

  test "a call carrying an unknown property produces the same error body across two calls", %{
    conn: conn
  } do
    browser = login(conn)
    credential = grant_credential(browser, "errors-repeat", "tasks.write")
    task_id = Ecto.UUID.generate()

    args = %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "title" => "Never written",
      "version" => 1,
      "priority" => "high"
    }

    first = call_tool(credential, "keepling.capture_task", args)
    second = call_tool(credential, "keepling.capture_task", args)

    assert first["error"] == second["error"]
    assert first["error"]["data"]["keepling_code"] == "invalid_command"
  end

  test "an unexpected internal failure maps to the single infrastructure member and exposes no internal detail" do
    rendered = Errors.infrastructure_failure()

    assert rendered.data.keepling_code == "service_unavailable"
    refute Map.has_key?(rendered.data, :stack)
    refute Map.has_key?(rendered.data, :reason)
    refute String.contains?(rendered.data.detail, "Postgrex")
    refute String.contains?(rendered.data.detail, "Ecto")
  end

  # Builds the exact same envelope shape a live call would produce, for
  # each closed member, using the SAME fixed inputs the vector's own
  # `http_problem_fixture` entries record -- so this test proves the
  # module and the vector describe the identical rendering, not two
  # independently-typed beliefs about it.
  defp render("insufficient_scope", _vectors), do: Errors.insufficient_scope()
  defp render("invalid_command", _vectors), do: Errors.invalid_params()
  defp render("unknown_tool", _vectors), do: Errors.unknown_tool()
  defp render("task_not_found", _vectors), do: Errors.task_not_found()
  defp render("no_match", _vectors), do: Errors.no_match()
  defp render("too_many_matches", _vectors), do: Errors.too_many_matches()
  defp render("preview_stale", _vectors), do: Errors.preview_stale()
  defp render("preview_expired", _vectors), do: Errors.preview_expired()
  defp render("preview_invalid", _vectors), do: Errors.preview_invalid()
  defp render("rate_limited", _vectors), do: Errors.rate_limited()
  defp render("service_unavailable", _vectors), do: Errors.infrastructure_failure()

  defp render("ambiguous_match", vectors) do
    candidates = get_in(vectors, ["errors", "ambiguous_match", "data", "candidates"])
    Errors.ambiguous_match(candidates)
  end

  defp render(code, vectors)
       when code in ~w(task_edit_conflict task_assignment_conflict task_lifecycle_conflict task_trash_conflict) do
    fixture = get_in(vectors, ["errors", code, "http_problem_fixture"])
    Errors.from_problem(fixture["status"], fixture)
  end

  defp stringify(map) do
    map
    |> Map.new(fn
      {:code, value} -> {"code", value}
      {:message, value} -> {"message", value}
      {:data, value} -> {"data", stringify_data(value)}
    end)
  end

  defp stringify_data(data) do
    Map.new(data, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp call_tool(credential, name, arguments) do
    build_conn()
    |> bearer(credential)
    |> post("/mcp/v1", %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => arguments}
    })
    |> json_response(200)
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
      "label" => "Errors test browser",
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
