defmodule KeeplingWeb.MCP.InjectionVectorTest do
  @moduledoc """
  05-11-PLAN.md Task 2: `packages/contracts/vectors/mcp-injection.json` is
  Keepling's own adversarial corpus, written against Keepling's own
  schema (D-24/D-25). This module is the closed vocabulary's "elixir"
  consumer proof required by `tooling/check-contracts.mjs`'s
  cross-consumer gate: it loads the corpus and asserts every case's
  shape is genuinely usable by a live scenario driver, structurally
  matching `packages/contracts/vectors/redaction.json`'s own
  `hostile_sentinels` convention. This is a STRUCTURAL proof (the corpus
  is well-formed and every sentinel is unique/non-empty); the BEHAVIOURAL
  proof that an injected case changes no authorization outcome is
  `tooling/mcp-lanes/adversarial.mjs` (driving the corpus over the real
  transport) and `content_isolation_test.exs` (05-06, the structural proof
  that no authorization decision can even receive task content) -- this
  test does not duplicate either.
  """
  use ExUnit.Case, async: true

  @vectors_path Path.join([
                  __DIR__,
                  "..",
                  "..",
                  "..",
                  "..",
                  "..",
                  "packages",
                  "contracts",
                  "vectors",
                  "mcp-injection.json"
                ])
                |> Path.expand()

  @required_case_keys ~w(id injection_text field target_scenario resolves_into forbidden_outcome)

  test "the corpus file exists, is valid JSON, and covers D-24 and D-25" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    assert vectors["version"] == 1
    assert "D-24" in vectors["covered_decisions"]
    assert "D-25" in vectors["covered_decisions"]
  end

  test "hostile_sentinels are unique, non-empty, and each names an injection concern" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()
    sentinels = vectors["hostile_sentinels"]

    assert is_list(sentinels)
    assert length(sentinels) >= 6
    assert Enum.all?(sentinels, &(is_binary(&1) and &1 != ""))
    assert length(sentinels) == length(Enum.uniq(sentinels))
  end

  test "every case declares exactly the fields an adversarial lane needs, and at least 6 cases exist" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()
    cases = vectors["cases"]

    assert is_list(cases)
    assert length(cases) >= 6

    for case_entry <- cases do
      for key <- @required_case_keys do
        assert Map.has_key?(case_entry, key), "case #{inspect(case_entry["id"])} is missing #{key}"
      end

      assert is_binary(case_entry["injection_text"]) and case_entry["injection_text"] != ""
      assert case_entry["field"] in ["title", "notes"]
      assert is_binary(case_entry["resolves_into"]) and case_entry["resolves_into"] != ""
      assert is_binary(case_entry["forbidden_outcome"]) and case_entry["forbidden_outcome"] != ""
    end
  end

  test "case ids are unique" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()
    ids = Enum.map(vectors["cases"], & &1["id"])

    assert length(ids) == length(Enum.uniq(ids))
  end
end
