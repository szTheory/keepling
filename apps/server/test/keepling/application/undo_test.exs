defmodule Keepling.Application.UndoTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Undo
  alias Keepling.Domain.Task

  test "the storage-neutral vector closes the supported matrix and inverse labels" do
    vectors = undo_vectors()

    assert vectors["version"] == 1
    assert vectors["valid_for_seconds"] == 86_400

    for supported <- vectors["supported"] do
      command_type = String.to_existing_atom(supported["command"])

      assert Undo.supported_command?(command_type), supported["command"]

      assert {:ok, compensation} =
               Undo.compensation(
                 %{type: command_type},
                 activity_for(command_type)
               )

      assert Atom.to_string(compensation.inverse.kind) == supported["inverse"]
      assert compensation.label == supported["label"]
    end

    for unsupported <- vectors["unsupported"] do
      refute Undo.supported_command?(String.to_atom(unsupported)), unsupported
    end

    # D-22/T-05-44: the agent case names a supported command and carries no
    # actor-specific clause -- `Undo.compensation/2` takes no actor argument
    # at all, so there is nothing in this module's own signature that could
    # discriminate on who performed the original action.
    agent_command = String.to_existing_atom(vectors["agent_case"]["command"])
    assert Undo.supported_command?(agent_command)
  end

  test "typed compensation restores only the closed original values and appends an inverse fact" do
    current = task(revision: 8, title: "After", notes: "After notes")

    inverse = %{
      kind: :details,
      values: %{"notes" => "Before notes", "title" => "Before"}
    }

    assert {:ok, restored, activity} =
             Undo.apply(current, inverse, ~U[2026-08-31 14:00:00.000000Z])

    assert restored.revision == 9
    assert restored.title == "Before"
    assert restored.notes == "Before notes"
    assert restored.inbox_state == current.inbox_state
    assert restored.planned_on == current.planned_on
    assert restored.completed_at == current.completed_at
    assert restored.trashed_at == current.trashed_at

    assert activity == %{
             accepted_at: ~U[2026-08-31 14:00:00.000000Z],
             changed_fields: %{
               "notes" => %{"from" => "After notes", "to" => "Before notes"},
               "title" => %{"from" => "After", "to" => "Before"}
             },
             from_revision: 8,
             to_revision: 9,
             type: :task_undo_applied,
             version: 1
           }

    assert {:error, :invalid_inverse} =
             Undo.apply(
               current,
               %{kind: :details, values: %{"project_id" => nil}},
               ~U[2026-08-31 14:00:00.000000Z]
             )
  end

  defp task(overrides) do
    struct!(
      Task,
      Keyword.merge(
        [
          captured_at: ~U[2026-08-31 12:00:00.000000Z],
          completed_at: nil,
          deadline_on: ~D[2026-09-03],
          id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
          inbox_state: :inbox,
          lifecycle_revision: 0,
          notes: "",
          planned_on: ~D[2026-08-31],
          revision: 1,
          title: "Before",
          trashed_at: nil
        ],
        overrides
      )
    )
  end

  defp activity_for(:edit_task),
    do: activity(%{"title" => %{"from" => "Before", "to" => "After"}})

  defp activity_for(:clarify_task),
    do: activity(%{"inbox_state" => %{"from" => "inbox", "to" => "clarified"}})

  defp activity_for(:return_to_inbox),
    do: activity(%{"inbox_state" => %{"from" => "clarified", "to" => "inbox"}})

  defp activity_for(type) when type in [:plan_for_today, :unplan_task],
    do: activity(%{"planned_on" => %{"from" => nil, "to" => ~D[2026-08-31]}})

  defp activity_for(type) when type in [:complete_task, :reopen_task],
    do: activity(%{"completed_at" => %{"from" => nil, "to" => ~U[2026-08-31 13:00:00Z]}})

  defp activity_for(type) when type in [:trash_task, :restore_task],
    do: activity(%{"trashed_at" => %{"from" => nil, "to" => ~U[2026-08-31 13:00:00Z]}})

  defp activity(changed_fields),
    do: %{
      accepted_at: ~U[2026-08-31 13:00:00.000000Z],
      changed_fields: changed_fields,
      from_revision: 1,
      to_revision: 2,
      type: :task_details_updated,
      version: 1
    }

  defp undo_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/undo.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule Keepling.Application.UndoRaceTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.{Commands, Undo}
  alias Keepling.Repo

  @captured_at ~U[2026-08-31 15:00:00.000000Z]

  setup do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
        VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
        """,
        [account_id, @captured_at]
      )
    end)

    on_exit(fn ->
      with_connection(fn _backend_pid ->
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id}
  end

  test "independent compensation consumers serialize to one inverse, activity, and winner", %{
    account_id: account_id
  } do
    task_id = Ecto.UUID.generate()

    {:ok, %{status: 201}} =
      with_connection(fn _backend_pid ->
        Commands.dispatch(
          %{
            mutation_id: Ecto.UUID.generate(),
            task_id: task_id,
            title: "Race one undo",
            type: :capture_task,
            version: 1
          },
          context(account_id, @captured_at),
          CommandStore
        )
      end)

    {:ok, %{body: %{"undo" => %{"handle" => handle}}}} =
      with_connection(fn _backend_pid ->
        Commands.dispatch(
          %{
            base_values: %{title: "Race one undo"},
            expected_revision: 1,
            fields: %{title: "Race changed"},
            mutation_id: Ecto.UUID.generate(),
            task_id: task_id,
            type: :edit_task,
            version: 1
          },
          context(account_id, ~U[2026-08-31 15:01:00.000000Z]),
          CommandStore
        )
      end)

    barrier = start_barrier(2)

    results =
      for second <- [2, 3] do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            result =
              Undo.dispatch(
                %{
                  handle: handle,
                  mutation_id: Ecto.UUID.generate(),
                  type: :undo_task,
                  version: 1
                },
                context(account_id, DateTime.add(@captured_at, second * 60, :second)),
                CommandStore
              )

            {backend_pid, result}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 10_000))

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2

    assert Enum.sort(
             Enum.map(results, fn {_pid, {:ok, %{body: %{"outcome" => outcome}}}} -> outcome end)
           ) == ["accepted", "already_applied"]

    with_connection(fn _backend_pid ->
      assert %{rows: [[3, "Race one undo", 3, 1, 1]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT tasks.revision, tasks.title,
                        (SELECT count(*) FROM task_activities WHERE account_id = $1),
                        (SELECT count(*) FROM task_activities
                         WHERE account_id = $1 AND activity_type = 'task_undo_applied'),
                        (SELECT count(*) FROM undo_handles
                         WHERE account_id = $1 AND state = 'applied')
                 FROM tasks WHERE account_id = $1 AND id = $2
                 """,
                 [account_id, Ecto.UUID.dump!(task_id)]
               )
    end)
  end

  defp context(account_id, accepted_at),
    do: %{
      accepted_at: accepted_at,
      account_id: account_id,
      actor_type: "user",
      client_kind: "web"
    }
