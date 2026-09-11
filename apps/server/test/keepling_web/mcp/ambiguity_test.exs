defmodule KeeplingWeb.MCP.AmbiguityTest do
  @moduledoc """
  05-06-PLAN.md Task 2: under-determination is a refusal, not a guess.
  `Keepling.Application.TaskAddressing.resolve/3` is identity-only;
  `keepling.update_task` -- and by construction every other identity-
  addressing write tool -- refuses a phrase-shaped `task_id` with one of
  three distinct closed errors (`no_match`, `ambiguous_match`,
  `too_many_matches`) and performs ZERO mutation in every case, proven
  here by comparing task revisions before and after each refusal, not
  merely by inspecting the response body.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Application.TaskAddressing
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("ambiguity-test-password-", 12)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-ambiguity-test",
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

  # -- TaskAddressing.resolve/3, called directly -------------------------

  test "resolve/3 given a map containing a title or any free-text key returns a closed argument error without querying anything" do
    context = %{account_id: Ecto.UUID.generate()}

    assert TaskAddressing.resolve(context, %{title: "Buy milk"}, RaisingPort) ==
             {:error, :invalid_command}

    assert TaskAddressing.resolve(
             context,
             %{task_id: Ecto.UUID.generate(), title: "Buy milk"},
             RaisingPort
           ) == {:error, :invalid_command}

    assert TaskAddressing.resolve(context, %{}, RaisingPort) == {:error, :invalid_command}
  end

  test "resolve/3 given exactly task_id accepts no other addressing key and never crashes on a non-identity-shaped value" do
    context = %{account_id: Ecto.UUID.generate()}

    assert TaskAddressing.resolve(context, %{task_id: "not a uuid at all"}, RaisingPort) ==
             {:error, :not_found}
  end

  # -- classify_match_count/2: structural, never receives candidate content

  test "classify_match_count/2 takes only an integer count" do
    limit = TaskAddressing.candidate_limit()

    assert TaskAddressing.classify_match_count(0, limit) == :no_match
    assert TaskAddressing.classify_match_count(1, limit) == :ambiguous_match
    assert TaskAddressing.classify_match_count(limit, limit) == :ambiguous_match
    assert TaskAddressing.classify_match_count(limit + 1, limit) == :too_many_matches

    assert_raise FunctionClauseError, fn ->
      TaskAddressing.classify_match_count("not an integer", limit)
    end
  end

  # -- End-to-end: a phrase where an identity belongs -------------------

  test "a phrase matching zero tasks returns no_match, and the task rows are unchanged",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "no-match", "tasks.write")
    task_id = capture_task(credential, "Unrelated Item")
    before_revision = current_revision(task_id)

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => "term-that-matches-absolutely-nothing-zzqx",
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should never apply"
      })

    assert response["error"]["data"]["keepling_code"] == "no_match"
    assert current_revision(task_id) == before_revision
  end

  test "a phrase matching between two and the candidate limit tasks returns ambiguous_match with the bounded candidate set, and task revisions are unchanged",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "ambiguous", "tasks.write")

    task_ids =
      for n <- 1..3, do: capture_task(credential, "Gadget assembly step #{n}")

    revisions_before = Enum.map(task_ids, &current_revision/1)

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => "Gadget",
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should never apply"
      })

    assert response["error"]["data"]["keepling_code"] == "ambiguous_match"
    candidates = response["error"]["data"]["candidates"]
    assert is_list(candidates)
    assert length(candidates) == 3
    assert Enum.all?(candidates, &(&1["id"] in task_ids))

    revisions_after = Enum.map(task_ids, &current_revision/1)
    assert revisions_before == revisions_after
  end

  test "a phrase matching more than the candidate limit returns too_many_matches, and task revisions are unchanged",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "too-many", "tasks.write")

    limit = TaskAddressing.candidate_limit()

    task_ids =
      for n <- 1..(limit + 2), do: capture_task(credential, "Widget order line #{n}")

    revisions_before = Enum.map(task_ids, &current_revision/1)

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => "Widget",
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should never apply"
      })

    assert response["error"]["data"]["keepling_code"] == "too_many_matches"

    revisions_after = Enum.map(task_ids, &current_revision/1)
    assert revisions_before == revisions_after
  end

  test "keepling.complete_task and keepling.reopen_task also refuse a phrase-shaped task_id via the same disambiguation path",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "lifecycle-phrase", "tasks.write")
    task_id = capture_task(credential, "Solo completable task")
    before_revision = current_revision(task_id)

    complete_response =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => "no-such-phrase-matches-anything-here",
        "expected_revision" => 1,
        "version" => 1
      })

    assert complete_response["error"]["data"]["keepling_code"] == "no_match"

    reopen_response =
      call_tool(credential, "keepling.reopen_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => "no-such-phrase-matches-anything-here",
        "expected_revision" => 1,
        "version" => 1
      })

    assert reopen_response["error"]["data"]["keepling_code"] == "no_match"
    assert current_revision(task_id) == before_revision
  end

  test "a payload carrying an addressing key resolve/3 does not accept is rejected before any query runs",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "extra-key", "tasks.write")
    task_id = capture_task(credential, "Untouched by extra key")

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should not apply",
        "task_query" => "Untouched"
      })

    assert response["error"]["data"]["keepling_code"] == "invalid_command"
    assert current_revision(task_id) == 1
  end

  # -- helpers ------------------------------------------------------------

  defp capture_task(credential, title) do
    task_id = Ecto.UUID.generate()

    response =
      call_tool(credential, "keepling.capture_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => title,
        "version" => 1
      })

    assert response["result"]["structuredContent"]["outcome"] == "accepted"
    task_id
  end

  defp current_revision(task_id) do
    {:ok, %{rows: [[revision]]}} =
      SQL.query(Repo, "SELECT revision FROM tasks WHERE id = $1", [Ecto.UUID.dump!(task_id)])

    revision
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
      :crypto.hash(:sha256, "ambiguity-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Ambiguity test browser",
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
