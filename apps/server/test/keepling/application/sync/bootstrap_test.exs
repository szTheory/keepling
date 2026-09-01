defmodule Keepling.Application.Sync.BootstrapTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.{CommandStore, SyncFeed}
  alias Keepling.Application.Commands
  alias Keepling.Application.Sync
  alias Keepling.Application.Sync.ReferenceModel
  alias Keepling.Repo
  alias Keepling.SyncScenario

  @now ~U[2026-09-01 12:00:00.000000Z]
  @secret String.duplicate("bootstrap-cursor-key", 2)
  @keyring %{active: "v1", keys: %{"v1" => @secret}}

  setup do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    namespace = %{
      issuer: "https://id.keepling.test",
      origin: "https://keepling.test",
      server_instance: "server-01",
      subject: Ecto.UUID.load!(account_id),
      generation: 1,
      sync_epoch: "00000000-0000-4000-8000-0000000000e1",
      protocol_train: 1
    }

    %{
      account_id: account_id,
      context: %{
        account_id: account_id,
        authoritative_namespace: namespace,
        cursor_keyring: @keyring,
        namespace: namespace,
        now: @now
      }
    }
  end

  test "empty bootstrap is bounded and authorized", %{context: context} do
    assert {:ok,
            %{
              entities: [],
              high_water: %{sequence: 0, ordinal: -1},
              next_cursor: nil
            }} = Sync.bootstrap(context, %{limit: 2}, SyncFeed)
  end

  test "concurrent writes after high water remain in catch-up and Trash stays a snapshot", %{
    account_id: account_id,
    context: context
  } do
    first_id = capture(account_id, "First")
    trashed_id = capture(account_id, "Trash remains canonical")

    assert {:ok, %{body: %{"revision" => 2}}} =
             dispatch(account_id, %{
               expected_revision: 1,
               mutation_id: Ecto.UUID.generate(),
               task_id: trashed_id,
               type: :trash_task,
               version: 1
             })

    assert {:ok, first_page} = Sync.bootstrap(context, %{limit: 1}, SyncFeed)
    assert first_page.next_cursor
    high_water = first_page.high_water

    concurrent_id = capture(account_id, "Arrived between bootstrap pages")

    assert {:ok, remaining_pages} =
             SyncScenario.collect_bootstrap(
               context,
               %{cursor: first_page.next_cursor, limit: 1},
               SyncFeed
             )

    entities = first_page.entities ++ Enum.flat_map(remaining_pages, & &1.entities)
    entity_ids = Enum.map(entities, & &1["entity_id"])

    assert first_id in entity_ids
    assert trashed_id in entity_ids
    assert concurrent_id in entity_ids

    assert %{
             "kind" => "task_snapshot",
             "snapshot" => %{"trashed_at" => trashed_at}
           } = Enum.find(entities, &(&1["entity_id"] == trashed_id))

    assert is_binary(trashed_at)

    assert {:ok, %{changes: catch_up}} = SyncFeed.list_after(account_id, high_water, 200)

    assert Enum.any?(catch_up, fn change ->
             change.kind == "task_snapshot" and change.entity_id == concurrent_id
           end)
  end

  test "bootstrap replaces canonical shadow while immutable local intent replays unchanged", %{
    account_id: account_id,
    context: context
  } do
    server_task_id = capture(account_id, "Server truth")
    assert {:ok, pages} = SyncScenario.collect_bootstrap(context, %{limit: 2}, SyncFeed)

    command_bytes = Jason.encode!(%{"mutation_id" => "local-1", "type" => "capture_task"})

    mutation = %{
      "accepted_at" => DateTime.to_iso8601(@now),
      "command_bytes" => command_bytes,
      "dependencies" => [],
      "effect" => %{
        "entity_id" => "local-task",
        "snapshot" => %{"revision" => 1, "title" => "Pending locally"}
      },
      "fingerprint" => :crypto.hash(:sha256, command_bytes) |> Base.encode16(case: :lower),
      "mutation_id" => "local-1",
      "resource_keys" => ["task:local-task"]
    }

    {:ok, "local_saved", local_state} =
      ReferenceModel.local_accept(ReferenceModel.new(), mutation)

    entities = pages |> Enum.flat_map(& &1.entities) |> Enum.map(&bootstrap_change/1)
    final_page = List.last(pages)

    assert {:ok, rebuilt} =
             ReferenceModel.bootstrap(local_state, %{
               "cursor" => inspect(final_page.high_water),
               "entities" => entities
             })

    assert rebuilt["outbox"] == local_state["outbox"]
    assert rebuilt["journal"] == local_state["journal"]
    assert get_in(rebuilt, ["canonical_shadow", server_task_id, "title"]) == "Server truth"
    assert get_in(rebuilt, ["visible", "local-task", "title"]) == "Pending locally"
  end

  test "namespace and restore-epoch mismatches quarantine or reset before enumeration", %{
    context: context
  } do
    foreign = put_in(context, [:namespace, :generation], 2)

    assert {:quarantined, :namespace_mismatch} =
             Sync.bootstrap(foreign, %{limit: 2}, SyncFeed)

    assert {:ok, first_page} = Sync.bootstrap(context, %{limit: 1}, SyncFeed)

    restored =
      context
      |> put_in([:namespace, :sync_epoch], "00000000-0000-4000-8000-0000000000e2")
      |> put_in([:authoritative_namespace, :sync_epoch], "00000000-0000-4000-8000-0000000000e2")

    if first_page.next_cursor do
      assert {:reset_required, %{reason: "restore_epoch_changed"}} =
               Sync.bootstrap(
                 restored,
                 %{cursor: first_page.next_cursor, limit: 1},
                 SyncFeed
               )
    end
  end

  defp capture(account_id, title) do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, %{
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: title,
               type: :capture_task,
               version: 1
             })

    task_id
  end

  defp dispatch(account_id, command) do
    Commands.dispatch(
      command,
      %{account_id: account_id, accepted_at: @now, actor_type: "user", client_kind: "web"},
      CommandStore
    )
  end

  defp bootstrap_change(entity) do
    %{
      "entity_id" => entity["entity_id"],
      "snapshot" => entity["snapshot"]
    }
  end
end
