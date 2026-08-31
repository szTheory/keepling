defmodule Keepling.Domain.MergeConflictTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Merge

  test "storage-neutral vectors keep the merge field set closed and deterministic" do
    vectors = conflict_vectors()

    assert vectors["version"] == 1
    assert vectors["fields"] == ["notes", "title"]

    for vector <- vectors["cases"] do
      current = atomize(vector["current"])
      base_values = atomize(vector["base_values"])
      requested_values = atomize(vector["requested_values"])

      case vector["result"]["outcome"] do
        "merged" ->
          assert {:ok, merged, _changes} =
                   Merge.three_way(current, base_values, requested_values, [:notes, :title]),
                 vector["name"]

          assert merged == atomize(vector["result"]["values"])

        "conflict" ->
          assert {:conflict, affected_fields} =
                   Merge.three_way(current, base_values, requested_values, [:notes, :title]),
                 vector["name"]

          assert affected_fields == vector["result"]["affected_fields"]
      end
    end

    assert {:error, :invalid_merge_fields} =
             Merge.three_way(
               %{title: "Task"},
               %{completed_at: nil},
               %{completed_at: "now"},
               [:notes, :title]
             )
  end

  defp atomize(values) do
    Map.new(values, fn
      {"notes", value} -> {:notes, value}
      {"title", value} -> {:title, value}
    end)
  end

  defp conflict_vectors do
    path = Path.expand("../../../../../../packages/contracts/vectors/conflicts.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule Keepling.Adapters.Postgres.ConflictTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @accepted_at ~U[2026-08-31 12:40:00.000000Z]

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
      [account_id, @accepted_at]
    )

    %{account_id: account_id}
  end

  test "overlap persists one stable conflict and explicit resolution uses a fresh identity", %{
    account_id: account_id
  } do
    task_id = capture(account_id, "Base title")

    SQL.query!(
      Repo,
      "UPDATE tasks SET title = 'Current title', revision = 2 WHERE account_id = $1 AND id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    original_mutation_id = Ecto.UUID.generate()

    original_command = %{
      type: :edit_task,
      base_values: %{notes: "", title: "Base title"},
      expected_revision: 1,
      fields: %{notes: "Keep this draft", title: "My title"},
      mutation_id: original_mutation_id,
      task_id: task_id,
      version: 1
    }

    conflict = dispatch(account_id, ~U[2026-08-31 12:41:00.000000Z], original_command)

    assert {:ok,
            %{
              status: 409,
              body: %{
                "affected_fields" => ["title"],
                "code" => "task_edit_conflict",
                "conflict" => %{
                  "fields" => [
                    %{
                      "base" => "Base title",
                      "current" => "Current title",
                      "field" => "title",
                      "mine" => "My title"
                    }
                  ],
                  "id" => conflict_id,
                  "latest_revision" => 2
                }
              }
            }} = conflict

    assert conflict == dispatch(account_id, ~U[2026-08-31 12:42:00.000000Z], original_command)

    assert %{count: 1, resolved_by: nil} = stored_conflict(account_id, conflict_id)
    assert stored_task(account_id, task_id) == %{notes: "", revision: 2, title: "Current title"}

    resolution_mutation_id = Ecto.UUID.generate()

    resolution_command = %{
      type: :resolve_task_conflict,
      conflict_id: conflict_id,
      latest_revision: 2,
      mutation_id: resolution_mutation_id,
      selections: %{title: :mine},
      task_id: task_id,
      version: 1
    }

    resolution = dispatch(account_id, ~U[2026-08-31 12:43:00.000000Z], resolution_command)

    assert {:ok,
            %{
              status: 200,
              body: %{
                "mutation_id" => ^resolution_mutation_id,
                "outcome" => "accepted",
                "revision" => 3,
                "snapshot" => %{"notes" => "Keep this draft", "title" => "My title"}
              }
            }} = resolution

    assert resolution ==
             dispatch(account_id, ~U[2026-08-31 12:44:00.000000Z], resolution_command)

    assert %{count: 1, resolved_by: ^resolution_mutation_id} =
             stored_conflict(account_id, conflict_id)

    assert stored_task(account_id, task_id) ==
             %{notes: "Keep this draft", revision: 3, title: "My title"}

    assert conflict == dispatch(account_id, ~U[2026-08-31 12:45:00.000000Z], original_command)
  end

  test "stale and cross-account conflict resolution disclose and mutate nothing", %{
    account_id: account_id
  } do
    task_id = capture(account_id, "Base title")

    SQL.query!(
      Repo,
      "UPDATE tasks SET title = 'Current title', revision = 2 WHERE account_id = $1 AND id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    conflict_command = %{
      type: :edit_task,
      base_values: %{title: "Base title"},
      expected_revision: 1,
      fields: %{title: "My title"},
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      version: 1
    }

    assert {:ok, %{body: %{"conflict" => %{"id" => conflict_id}}}} =
             dispatch(account_id, ~U[2026-08-31 12:41:00.000000Z], conflict_command)

    SQL.query!(
      Repo,
      "UPDATE tasks SET notes = 'Later edit', revision = 3 WHERE account_id = $1 AND id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    stale_command = %{
      type: :resolve_task_conflict,
      conflict_id: conflict_id,
      latest_revision: 2,
      mutation_id: Ecto.UUID.generate(),
      selections: %{title: :mine},
      task_id: task_id,
      version: 1
    }

    assert {:ok,
            %{
              status: 409,
              body: %{
                "code" => "task_conflict_stale",
                "current_revision" => 3,
                "retryable" => false
              }
            }} = dispatch(account_id, ~U[2026-08-31 12:42:00.000000Z], stale_command)

    assert stored_task(account_id, task_id) ==
             %{notes: "Later edit", revision: 3, title: "Current title"}

    foreign_account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    assert {:error, :infrastructure_failure} =
             dispatch(
               foreign_account_id,
               ~U[2026-08-31 12:43:00.000000Z],
               %{stale_command | mutation_id: Ecto.UUID.generate()}
             )

    assert stored_task(account_id, task_id) ==
             %{notes: "Later edit", revision: 3, title: "Current title"}
  end

  defp capture(account_id, title) do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, @accepted_at, %{
               type: :capture_task,
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: title,
               version: 1
             })

    task_id
  end

  defp dispatch(account_id, accepted_at, command) do
    Commands.dispatch(
      command,
      %{account_id: account_id, accepted_at: accepted_at, actor_type: "user", client_kind: "web"},
      CommandStore
    )
  end

  defp stored_conflict(account_id, conflict_id) do
    %{rows: [[count, resolved_by]]} =
      SQL.query!(
        Repo,
        """
        SELECT count(*), max(resolved_by_mutation_id)
        FROM persisted_conflicts
        WHERE account_id = $1 AND id = $2
        """,
        [account_id, Ecto.UUID.dump!(conflict_id)]
      )

    %{count: count, resolved_by: if(resolved_by, do: Ecto.UUID.load!(resolved_by))}
  end

  defp stored_task(account_id, task_id) do
    %{rows: [[title, notes, revision]]} =
      SQL.query!(
        Repo,
        "SELECT title, notes, revision FROM tasks WHERE account_id = $1 AND id = $2",
        [account_id, Ecto.UUID.dump!(task_id)]
      )

    %{notes: notes, revision: revision, title: title}
  end
