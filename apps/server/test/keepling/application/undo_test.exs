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
      refute Undo.supported_command?(String.to_existing_atom(unsupported)), unsupported
    end
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
             Undo.apply(current, %{kind: :details, values: %{"project_id" => nil}},
               ~U[2026-08-31 14:00:00.000000Z]
             )
  end

  defp task(overrides) do
    struct!(Task,
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

defmodule Keepling.Application.UndoPersistenceTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.{Commands, Undo}
  alias Keepling.Repo

  @captured_at ~U[2026-08-31 12:00:00.000000Z]

  setup do
    account_id = create_account(true)
    %{account_id: account_id}
  end

  test "accepted compensation is hash-only, exact-revision, atomic, one-shot, linked, and replayable", %{
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

    accepted = Undo.dispatch(undo_command, context(account_id, ~U[2026-08-31 12:02:00Z]), CommandStore)

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
             Undo.dispatch(undo_command, context(account_id, ~U[2026-08-31 12:03:00Z]), CommandStore)

    state = stored_state(account_id, task_id)
    assert state.revision == 3
    assert state.title == "Undo proof"
    assert state.activities == 3
    assert state.undo_rows == 1
    assert state.applied_handles == 1
    assert state.original_recovery_state == "undone"
    assert state.undo_linked == 1

    second_id = Ecto.UUID.generate()

    assert {:ok,
            %{body: %{"code" => "undo_already_applied", "outcome" => "already_applied"}}} =
             Undo.dispatch(
               %{undo_command | mutation_id: second_id},
               context(account_id, ~U[2026-08-31 12:04:00Z]),
               CommandStore
             )

    assert stored_state(account_id, task_id).activities == 3
  end

  test "expired, stale, unknown, and cross-account handles apply no inverse", %{
    account_id: account_id
  } do
    task_id = capture(account_id)
    {handle, _edit_id} = edit_title(account_id, task_id, 1, "Changed")

    {_newer_handle, _newer_edit_id} = edit_title(account_id, task_id, 2, "Changed again")

    assert {:ok, %{body: %{"code" => "undo_stale", "outcome" => "stale"}}} =
             undo(account_id, handle, ~U[2026-08-31 12:04:00Z])

    assert stored_state(account_id, task_id).title == "Changed again"

    other_account = create_account(false)

    assert {:ok, %{body: %{"code" => "undo_unknown", "outcome" => "unknown"}}} =
             undo(other_account, handle, ~U[2026-08-31 12:05:00Z])

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
        base_values: %{title: if(revision == 1, do: "Undo proof", else: stored_state(account_id, task_id).title)},
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

  defp create_account(singleton_key) do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, $2, '$argon2id$test-fixture', 'Etc/UTC', $3, $3)
      """,
      [account_id, singleton_key, @captured_at]
    )

    account_id
  end

  defp dispatch(account_id, accepted_at, command),
    do: Commands.dispatch(command, context(account_id, accepted_at), CommandStore)

  defp context(account_id, accepted_at),
    do: %{accepted_at: accepted_at, account_id: account_id, actor_type: "user", client_kind: "web"}

  defp stored_undo_text(account_id) do
    %{rows: [[value]]} =
      SQL.query!(Repo, "SELECT row_to_json(undo_handles)::text FROM undo_handles WHERE account_id = $1", [account_id])

    value
  end

  defp stored_receipt_text(account_id, mutation_id) do
    %{rows: [[value]]} =
      SQL.query!(Repo, "SELECT response::text FROM command_receipts WHERE account_id = $1 AND mutation_id = $2", [
        account_id,
        Ecto.UUID.dump!(mutation_id)
      ])

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

  defp undo_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/undo.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end