end

defmodule KeeplingWeb.UndoBoundaryTest do
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
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
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

  test "authenticated closed undo route applies exact compensation without exposing the handle in reads",
       %{conn: conn, csrf_token: csrf_token} do
    task_id = Ecto.UUID.generate()

    captured =
      command(conn, csrf_token, "/api/v1/commands/capture-task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => "Boundary undo",
        "version" => 1
      })

    assert %{"revision" => 1} = json_response(captured, 201)

    edited =
      command(conn, csrf_token, "/api/v1/commands/edit-task", %{
        "base_values" => %{"title" => "Boundary undo"},
        "expected_revision" => 1,
        "fields" => %{"title" => "Boundary changed"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"undo" => %{"handle" => handle, "label" => "Undo task edit"}} =
             json_response(edited, 200)

    unauthenticated =
      build_conn()
      |> trusted_request()
      |> post("/api/v1/commands/undo-task", %{
        "handle" => handle,
        "mutation_id" => Ecto.UUID.generate(),
        "version" => 1
      })

    assert %{"code" => "authentication_required"} = json_response(unauthenticated, 401)

    undone =
      command(conn, csrf_token, "/api/v1/commands/undo-task", %{
        "handle" => handle,
        "mutation_id" => Ecto.UUID.generate(),
        "version" => 1
      })

    assert %{
             "outcome" => "accepted",
             "revision" => 3,
             "snapshot" => %{"title" => "Boundary undo"}
           } =
             json_response(undone, 200)

    activity = conn |> recycle() |> get("/api/v1/tasks/#{task_id}/activity") |> json_response(200)
    activity_text = Jason.encode!(activity)

    assert [
             %{"type" => "task_undo_applied", "undone_activity_id" => undone_id},
             %{"recovery_state" => "undone", "type" => "task_details_updated"} | _
           ] =
             activity["items"]

    assert is_integer(undone_id)
    refute activity_text =~ handle
    refute activity_text =~ "undo_handle"
  end

  test "closed transport rejects malformed handle before creating a receipt", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    mutation_id = Ecto.UUID.generate()

    invalid =
      command(conn, csrf_token, "/api/v1/commands/undo-task", %{
        "handle" => "not-a-handle",
        "mutation_id" => mutation_id,
        "version" => 1
      })

    assert %{"code" => "invalid_command"} = json_response(invalid, 400)

    assert %{rows: [[0]]} =
             SQL.query!(Repo, "SELECT count(*) FROM command_receipts WHERE mutation_id = $1", [
               Ecto.UUID.dump!(mutation_id)
             ])
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

defmodule Keepling.Application.UndoPersistenceTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.{Commands, Undo}
  alias Keepling.Repo

  @captured_at ~U[2026-08-31 12:00:00.000000Z]

  setup do
    account_id = create_account()
    %{account_id: account_id}
  end

  test "accepted compensation is hash-only, exact-revision, atomic, one-shot, linked, and replayable",
       %{
         account_id: account_id
       } do
    task_id = capture(account_id)
    edit_id = Ecto.UUID.generate()

    edit =
      dispatch(account_id, ~U[2026-08-31 12:01:00.000000Z], %{
        base_values: %{title: "Undo proof"},
        expected_revision: 1,
        fields: %{title: "Changed once"},
        mutation_id: edit_id,
        task_id: task_id,
        type: :edit_task,
        version: 1
      })

    assert {:ok,
            %{
              body: %{
                "revision" => 2,
                "undo" => %{
                  "expires_at" => "2026-09-01T12:01:00.000000Z",
                  "handle" => handle,
                  "label" => "Undo task edit"
                }
              }
            }} = edit

    assert is_binary(handle) and byte_size(handle) >= 43
    refute stored_undo_text(account_id) =~ handle
    refute stored_receipt_text(account_id, edit_id) =~ handle

    undo_id = Ecto.UUID.generate()

    undo_command = %{
      handle: handle,
      mutation_id: undo_id,
      type: :undo_task,
      version: 1
    }

    accepted =
      Undo.dispatch(undo_command, context(account_id, ~U[2026-08-31 12:02:00Z]), CommandStore)

    assert {:ok,
            %{
              body: %{
                "mutation_id" => ^undo_id,
                "outcome" => "accepted",
                "revision" => 3,
                "snapshot" => %{"title" => "Undo proof"},
                "task_id" => ^task_id,
                "warnings" => []
              }
            }} = accepted

    assert accepted ==
             Undo.dispatch(
               undo_command,
               context(account_id, ~U[2026-08-31 12:03:00Z]),
               CommandStore
             )

    state = stored_state(account_id, task_id)
    assert state.revision == 3
    assert state.title == "Undo proof"
    assert state.activities == 3
    assert state.undo_rows == 1
    assert state.applied_handles == 1
    assert state.original_recovery_state == "undone"
    assert state.undo_linked == 1

    second_id = Ecto.UUID.generate()

    assert {:ok, %{body: %{"code" => "undo_already_applied", "outcome" => "already_applied"}}} =
             Undo.dispatch(
               %{undo_command | mutation_id: second_id},
               context(account_id, ~U[2026-08-31 12:04:00Z]),
               CommandStore
             )

    assert stored_state(account_id, task_id).activities == 3
  end

  test "expired, stale, and unknown handles apply no inverse", %{
    account_id: account_id
  } do
    task_id = capture(account_id)
    {handle, _edit_id} = edit_title(account_id, task_id, 1, "Changed")

    {_newer_handle, _newer_edit_id} = edit_title(account_id, task_id, 2, "Changed again")

    assert {:ok, %{body: %{"code" => "undo_stale", "outcome" => "stale"}}} =
             undo(account_id, handle, ~U[2026-08-31 12:04:00Z])

    assert stored_state(account_id, task_id).title == "Changed again"

    assert {:ok, %{body: %{"code" => "undo_unknown", "outcome" => "unknown"}}} =
             undo(
               account_id,
               Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
               ~U[2026-08-31 12:05:00Z]
             )

    {expiring_handle, _edit_id} = edit_title(account_id, task_id, 3, "Expires")

    assert {:ok, %{body: %{"code" => "undo_expired", "outcome" => "expired"}}} =
             undo(account_id, expiring_handle, ~U[2026-09-01 12:05:01Z])

    assert stored_state(account_id, task_id).title == "Expires"
  end

  defp capture(account_id) do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, @captured_at, %{
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: "Undo proof",
               type: :capture_task,
               version: 1
             })

    task_id
  end

  defp edit_title(account_id, task_id, revision, title) do
    mutation_id = Ecto.UUID.generate()

    {:ok, %{body: %{"snapshot" => snapshot, "undo" => %{"handle" => handle}}}} =
      dispatch(account_id, ~U[2026-08-31 12:05:00Z], %{
        base_values: %{
          title:
            if(revision == 1, do: "Undo proof", else: stored_state(account_id, task_id).title)
        },
        expected_revision: revision,
        fields: %{title: title},
        mutation_id: mutation_id,
        task_id: task_id,
        type: :edit_task,
        version: 1
      })

    assert snapshot["title"] == title
    {handle, mutation_id}
  end

  defp undo(account_id, handle, accepted_at) do
    Undo.dispatch(
      %{handle: handle, mutation_id: Ecto.UUID.generate(), type: :undo_task, version: 1},
      context(account_id, accepted_at),
      CommandStore
    )
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @captured_at]
    )

    account_id
  end

  defp dispatch(account_id, accepted_at, command),
    do: Commands.dispatch(command, context(account_id, accepted_at), CommandStore)

  defp context(account_id, accepted_at),
    do: %{
      accepted_at: accepted_at,
      account_id: account_id,
      actor_type: "user",
      client_kind: "web"
    }

  defp stored_undo_text(account_id) do
    %{rows: [[value]]} =
      SQL.query!(
        Repo,
        "SELECT row_to_json(undo_handles)::text FROM undo_handles WHERE account_id = $1",
        [account_id]
      )

    value
  end

  defp stored_receipt_text(account_id, mutation_id) do
    %{rows: [[value]]} =
      SQL.query!(
        Repo,
        "SELECT response::text FROM command_receipts WHERE account_id = $1 AND mutation_id = $2",
        [
          account_id,
          Ecto.UUID.dump!(mutation_id)
        ]
      )

    value
  end

  defp stored_state(account_id, task_id) do
    %{rows: [[revision, title, activities, undo_rows, applied, original_state, linked]]} =
      SQL.query!(
        Repo,
        """
        SELECT tasks.revision, tasks.title,
               (SELECT count(*) FROM task_activities WHERE account_id = $1 AND task_id = $2),
               (SELECT count(*) FROM undo_handles WHERE account_id = $1 AND task_id = $2),
               (SELECT count(*) FROM undo_handles WHERE account_id = $1 AND task_id = $2 AND state = 'applied'),
               (SELECT recovery_state FROM task_activities
                WHERE account_id = $1 AND task_id = $2 AND activity_type = 'task_details_updated'
                ORDER BY id ASC LIMIT 1),
               (SELECT count(*) FROM task_activities
                WHERE account_id = $1 AND task_id = $2 AND activity_type = 'task_undo_applied'
                  AND undone_activity_id IS NOT NULL)
        FROM tasks WHERE account_id = $1 AND id = $2
        """,
        [account_id, Ecto.UUID.dump!(task_id)]
      )

    %{
      activities: activities,
      applied_handles: applied,
      original_recovery_state: original_state,
      revision: revision,
      title: title,
      undo_linked: linked,
      undo_rows: undo_rows
    }
  end
end
