defmodule Keepling.Domain.TaskDatesTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.{Task, TaskDates}

  @accepted_at ~U[2026-08-31 03:30:00.000000Z]

  test "the configured IANA zone and injected instant define one account civil day" do
    assert {:ok, ~D[2026-08-30]} =
             TaskDates.account_day(@accepted_at, "America/Los_Angeles")

    assert {:ok, ~D[2026-08-31]} =
             TaskDates.account_day(@accepted_at, "America/New_York")

    assert {:ok, ~D[2026-03-07]} =
             TaskDates.account_day(~U[2026-03-08 04:59:59.999999Z], "America/New_York")

    assert {:ok, ~D[2026-03-08]} =
             TaskDates.account_day(~U[2026-03-08 05:00:00.000000Z], "America/New_York")

    assert {:error, :invalid_timezone} =
             TaskDates.account_day(@accepted_at, "UTC-08:00")
  end

  test "the versioned truth table keeps Today intent, deadlines, and upcoming separate" do
    vectors = task_date_vectors()

    assert vectors["version"] == 1
    assert vectors["date_format"] == "YYYY-MM-DD"
    assert vectors["unsupported"] == ["exact_times", "recurrence", "reminders", "start_dates"]

    for vector <- vectors["cases"] do
      planned_on = parse_optional_date(vector["planned_on"])
      deadline_on = parse_optional_date(vector["deadline_on"])
      account_day = Date.from_iso8601!(vector["account_day"])

      assert TaskDates.classify(planned_on, deadline_on, account_day) ==
               atomize_classification(vector["classification"]),
             vector["name"]
    end
  end

  test "date edits, plan Today, and unplan preserve the independent deadline and warning" do
    task = task(planned_on: nil, deadline_on: ~D[2026-08-30])

    assert {:ok, planned, planned_activity, :accepted, [:planned_after_deadline]} =
             TaskDates.plan_for_today(
               task,
               %{accepted_at: @accepted_at, base_planned_on: nil, expected_revision: 1},
               ~D[2026-08-31]
             )

    assert planned.planned_on == ~D[2026-08-31]
    assert planned.deadline_on == ~D[2026-08-30]
    assert planned.revision == 2
    assert planned_activity.type == :task_planned

    assert planned_activity.changed_fields == %{
             "planned_on" => %{"from" => nil, "to" => ~D[2026-08-31]}
           }

    assert {:ok, edited, edited_activity, :accepted, []} =
             TaskDates.edit(planned, %{
               accepted_at: @accepted_at,
               base_values: %{deadline_on: ~D[2026-08-30], planned_on: ~D[2026-08-31]},
               expected_revision: 2,
               fields: %{deadline_on: ~D[2026-09-02], planned_on: ~D[2026-08-31]}
             })

    assert edited.planned_on == ~D[2026-08-31]
    assert edited.deadline_on == ~D[2026-09-02]
    assert edited_activity.type == :task_details_updated

    assert {:ok, unplanned, unplanned_activity, :accepted, []} =
             TaskDates.unplan(edited, %{
               accepted_at: @accepted_at,
               base_planned_on: ~D[2026-08-31],
               expected_revision: 3
             })

    assert unplanned.planned_on == nil
    assert unplanned.deadline_on == ~D[2026-09-02]
    assert unplanned_activity.type == :task_unplanned
  end

  test "date changes use touched base values and never silently win an overlap" do
    task = task(planned_on: ~D[2026-09-01], deadline_on: nil, revision: 4)

    assert {:error, {:edit_conflict, ["planned_on"]}} =
             TaskDates.edit(task, %{
               accepted_at: @accepted_at,
               base_values: %{planned_on: ~D[2026-08-31]},
               expected_revision: 3,
               fields: %{planned_on: ~D[2026-09-02]}
             })

    assert {:ok, unchanged, nil, :already_satisfied, []} =
             TaskDates.edit(task, %{
               accepted_at: @accepted_at,
               base_values: %{planned_on: ~D[2026-08-31]},
               expected_revision: 3,
               fields: %{planned_on: ~D[2026-09-01]}
             })

    assert unchanged == task
  end

  test "the sole migration and closed transport artifacts own the temporal shape" do
    root = Path.expand("../../../../../", __DIR__)

    migration =
      File.read!(
        Path.join(root, "apps/server/priv/repo/migrations/20260830000600_add_task_dates.exs")
      )

    openapi = File.read!(Path.join(root, "packages/contracts/openapi/keepling.yaml"))
    generated = File.read!(Path.join(root, "packages/contracts/generated/keepling.ts"))

    assert migration =~ "add :planned_on, :date"
    assert migration =~ "add :deadline_on, :date"
    assert openapi =~ "/commands/plan-for-today:"
    assert openapi =~ "/commands/unplan-task:"
    assert openapi =~ "/commands/edit-task-dates:"
    assert openapi =~ "PlanForTodayRequest:"
    assert openapi =~ "planned_on:"
    assert openapi =~ "deadline_on:"
    assert generated =~ "PlanForTodayRequest"
  end

  defp task(overrides) do
    struct!(
      Task,
      Keyword.merge(
        [
          captured_at: ~U[2026-08-30 20:00:00.000000Z],
          deadline_on: nil,
          id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
          inbox_state: :inbox,
          notes: "",
          planned_on: nil,
          revision: 1,
          title: "Keep dates distinct"
        ],
        overrides
      )
    )
  end

  defp parse_optional_date(nil), do: nil
  defp parse_optional_date(value), do: Date.from_iso8601!(value)

  defp atomize_classification(classification) do
    %{
      today_reasons: Enum.map(classification["today_reasons"], &String.to_existing_atom/1),
      today_section: optional_atom(classification["today_section"]),
      upcoming_on: parse_optional_date(classification["upcoming_on"]),
      upcoming_reason: optional_atom(classification["upcoming_reason"]),
      warnings: Enum.map(classification["warnings"], &String.to_existing_atom/1)
    }
  end

  defp optional_atom(nil), do: nil
  defp optional_atom(value), do: String.to_existing_atom(value)

  defp task_date_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/task-dates.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end
