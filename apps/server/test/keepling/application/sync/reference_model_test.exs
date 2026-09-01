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

  defp tracer_mutation do
    @vectors_path
    |> File.read!()
    |> Jason.decode!()
    |> then(&hd(&1["cases"]))
    |> then(&hd(&1["actions"]))
    |> Map.fetch!("mutation")
  end
end
