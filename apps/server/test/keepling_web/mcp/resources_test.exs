defmodule KeeplingWeb.MCP.ResourcesTest do
  @moduledoc """
  05-04-PLAN.md: `KeeplingWeb.MCP.Redaction`'s field-by-field projection
  (Task 1). `resources/list`/`resources/read`/`keepling.search_tasks` over
  the real MCP JSON-RPC transport (Task 2) extend this file.
  """
  use KeeplingWeb.ConnCase, async: false

  alias KeeplingWeb.MCP.Redaction

  @redaction_vectors_path Path.join([
                            __DIR__,
                            "..",
                            "..",
                            "..",
                            "..",
                            "..",
                            "packages",
                            "contracts",
                            "vectors",
                            "redaction.json"
                          ])
                          |> Path.expand()

  describe "Redaction.task/1 and Redaction.project/1 (Task 1)" do
    test "emits exactly the documented task field set" do
      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => "Book the ferry",
        "notes" => "Ask about the car deck",
        "project" => %{"id" => Ecto.UUID.generate(), "name" => "Trip", "archived" => false},
        "tags" => [%{"id" => Ecto.UUID.generate(), "name" => "travel", "archived" => false}],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => "2026-02-01",
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)

      assert Enum.sort(Map.keys(projected)) ==
               Enum.sort(~w(
                 id title notes project tags captured_at planned_on deadline_on
                 completed_at lifecycle_state revision
               )a)

      assert projected.project == %{id: row["project"]["id"], name: "Trip"}
      assert projected.tags == ["travel"]
      assert projected.lifecycle_state == "inbox"
    end

    test "emits exactly the documented project field set" do
      row = %{id: Ecto.UUID.generate(), name: "Trip", task_count: 3}

      projected = Redaction.project(row)

      assert Enum.sort(Map.keys(projected)) == Enum.sort(~w(id name archived task_count)a)
      assert projected.archived == false
      assert projected.task_count == 3
    end

    test "a task with no project and no tags emits nil project and an empty tag list" do
      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => "No project",
        "notes" => nil,
        "project" => nil,
        "tags" => [],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => nil,
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)
      assert projected.project == nil
      assert projected.tags == []
    end

    test "title and notes round-trip every hostile sentinel verbatim; no sentinel appears in any structural field" do
      sentinels = @redaction_vectors_path |> File.read!() |> Jason.decode!() |> Map.fetch!("hostile_sentinels")
      poisoned = Enum.join(sentinels, " ")

      row = %{
        "id" => Ecto.UUID.generate(),
        "title" => poisoned,
        "notes" => poisoned,
        "project" => nil,
        "tags" => [],
        "captured_at" => "2026-01-01T00:00:00Z",
        "planned_on" => nil,
        "deadline_on" => nil,
        "completed_at" => nil,
        "inbox_state" => "inbox",
        "revision" => 1
      }

      projected = Redaction.task(row)

      assert projected.title == poisoned
      assert projected.notes == poisoned

      structural = projected |> Map.drop([:title, :notes]) |> Jason.encode!()

      for sentinel <- sentinels do
        refute structural =~ sentinel,
               "expected hostile sentinel #{inspect(sentinel)} to be absent from structural fields"
      end
    end

    test "never takes a domain struct wholesale" do
      redaction_source =
        [__DIR__, "..", "..", "..", "lib", "keepling_web", "mcp", "redaction.ex"]
        |> Path.join()
        |> Path.expand()
        |> File.read!()

      refute redaction_source =~ "Map.from_struct"
    end
  end
end
