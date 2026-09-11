defmodule KeeplingWeb.AgentAuthorizationTest do
  @moduledoc """
  T-05-14 / WINDOWS #72: the SCOPE half of the agent authorization boundary.

  05-13 closed the `client_kind` half on `:device_grant_authenticated`. This
  covers the other factor of the same product. Scope outside `/mcp/v1` was not
  merely unchecked -- it was NOT CARRIED: `authenticate_device_grant/1`
  assigned `current_client_kind` and never `current_scope`, so no route behind
  `:client_authenticated` or `:client_mutation` could have checked it even if
  it had tried, and `CommandController` contained no reference to scope.

  Found by live probe against a real server with real PKCE grants, before the
  fix: a `tasks.read`-only grant POSTed `/api/v1/commands/capture-task` and got
  201 persisted, and `/api/v1/commands/trash-task` and got 200 with the owner's
  subsequent read returning 404 -- while the SAME token at `/mcp/v1` was
  refused `insufficient_scope`. The mirror held too: a `tasks.write`-only grant
  read `/api/v1/search` and `/api/v1/projects` and got 200.

  Every refusal here is asserted as EXACTLY 403, never as "not 200": a deleted
  route answers 404 and a broken server answers 500, and accepting either as
  evidence of a refusal would hollow this file out the day someone moves a
  route. Every refusal is also paired with a control proving the same
  credential still reaches what its grant does cover -- without which these
  assertions would pass equally well against a revoked token, i.e. against
  credential breakage rather than a boundary.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @now ~U[2026-09-11 12:00:00.000000Z]
  @refusal %{
    "code" => "insufficient_scope",
    "recovery_action" => "reauthorize_device",
    "retryable" => false,
    "status" => 403,
    "title" => "Insufficient scope",
    "type" => "/problems/insufficient_scope"
  }

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-agent-authorization",
      redirect_uris: %{
        "electron" => ["keepling://auth/callback"],
        "mcp" => ["https://mcp.invalid/callback"]
      }
    )

    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()
    install_epoch()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    {:ok, session} =
      Keepling.Accounts.create_session(account_id, label: "Owner browser", client_kind: "web")

    %{
      account_id: account_id,
      bulk: create_grant(account_id, "mcp", "mcp-bulk", scope: ["tasks.bulk"]),
      read: create_grant(account_id, "mcp", "mcp-read", scope: ["tasks.read"]),
      session: session,
      unscoped: create_grant(account_id, "mcp", "mcp-unscoped", scope: []),
      write: create_grant(account_id, "mcp", "mcp-write", scope: ["tasks.write"])
    }
  end

  test "a tasks.read-only agent grant cannot capture a task, and nothing is persisted", %{
    read: read,
    session: session,
    write: write
  } do
    canary = "read-only grant must not capture #{Ecto.UUID.generate()}"

    response =
      build_conn()
      |> bearer(read)
      |> post("/api/v1/commands/capture-task", capture_body(canary))

    assert @refusal == json_response(response, 403)
    assert task_count(canary) == 0

    # CONTROL 1: the credential is not merely broken -- a grant that DOES
    # carry tasks.write captures through the same route in the same second.
    accepted = "write grant may capture #{Ecto.UUID.generate()}"

    assert %{"outcome" => "accepted"} =
             build_conn()
             |> bearer(write)
             |> post("/api/v1/commands/capture-task", capture_body(accepted))
             |> json_response(201)

    assert task_count(accepted) == 1

    # CONTROL 2: the owner's browser session is untouched by any of this.
    owned = "the owner may capture #{Ecto.UUID.generate()}"

    assert %{"outcome" => "accepted"} =
             build_conn()
             |> browser_session(session)
             |> trusted_origin()
             |> post("/api/v1/commands/capture-task", capture_body(owned))
             |> json_response(201)

    assert task_count(owned) == 1
  end

  test "no agent grant can trash a task, whatever it is scoped, while the owner still can", %{
    bulk: bulk,
    read: read,
    session: session,
    write: write
  } do
    # The sharpest edge of the probe: `tasks.read` alone trashed a task and
    # the owner's next read of it returned 404.
    task_id = owner_capture(session, "a task an agent must not trash")

    for {label, credential} <- [{"read", read}, {"write", write}, {"bulk", bulk}] do
      response =
        build_conn()
        |> bearer(credential)
        |> post("/api/v1/commands/trash-task", lifecycle_body(task_id))

      assert @refusal == json_response(response, 403), "the #{label} grant was not refused"

      # Scored on final state, not on the status alone: the task is still
      # readable by its owner after each refusal.
      assert %{"id" => ^task_id} =
               build_conn()
               |> browser_session(session)
               |> get("/api/v1/tasks/#{task_id}")
               |> json_response(200)
    end

    # `tasks.bulk` is refused here too, and that is the point rather than an
    # accident: an agent reaches the closed D-19 destructive vocabulary only
    # through preview + commit, a two-step bound to exact targets and their
    # expected revisions (D-17, D-18). A one-step HTTP trash would route
    # around the safeguard the bulk path exists to impose.

    # CONTROL: the route itself works. The refusals above are a property of
    # the credential, not of a broken or missing endpoint.
    assert %{"outcome" => "accepted"} =
             build_conn()
             |> browser_session(session)
             |> trusted_origin()
             |> post("/api/v1/commands/trash-task", lifecycle_body(task_id))
             |> json_response(200)

    assert build_conn()
           |> browser_session(session)
           |> get("/api/v1/tasks/#{task_id}")
           |> response(404)
  end

  test "a tasks.write-only agent grant cannot read the shared queries a tasks.read grant can",
       %{account_id: account_id, read: read, session: session, unscoped: unscoped, write: write} do
    secret = "a title only a reader may see #{Ecto.UUID.generate()}"
    project_id = insert_project(account_id, "Renovation")
    insert_task(account_id, Ecto.UUID.generate(), secret, project_id)

    routes = [
      "/api/v1/search?q=#{URI.encode_www_form("title")}",
      "/api/v1/projects",
      "/api/v1/projects/#{project_id}/tasks"
    ]

    for credential <- [write, unscoped], route <- routes do
      response = build_conn() |> bearer(credential) |> get(route)

      assert @refusal == json_response(response, 403), "#{route} was not refused"
      refute response.resp_body =~ secret
      refute response.resp_body =~ project_id
    end

    # CONTROL, and D-09 preserved: the same routes still answer a grant whose
    # scope covers them, and answer it BYTE-IDENTICALLY to the owner's own
    # browser session. The shared query stays one query, not a parallel one.
    for route <- routes do
      agent_body = build_conn() |> bearer(read) |> get(route) |> json_response(200)
      owner_body = build_conn() |> browser_session(session) |> get(route) |> json_response(200)

      assert agent_body == owner_body
      assert %{"items" => _items} = agent_body
    end

    assert %{"items" => [%{"title" => ^secret}]} =
             build_conn() |> bearer(read) |> get(Enum.at(routes, 2)) |> json_response(200)
  end

  test "an agent grant is refused on a shared command outside the published tool set, whatever its scope",
       %{read: read, session: session, write: write} do
    # Ten of the nineteen shared commands are simply not in the closed tool
    # set the phase published (D-11). An authority an agent cannot express
    # through its own surface is not one its credential should carry, so the
    # route table is an allow-list: these are refused by DEFAULT, not by a
    # denial someone remembered to write.
    task_id = owner_capture(session, "a task outside the agent tool set")

    for credential <- [read, write] do
      assert @refusal ==
               build_conn()
               |> bearer(credential)
               |> post("/api/v1/commands/plan-for-today", planning_body(task_id))
               |> json_response(403)

      assert @refusal ==
               build_conn()
               |> bearer(credential)
               |> post("/api/v1/commands/create-organization", organization_body("Agent org"))
               |> json_response(403)
    end

    assert organization_count() == 0
  end

  test "first-party grants and the owner's session are not touched by the agent gate", %{
    account_id: account_id,
    session: session
  } do
    # The gate keys on the AGENT client kinds alone. A refusal that also locks
    # out the Mac, the iPhone or the browser is not a fix, and a first-party
    # grant carries no scope at all -- so had the check been written as a
    # blanket scope requirement, every one of these would now be a 403.
    for client_kind <- ["electron", "iphone"] do
      credential = create_grant(account_id, client_kind, "first-party-#{client_kind}")
      title = "captured by #{client_kind} #{Ecto.UUID.generate()}"

      assert %{"outcome" => "accepted"} =
               build_conn()
               |> bearer(credential)
               |> post("/api/v1/commands/capture-task", capture_body(title))
               |> json_response(201)

      assert %{"items" => _items} =
               build_conn() |> bearer(credential) |> get("/api/v1/projects") |> json_response(200)
    end

    # The owner reaches every shared command the agent was just refused on.
    task_id = owner_capture(session, "the owner is unaffected")

    owner_command(session, "/api/v1/commands/plan-for-today", planning_body(task_id))

    owner_command(session, "/api/v1/commands/create-organization", organization_body("Owner org"))

    assert organization_count() == 1

    assert %{"items" => _items} =
             build_conn()
             |> browser_session(session)
             |> get("/api/v1/search?q=owner")
             |> json_response(200)
  end

  defp owner_capture(session, title) do
    task_id = Ecto.UUID.generate()

    assert %{"outcome" => "accepted"} =
             build_conn()
             |> browser_session(session)
             |> trusted_origin()
             |> post(
               "/api/v1/commands/capture-task",
               capture_body(title) |> Map.put("task_id", task_id)
             )
             |> json_response(201)

    task_id
  end

  defp owner_command(session, path, body) do
    response =
      build_conn()
      |> browser_session(session)
      |> trusted_origin()
      |> post(path, body)

    assert response.status in [200, 201],
           "the owner was refused on #{path}: #{response.status} #{response.resp_body}"

    response
  end

  defp capture_body(title) do
    %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => Ecto.UUID.generate(),
      "title" => title,
      "version" => 1
    }
  end

  defp organization_body(name) do
    %{
      "kind" => "project",
      "mutation_id" => Ecto.UUID.generate(),
      "name" => name,
      "organization_id" => Ecto.UUID.generate(),
      "version" => 1
    }
  end

  defp planning_body(task_id) do
    %{
      "base_planned_on" => nil,
      "expected_revision" => 1,
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "version" => 1
    }
  end

  defp lifecycle_body(task_id) do
    %{
      "expected_revision" => 1,
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "version" => 1
    }
  end

  defp task_count(title) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM tasks WHERE title = $1", [title])

    count
  end

  defp organization_count do
    %{rows: [[count]]} = SQL.query!(Repo, "SELECT count(*) FROM organizations", [])
    count
  end

  defp browser_session(conn, session) do
    Plug.Test.init_test_session(conn, %{session_credential: session.credential})
  end

  defp trusted_origin(conn) do
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

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$agent-authorization-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    account_id
  end

  defp install_epoch do
    SQL.query!(
      Repo,
      """
      INSERT INTO sync_epochs (singleton_key, epoch, finalized, inserted_at, updated_at)
      VALUES (TRUE, $1, TRUE, $2, $2)
      ON CONFLICT (singleton_key) DO UPDATE
      SET epoch = EXCLUDED.epoch, finalized = TRUE, updated_at = EXCLUDED.updated_at
      """,
      [Ecto.UUID.generate() |> Ecto.UUID.dump!(), @now]
    )
  end

  defp insert_project(account_id, name) do
    project_id = Ecto.UUID.generate()

    SQL.query!(
      Repo,
      """
      INSERT INTO organizations (
        account_id, id, kind, display_name, name_key, name_key_version,
        archived_at, revision, inserted_at, updated_at
      )
      VALUES ($1, $2, 'project', $3, $4, 1, NULL, 1, $5, $5)
      """,
      [account_id, Ecto.UUID.dump!(project_id), name, String.downcase(name), @now]
    )

    project_id
  end

  defp insert_task(account_id, id, title, project_id) do
    SQL.query!(
      Repo,
      """
      INSERT INTO tasks (
        account_id, id, title, notes, inbox_state, revision, captured_at,
        project_id, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, '', 'inbox', 1, $4, $5, $4, $4)
      """,
      [account_id, Ecto.UUID.dump!(id), title, @now, project_id && Ecto.UUID.dump!(project_id)]
    )
  end

  defp create_grant(account_id, client_kind, installation_id, options \\ []) do
    credential = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    authorization_hash = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.add(DateTime.utc_now(), 90, :day)
    scope = Keyword.get(options, :scope, [])

    redirect_uri =
      if client_kind == "mcp",
        do: "https://mcp.invalid/callback",
        else: "keepling://auth/callback"

    SQL.query!(
      Repo,
      """
      INSERT INTO device_grants (
        id, account_id, installation_id, label, client_kind, redirect_uri,
        authorization_code_hash, authorization_code_expires_at, authorization_code_consumed_at,
        state_hash, pkce_challenge, access_token_hash, access_expires_at,
        family_absolute_expires_at, generation, scope, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, 'Agent authorization fixture', $4, $5,
              $6, $7, $8, $9, 'fixture-challenge', $10, $7, $7, $11, $12, $8, $8)
      """,
      [
        grant_id,
        account_id,
        installation_id,
        client_kind,
        redirect_uri,
        authorization_hash,
        expires_at,
        @now,
        :crypto.strong_rand_bytes(32),
        :crypto.hash(:sha256, credential),
        1,
        scope
      ]
    )

    credential
  end
end