end

defmodule KeeplingWeb.ConflictBoundaryTest do
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

    %{
      account_id: account_id,
      conn: login,
      csrf_token: json_response(login, 200)["csrf_token"]
    }
  end

  test "closed Phoenix conflict resolution carries the persisted DTO through acknowledgement", %{
    account_id: account_id,
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    assert %{"revision" => 1} =
             conn
             |> command(csrf_token, "/api/v1/commands/capture-task", %{
               "mutation_id" => Ecto.UUID.generate(),
               "task_id" => task_id,
               "title" => "Base title",
               "version" => 1
             })
             |> json_response(201)

    SQL.query!(
      Repo,
      "UPDATE tasks SET title = 'Current title', revision = 2 WHERE account_id = $1 AND id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    conflict =
      conn
      |> command(csrf_token, "/api/v1/commands/edit-task", %{
        "base_values" => %{"title" => "Base title"},
        "expected_revision" => 1,
        "fields" => %{"title" => "My title"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })
      |> json_response(409)

    assert %{
             "affected_fields" => ["title"],
             "conflict" => %{"id" => conflict_id, "latest_revision" => 2}
           } = conflict

    resolution_mutation_id = Ecto.UUID.generate()

    resolved =
      conn
      |> command(csrf_token, "/api/v1/commands/resolve-task-conflict", %{
        "conflict_id" => conflict_id,
        "latest_revision" => 2,
        "mutation_id" => resolution_mutation_id,
        "selections" => %{"title" => "mine"},
        "task_id" => task_id,
        "version" => 1
      })
      |> json_response(200)

    assert %{
             "mutation_id" => ^resolution_mutation_id,
             "revision" => 3,
             "snapshot" => %{"title" => "My title"}
           } = resolved

    invalid =
      conn
      |> command(csrf_token, "/api/v1/commands/resolve-task-conflict", %{
        "conflict_id" => conflict_id,
        "latest_revision" => 3,
        "mutation_id" => Ecto.UUID.generate(),
        "selections" => %{"title" => "current"},
        "task_id" => task_id,
        "unexpected" => true,
        "version" => 1
      })

    assert %{"code" => "invalid_command"} = json_response(invalid, 400)
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
