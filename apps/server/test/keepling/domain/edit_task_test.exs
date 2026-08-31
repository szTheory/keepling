defmodule Keepling.Domain.EditTaskTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Task

  @accepted_at ~U[2026-08-30 21:00:00.000000Z]

  test "storage-neutral vectors preserve unrelated accepted fields and expose overlaps" do
    vectors = editing_vectors()

    assert vectors["version"] == 1
    assert vectors["limits"] == %{
             "notes_normalization" => "preserve_plain_text",
             "notes_unicode_scalars" => 50_000,
             "title_normalization" => "outer_whitespace_trim",
             "title_unicode_scalars" => 512
           }

    for vector <- vectors["cases"] do
      task = task_from(vector["current"])
      command = atomize_command(vector["command"])

      case vector["result"]["outcome"] do
        "accepted" ->
          operation =
            if String.starts_with?(vector["name"], "clarify"),
              do: &Task.clarify/2,
              else: &Task.edit/2

          assert {:ok, updated, activity, :accepted} = operation.(task, command)
          assert updated.title == vector["result"]["title"]
          assert updated.notes == vector["result"]["notes"]
          assert Atom.to_string(updated.inbox_state) == vector["result"]["inbox_state"]
          assert updated.revision == vector["result"]["revision"]
          assert activity.to_revision == updated.revision

        "conflict" ->
          assert {:error, {:edit_conflict, affected}} = Task.edit(task, command)
          assert Enum.sort(affected) == vector["result"]["affected_fields"]
      end
    end
  end

  test "title is trimmed, notes are preserved, and validation is versioned" do
    task = task_from(%{"title" => "Before", "notes" => "line one\n", "inbox_state" => "inbox", "revision" => 1})

    assert Task.details_version() == 1
    assert Task.details_limits() == %{notes: 50_000, title: 512}

    assert {:ok, updated, activity, :accepted} =
             Task.edit(task, %{
               accepted_at: @accepted_at,
               expected_revision: 1,
               base_values: %{title: "Before", notes: "line one\n"},
               fields: %{title: "  After  ", notes: "  line two\n"}
             })

    assert updated.title == "After"
    assert updated.notes == "  line two\n"
    assert activity.changed_fields == %{
             "notes" => %{"from" => "line one\n", "to" => "  line two\n"},
             "title" => %{"from" => "Before", "to" => "After"}
           }

    assert {:error, :title_required} =
             Task.edit(task, edit_command(:title, "Before", "   "))

    assert {:error, :notes_too_long} =
             Task.edit(task, edit_command(:notes, "line one\n", String.duplicate("n", 50_001)))
  end

  test "ordinary edits preserve Inbox and only return_to_inbox is the inverse of clarify" do
    task = task_from(%{"title" => "Before", "notes" => "", "inbox_state" => "inbox", "revision" => 1})

    assert {:ok, edited, _, :accepted} =
             Task.edit(task, edit_command(:title, "Before", "After"))

    assert edited.inbox_state == :inbox

    assert {:ok, clarified, activity, :accepted} =
             Task.clarify(edited, %{
               accepted_at: @accepted_at,
               expected_revision: 2,
               base_values: %{},
               fields: %{}
             })

    assert clarified.inbox_state == :clarified
    assert activity.type == :task_clarified

    assert {:ok, returned, returned_activity, :accepted} =
             Task.return_to_inbox(clarified, %{
               accepted_at: @accepted_at,
               expected_revision: clarified.revision
             })

    assert returned.inbox_state == :inbox
    assert returned_activity.type == :task_returned_to_inbox
  end

  defp edit_command(field, base, requested) do
    %{
      accepted_at: @accepted_at,
      expected_revision: 1,
      base_values: %{field => base},
      fields: %{field => requested}
    }
  end

  defp task_from(current) do
    %Task{
      captured_at: ~U[2026-08-30 20:00:00.000000Z],
      id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
      inbox_state: String.to_existing_atom(current["inbox_state"]),
      notes: current["notes"],
      revision: current["revision"],
      title: current["title"]
    }
  end

  defp atomize_command(command) do
    %{
      accepted_at: @accepted_at,
      base_values: Map.new(command["base_values"], fn {key, value} -> {String.to_existing_atom(key), value} end),
      expected_revision: command["expected_revision"],
      fields: Map.new(command["fields"], fn {key, value} -> {String.to_existing_atom(key), value} end)
    }
  end

  defp editing_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/editing.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end
