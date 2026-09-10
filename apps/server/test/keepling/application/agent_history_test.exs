defmodule Keepling.Application.AgentHistoryTest do
  @moduledoc """
  MCP-04 in full: agent attribution in the one existing history, a
  storage-level enumeration proving no reasoning/prompt/rationale/
  conversation column exists anywhere this phase writes, and the agent undo
  handle proven end to end (D-20, D-21, D-22, T-05-40..T-05-45).

  Every assertion here dispatches through `Commands.dispatch/3` (and, for the
  MCP-specific refusal causes, `KeeplingWeb.MCP.Tools.call/2`) with the exact
  same code path every other adapter uses -- there is no agent-only history
  surface to test against (D-20).
  """

  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.{Activity, Commands, Undo}
  alias Keepling.Repo
  alias KeeplingWeb.MCP.Tools

  @accepted_at ~U[2026-09-10 12:00:00.000000Z]
  @agent_label "Test Agent Grant"

  # T-05-40: the closed, explicit allow-list of text-bearing columns on the
  # two tables this phase writes to. Anything NOT in this list that shows up
  # in `information_schema.columns` fails the test -- a future migration
  # adding a free-text reasoning/prompt/rationale/conversation column fails
  # here before it ships, per D-21.
  @allowed_text_columns MapSet.new([
                          {"task_activities", "activity_type"},
                          {"task_activities", "actor_type"},
                          {"task_activities", "actor_principal"},
                          {"task_activities", "actor_label"},
                          {"task_activities", "client_kind"},
                          {"task_activities", "changed_fields"},
                          {"task_activities", "recovery_state"},
                          {"undo_handles", "original_command_type"},
                          {"undo_handles", "inverse_type"},
                          {"undo_handles", "inverse_payload"},
                          {"undo_handles", "label"},
                          {"undo_handles", "state"}
                        ])

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

  describe "agent attribution (Task 2)" do
    test "an accepted agent write produces exactly one activity fact naming the grant", %{
      account_id: account_id
    } do
      task_id = Ecto.UUID.generate()

      assert {:ok, %{status: 201}} =
               dispatch_agent(account_id, %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Capture via agent",
                 type: :capture_task,
                 version: 1
               })

      assert %{rows: [[1]]} = count_activity(account_id, task_id)

      assert {:ok, %{items: [fact]}} =
               Activity.list_task(
                 %{account_id: account_id, cursor_secret: String.duplicate("x", 32)},
                 task_id,
                 %{limit: 20},
                 CommandStore
               )

      assert fact.actor == %{label: @agent_label, principal: "authorized_grant", type: "agent"}
      assert fact.client_kind == "mcp"
    end

    test "an oversized grant label is truncated at write time rather than raising", %{
      account_id: account_id
    } do
      task_id = Ecto.UUID.generate()
      oversized_label = String.duplicate("A", 500)

      assert {:ok, %{status: 201}} =
               Commands.dispatch(
                 %{
                   mutation_id: Ecto.UUID.generate(),
                   task_id: task_id,
                   title: "Capture with oversized label",
                   type: :capture_task,
                   version: 1
                 },
                 %{
                   accepted_at: @accepted_at,
                   account_id: account_id,
                   actor_label: oversized_label,
                   actor_principal: "authorized_grant",
                   actor_type: "agent",
                   client_kind: "mcp"
                 },
                 CommandStore
               )

      assert %{rows: [[stored_label]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT actor_label FROM task_activities
                 WHERE account_id = $1 AND task_id = $2
                 """,
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert String.length(stored_label) == 200
      assert stored_label == String.duplicate("A", 200)
    end

    test "refused agent calls write zero activity facts, across four named causes", %{
      account_id: account_id
    } do
      # Cause 1: insufficient_scope -- refused at the MCP tool boundary,
      # before Commands.dispatch/3 is ever reached.
      scopeless_task_id = Ecto.UUID.generate()

      assert {:error, %{data: %{keepling_code: "insufficient_scope"}}} =
               Tools.call(
                 %{
                   "name" => "keepling.capture_task",
                   "arguments" => %{
                     "mutation_id" => Ecto.UUID.generate(),
                     "task_id" => scopeless_task_id,
                     "title" => "Should be refused for scope",
                     "version" => 1
                   }
                 },
                 mcp_context(account_id, [])
               )

      # Cause 2: invalid_command -- a malformed/incomplete tool call, refused
      # by the closed-key schema decoder before dispatch.
      assert {:error, %{data: %{keepling_code: "invalid_command"}}} =
               Tools.call(
                 %{"name" => "keepling.capture_task", "arguments" => %{"title" => "missing keys"}},
                 mcp_context(account_id, ["tasks.write"])
               )

      # Cause 3: task_not_found -- a real target that does not exist.
      assert {:ok, %{status: 404}} =
               dispatch_agent(account_id, %{
                 base_values: %{title: "X"},
                 expected_revision: 1,
                 fields: %{title: "Y"},
                 mutation_id: Ecto.UUID.generate(),
                 task_id: Ecto.UUID.generate(),
                 type: :edit_task,
                 version: 1
               })

      # Cause 4: stale revision -- an existing task whose lifecycle already
      # moved past the expected revision the agent still holds. `complete_task`
      # on a never-completed task treats `expected_revision: 0` as current
      # (lifecycle_revision starts at 0), so the setup below completes the
      # task first (advancing lifecycle_revision to 2) and then reopens it
      # with a now-stale `expected_revision: 0`.
      present_task_id = Ecto.UUID.generate()

      assert {:ok, %{status: 201}} =
               dispatch_agent(account_id, %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: present_task_id,
                 title: "Present",
                 type: :capture_task,
                 version: 1
               })

      assert {:ok, %{status: 200}} =
               dispatch_agent(account_id, %{
                 expected_revision: 0,
                 mutation_id: Ecto.UUID.generate(),
                 task_id: present_task_id,
                 type: :complete_task,
                 version: 1
               })

      assert {:ok, %{status: 409}} =
               dispatch_agent(account_id, %{
                 expected_revision: 1,
                 mutation_id: Ecto.UUID.generate(),
                 task_id: present_task_id,
                 type: :reopen_task,
                 version: 1
               })

      # Only the successful capture and complete (cause 4's setup) wrote
      # facts -- every refusal above, including the stale reopen, wrote zero.
      assert %{rows: [[2]]} = count_activity(account_id, present_task_id)
      assert %{rows: [[0]]} = count_activity(account_id, scopeless_task_id)
    end

    test "storage-level privacy: no reasoning/prompt/rationale/conversation column exists" do
      assert %{rows: rows} =
               SQL.query!(
                 Repo,
                 """
                 SELECT table_name, column_name
                 FROM information_schema.columns
                 WHERE table_schema = 'public'
                   AND table_name = ANY($1)
                   AND data_type IN ('text', 'character varying', 'json', 'jsonb')
                 """,
                 [["task_activities", "undo_handles"]]
               )

      found = MapSet.new(rows, fn [table, column] -> {table, column} end)

      unexpected = MapSet.difference(found, @allowed_text_columns)

      assert MapSet.size(unexpected) == 0,
             "unlisted text-bearing column(s) found -- review before allowing: #{inspect(MapSet.to_list(unexpected))}"

      # The allow-list itself must not have drifted stale (every listed
      # column must actually exist), so this test fails loudly if a column
      # this test relies on is ever renamed or dropped without updating it.
      missing = MapSet.difference(@allowed_text_columns, found)

      assert MapSet.size(missing) == 0,
             "allow-listed column(s) no longer exist -- update the allow-list: #{inspect(MapSet.to_list(missing))}"
    end
  end

  describe "agent undo handle (Task 3)" do
    test "an agent action of a supported command type is recorded available, and undoing it through the server reverses it",
         %{account_id: account_id} do
      task_id = Ecto.UUID.generate()

      # Before: capture the task (agent-authored), title "Original".
      assert {:ok, %{status: 201}} =
               dispatch_agent(account_id, %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Original",
                 type: :capture_task,
                 version: 1
               })

      assert {:ok, "Original"} = current_title(account_id, task_id)

      # After: the agent edits the task -- a supported command type.
      assert {:ok, %{status: 200, body: body}} =
               dispatch_agent(account_id, %{
                 base_values: %{notes: "", title: "Original"},
                 expected_revision: 1,
                 fields: %{notes: "", title: "Edited by agent"},
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 type: :edit_task,
                 version: 1
               })

      assert {:ok, "Edited by agent"} = current_title(account_id, task_id)
      assert %{"undo" => %{"handle" => handle, "label" => "Undo task edit"}} = body

      assert %{rows: [[2]]} = count_activity(account_id, task_id)

      assert %{rows: [[recovery_state]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT recovery_state FROM task_activities
                 WHERE account_id = $1 AND task_id = $2
                 ORDER BY accepted_at DESC, id DESC
                 LIMIT 1
                 """,
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert recovery_state == "available"

      # After the undo: the same undo endpoint a human action uses, exactly.
      assert {:ok, %{status: 200}} =
               Undo.dispatch(
                 %{handle: handle, mutation_id: Ecto.UUID.generate(), type: :undo_task, version: 1},
                 agent_context(account_id),
                 CommandStore
               )

      assert {:ok, "Original"} = current_title(account_id, task_id)

      assert %{rows: [[revision]]} =
               SQL.query!(
                 Repo,
                 "SELECT revision FROM tasks WHERE account_id = $1 AND id = $2",
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert revision == 3

      # The undo of the agent action is itself an activity fact.
      assert %{rows: [[3]]} = count_activity(account_id, task_id)

      assert %{rows: [[undo_type, undo_actor_type]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT activity_type, actor_type FROM task_activities
                 WHERE account_id = $1 AND task_id = $2
                 ORDER BY accepted_at DESC, id DESC
                 LIMIT 1
                 """,
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert undo_type == "task_undo_applied"
      assert undo_actor_type == "agent"

      # The original activity's recovery_state has moved to "undone".
      assert %{rows: [[original_recovery_state]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT recovery_state FROM task_activities
                 WHERE account_id = $1 AND task_id = $2 AND activity_type = 'task_details_updated'
                 """,
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert original_recovery_state == "undone"
    end

    test "an agent action of an unsupported command type records not_available", %{
      account_id: account_id
    } do
      task_id = Ecto.UUID.generate()

      assert {:ok, %{status: 201, body: body}} =
               dispatch_agent(account_id, %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Captured (capture is not undoable)",
                 type: :capture_task,
                 version: 1
               })

      refute Map.has_key?(body, "undo")

      assert %{rows: [[recovery_state]]} =
               SQL.query!(
                 Repo,
                 "SELECT recovery_state FROM task_activities WHERE account_id = $1 AND task_id = $2",
                 [account_id, Ecto.UUID.dump!(task_id)]
               )

      assert recovery_state == "not_available"
      refute Undo.supported_command?(:capture_task)
    end

    test "the undo handle expires on the same bound as a human action, and an expired handle reports expired rather than failing opaquely",
         %{account_id: account_id} do
      task_id = Ecto.UUID.generate()

      assert {:ok, %{status: 201}} =
               dispatch_agent(account_id, %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Original",
                 type: :capture_task,
                 version: 1
               })

      assert {:ok, %{status: 200, body: body}} =
               dispatch_agent(account_id, %{
                 base_values: %{notes: "", title: "Original"},
                 expected_revision: 1,
                 fields: %{notes: "", title: "Edited"},
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 type: :edit_task,
                 version: 1
               })

      assert %{"undo" => %{"expires_at" => expires_at, "handle" => handle}} = body
      {:ok, parsed_expires_at, _offset} = DateTime.from_iso8601(expires_at)

      assert DateTime.diff(parsed_expires_at, @accepted_at, :second) == Undo.valid_for_seconds()

      # Force expiry directly, exactly like a human-authored handle would
      # age out -- the mechanism carries no actor-specific expiry logic.
      SQL.query!(
        Repo,
        "UPDATE undo_handles SET expires_at = $3 WHERE account_id = $1 AND handle_hash = $2",
        [
          account_id,
          :crypto.hash(:sha256, handle),
          DateTime.add(@accepted_at, -1, :second)
        ]
      )

      assert {:ok, %{status: 200, body: undo_body}} =
               Undo.dispatch(
                 %{handle: handle, mutation_id: Ecto.UUID.generate(), type: :undo_task, version: 1},
                 agent_context(account_id),
                 CommandStore
               )

      assert undo_body["outcome"] == "expired"
      assert undo_body["code"] == "undo_expired"

      # Nothing was mutated -- the task still holds its edited title.
      assert {:ok, "Edited"} = current_title(account_id, task_id)
    end
  end

  defp dispatch_agent(account_id, command), do: Commands.dispatch(command, agent_context(account_id), CommandStore)

  defp agent_context(account_id) do
    %{
      accepted_at: @accepted_at,
      account_id: account_id,
      actor_label: @agent_label,
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: "mcp"
    }
  end

  defp mcp_context(account_id, scope) do
    %{
      account_id: account_id,
      accepted_at: @accepted_at,
      actor_label: @agent_label,
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: "mcp",
      scope: scope
    }
  end

  defp count_activity(account_id, task_id) do
    SQL.query!(
      Repo,
      "SELECT count(*) FROM task_activities WHERE account_id = $1 AND task_id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )
  end

  defp current_title(account_id, task_id) do
    case SQL.query!(Repo, "SELECT title FROM tasks WHERE account_id = $1 AND id = $2", [
           account_id,
           Ecto.UUID.dump!(task_id)
         ]) do
      %{rows: [[title]]} -> {:ok, title}
      %{rows: []} -> {:error, :not_found}
    end
  end
end
