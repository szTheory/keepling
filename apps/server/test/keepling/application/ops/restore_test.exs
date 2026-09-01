defmodule Keepling.Application.Ops.RestoreTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Ops.Restore

  @source "sha256:" <> String.duplicate("a", 64)
  @image "sha256:" <> String.duplicate("b", 64)
  @target "recovery-target-alpha"
  @now ~U[2026-09-01 12:00:00.000000Z]

  defmodule Store do
    @behaviour Keepling.Application.Ops.Restore.Port

    def start_link, do: Agent.start_link(fn -> %{completed: %{}, leases: %{}, runs: %{}} end)
    def state(store), do: Agent.get(store, & &1)

    @impl true
    def lookup_completed(key, store), do: Agent.get(store, &Map.fetch(&1.completed, key))

    @impl true
    def acquire_target(target_digest, lease, store) do
      Agent.get_and_update(store, fn state ->
        case Map.fetch(state.leases, target_digest) do
          :error -> {:ok, put_in(state, [:leases, target_digest], lease)}
          {:ok, _held} -> {{:error, :target_busy}, state}
        end
      end)
    end

    @impl true
    def begin_restore(record, store) do
      Agent.update(store, &put_in(&1, [:runs, record.run_id], record))
      :ok
    end

    @impl true
    def finalize_restore(run, proof, epoch, store) do
      Agent.get_and_update(store, fn state ->
        if get_in(state, [:leases, run.target_digest]) == run.lease do
          completed = Map.merge(run, proof) |> Map.put(:sync_epoch, epoch)

          next =
            state
            |> put_in([:completed, run.verification_key], completed)
            |> update_in([:leases], &Map.delete(&1, run.target_digest))
            |> put_in([:runs, run.run_id], completed)

          {{:ok, completed}, next}
        else
          {{:error, :lease_lost}, state}
        end
      end)
    end
  end

  setup do
    {:ok, store} = Store.start_link()
    %{store: store}
  end

  test "fixed vectors refuse every unsafe source or target before mutation", %{store: store} do
    vectors = recovery_vectors()

    for vector <- vectors["refusals"] do
      input = Map.merge(valid_input(), vector["input"])
      expected = vector["outcome"]

      assert {:refused, ^expected} =
               Restore.begin(input, Store, store, random_bytes: fn _ -> <<1::128>> end)

      assert Store.state(store) == %{completed: %{}, leases: %{}, runs: %{}}
    end
  end

  test "an explicit recorded compatibility override is narrow and auditable", %{store: store} do
    input =
      valid_input()
      |> Map.put("compatibility", "expired")
      |> Map.put("recovery_override", %{
        "recorded" => true,
        "reason" => "expired_compatibility",
        "approved_at" => "2026-09-01T11:55:00Z"
      })

    assert {:ok, run} = Restore.begin(input, Store, store, random_bytes: &fixed_bytes/1)
    assert run.override_code == "expired_compatibility"
    refute inspect(run) =~ @target
  end

  test "same-target attempts are mutually exclusive and separate targets may proceed", %{
    store: store
  } do
    assert {:ok, first} = Restore.begin(valid_input(), Store, store, random_bytes: &fixed_bytes/1)
    assert {:refused, "target_busy"} = Restore.begin(valid_input(), Store, store)

    assert {:ok, other} =
             Restore.begin(
               Map.put(valid_input(), "target", "recovery-target-beta"),
               Store,
               store
             )

    assert first.target_digest != other.target_digest
  end

  test "verification rotates the epoch transactionally before readiness and persists bounded proof",
       %{
         store: store
       } do
    assert {:ok, run} = Restore.begin(valid_input(), Store, store, random_bytes: &fixed_bytes/1)
    assert run.ready == false

    old_epoch = "00000000-0000-4000-8000-0000000000e1"

    assert {:ok, completed} =
             Restore.finalize(
               run,
               valid_proof(old_epoch),
               Store,
               store,
               random_bytes: &epoch_bytes/1
             )

    assert completed.ready == true
    assert completed.epoch_finalized == true
    assert completed.sync_epoch != old_epoch
    assert completed.outcome_code == "verified"

    persisted = Store.state(store).completed[run.verification_key]
    assert persisted.sync_epoch == completed.sync_epoch
    assert persisted.semantic_smoke == ~w(history login read schema undo write)
    refute inspect(persisted) =~ @target
    refute inspect(persisted) =~ "A private task title"
  end

  test "failed semantic proof never finalizes epoch or readiness", %{store: store} do
    assert {:ok, run} = Restore.begin(valid_input(), Store, store)

    assert {:refused, "semantic_smoke_incomplete"} =
             Restore.finalize(
               run,
               put_in(valid_proof(), ["semantic", "undo"], false),
               Store,
               store
             )

    assert Store.state(store).completed == %{}
    assert Store.state(store).runs[run.run_id].ready == false
  end

  test "rerunning completed verification is read-only and idempotent", %{store: store} do
    assert {:ok, run} = Restore.begin(valid_input(), Store, store)
    assert {:ok, completed} = Restore.finalize(run, valid_proof(), Store, store)
    before = Store.state(store)

    assert {:already_verified, replayed} = Restore.begin(valid_input(), Store, store)
    assert replayed == completed
    assert Store.state(store) == before
  end

  defp valid_input do
    %{
      "source_digest" => @source,
      "source_target_distinct" => true,
      "target" => @target,
      "target_class" => "empty_isolated",
      "target_empty" => true,
      "production_side_effects" => false,
      "wal_complete" => true,
      "source_verified" => true,
      "image_digest" => @image,
      "image_immutable" => true,
      "compatibility" => "current",
      "schema_version" => 4,
      "protocol_train" => 1,
      "verifier_version" => 1,
      "recovery_point" => "2026-09-01T11:59:00Z",
      "started_at" => DateTime.to_iso8601(@now),
      "recovery_override" => nil
    }
  end

  defp valid_proof(old_epoch \\ "00000000-0000-4000-8000-0000000000e1") do
    %{
      "manifest_verified" => true,
      "checksum_verified" => true,
      "old_sync_epoch" => old_epoch,
      "finished_at" => "2026-09-01T12:03:00Z",
      "duration_seconds" => 180,
      "rpo_seconds" => 60,
      "semantic" => %{
        "schema" => true,
        "history" => true,
        "login" => true,
        "read" => true,
        "write" => true,
        "undo" => true
      }
    }
  end

  defp recovery_vectors do
    path = Path.expand("../../../../../../packages/contracts/vectors/recovery.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end

  defp fixed_bytes(16), do: <<1::128>>
  defp fixed_bytes(32), do: <<2::256>>
  defp epoch_bytes(16), do: <<3::128>>
end
