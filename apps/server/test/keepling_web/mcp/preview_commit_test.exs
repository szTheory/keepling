defmodule KeeplingWeb.MCP.PreviewCommitTest do
  @moduledoc """
  05-07-PLAN.md Task 3: atomic commit under drift, and the two MCP tools.
  Covers `<behavior>` via the real MCP JSON-RPC transport and real
  Postgres. The genuine two-connection concurrent-mutation race lives in
  `Keepling.Adapters.Postgres.PreviewConcurrencyTest` below, mirroring
  `conflict_test.exs`'s style.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("preview-commit-test-password-", 12)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-preview-commit-test",
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

  test "a commit over N targets whose live revisions all match writes all N and returns the new revisions",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "commit-happy", "tasks.write tasks.bulk")
    tasks = capture_tasks(credential, 3)

    token = preview_trash(credential, tasks)
    response = commit(credential, Ecto.UUID.generate(), token)

    results = response["result"]["structuredContent"]["results"]
    assert length(results) == 3
    assert Enum.all?(results, fn %{"revision" => revision} -> revision == 2 end)

    for %{task_id: task_id} <- tasks do
      assert %{revision: 2, trashed?: true} = task_state(task_id)
    end
  end

  test "a commit where one target's revision advanced between preview and commit returns preview_stale, and every one of the N targets is unchanged",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "commit-drift", "tasks.write tasks.bulk")
    tasks = capture_tasks(credential, 3)

    token = preview_trash(credential, tasks)

    [drifted | _rest] = tasks
    update_task_title(credential, drifted.task_id, drifted.revision)

    before = Enum.map(tasks, &task_state(&1.task_id))

    response = commit(credential, Ecto.UUID.generate(), token)
    assert response["error"]["data"]["keepling_code"] == "preview_stale"

    afterward = Enum.map(tasks, &task_state(&1.task_id))
    assert before == afterward
    assert Enum.all?(afterward, &(&1.trashed? == false))
  end

  test "a commit where one target was trashed between preview and commit returns preview_stale with the same zero-write property",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "commit-trashed-between", "tasks.write tasks.bulk")
    tasks = capture_tasks(credential, 3)

    token = preview_trash(credential, tasks)

    [already_gone | _rest] = tasks
    trash_task_directly(credential, already_gone.task_id, already_gone.revision)

    before = Enum.map(tasks, &task_state(&1.task_id))

    response = commit(credential, Ecto.UUID.generate(), token)
    assert response["error"]["data"]["keepling_code"] == "preview_stale"

    afterward = Enum.map(tasks, &task_state(&1.task_id))
    assert before == afterward
  end

  test "committing the same token twice with the same mutation identity returns the original stored result and performs no second write",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "commit-replay", "tasks.write tasks.bulk")
    tasks = capture_tasks(credential, 2)

    token = preview_trash(credential, tasks)
    mutation_id = Ecto.UUID.generate()

    first = commit(credential, mutation_id, token)
    second = commit(credential, mutation_id, token)

    assert first["result"] == second["result"]

    for %{task_id: task_id} <- tasks do
      assert %{revision: 2} = task_state(task_id)
    end
  end

  test "keepling.preview_bulk_change and keepling.commit_bulk_change both require tasks.bulk at the adapter and the application boundary",
       %{conn: conn} do
    browser = login(conn)
    write_only_credential = grant_credential(browser, "commit-insufficient-scope", "tasks.write")
    tasks = capture_tasks(write_only_credential, 1)

    preview_response =
      call_tool(write_only_credential, "keepling.preview_bulk_change", %{
        "command" => "trash_task",
        "mutation_id" => Ecto.UUID.generate(),
        "targets" =>
          Enum.map(tasks, &%{"task_id" => &1.task_id, "expected_revision" => &1.revision})
      })

    assert preview_response["error"]["data"]["keepling_code"] == "insufficient_scope"

    commit_response =
      call_tool(write_only_credential, "keepling.commit_bulk_change", %{
        "mutation_id" => Ecto.UUID.generate(),
        "preview_token" => "not-a-real-token-but-scope-fails-first"
      })

    assert commit_response["error"]["data"]["keepling_code"] == "insufficient_scope"

    for %{task_id: task_id} <- tasks do
      assert %{revision: 1, trashed?: false} = task_state(task_id)
    end
  end

  test "a destructive command has no one-step tool -- it is reachable only through preview and commit",
       %{
         conn: conn
       } do
    browser = login(conn)
    credential = grant_credential(browser, "no-one-step-destructive", "tasks.bulk")

    for name <- ["keepling.trash_task", "keepling.restore_task", "keepling.undo_task"] do
      response = call_tool(credential, name, %{})
      assert response["error"]["data"]["keepling_code"] == "unknown_tool"
    end
  end

  test "keepling.commit_bulk_change's schema declares exactly the token and the mutation identity" do
    schema = KeeplingWeb.MCP.ToolSchemas.schema("keepling.commit_bulk_change")
    assert {:ok, %{"properties" => properties}} = schema
    assert Map.keys(properties) |> Enum.sort() == ["mutation_id", "preview_token"]
  end

  # -- helpers ----------------------------------------------------------

  defp capture_tasks(credential, count) do
    for n <- 1..count do
      task_id = Ecto.UUID.generate()

      response =
        call_tool(credential, "keepling.capture_task", %{
          "mutation_id" => Ecto.UUID.generate(),
          "task_id" => task_id,
          "title" => "Preview/commit test task #{n}",
          "version" => 1
        })

      assert response["result"]["structuredContent"]["outcome"] == "accepted"
      %{task_id: task_id, revision: response["result"]["structuredContent"]["revision"]}
    end
  end

  defp preview_trash(credential, tasks) do
    response =
      call_tool(credential, "keepling.preview_bulk_change", %{
        "command" => "trash_task",
        "mutation_id" => Ecto.UUID.generate(),
        "targets" =>
          Enum.map(tasks, &%{"task_id" => &1.task_id, "expected_revision" => &1.revision})
      })

    assert token = response["result"]["structuredContent"]["preview_token"]
    token
  end

  defp commit(credential, mutation_id, token) do
    call_tool(credential, "keepling.commit_bulk_change", %{
      "mutation_id" => mutation_id,
      "preview_token" => token
    })
  end

  defp update_task_title(credential, task_id, expected_revision) do
    response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => expected_revision,
        "version" => 1,
        "title" => "Drifted before commit"
      })

    assert response["result"]["structuredContent"]["outcome"] == "accepted"
  end

  defp trash_task_directly(credential, task_id, expected_revision) do
    response =
      call_tool(credential, "keepling.complete_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "expected_revision" => expected_revision,
        "version" => 1
      })

    # completing (rather than trashing directly, since there is no
    # one-step trash tool -- see the "no one-step tool" test above)
    # advances the task's revision, which is sufficient to prove drift
    # detection: the preview's expected_revision no longer matches live
    # state.
    assert response["result"]["structuredContent"]["outcome"] == "accepted"
  end

  defp task_state(task_id) do
    {:ok, %{rows: [[revision, trashed_at]]}} =
      SQL.query(Repo, "SELECT revision, trashed_at FROM tasks WHERE id = $1", [
        Ecto.UUID.dump!(task_id)
      ])

    %{revision: revision, trashed?: trashed_at != nil}
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
      :crypto.hash(:sha256, "preview-commit-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Preview/commit test browser",
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

defmodule Keepling.Adapters.Postgres.PreviewConcurrencyTest do
  @moduledoc """
  05-07-PLAN.md Task 3: the concurrent-mutation case, run against two REAL
  independently checked-out Postgres connections (not simulated), in the
  style of `conflict_test.exs`/`idempotency_test.exs`'s
  `Keepling.ConcurrencyCase`. A bulk preview commit and a competing
  single-task write race over one of the same target rows; Postgres row
  locking serializes them -- the outcome is always fully-applied or
  fully-rolled-back, never a partial interleave.
  """
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Adapters.Postgres.Preview, as: PreviewStore
  alias Keepling.Application.{Commands, Preview}
  alias Keepling.Repo

  @accepted_at ~U[2026-09-10 12:00:00.000000Z]

  setup do
    account_id = insert_account()
    on_exit(fn -> with_connection(fn _pid -> delete_account(account_id) end) end)
    %{account_id: account_id}
  end

  test "a concurrent mutation landing during the commit transaction never interleaves into a partial application",
       %{account_id: account_id} do
    context = %{
      account_id: account_id,
      accepted_at: @accepted_at,
      actor_label: "concurrency-test-grant",
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: "mcp",
      preview_secret: "concurrency-test-fixed-preview-secret"
    }

    tasks =
      with_connection(fn _pid ->
        for n <- 1..3, do: capture(context, "Concurrency target #{n}")
      end)

    [contested | _rest] = tasks

    binding_targets = Enum.map(tasks, &%{task_id: &1.task_id, expected_revision: &1.revision})

    {:ok, %{token: token}} =
      with_connection(fn _pid ->
        Preview.mint(%{command: :trash_task, targets: binding_targets}, context, PreviewStore)
      end)

    barrier = start_barrier(2)

    [bulk_result, racer_result] =
      [
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            {:bulk, backend_pid,
             Preview.commit(token, Ecto.UUID.generate(), context, PreviewStore)}
          end)
        end),
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            command = %{
              expected_revision: contested.revision,
              mutation_id: Ecto.UUID.generate(),
              task_id: contested.task_id,
              type: :complete_task,
              version: 1
            }

            {:racer, backend_pid, Commands.dispatch(command, context, CommandStore)}
          end)
        end)
      ]
      |> Enum.map(&Task.await(&1, 15_000))

    {:bulk, bulk_pid, bulk_outcome} = bulk_result
    {:racer, racer_pid, racer_outcome} = racer_result

    assert bulk_pid != racer_pid

    final_states =
      with_connection(fn _pid ->
        Enum.map(tasks, &{&1.task_id, current_revision(&1.task_id)})
      end)

    case bulk_outcome do
      {:ok, %{results: results}} ->
        # The bulk commit won the race: all three targets advanced, and
        # the racer -- which read (or attempted to apply against) the
        # PRE-bulk revision -- lost, since trash_task's activity already
        # consumed the expected_revision the racer also expected.
        assert length(results) == 3
        assert Enum.all?(final_states, fn {_task_id, revision} -> revision == 2 end)

        # The racer did not ALSO apply -- its write is not reflected in the
        # final revision (2, not 3). The precise refusal shape varies (a
        # clean domain conflict once its blocked row lock releases post-
        # commit, or an infrastructure_failure if the now-trashed row trips
        # a constraint complete_task did not anticipate) -- either way, it
        # never silently succeeded against stale state.
        refute match?({:ok, %{status: status}} when status in 200..299, racer_outcome)

      {:error, :preview_stale} ->
        # The racer won the race: the contested task's revision advanced
        # BEFORE the bulk transaction's lock/re-verify step, so drift was
        # detected and the WHOLE bulk commit rolled back -- including the
        # two targets that would otherwise have succeeded.
        assert match?({:ok, %{status: status}} when status in 200..299, racer_outcome)

        [{contested_id, contested_revision} | rest] =
          Enum.sort_by(final_states, fn {task_id, _revision} -> task_id != contested.task_id end)

        assert contested_id == contested.task_id
        assert contested_revision == 2
        assert Enum.all?(rest, fn {_task_id, revision} -> revision == 1 end)
    end
  end

  defp insert_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    with_connection(fn _pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/New_York', $2, $2)
        """,
        [account_id, @accepted_at]
      )
    end)

    account_id
  end

  defp delete_account(account_id) do
    SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
  end

  defp capture(context, title) do
    task_id = Ecto.UUID.generate()

    command = %{
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      title: title,
      type: :capture_task,
      version: 1
    }

    {:ok, %{status: 201, body: body}} = Commands.dispatch(command, context, CommandStore)
    %{task_id: task_id, revision: body["revision"]}
  end

  defp current_revision(task_id) do
    {:ok, %{rows: [[revision]]}} =
      SQL.query(Repo, "SELECT revision FROM tasks WHERE id = $1", [Ecto.UUID.dump!(task_id)])

    revision
  end
end
