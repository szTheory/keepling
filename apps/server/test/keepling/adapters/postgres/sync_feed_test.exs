defmodule Keepling.Adapters.Postgres.SyncFeedTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.{CommandStore, SyncFeed}
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @accepted_at ~U[2026-09-01 10:00:00.000000Z]

  setup do
    account_id = insert_account()

    on_exit(fn ->
      with_connection(fn _backend_pid ->
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id}
  end

  test "first delivery commits terminal outcomes and stable envelopes while replay appends nothing", %{
    account_id: account_id
  } do
    task_id = Ecto.UUID.generate()
    mutation_id = Ecto.UUID.generate()

    command = %{
      mutation_id: mutation_id,
      task_id: task_id,
      title: "Feed-backed capture",
      type: :capture_task,
      version: 1
    }

    assert {:ok, %{status: 201}} = dispatch(account_id, command, @accepted_at)

    assert {:ok,
            %{
              high_water: %{sequence: 1, ordinal: 1},
              changes: [outcome, snapshot]
            }} = list_after(account_id)

    assert %{kind: "command_outcome", sequence: 1, ordinal: 0} = outcome

    assert %{
             kind: "task_snapshot",
             sequence: 1,
             ordinal: 1,
             entity_id: ^task_id,
             entity_revision: 1,
             payload: %{"trashed_at" => nil}
           } = snapshot

    assert {:ok, %{status: 201}} =
             dispatch(account_id, command, DateTime.add(@accepted_at, 60, :second))

    assert {:ok, %{changes: replay_changes}} = list_after(account_id)
    assert length(replay_changes) == 2

    rejected = %{
      mutation_id: Ecto.UUID.generate(),
      task_id: Ecto.UUID.generate(),
      title: "   ",
      type: :capture_task,
      version: 1
    }

    assert {:ok, %{status: 422}} =
             dispatch(account_id, rejected, DateTime.add(@accepted_at, 120, :second))

    assert {:ok, %{changes: changes, high_water: %{sequence: 2, ordinal: 0}}} =
             list_after(account_id)

    assert Enum.map(changes, &{&1.sequence, &1.ordinal, &1.kind}) == [
             {1, 0, "command_outcome"},
             {1, 1, "task_snapshot"},
             {2, 0, "command_outcome"}
           ]
  end

  test "persisted conflict is emitted in the same ordered transaction", %{account_id: account_id} do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, %{
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: "Base title",
               type: :capture_task,
               version: 1
             })

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        "UPDATE tasks SET title = 'Current title', revision = 2 WHERE account_id = $1 AND id = $2",
        [account_id, Ecto.UUID.dump!(task_id)]
      )
    end)

    conflict_command = %{
      base_values: %{title: "Base title"},
      expected_revision: 1,
      fields: %{title: "Mine"},
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      type: :edit_task,
      version: 1
    }

    assert {:ok, %{status: 409, body: %{"conflict" => %{"id" => conflict_id}}}} =
             dispatch(account_id, conflict_command, DateTime.add(@accepted_at, 60, :second))

    assert {:ok, %{changes: changes}} = list_after(account_id)

    assert Enum.any?(changes, fn change ->
             change.kind == "conflict_snapshot" and change.entity_id == conflict_id and
               change.sequence == 2
           end)
  end

  test "rollback exposes no feed position and concurrent backends allocate a gap-free account order", %{
    account_id: account_id
  } do
    assert {:error, :forced_rollback} =
             with_connection(fn _backend_pid ->
               Repo.transact(fn repo ->
                 assert {:ok, 1} = SyncFeed.reserve_sequence(repo, account_id, @accepted_at)
                 Repo.rollback(:forced_rollback)
               end)
             end)

    assert {:ok, %{changes: [], high_water: nil}} = list_after(account_id)

    barrier = start_barrier(2)

    deliveries =
      for index <- 1..2 do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            result =
              dispatch_direct(account_id, %{
                mutation_id: Ecto.UUID.generate(),
                task_id: Ecto.UUID.generate(),
                title: "Concurrent #{index}",
                type: :capture_task,
                version: 1
              })

            {backend_pid, result}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 10_000))

    assert deliveries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2
    assert Enum.all?(deliveries, &match?({_pid, {:ok, %{status: 201}}}, &1))

    assert {:ok, %{changes: changes, high_water: %{sequence: 2, ordinal: 1}}} =
             list_after(account_id)

    assert changes |> Enum.map(& &1.sequence) |> Enum.uniq() == [1, 2]
    assert Enum.map(changes, &{&1.sequence, &1.ordinal}) == [{1, 0}, {1, 1}, {2, 0}, {2, 1}]
  end

  defp dispatch(account_id, command, accepted_at \\ @accepted_at) do
    with_connection(fn _backend_pid -> dispatch_direct(account_id, command, accepted_at) end)
  end

  defp dispatch_direct(account_id, command, accepted_at \\ @accepted_at) do
    Commands.dispatch(
      command,
      %{account_id: account_id, accepted_at: accepted_at, actor_type: "user", client_kind: "web"},
      CommandStore
    )
  end

  defp list_after(account_id) do
    with_connection(fn _backend_pid -> SyncFeed.list_after(account_id, nil, 200) end)
  end

  defp insert_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
        """,
        [account_id, @accepted_at]
      )
    end)

    account_id
  end
end
