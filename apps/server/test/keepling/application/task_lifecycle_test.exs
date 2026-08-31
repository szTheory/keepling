defmodule Keepling.Domain.TaskLifecycleTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Task

  test "storage-neutral vectors classify lifecycle acceptance, replay, rebase, and conflict" do
    vectors = lifecycle_vectors()

    assert vectors["version"] == 1
    assert vectors["field"] == "completed_at"

    for vector <- vectors["cases"] do
      task = task_from(vector["current"])
      command = command_from(vector["command"])
      result = lifecycle_operation(vector["command"]["type"]).(task, command)

      case vector["result"]["outcome"] do
        "accepted" ->
          assert {:ok, updated, activity, :accepted} = result, vector["name"]
          assert updated.revision == vector["result"]["revision"]
          assert optional_iso8601(updated.completed_at) == vector["result"]["completed_at"]
          assert Atom.to_string(activity.type) == vector["result"]["activity_type"]

          assert activity.changed_fields == %{
                   "completed_at" => %{
                     "from" => task.completed_at,
                     "to" => updated.completed_at
                   }
                 }

        "already_satisfied" ->
          assert {:ok, unchanged, nil, :already_satisfied} = result, vector["name"]
          assert unchanged == task

        "conflict" ->
          assert {:error, {:lifecycle_conflict, affected_fields}} = result, vector["name"]
          assert affected_fields == vector["result"]["affected_fields"]
      end
    end
  end

  defp lifecycle_operation("complete_task"), do: &Task.complete/2
  defp lifecycle_operation("reopen_task"), do: &Task.reopen/2

  defp task_from(current) do
    struct!(Task,
      captured_at: ~U[2026-08-30 20:00:00.000000Z],
      completed_at: parse_optional_datetime(current["completed_at"]),
      deadline_on: nil,
      id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
      inbox_state: :inbox,
      lifecycle_revision: current["lifecycle_revision"],
      notes: "",
      planned_on: nil,
      revision: current["revision"],
      title: "Keep lifecycle exact"
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

  defp lifecycle_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/lifecycle.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule Keepling.Application.TaskLifecyclePersistenceTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @captured_at ~U[2026-08-31 11:55:00.000000Z]

  setup do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/New_York', $2, $2)
      """,
      [account_id, @captured_at]
    )

    %{account_id: account_id}
  end

  test "accepted lifecycle transitions commit one revision, fact, receipt, and exact replay", %{
    account_id: account_id
  } do
    task_id = Ecto.UUID.generate()
    capture_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(
               account_id,
               @captured_at,
               %{
                 type: :capture_task,
                 mutation_id: capture_id,
                 task_id: task_id,
                 title: "Finish me",
                 version: 1
               }
             )

    edit_id = Ecto.UUID.generate()

    assert {:ok, %{body: %{"revision" => 2}}} =
             dispatch(account_id, ~U[2026-08-31 11:56:00.000000Z], %{
               type: :edit_task,
               base_values: %{notes: ""},
               expected_revision: 1,
               fields: %{notes: "Unrelated edit"},
               mutation_id: edit_id,
               task_id: task_id,
               version: 1
             })

    complete_id = Ecto.UUID.generate()

    complete_command = %{
      type: :complete_task,
      expected_revision: 1,
      mutation_id: complete_id,
      task_id: task_id,
      version: 1
    }

    accepted = dispatch(account_id, ~U[2026-08-31 12:00:00.000000Z], complete_command)

    assert {:ok,
            %{
              status: 200,
              body: %{
                "mutation_id" => ^complete_id,
                "outcome" => "accepted",
                "revision" => 3,
                "snapshot" => %{
                  "completed_at" => "2026-08-31T12:00:00.000000Z",
                  "inbox_state" => "inbox",
                  "notes" => "Unrelated edit"
                }
              }
            }} = accepted

    assert accepted == dispatch(account_id, ~U[2026-08-31 12:05:00.000000Z], complete_command)
    assert {:ok, []} = CommandStore.list_inbox(context(account_id, @captured_at))

    assert %{
             activities: 3,
             completed_at: ~U[2026-08-31 12:00:00.000000Z],
             receipts: 3,
             revision: 3
           } =
             stored_state(account_id, task_id)

    already_id = Ecto.UUID.generate()

    assert {:ok, %{body: %{"outcome" => "already_satisfied", "revision" => 3}}} =
             dispatch(account_id, ~U[2026-08-31 12:06:00.000000Z], %{
               type: :complete_task,
               expected_revision: 1,
               mutation_id: already_id,
               task_id: task_id,
               version: 1
             })

    reopen_id = Ecto.UUID.generate()

    assert {:ok,
            %{
              body: %{
                "outcome" => "accepted",
                "revision" => 4,
                "snapshot" => %{"completed_at" => nil, "inbox_state" => "inbox"}
              }
            }} =
             dispatch(account_id, ~U[2026-08-31 12:07:00.000000Z], %{
               type: :reopen_task,
               expected_revision: 3,
               mutation_id: reopen_id,
               task_id: task_id,
               version: 1
             })

    assert {:ok, [%{"id" => ^task_id}]} =
             CommandStore.list_inbox(context(account_id, @captured_at))

    conflict_id = Ecto.UUID.generate()

    conflict_command = %{
      type: :complete_task,
      expected_revision: 3,
      mutation_id: conflict_id,
      task_id: task_id,
      version: 1
    }

    conflict = dispatch(account_id, ~U[2026-08-31 12:08:00.000000Z], conflict_command)

    assert {:ok,
            %{
              status: 409,
              body: %{
                "affected_fields" => ["completed_at"],
                "code" => "task_lifecycle_conflict",
                "current_revision" => 4
              }
            }} = conflict

    assert conflict == dispatch(account_id, ~U[2026-08-31 12:09:00.000000Z], conflict_command)

    assert %{activities: 4, completed_at: nil, receipts: 6, revision: 4} =
             stored_state(account_id, task_id)
  end

  defp dispatch(account_id, accepted_at, command),
    do: Commands.dispatch(command, context(account_id, accepted_at), CommandStore)

  defp context(account_id, accepted_at) do
    %{accepted_at: accepted_at, account_id: account_id, actor_type: "user", client_kind: "web"}
  end

  defp stored_state(account_id, task_id) do
    %{rows: [[revision, completed_at, receipts, activities]]} =
      SQL.query!(
        Repo,
        """
        SELECT tasks.revision,
               tasks.completed_at,
               (SELECT count(*) FROM command_receipts WHERE account_id = $1),
               (SELECT count(*) FROM task_activities WHERE account_id = $1)
        FROM tasks
        WHERE tasks.account_id = $1 AND tasks.id = $2
        """,
        [account_id, Ecto.UUID.dump!(task_id)]
      )

    %{
      activities: activities,
      completed_at: normalize_datetime(completed_at),
      receipts: receipts,
      revision: revision
    }
  end

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = value), do: value
  defp normalize_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end

defmodule KeeplingWeb.TaskLifecycleBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
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

  test "Phoenix lifecycle commands move the task only after exact acknowledgement", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    captured =
      command(conn, csrf_token, "/api/v1/commands/capture-task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => "Cross every lifecycle boundary",
        "version" => 1
      })

    assert %{"revision" => 1, "snapshot" => %{"completed_at" => nil}} =
             json_response(captured, 201)

    completed =
      command(conn, csrf_token, "/api/v1/commands/complete-task", %{
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "outcome" => "accepted",
             "revision" => 2,
             "snapshot" => %{"completed_at" => completed_at}
           } = json_response(completed, 200)

    assert is_binary(completed_at)

    assert %{"items" => []} =
             conn |> recycle() |> get("/api/v1/views/inbox") |> json_response(200)

    assert %{"items" => [%{"id" => ^task_id, "completed_at" => ^completed_at}]} =
             conn |> recycle() |> get("/api/v1/completed") |> json_response(200)

    activity = conn |> recycle() |> get("/api/v1/tasks/#{task_id}/activity") |> json_response(200)
    assert [%{"type" => "task_completed"}, %{"type" => "task_captured"}] = activity["items"]

    reopened =
      command(conn, csrf_token, "/api/v1/commands/reopen-task", %{
        "expected_revision" => 2,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"outcome" => "accepted", "revision" => 3, "snapshot" => %{"completed_at" => nil}} =
             json_response(reopened, 200)

    assert %{"items" => [%{"id" => ^task_id}]} =
             conn |> recycle() |> get("/api/v1/views/inbox") |> json_response(200)

    assert %{"items" => []} = conn |> recycle() |> get("/api/v1/completed") |> json_response(200)
  end

  test "lifecycle transport remains closed and structural failures are not receipted", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    mutation_id = Ecto.UUID.generate()

    invalid =
      command(conn, csrf_token, "/api/v1/commands/complete-task", %{
        "expected_revision" => 1,
        "mutation_id" => mutation_id,
        "task_id" => Ecto.UUID.generate(),
        "unexpected" => true,
        "version" => 1
      })

    assert %{"code" => "invalid_command"} = json_response(invalid, 400)
    assert receipt_count(mutation_id) == 0
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

  defp receipt_count(mutation_id) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM command_receipts WHERE mutation_id = $1", [
        Ecto.UUID.dump!(mutation_id)
      ])

    count
  end
end
