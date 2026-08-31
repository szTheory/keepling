defmodule Keepling.Domain.LongSequenceTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Undo
  alias Keepling.Domain.{Task, TaskDates}

  @start ~U[2026-08-31 12:00:00.000000Z]

  test "seeded semantic sequences preserve task, date, lifecycle, Trash, undo, replay, and conflict invariants" do
    :rand.seed(:exsss, {41, 42, 43})
    {:ok, initial, _activity} =
      Task.capture(%{accepted_at: @start, task_id: "018d8b40-2f10-7b1a-9d71-263f4af77019", title: "Sequence origin"})

    final = Enum.reduce(1..32, initial, &cycle/2)

    assert final.revision == 1 + 32 * 10
    assert final.title == "Sequence origin"
    assert final.notes == ""
    assert final.inbox_state == :inbox
    assert final.planned_on == nil
    assert final.deadline_on == nil
    assert final.completed_at == nil
    assert final.trashed_at == nil
    assert final.lifecycle_revision < final.revision
  end

  defp cycle(index, task) do
    accepted_at = DateTime.add(@start, index * 60, :second)
    requested_title = "Sequence #{index}-#{:rand.uniform(1_000_000)}"
    edit = %{
      accepted_at: accepted_at,
      base_values: %{title: task.title},
      expected_revision: task.revision,
      fields: %{title: requested_title}
    }

    accepted = Task.edit(task, edit)
    assert accepted == Task.edit(task, edit), "pure replay diverged at cycle #{index}"
    assert {:ok, edited, edit_activity, :accepted} = accepted

    assert {:error, {:edit_conflict, ["title"]}} =
             Task.edit(edited, %{
               edit
               | base_values: %{title: task.title},
                 expected_revision: task.revision,
                 fields: %{title: "conflicting #{index}"}
             })

    assert {:ok, compensation} = Undo.compensation(%{type: :edit_task}, edit_activity)
    assert {:ok, undone, undo_activity} = Undo.apply(edited, compensation.inverse, accepted_at)
    assert undone.title == task.title
    assert undo_activity.from_revision == edited.revision

    assert {:ok, planned, _, :accepted, warnings} =
             TaskDates.plan_for_today(
               undone,
               %{
                 accepted_at: accepted_at,
                 base_planned_on: nil,
                 expected_revision: undone.revision
               },
               ~D[2026-08-31]
             )

    assert warnings == []
    assert TaskDates.classify(planned.planned_on, planned.deadline_on, ~D[2026-08-31]).today_section == :today

    assert {:ok, unplanned, _, :accepted, []} =
             TaskDates.unplan(planned, %{
               accepted_at: accepted_at,
               base_planned_on: planned.planned_on,
               expected_revision: planned.revision
             })

    assert {:ok, completed, _, :accepted} =
             Task.complete(unplanned, %{accepted_at: accepted_at, expected_revision: unplanned.revision})

    assert {:ok, reopened, _, :accepted} =
             Task.reopen(completed, %{accepted_at: accepted_at, expected_revision: completed.revision})

    assert {:ok, trashed, _, :accepted} =
             Task.trash(reopened, %{accepted_at: accepted_at, expected_revision: reopened.revision})

    assert {:ok, restored, _, :accepted} =
             Task.restore(trashed, %{accepted_at: accepted_at, expected_revision: trashed.revision})

    assert {:ok, clarified, _, :accepted} =
             Task.clarify(restored, %{
               accepted_at: accepted_at,
               base_values: %{},
               expected_revision: restored.revision,
               fields: %{}
             })

    assert {:ok, returned, _, :accepted} =
             Task.return_to_inbox(clarified, %{
               accepted_at: accepted_at,
               expected_revision: clarified.revision
             })

    assert Map.take(returned, [:completed_at, :deadline_on, :inbox_state, :notes, :planned_on, :title, :trashed_at]) ==
             Map.take(task, [:completed_at, :deadline_on, :inbox_state, :notes, :planned_on, :title, :trashed_at])

    returned
  end
end
