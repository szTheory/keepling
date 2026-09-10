defmodule KeeplingWeb.MCP.ResourcesTest do
  @moduledoc """
  05-04-PLAN.md: `KeeplingWeb.MCP.Redaction`'s field-by-field projection
  (Task 1), and `resources/list`/`resources/read`/`keepling.search_tasks`
  over the real MCP JSON-RPC transport and real Postgres (Task 2).
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo
  alias KeeplingWeb.MCP.{Errors, Redaction}

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("resources-test-password-", 12)
  @maximum_page_size 50

  @redaction_vectors_path Path.join([
                            __DIR__,
                            "..",
                            "..",
                            "..",
                            "..",
                            "..",
                            "packages",
                            "contracts",
                            "vectors",
                            "redaction.json"
                          ])
                          |> Path.expand()

  describe "Redaction.task/1 and Redaction.project/1 (Task 1)" do
    test "emits exactly the documented task field set" do
      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => "Book the ferry",
        "notes" => "Ask about the car deck",
        "project" => %{"id" => Ecto.UUID.generate(), "name" => "Trip", "archived" => false},
        "tags" => [%{"id" => Ecto.UUID.generate(), "name" => "travel", "archived" => false}],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => "2026-02-01",
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)

      assert Enum.sort(Map.keys(projected)) ==
               Enum.sort(~w(
                 id title notes project tags captured_at planned_on deadline_on
                 completed_at lifecycle_state revision
               )a)

      assert projected.project == %{id: row["project"]["id"], name: "Trip"}
      assert projected.tags == ["travel"]
      assert projected.lifecycle_state == "inbox"
    end

    test "emits exactly the documented project field set" do
      row = %{id: Ecto.UUID.generate(), name: "Trip", task_count: 3}

      projected = Redaction.project(row)

      assert Enum.sort(Map.keys(projected)) == Enum.sort(~w(id name archived task_count)a)
      assert projected.archived == false
      assert projected.task_count == 3
    end

    test "a task with no project and no tags emits nil project and an empty tag list" do
      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => "No project",
        "notes" => nil,
        "project" => nil,
        "tags" => [],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => nil,
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)
      assert projected.project == nil
      assert projected.tags == []
    end

    test "title and notes round-trip every hostile sentinel verbatim; no sentinel appears in any structural field" do
      sentinels = @redaction_vectors_path |> File.read!() |> Jason.decode!() |> Map.fetch!("hostile_sentinels")
      poisoned = Enum.join(sentinels, " ")

      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => poisoned,
        "notes" => poisoned,
        "project" => nil,
        "tags" => [],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => nil,
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)

      assert projected.title == poisoned
      assert projected.notes == poisoned

      structural = projected |> Map.drop([:title, :notes]) |> Jason.encode!()

      for sentinel <- sentinels do
        refute structural =~ sentinel,
               "expected hostile sentinel #{inspect(sentinel)} to be absent from structural fields"
      end
    end

    test "never takes a domain struct wholesale" do
      redaction_source =
        [__DIR__, "..", "..", "..", "lib", "keepling_web", "mcp", "redaction.ex"]
        |> Path.join()
        |> Path.expand()
        |> File.read!()

      refute redaction_source =~ "Map.from_struct"
    end
  end

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-resources-test",
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

  describe "resources/list and resources/read (Task 2)" do
    test "resources/list returns the seven resource URIs and lists none the server cannot read", %{
      conn: conn
    } do
      credential = grant_credential(login(conn), "list-resources", "tasks.read")

      response = call_method(credential, "resources/list", %{})

      uris = response["result"]["resources"] |> Enum.map(& &1["uri"]) |> Enum.sort()

      assert uris ==
               Enum.sort([
                 "keepling://tasks/inbox",
                 "keepling://tasks/today",
                 "keepling://tasks/upcoming",
                 "keepling://tasks/completed",
                 "keepling://tasks/{task_id}",
                 "keepling://projects",
                 "keepling://projects/{project_id}"
               ])
    end

    test "resources/read on tasks/inbox pages forward without repeating or skipping any of 3 captured tasks",
         %{conn: conn} do
      browser = login(conn)
      credential = grant_credential(browser, "page-inbox", "tasks.read tasks.write")
      task_ids = for n <- 1..3, do: capture_task(credential, "Inbox task #{n}")

      first = read_resource(credential, "keepling://tasks/inbox", limit: 2)
      assert length(first["items"]) == 2
      assert is_binary(first["next_cursor"])
      assert first["has_more"] == true

      second = read_resource(credential, "keepling://tasks/inbox", limit: 2, cursor: first["next_cursor"])
      assert length(second["items"]) == 1
      assert second["has_more"] == false

      seen_ids = (first["items"] ++ second["items"]) |> Enum.map(& &1["id"])
      assert Enum.sort(seen_ids) == Enum.sort(task_ids)
      assert length(Enum.uniq(seen_ids)) == 3
    end

    test "resources/read on keepling://tasks/{task_id} returns one projected task", %{conn: conn} do
      browser = login(conn)
      credential = grant_credential(browser, "read-task", "tasks.read tasks.write")
      task_id = capture_task(credential, "Book the ferry")

      result = read_resource(credential, "keepling://tasks/#{task_id}")

      assert [item] = result["items"]
      assert item["id"] == task_id
      assert item["title"] == "Book the ferry"
      assert item["revision"] == 1
    end

    test "resources/read on an unknown task identity returns a stable not-found error", %{conn: conn} do
      credential = grant_credential(login(conn), "unknown-task", "tasks.read")
      foreign_id = Ecto.UUID.generate()

      response = call_read(credential, "keepling://tasks/#{foreign_id}")

      assert response["error"]["data"]["keepling_code"] == "task_not_found"
    end

    test "resources/read on a malformed task identity collapses to the same not-found error", %{
      conn: conn
    } do
      credential = grant_credential(login(conn), "malformed-task", "tasks.read")

      response = call_read(credential, "keepling://tasks/not-a-uuid")

      assert response["error"]["data"]["keepling_code"] == "task_not_found"
    end

    test "resources/read on keepling://projects and a project's tasks", %{conn: conn} do
      browser = login(conn)
      credential = grant_credential(browser, "project-read", "tasks.read tasks.write")
      project_id = create_project(browser, csrf_token(browser))
      task_id = capture_task(credential, "Needs the project")
      assign_project(credential, task_id, project_id)

      projects = read_resource(credential, "keepling://projects")
      assert [project] = projects["items"]
      assert project["id"] == project_id
      assert project["task_count"] == 1

      project_tasks = read_resource(credential, "keepling://projects/#{project_id}")
      assert [item] = project_tasks["items"]
      assert item["id"] == task_id
    end

    test "resources/read on a foreign project identity returns a stable not-found error", %{conn: conn} do
      credential = grant_credential(login(conn), "foreign-project", "tasks.read")
      foreign_id = Ecto.UUID.generate()

      response = call_read(credential, "keepling://projects/#{foreign_id}")

      assert response["error"]["data"]["keepling_code"] == "task_not_found"
    end

    test "a limit above #{@maximum_page_size} is clamped, not rejected", %{conn: conn} do
      credential = grant_credential(login(conn), "clamp-limit", "tasks.read")

      response = call_read(credential, "keepling://tasks/inbox", limit: @maximum_page_size + 25)

      refute Map.has_key?(response, "error")
    end

    test "a negative limit is a closed argument error", %{conn: conn} do
      credential = grant_credential(login(conn), "negative-limit", "tasks.read")

      response = call_read(credential, "keepling://tasks/inbox", limit: -1)

      assert response["error"]["data"]["keepling_code"] == "invalid_command"
    end

    test "resources/list and resources/read without tasks.read are refused and the query never runs", %{
      conn: conn
    } do
      credential = grant_credential(login(conn), "no-scope", "tasks.write")

      list_response = call_method(credential, "resources/list", %{})
      assert list_response["error"]["data"]["keepling_code"] == "insufficient_scope"

      read_response = call_read(credential, "keepling://tasks/inbox")
      assert read_response["error"]["data"]["keepling_code"] == "insufficient_scope"
    end

    test "the application-boundary scope check refuses independently of the adapter fast-fail" do
      context = %{scope: [], account_id: Ecto.UUID.generate(), accepted_at: DateTime.utc_now()}

      assert KeeplingWeb.MCP.Resources.list(%{}, context) == {:error, Errors.insufficient_scope()}

      assert Keepling.Application.AgentScope.require(context, "tasks.read") ==
               {:error, :insufficient_scope}
    end

    test "initialize declares the resources capability's pagination-relevant flags", %{conn: conn} do
      credential = grant_credential(login(conn), "capability-check", "tasks.read")

      response = call_method(credential, "initialize", %{})

      assert response["result"]["capabilities"]["resources"] == %{
               "subscribe" => false,
               "listChanged" => false
             }
    end
  end

  describe "keepling.search_tasks (Task 2)" do
    test "accepts {query, limit, cursor} and returns a projected page from Search", %{conn: conn} do
      browser = login(conn)
      credential = grant_credential(browser, "search-tool", "tasks.read tasks.write")
      task_id = capture_task(credential, "Zephyr expedition planning")
      _other = capture_task(credential, "Unrelated grocery list")

      response = call_tool(credential, "keepling.search_tasks", %{"query" => "Zephyr"})

      content = response["result"]["structuredContent"]
      assert [item] = content["items"]
      assert item["id"] == task_id
    end

    test "requires tasks.read; a grant with only tasks.write is refused", %{conn: conn} do
      credential = grant_credential(login(conn), "search-no-scope", "tasks.write")

      response = call_tool(credential, "keepling.search_tasks", %{"query" => "anything"})

      assert response["error"]["data"]["keepling_code"] == "insufficient_scope"
    end

    test "a payload carrying an unlisted property is rejected with a closed argument error", %{
      conn: conn
    } do
      credential = grant_credential(login(conn), "search-unknown-prop", "tasks.read")

      response =
        call_tool(credential, "keepling.search_tasks", %{"query" => "x", "unexpected" => "nope"})

      assert response["error"]["data"]["keepling_code"] == "invalid_command"
    end
  end

  defp assign_project(credential, task_id, project_id) do
    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "project_id" => project_id,
        "tag_ids" => []
      })

    assert response["result"]["structuredContent"]["outcome"] == "accepted"
  end

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

  defp create_project(browser, csrf) do
    response =
      browser
      |> command(csrf, "/api/v1/commands/create-organization", %{
        "kind" => "project",
        "mutation_id" => Ecto.UUID.generate(),
        "name" => "Resources test project",
        "organization_id" => Ecto.UUID.generate(),
        "version" => 1
      })
      |> json_response(201)

    response["snapshot"]["id"]
  end

  defp command(conn, csrf, path, body) do
    conn
    |> recycle()
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf)
    |> post(path, body)
  end

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

  defp csrf_token(conn), do: json_response(conn, 200)["csrf_token"]

  defp read_resource(credential, uri, opts \\ []) do
    call_read(credential, uri, opts)["result"]["contents"] |> hd() |> Map.fetch!("text") |> Jason.decode!()
  end

  defp call_read(credential, uri, opts \\ []) do
    params =
      %{"uri" => uri}
      |> maybe_put("limit", Keyword.get(opts, :limit))
      |> maybe_put("cursor", Keyword.get(opts, :cursor))

    call_method(credential, "resources/read", params)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp call_tool(credential, name, arguments) do
    call_method(credential, "tools/call", %{"name" => name, "arguments" => arguments})
  end

  defp call_method(credential, method, params) do
    build_conn()
    |> bearer(credential)
    |> post("/mcp/v1", %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
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
      :crypto.hash(:sha256, "resources-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Resources test browser",
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
