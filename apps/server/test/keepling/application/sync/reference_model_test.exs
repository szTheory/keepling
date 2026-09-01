defmodule Keepling.Application.Sync.ReferenceModelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Keepling.Application.Sync.ReferenceModel
  alias Keepling.SyncScenario

  @vectors_path Path.expand(
                  "../../../../../../packages/contracts/vectors/sync.json",
                  __DIR__
                )

  @tag :tracer
  test "immutable local intent survives a pending pull and settles only from an exact acknowledgement" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()
    tracer = Enum.find(vectors["cases"], &(&1["name"] == "durable mutation tracer"))

    assert {:ok, %{state: state, ready_pushes: [ready]}} = SyncScenario.run(tracer)

    assert ready["mutation_id"] == "mutation-001"
    assert state["canonical_shadow"]["task-001"]["revision"] == 3
    assert state["visible"]["task-001"]["revision"] == 3
    assert state["visible"]["task-001"]["title"] == "Local title"
    assert state["outbox"] == []

    assert state["journal"]["mutation-001"]["outcome"] == "accepted"
    assert state["journal"]["mutation-001"]["fingerprint"] == ready["fingerprint"]
    assert state["cursor"] == "cursor-002"
  end

  @tag :tracer
  test "mismatched acknowledgement cannot remove immutable intent" do
    mutation = tracer_mutation()

    assert {:ok, "local_saved", pending} =
             ReferenceModel.local_accept(ReferenceModel.new(), mutation)

    mismatch = %{
      "mutation_id" => mutation["mutation_id"],
      "fingerprint" => String.duplicate("0", 64),
      "outcome" => "accepted",
      "snapshot" => mutation["effect"]["snapshot"]
    }

    assert {:error, :acknowledgement_mismatch, unchanged} =
             ReferenceModel.acknowledge(pending, mismatch)

    assert unchanged == pending
    assert [^mutation] = unchanged["outbox"]
    assert unchanged["journal"][mutation["mutation_id"]]["outcome"] == "pending"
  end

  test "overlapping lanes preserve FIFO while disjoint lanes progress" do
    first = mutation("mutation-a", ["task:task-a", "today-order"], [])
    overlapping = mutation("mutation-b", ["task:task-b", "today-order"], [])
    disjoint = mutation("mutation-c", ["task:task-c"], [])

    state = accept_all([first, overlapping, disjoint])

    assert Enum.map(ReferenceModel.ready_pushes(state), & &1["mutation_id"]) == [
             "mutation-a",
             "mutation-c"
           ]

    assert {:ok, after_first} = ReferenceModel.acknowledge(state, accepted(first))

    assert Enum.map(ReferenceModel.ready_pushes(after_first), & &1["mutation_id"]) == [
             "mutation-b",
             "mutation-c"
           ]
  end

  test "failed dependencies block descendants without stopping unrelated work" do
    prerequisite = mutation("mutation-parent", ["task:task-parent"], [])
    descendant = mutation("mutation-child", ["task:task-child"], ["mutation-parent"])
    unrelated = mutation("mutation-unrelated", ["task:task-unrelated"], [])
    state = accept_all([prerequisite, descendant, unrelated])

    assert Enum.map(ReferenceModel.ready_pushes(state), & &1["mutation_id"]) == [
             "mutation-parent",
             "mutation-unrelated"
           ]

    conflict = accepted(prerequisite) |> Map.put("outcome", "conflict")
    assert {:ok, conflicted} = ReferenceModel.acknowledge(state, conflict)

    assert Enum.map(ReferenceModel.ready_pushes(conflicted), & &1["mutation_id"]) == [
             "mutation-unrelated"
           ]
  end

  test "orphans and cycles are explicit invalid durable state" do
    orphan = mutation("mutation-orphan", ["task:task-orphan"], ["missing-parent"])

    assert {:error, :orphan_dependency, unchanged} =
             ReferenceModel.local_accept(ReferenceModel.new(), orphan)

    assert unchanged == ReferenceModel.new()

    cyclic =
      accept_all([
        mutation("mutation-a", ["task:task-a"], []),
        mutation("mutation-b", ["task:task-b"], ["mutation-a"])
      ])
      |> put_in(["dependencies", "mutation-a"], ["mutation-b"])

    assert {:error, :dependency_cycle} = ReferenceModel.ready_pushes(cyclic)
  end

  test "bounded pulls and authentication fencing retain exact durable intent" do
    pending = accept_all([mutation("mutation-a", ["task:task-a"], [])])
    serialized = :erlang.term_to_binary(pending, [:deterministic])
    relaunched = :erlang.binary_to_term(serialized, [:safe])

    assert {:ok, fenced} = ReferenceModel.fence(relaunched, "authentication_required")
    assert ReferenceModel.ready_pushes(fenced) == []
    assert fenced["outbox"] == pending["outbox"]
    assert fenced["journal"] == pending["journal"]

    assert {:ok, resumed} = ReferenceModel.fence(fenced, nil)
    assert ReferenceModel.ready_pushes(resumed) == pending["outbox"]

    oversized = %{
      "cursor" => "cursor-oversized",
      "changes" =>
        for revision <- 1..51 do
          %{
            "entity_id" => "remote-#{revision}",
            "snapshot" => %{"id" => "remote-#{revision}", "revision" => revision}
          }
        end
    }

    assert {:error, :pull_page_too_large, ^resumed} = ReferenceModel.pull(resumed, oversized)
  end

  test "response loss retries the byte-identical mutation until local settlement" do
    mutation = mutation("mutation-response-loss", ["task:task-a"], [])
    state = accept_all([mutation])

    assert [first_delivery] = ReferenceModel.ready_pushes(state)
    assert [retry_delivery] = ReferenceModel.ready_pushes(state)
    assert first_delivery == retry_delivery

    assert {:ok, settled} = ReferenceModel.acknowledge(state, accepted(mutation))
    assert settled["outbox"] == []

    assert settled["journal"][mutation["mutation_id"]]["command_bytes"] ==
             mutation["command_bytes"]
  end

  property "generated action sequences preserve identity, FIFO, dependencies, and revisions" do
    check all(
            steps <-
              list_of(
                member_of([
                  :accept_a,
                  :accept_b,
                  :accept_shared_a,
                  :accept_shared_b,
                  :accept_parent,
                  :accept_child,
                  :pull_a_1,
                  :pull_a_2,
                  :pull_a_older,
                  :ack_a,
                  :conflict_parent,
                  :fence,
                  :unfence
                ]),
                min_length: 1,
                max_length: 80
              ),
            max_runs: 60
          ) do
      Enum.reduce(steps, ReferenceModel.new(), fn step, state ->
        next = property_step(state, step)
        assert_reference_invariants(state, next)
        next
      end)
    end
  end

  defp tracer_mutation do
    @vectors_path
    |> File.read!()
    |> Jason.decode!()
    |> then(&hd(&1["cases"]))
    |> then(&hd(&1["actions"]))
    |> Map.fetch!("mutation")
  end

  defp accept_all(mutations) do
    Enum.reduce(mutations, ReferenceModel.new(), fn mutation, state ->
      assert {:ok, "local_saved", next} = ReferenceModel.local_accept(state, mutation)
      next
    end)
  end

  defp mutation(mutation_id, resource_keys, dependencies) do
    command_bytes =
      Jason.encode!(%{
        "mutation_id" => mutation_id,
        "task_id" => String.replace_prefix(mutation_id, "mutation-", "task-"),
        "type" => "edit_task"
      })

    %{
      "mutation_id" => mutation_id,
      "fingerprint" => :crypto.hash(:sha256, command_bytes) |> Base.encode16(case: :lower),
      "command_bytes" => command_bytes,
      "resource_keys" => resource_keys,
      "dependencies" => dependencies,
      "accepted_at" => "2026-09-01T12:00:00.000000Z",
      "effect" => %{
        "entity_id" => String.replace_prefix(mutation_id, "mutation-", "task-"),
        "snapshot" => %{
          "id" => String.replace_prefix(mutation_id, "mutation-", "task-"),
          "revision" => 1,
          "title" => mutation_id
        }
      }
    }
  end

  defp accepted(mutation) do
    %{
      "mutation_id" => mutation["mutation_id"],
      "fingerprint" => mutation["fingerprint"],
      "outcome" => "accepted",
      "snapshot" => mutation["effect"]["snapshot"]
    }
  end

  defp property_step(state, :accept_a),
    do: accept_or_retain(state, mutation("mutation-a", ["task:task-a"], []))

  defp property_step(state, :accept_b),
    do: accept_or_retain(state, mutation("mutation-b", ["task:task-b"], []))

  defp property_step(state, :accept_shared_a),
    do:
      accept_or_retain(
        state,
        mutation("mutation-shared-a", ["task:task-a", "today-order"], [])
      )

  defp property_step(state, :accept_shared_b),
    do:
      accept_or_retain(
        state,
        mutation("mutation-shared-b", ["task:task-b", "today-order"], [])
      )

  defp property_step(state, :accept_parent),
    do: accept_or_retain(state, mutation("mutation-parent", ["task:task-parent"], []))

  defp property_step(state, :accept_child),
    do:
      accept_or_retain(
        state,
        mutation("mutation-child", ["task:task-child"], ["mutation-parent"])
      )

  defp property_step(state, :pull_a_1), do: pull_or_retain(state, 1)
  defp property_step(state, :pull_a_2), do: pull_or_retain(state, 2)
  defp property_step(state, :pull_a_older), do: pull_or_retain(state, 0)

  defp property_step(state, :ack_a) do
    acknowledge_or_retain(state, "mutation-a", "accepted")
  end

  defp property_step(state, :conflict_parent) do
    acknowledge_or_retain(state, "mutation-parent", "conflict")
  end

  defp property_step(state, :fence),
    do: ReferenceModel.fence(state, "authentication_required") |> elem(1)

  defp property_step(state, :unfence), do: ReferenceModel.fence(state, nil) |> elem(1)

  defp accept_or_retain(state, mutation) do
    case ReferenceModel.local_accept(state, mutation) do
      {:ok, "local_saved", next} -> next
      {:error, _reason, ^state} -> state
    end
  end

  defp pull_or_retain(state, revision) do
    page = %{
      "cursor" => "cursor-#{revision}",
      "changes" => [
        %{
          "entity_id" => "task-a",
          "snapshot" => %{"id" => "task-a", "revision" => revision}
        }
      ]
    }

    ReferenceModel.pull(state, page) |> elem(1)
  end

  defp acknowledge_or_retain(state, mutation_id, outcome) do
    case Enum.find(state["outbox"], &(&1["mutation_id"] == mutation_id)) do
      nil ->
        state

      queued ->
        queued
        |> accepted()
        |> Map.put("outcome", outcome)
        |> then(&ReferenceModel.acknowledge(state, &1))
        |> elem(1)
    end
  end

  defp assert_reference_invariants(previous, current) do
    for queued <- current["outbox"] do
      journal = current["journal"][queued["mutation_id"]]
      assert journal["outcome"] == "pending"
      assert journal["command_bytes"] == queued["command_bytes"]
      assert journal["fingerprint"] == queued["fingerprint"]
      assert queued["resource_keys"] == Enum.sort(Enum.uniq(queued["resource_keys"]))

      assert Enum.all?(queued["dependencies"], &Map.has_key?(current["journal"], &1))
    end

    for {entity_id, snapshot} <- previous["canonical_shadow"] do
      assert get_in(current, ["canonical_shadow", entity_id, "revision"]) >= snapshot["revision"]
    end

    case ReferenceModel.ready_pushes(current) do
      ready when is_list(ready) -> assert_ready_invariants(current, ready)
      {:error, reason} -> flunk("generated valid state became invalid: #{inspect(reason)}")
    end
  end

  defp assert_ready_invariants(state, ready) do
    for mutation <- ready do
      index = Enum.find_index(state["outbox"], &(&1["mutation_id"] == mutation["mutation_id"]))

      assert state["fence"] == nil

      assert Enum.all?(mutation["dependencies"], fn dependency_id ->
               get_in(state, ["journal", dependency_id, "outcome"]) in [
                 "accepted",
                 "already_satisfied"
               ]
             end)

      assert Enum.all?(Enum.take(state["outbox"], index), fn earlier ->
               MapSet.disjoint?(
                 MapSet.new(earlier["resource_keys"]),
                 MapSet.new(mutation["resource_keys"])
               )
             end)
    end
  end
end
