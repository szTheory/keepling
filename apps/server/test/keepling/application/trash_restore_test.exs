defmodule Keepling.Domain.TrashRestoreTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Task

  test "storage-neutral vectors require exact revision and preserve every non-Trash field" do
    vectors = trash_restore_vectors()

    assert vectors["version"] == 1
    assert vectors["field"] == "trashed_at"

    for vector <- vectors["cases"] do
      task = task_from(vector["current"])
      command = command_from(vector["command"])
      result = operation(vector["command"]["type"]).(task, command)

      case vector["result"]["outcome"] do
        "accepted" ->
          assert {:ok, updated, activity, :accepted} = result, vector["name"]
          assert updated.revision == vector["result"]["revision"]
          assert optional_iso8601(updated.trashed_at) == vector["result"]["trashed_at"]
          assert Atom.to_string(activity.type) == vector["result"]["activity_type"]

          assert Map.drop(updated, [:revision, :trashed_at]) ==
                   Map.drop(task, [:revision, :trashed_at])

          assert activity.changed_fields == %{
                   "trashed_at" => %{"from" => task.trashed_at, "to" => updated.trashed_at}
                 }

        "already_satisfied" ->
          assert {:ok, unchanged, nil, :already_satisfied} = result, vector["name"]
          assert unchanged == task

        "conflict" ->
          assert {:error, {:trash_conflict, affected_fields}} = result, vector["name"]
          assert affected_fields == vector["result"]["affected_fields"]
      end
    end
  end

  defp operation("trash_task"), do: &Task.trash/2
  defp operation("restore_task"), do: &Task.restore/2

  defp task_from(current) do
    struct!(Task,
      captured_at: ~U[2026-08-30 20:00:00.000000Z],
      completed_at: ~U[2026-08-31 12:00:00.000000Z],
      deadline_on: ~D[2026-09-04],
      id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
      inbox_state: :inbox,
      lifecycle_revision: 6,
      notes: "Preserve all details",
      planned_on: ~D[2026-09-02],
      revision: current["revision"],
      title: "Keep Trash recoverable",
      trashed_at: parse_optional_datetime(current["trashed_at"])
    )
  end

  defp command_from(command) do
    %{
      accepted_at: DateTime.from_iso8601(command["accepted_at"]) |> elem(1),
      expected_revision: command["expected_revision"]
    }
  end

  defp optional_iso8601(nil), do: nil
  defp optional_iso8601(value), do: DateTime.to_iso8601(value)
  defp parse_optional_datetime(nil), do: nil
  defp parse_optional_datetime(value), do: DateTime.from_iso8601(value) |> elem(1)

  defp trash_restore_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/trash-restore.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule Keepling.Application.TrashRestorePersistenceTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.{CommandStore, TaskViews}
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @captured_at ~U[2026-08-31 11:55:00.000000Z]

  setup do
    account_id = create_account()
    %{account_id: account_id}
  end

  test "trash and restore preserve canonical state, activity, assignments, completion, and order",
       %{
         account_id: account_id
       } do
    task_id = Ecto.UUID.generate()
    project_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()

    seed_preserved_task(account_id, task_id, project_id, tag_id)
    before = preserved_state(account_id, task_id)

    trash_id = Ecto.UUID.generate()

    trash_command = %{
      type: :trash_task,
      expected_revision: 7,
      mutation_id: trash_id,
      task_id: task_id,
      version: 1
    }

    trashed = dispatch(account_id, ~U[2026-08-31 13:00:00.000000Z], trash_command)

    assert {:ok,
            %{
              status: 200,
              body: %{
                "mutation_id" => ^trash_id,
                "outcome" => "accepted",
                "revision" => 8,
                "snapshot" => %{
                  "completed_at" => "2026-08-31T12:00:00.000000Z",
                  "inbox_state" => "inbox",
                  "notes" => "Every field survives",
                  "planned_on" => "2026-08-31",
                  "deadline_on" => "2026-09-02",
                  "trashed_at" => "2026-08-31T13:00:00.000000Z"
                }
              }
            }} = trashed

    assert trashed == dispatch(account_id, ~U[2026-08-31 13:05:00.000000Z], trash_command)
    assert {:ok, []} = CommandStore.list_inbox(context(account_id, @captured_at))
    assert {:ok, %{items: []}} = list_view(account_id, :today)
    assert {:ok, %{items: []}} = list_view(account_id, :completed)

    assert {:ok, [%{"id" => ^task_id, "revision" => 8}]} =
             CommandStore.list_trash(context(account_id, @captured_at))

    after_trash = preserved_state(account_id, task_id)

    assert Map.drop(after_trash, [:activities, :revision, :trashed_at]) ==
             Map.drop(before, [:activities, :revision, :trashed_at])

    assert after_trash.activities == before.activities + 1

    restore_id = Ecto.UUID.generate()

    restore_command = %{
      type: :restore_task,
      expected_revision: 8,
      mutation_id: restore_id,
      task_id: task_id,
      version: 1
    }

    restored = dispatch(account_id, ~U[2026-08-31 13:10:00.000000Z], restore_command)

    assert {:ok,
            %{
              body: %{
                "destinations" => ["Inbox", "Today", "Completed"],
                "mutation_id" => ^restore_id,
                "outcome" => "accepted",
                "revision" => 9,
                "snapshot" => %{"trashed_at" => nil}
              }
            }} = restored

    assert restored == dispatch(account_id, ~U[2026-08-31 13:15:00.000000Z], restore_command)
    assert {:ok, []} = CommandStore.list_trash(context(account_id, @captured_at))

    assert {:ok, [%{"id" => ^task_id}]} =
             CommandStore.list_inbox(context(account_id, @captured_at))

    assert {:ok, %{items: [%{id: ^task_id}]}} = list_view(account_id, :today)
    assert {:ok, %{items: [%{id: ^task_id}]}} = list_view(account_id, :completed)

    after_restore = preserved_state(account_id, task_id)

    assert Map.drop(after_restore, [:activities, :revision, :trashed_at]) ==
             Map.drop(before, [:activities, :revision, :trashed_at])

    assert after_restore.activities == before.activities + 2
  end

  test "stale Trash commands change nothing and cross-account reads disclose nothing", %{
    account_id: account_id
  } do
    other_account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    task_id = Ecto.UUID.generate()
    seed_preserved_task(account_id, task_id, Ecto.UUID.generate(), Ecto.UUID.generate())

    stale = %{
      type: :trash_task,
      expected_revision: 6,
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      version: 1
    }

    assert {:ok,
            %{
              status: 409,
              body: %{
                "affected_fields" => ["trashed_at"],
                "code" => "task_trash_conflict",
                "current_revision" => 7
              }
            }} = dispatch(account_id, @captured_at, stale)

    assert {:ok, []} = CommandStore.list_trash(context(other_account_id, @captured_at))

    assert {:error, :not_found} =
             Commands.lookup_result(
               %{account_id: other_account_id},
               stale.mutation_id,
               CommandStore
             )

    assert preserved_state(account_id, task_id).trashed_at == nil
  end

  test "Trash is newest-first and the migration contains no deletion or retention mechanism", %{
    account_id: account_id
  } do
    older_id = Ecto.UUID.generate()
    newer_id = Ecto.UUID.generate()

    seed_preserved_task(account_id, older_id, Ecto.UUID.generate(), Ecto.UUID.generate())
    seed_preserved_task(account_id, newer_id, Ecto.UUID.generate(), Ecto.UUID.generate())

    assert {:ok, _} =
             dispatch(account_id, ~U[2026-08-31 13:00:00.000000Z], %{
               type: :trash_task,
               expected_revision: 7,
               mutation_id: Ecto.UUID.generate(),
               task_id: older_id,
               version: 1
             })

    assert {:ok, _} =
             dispatch(account_id, ~U[2026-08-31 13:01:00.000000Z], %{
               type: :trash_task,
               expected_revision: 7,
               mutation_id: Ecto.UUID.generate(),
               task_id: newer_id,
               version: 1
             })

    assert {:ok, [%{"id" => ^newer_id}, %{"id" => ^older_id}]} =
             CommandStore.list_trash(context(account_id, @captured_at))

    migration =
      File.read!(
        Path.expand(
          "../../../priv/repo/migrations/20260830000700_add_trash_state.exs",
          __DIR__
        )
      )

    refute migration =~ ~r/DELETE\s+FROM/i
    refute migration =~ ~r/drop\s+table/i
    refute migration =~ ~r/retention|expire|purge/i
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      ) VALUES ($1, $2, '$argon2id$test-fixture', 'America/New_York', $3, $3)
      """,
      [account_id, true, @captured_at]
    )

    account_id
  end

  defp seed_preserved_task(account_id, task_id, project_id, tag_id) do
    project = Ecto.UUID.dump!(project_id)
    tag = Ecto.UUID.dump!(tag_id)
    task = Ecto.UUID.dump!(task_id)

    suffix = String.slice(task_id, -6, 6)

    for {id, kind, name} <- [
          {project, "project", "Project #{suffix}"},
          {tag, "tag", "Tag #{suffix}"}
        ] do
      SQL.query!(
        Repo,
        """
        INSERT INTO organizations (
          account_id, id, kind, display_name, name_key, name_key_version,
          archived_at, revision, inserted_at, updated_at
        ) VALUES ($1, $2, $3, $4, lower($4), 1, NULL, 1, $5, $5)
        """,
        [account_id, id, kind, name, @captured_at]
      )
    end

    SQL.query!(
      Repo,
      """
      INSERT INTO tasks (
        account_id, id, title, notes, inbox_state, revision, captured_at,
        planned_on, deadline_on, completed_at, project_id, inserted_at, updated_at
      ) VALUES ($1, $2, 'Preserved task', 'Every field survives', 'inbox', 7, $3,
                DATE '2026-08-31', DATE '2026-09-02', $4, $5, $3, $3)
      """,
      [account_id, task, @captured_at, ~U[2026-08-31 12:00:00.000000Z], project]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO task_tags (account_id, task_id, tag_id, tag_kind, inserted_at)
      VALUES ($1, $2, $3, 'tag', $4)
      """,
      [account_id, task, tag, @captured_at]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO today_task_order (
        account_id, task_id, section, position, inserted_at, updated_at
      ) VALUES ($1, $2, 'today', 1, $3, $3)
      ON CONFLICT (account_id, section, position) DO NOTHING
      """,
      [account_id, task, @captured_at]
    )
  end

  defp preserved_state(account_id, task_id) do
    %{
      rows: [
        [
          revision,
          trashed_at,
          title,
          notes,
          inbox_state,
          planned_on,
          deadline_on,
          completed_at,
          project_id,
          tag_ids,
          order_rows,
          activities
        ]
      ]
    } =
      SQL.query!(
        Repo,
        """
        SELECT tasks.revision, tasks.trashed_at, tasks.title, tasks.notes, tasks.inbox_state,
               tasks.planned_on, tasks.deadline_on, tasks.completed_at, tasks.project_id,
               (SELECT array_agg(tag_id ORDER BY tag_id) FROM task_tags
                WHERE account_id = $1 AND task_id = $2),
               (SELECT count(*) FROM today_task_order WHERE account_id = $1 AND task_id = $2),
               (SELECT count(*) FROM task_activities WHERE account_id = $1 AND task_id = $2)
        FROM tasks
        WHERE tasks.account_id = $1 AND tasks.id = $2
        """,
        [account_id, Ecto.UUID.dump!(task_id)]
      )

    %{
      activities: activities,
      completed_at: completed_at,
      deadline_on: deadline_on,
      inbox_state: inbox_state,
      notes: notes,
      order_rows: order_rows,
      planned_on: planned_on,
      project_id: project_id,
      revision: revision,
      tag_ids: tag_ids,
      title: title,
      trashed_at: trashed_at
    }
  end

  defp list_view(account_id, view) do
    TaskViews.list_tasks(context(account_id, @captured_at), view, %{cursor: nil, limit: 50})
  end

  defp dispatch(account_id, accepted_at, command),
    do: Commands.dispatch(command, context(account_id, accepted_at), CommandStore)

  defp context(account_id, accepted_at) do
    %{accepted_at: accepted_at, account_id: account_id, actor_type: "user", client_kind: "web"}
  end
end

defmodule KeeplingWeb.TrashRestoreBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/New_York', $2, $2)
      """,
      [account_id, now]
    )

    previous_seed = System.get_env("KEEPLING_E2E_SEED")
    System.put_env("KEEPLING_E2E_SEED", "phase-1")

    on_exit(fn ->
      if previous_seed,
        do: System.put_env("KEEPLING_E2E_SEED", previous_seed),
        else: System.delete_env("KEEPLING_E2E_SEED")
    end)

    login = conn |> trusted_request() |> post("/api/v1/test/session")
    %{conn: login, csrf_token: json_response(login, 200)["csrf_token"]}
  end

  test "authenticated Trash routes retain the row until restore acknowledgement", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    captured =
      command(conn, csrf_token, "/api/v1/commands/capture-task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => "Recover me",
        "version" => 1
      })

    assert %{"revision" => 1} = json_response(captured, 201)

    trashed =
      command(conn, csrf_token, "/api/v1/commands/trash-task", %{
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"revision" => 2, "snapshot" => %{"trashed_at" => trashed_at}} =
             json_response(trashed, 200)

    assert is_binary(trashed_at)

    assert %{"tasks" => [%{"id" => ^task_id, "trashed_at" => ^trashed_at}]} =
             conn |> recycle() |> get("/api/v1/trash") |> json_response(200)

    restored =
      command(conn, csrf_token, "/api/v1/commands/restore-task", %{
        "expected_revision" => 2,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "destinations" => ["Inbox"],
             "revision" => 3,
             "snapshot" => %{"trashed_at" => nil}
           } = json_response(restored, 200)

    assert %{"tasks" => []} = conn |> recycle() |> get("/api/v1/trash") |> json_response(200)

    activity = conn |> recycle() |> get("/api/v1/tasks/#{task_id}/activity") |> json_response(200)
    assert [%{"type" => "task_restored"}, %{"type" => "task_trashed"} | _] = activity["items"]
  end

  defp command(conn, csrf_token, path, body) do
    conn
    |> recycle()
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(path, body)
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
end
