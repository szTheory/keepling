defmodule Keepling.Application.Sync.ReferenceModelTest do
  use ExUnit.Case, async: true

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
end
