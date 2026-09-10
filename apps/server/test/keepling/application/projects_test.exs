defmodule Keepling.Application.ProjectsTest do
  @moduledoc """
  Covers `Keepling.Application.Projects` (project list + per-project task
  page) and the `GET /api/v1/search`, `GET /api/v1/projects`,
  `GET /api/v1/projects/:organization_id/tasks` HTTP surfaces every
  credential class in `:client_authenticated` reaches identically (D-09).
  """

  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.Projects, as: PostgresProjects
  alias Keepling.Application.Projects
  alias Keepling.Repo

  @cursor_secret String.duplicate("projects-cursor-secret", 2)
  @now ~U[2026-09-11 12:00:00.000000Z]

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-projects",
      redirect_uris: %{"electron" => ["keepling://auth/callback"], "mcp" => ["https://mcp.invalid/callback"]}
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

  test "Projects.list returns non-archived projects with identity, name, and task count", %{
    account_id: account_id
  } do
    project_id = insert_project(account_id, "Renovation")
    archived_id = insert_project(account_id, "Old project", archived: true)

    insert_task(account_id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "Paint", project_id)
    insert_task(account_id, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "Tile", project_id)

    assert {:ok, %{items: items}} = list_projects(context(account_id), %{limit: 20})

    assert Enum.map(items, &{&1.id, &1.name, &1.task_count}) == [{project_id, "Renovation", 2}]
    refute Enum.any?(items, &(&1.id == archived_id))
  end

  test "Projects.tasks returns one project's tasks as a bounded keyset page", %{
    account_id: account_id
  } do
    project_id = insert_project(account_id, "Renovation")
    other_id = insert_project(account_id, "Other")

    first_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    second_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    insert_task(account_id, first_id, "Paint", project_id, captured_at: ~U[2026-09-11 10:00:00.000000Z])
    insert_task(account_id, second_id, "Tile", project_id, captured_at: ~U[2026-09-11 10:01:00.000000Z])
    insert_task(account_id, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", "Other project task", other_id)

    assert {:ok, %{items: items, next_cursor: nil}} =
             project_tasks(context(account_id), project_id, %{limit: 20})

    assert Enum.map(items, & &1.id) == [second_id, first_id]
  end

  test "a foreign project identity returns not-found rather than an empty page", %{
    account_id: account_id
  } do
    project_id = insert_project(account_id, "Yours")

    foreign_context = %{context(account_id) | account_id: Ecto.UUID.bingenerate()}

    assert {:error, :not_found} = project_tasks(foreign_context, project_id, %{limit: 20})
  end

  test "GET /api/v1/search returns byte-identical rows across a browser session, a device-grant bearer, and an mcp bearer",
       %{account_id: account_id} do
    task_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    insert_task(account_id, task_id, "Buy milk", nil)

    electron_credential = create_grant(account_id, "electron", "electron-projects-1")
    mcp_credential = create_grant(account_id, "mcp", "mcp-projects-1", scope: ["tasks.read"])

    {:ok, session} =
      Keepling.Accounts.create_session(account_id, label: "Web", client_kind: "web")

    browser_body =
      build_conn()
      |> browser_session(session)
      |> get("/api/v1/search?q=milk")
      |> json_response(200)

    electron_body =
      build_conn()
      |> bearer(electron_credential)
      |> get("/api/v1/search?q=milk")
      |> json_response(200)

    mcp_body =
      build_conn()
      |> bearer(mcp_credential)
      |> get("/api/v1/search?q=milk")
      |> json_response(200)

    assert browser_body == electron_body
    assert electron_body == mcp_body

    assert %{"items" => [%{"id" => ^task_id}]} = browser_body
  end

  test "GET /api/v1/projects and GET /api/v1/projects/:organization_id/tasks behave likewise", %{
    account_id: account_id
  } do
    project_id = insert_project(account_id, "Renovation")
    insert_task(account_id, "12345678-1234-4234-8234-123456789abc", "Paint", project_id)

    credential = create_grant(account_id, "iphone", "iphone-projects-1")

    projects_body =
      build_conn()
      |> bearer(credential)
      |> get("/api/v1/projects")
      |> json_response(200)

    assert %{"items" => [%{"id" => ^project_id, "task_count" => 1}]} = projects_body

    tasks_body =
      build_conn()
      |> bearer(credential)
      |> get("/api/v1/projects/#{project_id}/tasks")
      |> json_response(200)

    assert %{"items" => [%{"title" => "Paint"}]} = tasks_body
  end

  test "an unknown query parameter is rejected", %{account_id: account_id} do
    credential = create_grant(account_id, "electron", "electron-projects-unknown-param")

    body =
      build_conn()
      |> bearer(credential)
      |> get("/api/v1/search?q=milk&unknown=1")
      |> json_response(400)

    assert body["code"] == "invalid_search_query"
  end

  test "a well-formed but foreign project identity over HTTP returns 404, not an empty page", %{
    account_id: account_id
  } do
    # `singleton_key` permits exactly one real `accounts` row (D-003), so
    # "foreign" here is a syntactically valid, never-inserted identity --
    # the same not-found path a truly cross-account identity would hit,
    # since the WHERE clause treats both identically.
    never_inserted_project_id = Ecto.UUID.generate()
    credential = create_grant(account_id, "electron", "electron-projects-foreign")

    body =
      build_conn()
      |> bearer(credential)
      |> get("/api/v1/projects/#{never_inserted_project_id}/tasks")
      |> json_response(404)

    assert body["code"] == "project_not_found"
  end

  # `singleton_key` is uniquely constrained to one TRUE row for the whole
  # system (D-003: single-account only) -- there is never a second real
  # account to create. A "foreign account" scenario is proven with a
  # syntactically valid but unregistered account_id instead (see the
  # not-found tests below), never with a second `accounts` row.
  defp create_account do
    account_id = Ecto.UUID.bingenerate()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$projects-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    account_id
  end

  defp insert_project(account_id, name, options \\ []) do
    project_id = Ecto.UUID.generate()

    SQL.query!(
      Repo,
      """
      INSERT INTO organizations (
        account_id, id, kind, display_name, name_key, name_key_version,
        archived_at, revision, inserted_at, updated_at
      )
      VALUES ($1, $2, 'project', $3, $4, 1, $5, 1, $6, $6)
      """,
      [
        dump_uuid(account_id),
        Ecto.UUID.dump!(project_id),
        name,
        String.downcase(name),
        if(Keyword.get(options, :archived, false), do: @now, else: nil),
        @now
      ]
    )

    project_id
  end

  defp insert_task(account_id, id, title, project_id, options \\ []) do
    SQL.query!(
      Repo,
      """
      INSERT INTO tasks (
        account_id, id, title, notes, inbox_state, revision, captured_at,
        project_id, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, '', 'inbox', 1, $4, $5, $4, $4)
      """,
      [
        dump_uuid(account_id),
        Ecto.UUID.dump!(id),
        title,
        Keyword.get(options, :captured_at, @now),
        project_id && Ecto.UUID.dump!(project_id)
      ]
    )
  end

  defp dump_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, canonical} -> Ecto.UUID.dump!(canonical)
      :error -> uuid
    end
  end

  defp context(account_id) do
    %{account_id: account_id, cursor_secret: @cursor_secret}
  end

  defp list_projects(context, options), do: Projects.list(context, options, PostgresProjects)

  defp project_tasks(context, project_id, options),
    do: Projects.tasks(context, project_id, options, PostgresProjects)

  defp browser_session(conn, session) do
    Plug.Test.init_test_session(conn, %{session_credential: session.credential})
  end

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp create_grant(account_id, client_kind, installation_id, options \\ []) do
    credential = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    authorization_hash = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.add(DateTime.utc_now(), 90, :day)
    scope = Keyword.get(options, :scope, [])
    redirect_uri = if client_kind == "mcp", do: "https://mcp.invalid/callback", else: "keepling://auth/callback"

    SQL.query!(
      Repo,
      """
      INSERT INTO device_grants (
        id, account_id, installation_id, label, client_kind, redirect_uri,
        authorization_code_hash, authorization_code_expires_at, authorization_code_consumed_at,
        state_hash, pkce_challenge, access_token_hash, access_expires_at,
        family_absolute_expires_at, generation, scope, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, 'Projects fixture', $4, $5,
              $6, $7, $8, $9, 'fixture-challenge', $10, $7, $7, $11, $12, $8, $8)
      """,
      [
        grant_id,
        dump_uuid(account_id),
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
