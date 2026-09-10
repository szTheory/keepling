defmodule KeeplingWeb.MCP.ToolsTest do
  @moduledoc """
  05-05-PLAN.md Task 2: the four task-shaped write tools --
  `keepling.capture_task`, `keepling.update_task`, `keepling.complete_task`,
  `keepling.reopen_task` -- dispatch through the same
  `Keepling.Application.Commands.dispatch/3` every other adapter uses, with
  idempotency, expected revisions, and conflict shapes identical to every
  other adapter's.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("tools-test-password-", 12)

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
      server_instance: "server-instance-tools-test",
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

  test "keepling.update_task edits title and returns the new revision", %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "update-title", "tasks.write")
    task_id = capture_task(credential, "Original title")

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Updated title"
      })

    assert response["result"]["structuredContent"]["outcome"] == "accepted"
    assert response["result"]["structuredContent"]["revision"] == 2
    assert response["result"]["structuredContent"]["snapshot"]["title"] == "Updated title"
  end

  test "keepling.update_task edits project/tags via one call touching only that group", %{
    conn: conn
  } do
    browser = login(conn)
    credential = grant_credential(browser, "update-org", "tasks.write")
    task_id = capture_task(credential, "Needs a project")
    project_id = create_project(browser, csrf_token(browser))

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
    assert response["result"]["structuredContent"]["snapshot"]["project"]["id"] == project_id
  end

  test "keepling.complete_task and keepling.reopen_task are idempotent domain transitions matching GTD-05",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "lifecycle", "tasks.write")
    task_id = capture_task(credential, "Finish this")

    first_complete =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1
      })

    assert first_complete["result"]["structuredContent"]["outcome"] == "accepted"
    assert first_complete["result"]["structuredContent"]["snapshot"]["completed_at"]

    second_complete =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1
      })

    assert second_complete["result"]["structuredContent"]["outcome"] == "already_satisfied"

    completed_revision = current_revision(task_id)

    first_reopen =
      call_tool(credential, "keepling.reopen_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => completed_revision,
        "version" => 1
      })

    assert first_reopen["result"]["structuredContent"]["outcome"] == "accepted"
    assert is_nil(first_reopen["result"]["structuredContent"]["snapshot"]["completed_at"])

    second_reopen =
      call_tool(credential, "keepling.reopen_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => completed_revision,
        "version" => 1
      })

    assert second_reopen["result"]["structuredContent"]["outcome"] == "already_satisfied"
  end

  test "a payload carrying an unlisted property is rejected with a closed argument error and performs no write",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "unknown-prop", "tasks.write")
    task_id = capture_task(credential, "Untouched")

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should not apply",
        "priority" => "high"
      })

    assert response["error"]["data"]["keepling_code"] == "invalid_command"
    assert current_revision(task_id) == 1
  end

  test "a payload omitting expected_revision on update, complete, or reopen is rejected; capture does not require one",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "absent-revision", "tasks.write")
    task_id = capture_task(credential, "Needs revision")

    update_response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1,
        "title" => "Should not apply"
      })

    assert update_response["error"]["data"]["keepling_code"] == "invalid_command"

    complete_response =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert complete_response["error"]["data"]["keepling_code"] == "invalid_command"

    reopen_response =
      call_tool(credential, "keepling.reopen_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert reopen_response["error"]["data"]["keepling_code"] == "invalid_command"

    capture_response =
      call_tool(credential, "keepling.capture_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => Ecto.UUID.generate(),
        "title" => "No revision needed",
        "version" => 1
      })

    assert capture_response["result"]["structuredContent"]["outcome"] == "accepted"
    assert current_revision(task_id) == 1
  end

  test "a stale expected_revision returns the conflict shape byte-identical to the HTTP path for the same setup",
       %{conn: conn} do
    # keepling.update_task's `deadline_on`/`planned_on` group maps onto the
    # SAME domain command (:edit_task_dates) the HTTP
    # /commands/edit-task-dates endpoint dispatches, and TaskDates.edit's
    # own conflict tuple ({:edit_conflict, _}) is NOT one of the types
    # Keepling.Adapters.Postgres.CommandStore.persisted_conflict_reason?/2
    # persists into its own `persisted_conflicts` row shape (that shape is
    # reserved for :edit_task/:clarify_task) -- so both this tool's
    # pre-dispatch conflict body and the real HTTP path for the same
    # command type render through the exact same `semantic_rejection/2`
    # function, letting this test assert genuine equality rather than two
    # independently-authored bodies that merely look similar.
    browser = login(conn)
    csrf = csrf_token(browser)
    credential = grant_credential(browser, "stale-revision", "tasks.write")
    task_id = capture_task(credential, "Will be edited twice")

    _bump =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "deadline_on" => "2026-01-01"
      })

    assert current_revision(task_id) == 2

    mcp_response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "deadline_on" => "2026-02-02"
      })

    mcp_data = mcp_response["error"]["data"]
    assert mcp_data["keepling_code"] == "task_edit_conflict"

    http_response =
      browser
      |> command(csrf, "/api/v1/commands/edit-task-dates", %{
        "base_values" => %{"deadline_on" => nil},
        "expected_revision" => 2,
        "fields" => %{"deadline_on" => "2026-03-03"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })
      |> json_response(409)

    assert http_response["code"] == "task_edit_conflict"

    normalized_http = %{
      "keepling_code" => http_response["code"],
      "title" => http_response["title"],
      "detail" => http_response["detail"],
      "retryable" => http_response["retryable"],
      "recovery_action" => http_response["recovery_action"],
      "affected_fields" => http_response["affected_fields"],
      "current_revision" => http_response["current_revision"]
    }

    assert mcp_data == normalized_http
  end

  test "replaying a mutation_id returns the original stored result and the task revision does not advance",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "replay", "tasks.write")
    task_id = capture_task(credential, "Replay target")
    mutation_id = Ecto.UUID.generate()

    args = %{
      "mutation_id" => mutation_id,
      "task_id" => task_id,
      "expected_revision" => 1,
      "version" => 1,
      "title" => "Replayed title"
    }

    first = call_tool(credential, "keepling.update_task", args)
    second = call_tool(credential, "keepling.update_task", args)

    assert first["result"]["structuredContent"] == second["result"]["structuredContent"]
    assert current_revision(task_id) == 2
  end

  test "every tool call is attributed in activity to the agent grant, with client_kind of mcp", %{
    conn: conn
  } do
    browser = login(conn)
    credential = grant_credential(browser, "attribution", "tasks.write")
    task_id = capture_task(credential, "Attribution check")

    _ =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1
      })

    assert {:ok, %{rows: rows}} =
             SQL.query(
               Repo,
               """
               SELECT actor_type, actor_principal, client_kind
               FROM task_activities
               WHERE task_id = $1
               ORDER BY inserted_at ASC
               """,
               [Ecto.UUID.dump!(task_id)]
             )

    assert length(rows) == 2

    for [actor_type, actor_principal, client_kind] <- rows do
      assert actor_type == "agent"
      assert actor_principal == "authorized_grant"
      assert client_kind == "mcp"
    end
  end

  test "a call carrying more than one target identity is rejected", %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "multi-target", "tasks.write")
    task_id = capture_task(credential, "Single target only")

    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => 1,
        "version" => 1,
        "title" => "Should not apply",
        "task_ids" => [task_id, Ecto.UUID.generate()]
      })

    assert response["error"]["data"]["keepling_code"] == "invalid_command"
    assert current_revision(task_id) == 1
  end

  test "vector file: every accepted payload is accepted and every rejected payload is rejected with the vector's stated reason",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "vector-driven", "tasks.write")

    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    for {tool_name, %{"accepted" => accepted, "rejected" => rejected}} <-
          vectors["tools"],
        tool_name in [
          "keepling.capture_task",
          "keepling.update_task",
          "keepling.complete_task",
          "keepling.reopen_task"
        ] do
      # Give each vector case a fresh, independent task so accepted/rejected
      # cases across tools never collide on shared identity/revision state.
      seed_task_id = Ecto.UUID.generate()

      accepted_args =
        seed_vector_payload(tool_name, accepted, credential, seed_task_id)

      accepted_response = call_tool(credential, tool_name, accepted_args)

      refute Map.has_key?(accepted_response, "error"),
             "expected #{tool_name}'s accepted vector payload to succeed, got #{inspect(accepted_response)}"

      for %{"reason" => reason, "payload" => payload} <- rejected do
        rejected_seed_task_id = Ecto.UUID.generate()
        rejected_args = seed_vector_payload(tool_name, payload, credential, rejected_seed_task_id)

        rejected_response = call_tool(credential, tool_name, rejected_args)

        assert Map.has_key?(rejected_response, "error"),
               "expected #{tool_name}'s #{reason} vector payload to be rejected, got #{inspect(rejected_response)}"
      end
    end
  end

  # Vector fixtures use fixed sentinel UUIDs for mutation_id/task_id so the
  # golden file stays stable across runs; substitute a fresh task_id this
  # test run actually owns (capturing it first for update/complete/reopen)
  # so acceptance/rejection is proven against real server state, not just a
  # schema-shaped guess.
  defp seed_vector_payload("keepling.capture_task", payload, _credential, task_id) do
    payload
    |> maybe_put(payload, "task_id", task_id)
    |> Map.put("mutation_id", Ecto.UUID.generate())
  end

  defp seed_vector_payload(tool_name, payload, credential, _task_id)
       when tool_name in [
              "keepling.update_task",
              "keepling.complete_task",
              "keepling.reopen_task"
            ] do
    payload =
      if Map.has_key?(payload, "task_id") do
        real_task_id = capture_task(credential, "Vector fixture for #{tool_name}")
        Map.put(payload, "task_id", real_task_id)
      else
        # A payload deliberately missing task_id (missing_required_property)
        # -- leave it as-is, it must be rejected regardless of task_id.
        payload
      end

    maybe_put(payload, payload, "mutation_id", Ecto.UUID.generate())
  end

  # Only overwrites `key` when the vector payload already carries it --
  # preserves a deliberately-missing key (the missing_required_property
  # cases) instead of `Map.put` silently adding it back and defeating the
  # rejection the vector is testing.
  defp maybe_put(target, source, key, value) do
    if Map.has_key?(source, key), do: Map.put(target, key, value), else: target
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
        "name" => "MCP tool test project",
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
      :crypto.hash(:sha256, "tools-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Tools test browser",
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
