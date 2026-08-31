defmodule Keepling.Domain.TaskDates do
  @moduledoc """
  Pure civil-date decisions for task planning and deadline semantics.

  Stored dates never depend on a device zone. The configured account IANA zone
  and an injected acceptance instant are used only to resolve an account day.
  """

  alias Keepling.Domain.Task

  @date_fields [:planned_on, :deadline_on]

  @type warning :: :planned_after_deadline
  @type today_reason ::
          :planned_overdue | :planned_today | :deadline_overdue | :deadline_today

  @spec account_day(DateTime.t(), String.t()) ::
          {:ok, Date.t()} | {:error, :invalid_timezone}
  def account_day(%DateTime{} = instant, timezone) when is_binary(timezone) do
    if fixed_offset?(timezone) do
      {:error, :invalid_timezone}
    else
      case DateTime.shift_zone(instant, timezone) do
        {:ok, shifted} -> {:ok, DateTime.to_date(shifted)}
        {:error, _reason} -> {:error, :invalid_timezone}
      end
    end
  end

  def account_day(_instant, _timezone), do: {:error, :invalid_timezone}

  @spec classify(Date.t() | nil, Date.t() | nil, Date.t()) :: map()
  def classify(planned_on, deadline_on, %Date{} = account_day) do
    today_reasons =
      planned_reason(planned_on, account_day) ++ deadline_reason(deadline_on, account_day)

    %{
      today_reasons: today_reasons,
      today_section: today_section(today_reasons),
      upcoming_on: upcoming_on(planned_on, deadline_on, account_day),
      upcoming_reason: upcoming_reason(planned_on, deadline_on, account_day),
      warnings: warnings(planned_on, deadline_on)
    }
  end

  @spec edit(Task.t(), map()) ::
          {:ok, Task.t(), map() | nil, :accepted | :already_satisfied, [warning()]}
          | {:error, atom() | {:edit_conflict, [String.t()]}}
  def edit(%Task{} = task, command) do
    with :ok <- require_touched_fields(command),
         {:ok, fields} <- normalize_fields(command.fields),
         {:ok, base_values} <- normalize_fields(command.base_values),
         :ok <- matching_fields(fields, base_values),
         {:ok, updated, changes} <- merge_fields(task, base_values, fields) do
      finish(task, updated, changes, command.accepted_at)
    end
  end

  @spec plan_for_today(Task.t(), map(), Date.t()) ::
          {:ok, Task.t(), map() | nil, :accepted | :already_satisfied, [warning()]}
          | {:error, atom() | {:edit_conflict, [String.t()]}}
  def plan_for_today(%Task{} = task, command, %Date{} = account_day) do
    edit(task, %{
      accepted_at: command.accepted_at,
      base_values: %{planned_on: command.base_planned_on},
      expected_revision: command.expected_revision,
      fields: %{planned_on: account_day}
    })
  end

  @spec unplan(Task.t(), map()) ::
          {:ok, Task.t(), map() | nil, :accepted | :already_satisfied, [warning()]}
          | {:error, atom() | {:edit_conflict, [String.t()]}}
  def unplan(%Task{} = task, command) do
    edit(task, %{
      accepted_at: command.accepted_at,
      base_values: %{planned_on: command.base_planned_on},
      expected_revision: command.expected_revision,
      fields: %{planned_on: nil}
    })
  end

  defp require_touched_fields(%{fields: fields}) when is_map(fields) and map_size(fields) > 0,
    do: :ok

  defp require_touched_fields(_command), do: {:error, :no_date_fields_touched}

  defp normalize_fields(fields) when is_map(fields) do
    if Enum.all?(fields, fn {field, value} ->
         field in @date_fields and (is_nil(value) or match?(%Date{}, value))
       end) do
      {:ok, fields}
    else
      {:error, :invalid_task_dates}
    end
  end

  defp normalize_fields(_fields), do: {:error, :invalid_task_dates}

  defp matching_fields(fields, base_values) do
    if MapSet.new(Map.keys(fields)) == MapSet.new(Map.keys(base_values)),
      do: :ok,
      else: {:error, :base_values_mismatch}
  end

  defp merge_fields(task, base_values, fields) do
    conflicts =
      fields
      |> Enum.reject(fn {field, requested} ->
        current = Map.fetch!(task, field)
        current == Map.fetch!(base_values, field) or current == requested
      end)
      |> Enum.map(fn {field, _value} -> Atom.to_string(field) end)
      |> Enum.sort()

    if conflicts == [] do
      {updated, changes} =
        Enum.reduce(fields, {task, %{}}, fn {field, requested}, {current_task, changed} ->
          current = Map.fetch!(current_task, field)

          if current == requested do
            {current_task, changed}
          else
            {
              Map.put(current_task, field, requested),
              Map.put(changed, Atom.to_string(field), %{"from" => current, "to" => requested})
            }
          end
        end)

      {:ok, updated, changes}
    else
      {:error, {:edit_conflict, conflicts}}
    end
  end

  defp finish(task, updated, changes, _accepted_at) when map_size(changes) == 0 do
    {:ok, task, nil, :already_satisfied, warnings(updated.planned_on, updated.deadline_on)}
  end

  defp finish(task, updated, changes, accepted_at) do
    updated = %{updated | revision: task.revision + 1}

    activity = %{
      accepted_at: accepted_at,
      changed_fields: changes,
      from_revision: task.revision,
      to_revision: updated.revision,
      type: activity_type(changes),
      version: 1
    }

    {:ok, updated, activity, :accepted, warnings(updated.planned_on, updated.deadline_on)}
  end

  defp activity_type(%{"planned_on" => %{"to" => nil}}), do: :task_unplanned
  defp activity_type(%{"planned_on" => _change}), do: :task_planned
  defp activity_type(_changes), do: :task_details_updated

  defp warnings(%Date{} = planned_on, %Date{} = deadline_on) do
    if Date.after?(planned_on, deadline_on), do: [:planned_after_deadline], else: []
  end

  defp warnings(_planned_on, _deadline_on), do: []

  defp planned_reason(nil, _account_day), do: []

  defp planned_reason(planned_on, account_day) do
    case Date.compare(planned_on, account_day) do
      :lt -> [:planned_overdue]
      :eq -> [:planned_today]
      :gt -> []
    end
  end

  defp deadline_reason(nil, _account_day), do: []

  defp deadline_reason(deadline_on, account_day) do
    case Date.compare(deadline_on, account_day) do
      :lt -> [:deadline_overdue]
      :eq -> [:deadline_today]
      :gt -> []
    end
  end

  defp today_section(reasons) do
    cond do
      Enum.any?(reasons, &(&1 in [:planned_overdue, :deadline_overdue])) -> :overdue
      reasons != [] -> :today
      true -> nil
    end
  end

  defp upcoming_on(%Date{} = planned_on, deadline_on, account_day) do
    if Date.after?(planned_on, account_day),
      do: planned_on,
      else: upcoming_on(nil, deadline_on, account_day)
  end

  defp upcoming_on(nil, %Date{} = deadline_on, account_day) do
    if Date.after?(deadline_on, account_day), do: deadline_on, else: nil
  end

  defp upcoming_on(_planned_on, _deadline_on, _account_day), do: nil

  defp upcoming_reason(%Date{} = planned_on, deadline_on, account_day) do
    if Date.after?(planned_on, account_day),
      do: :planned,
      else: upcoming_reason(nil, deadline_on, account_day)
  end

  defp upcoming_reason(nil, %Date{} = deadline_on, account_day) do
    if Date.after?(deadline_on, account_day), do: :deadline, else: nil
  end

  defp upcoming_reason(_planned_on, _deadline_on, _account_day), do: nil

  defp fixed_offset?(timezone) do
    timezone in ["UTC", "GMT"] or
      String.starts_with?(timezone, ["UTC+", "UTC-", "GMT+", "GMT-", "+", "-"])
  end
end
