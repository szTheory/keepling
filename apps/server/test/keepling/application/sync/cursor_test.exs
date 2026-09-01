defmodule Keepling.Application.Sync.CursorTest do
  use ExUnit.Case, async: true

  alias Keepling.Adapters.Postgres.SyncFeed
  alias Keepling.Application.Sync.{Cursor, ReferenceModel}

  @now ~U[2026-09-01 11:00:00.000000Z]
  @secret String.duplicate("sync-cursor-key-v1", 2)
  @keyring %{active: "v1", keys: %{"v1" => @secret}}
  @namespace %{
    issuer: "https://id.keepling.test",
    origin: "https://keepling.test",
    server_instance: "server-01",
    subject: "00000000-0000-4000-8000-000000000001",
    generation: 3,
    sync_epoch: "00000000-0000-4000-8000-0000000000e1",
    protocol_train: 1
  }

  test "authenticated cursor round trips only in its complete server-derived namespace" do
    position = %{sequence: 42, ordinal: 3}
    cursor = Cursor.encode(position, @namespace, @keyring, @now)

    assert {:ok, ^position} = Cursor.decode(cursor, @namespace, @keyring, @now)
    refute cursor =~ "server-01"
    refute cursor =~ @namespace.subject

    for {field, value} <- [
          issuer: "https://other-id.test",
          origin: "https://other-origin.test",
          server_instance: "server-02",
          subject: "00000000-0000-4000-8000-000000000002",
          generation: 4
        ] do
      assert {:reset_required, %{reason: "namespace_mismatch", recovery: "quarantine"}} =
               Cursor.decode(cursor, Map.put(@namespace, field, value), @keyring, @now),
             "expected #{field} mismatch to quarantine"
    end

    assert :ok = SyncFeed.authorize_namespace(@namespace, @namespace)

    assert {:error, :namespace_mismatch} =
             SyncFeed.authorize_namespace(@namespace, Map.put(@namespace, :generation, 4))
  end

  test "tamper restore protocol codec expiry and low-water failures are closed reset reasons" do
    position = %{sequence: 42, ordinal: 3}
    cursor = Cursor.encode(position, @namespace, @keyring, @now)
    prefix_size = byte_size(cursor) - 1
    <<prefix::binary-size(^prefix_size), last>> = cursor
    replacement = if last == ?A, do: ?B, else: ?A

    assert {:reset_required, %{reason: "tampered_cursor", recovery: "bootstrap"}} =
             Cursor.decode(prefix <> <<replacement>>, @namespace, @keyring, @now)

    assert {:reset_required, %{reason: "restore_epoch_changed", recovery: "bootstrap"}} =
             Cursor.decode(
               cursor,
               Map.put(@namespace, :sync_epoch, "00000000-0000-4000-8000-0000000000e2"),
               @keyring,
               @now
             )

    protocol_cursor =
      Cursor.encode(position, Map.put(@namespace, :protocol_train, 2), @keyring, @now)

    assert {:reset_required, %{reason: "unsupported_protocol", recovery: "upgrade"}} =
             Cursor.decode(protocol_cursor, @namespace, @keyring, @now)

    codec_cursor = Cursor.encode(position, @namespace, @keyring, @now, codec_version: 2)

    assert {:reset_required, %{reason: "unsupported_codec", recovery: "upgrade"}} =
             Cursor.decode(codec_cursor, @namespace, @keyring, @now)

    assert {:reset_required, %{reason: "cursor_expired", recovery: "bootstrap"}} =
             Cursor.decode(cursor, @namespace, @keyring, DateTime.add(@now, 91, :day))

    assert {:reset_required, %{reason: "below_low_water", recovery: "bootstrap"}} =
             Cursor.decode(cursor, @namespace, @keyring, @now,
               low_water: %{sequence: 42, ordinal: 4}
             )
  end

  test "retention defaults remain bounded and stale feed data cannot regress an acknowledgement" do
    assert %{
             pull_page_limit: 200,
             offline_grace_days: 30,
             pruning_batch_size: 1_000,
             destructive_pruning: false
           } = Cursor.defaults()

    mutation = mutation("mutation-1", 2)
    {:ok, "local_saved", state} = ReferenceModel.local_accept(ReferenceModel.new(), mutation)

    acknowledgement = %{
      "mutation_id" => "mutation-1",
      "fingerprint" => mutation["fingerprint"],
      "outcome" => "accepted",
      "snapshot" => %{"revision" => 3, "title" => "Acknowledged"}
    }

    assert {:ok, acknowledged} = ReferenceModel.acknowledge(state, acknowledgement)

    stale_page = %{
      "cursor" => "opaque-coverage-position",
      "changes" => [
        %{
          "entity_id" => "task-1",
          "snapshot" => %{"revision" => 2, "title" => "Stale feed"}
        }
      ]
    }

    assert {:ok, pulled} = ReferenceModel.pull(acknowledged, stale_page)
    assert get_in(pulled, ["canonical_shadow", "task-1", "title"]) == "Acknowledged"
    assert pulled["cursor"] == "opaque-coverage-position"
  end

  defp mutation(id, revision) do
    command_bytes = Jason.encode!(%{"mutation_id" => id, "type" => "edit_task"})

    %{
      "accepted_at" => DateTime.to_iso8601(@now),
      "command_bytes" => command_bytes,
      "dependencies" => [],
      "effect" => %{
        "entity_id" => "task-1",
        "snapshot" => %{"revision" => revision, "title" => "Local"}
      },
      "fingerprint" => :crypto.hash(:sha256, command_bytes) |> Base.encode16(case: :lower),
      "mutation_id" => id,
      "resource_keys" => ["task:task-1"]
    }
  end
end
