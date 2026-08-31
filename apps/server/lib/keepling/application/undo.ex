defmodule Keepling.Application.Undo do
  @moduledoc """
  Closed semantic compensation rules for bounded one-shot task undo.

  The application boundary validates typed inverse payloads and changes only
  fields owned by the original supported command. Persistence, authentication,
  account scoping, expiry, one-shot locking, and exact-revision arbitration are
  interpreted by the configured outward port.
  """

  import Kernel, except: [apply: 3]

  alias Keepling.Domain.Task

  @valid_for_seconds 24 * 60 * 60
  @supported_commands [
    :edit_task,
    :clarify_task,
    :return_to_inbox,
    :plan_for_today,
    :unplan_task,
    :complete_task,
    :reopen_task,
    :trash_task,
    :restore_task
  ]

  defmodule Port do
    @moduledoc "Persistence port for atomic compensation consumption."

    @callback execute_undo(map(), map(), function()) :: tuple()
  end

  @spec valid_for_seconds() :: 86_400
  def valid_for_seconds, do: @valid_for_seconds

  @spec supported_command?(atom()) :: boolean()
  def supported_command?(command_type), do: command_type in @supported_commands

  @spec dispatch(map(), map(), module()) :: tuple()
  def dispatch(%{type: :undo_task} = command, context, port) do
    port.execute_undo(command, context, &apply/3)
  end

  @spec compensation(map(), map()) ::
          {:ok, %{inverse: %{kind: atom(), values: map()}, label: String.t()}}
          | :not_supported
  def compensation(%{type: :edit_task}, activity),
    do: inverse(activity, :details, ["notes", "title"], "Undo task edit")

  def compensation(%{type: :clarify_task}, activity),
    do: inverse(activity, :inbox, ["inbox_state", "notes", "title"], "Undo clarification")

  def compensation(%{type: :return_to_inbox}, activity),
    do: inverse(activity, :inbox, ["inbox_state"], "Undo return to Inbox")

  def compensation(%{type: :plan_for_today}, activity),
    do: inverse(activity, :planning, ["planned_on"], "Undo Today planning")

  def compensation(%{type: :unplan_task}, activity),
    do: inverse(activity, :planning, ["planned_on"], "Undo unplanning")

  def compensation(%{type: :complete_task}, activity),
    do: inverse(activity, :completion, ["completed_at"], "Undo completion")

  def compensation(%{type: :reopen_task}, activity),
    do: inverse(activity, :completion, ["completed_at"], "Undo reopening")

  def compensation(%{type: :trash_task}, activity),
    do: inverse(activity, :trash, ["trashed_at"], "Undo Trash")

  def compensation(%{type: :restore_task}, activity),
    do: inverse(activity, :trash, ["trashed_at"], "Undo restore")

  def compensation(_command, _activity), do: :not_supported

  @spec apply(Task.t(), map(), DateTime.t()) ::
          {:ok, Task.t(), Task.activity()} | {:error, :invalid_inverse}
  def apply(%Task{} = task, inverse, %DateTime{} = accepted_at) do
    with {:ok, values} <- validate_inverse(inverse),
         {:ok, updated} <- restore_values(task, values) do
      changed_fields =
        Map.new(values, fn {field, value} ->
          {field, %{"from" => task_value(task, field), "to" => value}}
        end)

      revision = task.revision + 1

      updated =
        if Map.has_key?(values, "completed_at"),
          do: %{updated | revision: revision, lifecycle_revision: revision},
          else: %{updated | revision: revision}

      {:ok, updated,
       %{
         accepted_at: accepted_at,
         changed_fields: changed_fields,
         from_revision: task.revision,
         to_revision: revision,
         type: :task_undo_applied,
         version: 1
       }}
    end
  end

  defp inverse(activity, kind, allowed_fields, label) do
    values =
      activity.changed_fields
      |> Map.take(allowed_fields)
      |> Map.new(fn {field, change} -> {field, Map.fetch!(change, "from")} end)

    if map_size(values) > 0,
      do: {:ok, %{inverse: %{kind: kind, values: values}, label: label}},
      else: :not_supported
  end

  defp validate_inverse(%{kind: :details, values: values}),
    do: validate_values(values, ["notes", "title"])

  defp validate_inverse(%{kind: :inbox, values: values}),
    do: validate_values(values, ["inbox_state", "notes", "title"])

  defp validate_inverse(%{kind: :planning, values: values}),
    do: validate_values(values, ["planned_on"])

  defp validate_inverse(%{kind: :completion, values: values}),
    do: validate_values(values, ["completed_at"])

  defp validate_inverse(%{kind: :trash, values: values}),
    do: validate_values(values, ["trashed_at"])

  defp validate_inverse(_inverse), do: {:error, :invalid_inverse}

  defp validate_values(values, allowed) when is_map(values) and map_size(values) > 0 do
    if Enum.all?(Map.keys(values), &(&1 in allowed)),
      do: {:ok, values},
      else: {:error, :invalid_inverse}
  end

  defp validate_values(_values, _allowed), do: {:error, :invalid_inverse}

  defp restore_values(task, values) do
    Enum.reduce_while(values, {:ok, task}, fn
      {"title", value}, {:ok, current} when is_binary(value) ->
        {:cont, {:ok, %{current | title: value}}}

      {"notes", value}, {:ok, current} when is_binary(value) ->
        {:cont, {:ok, %{current | notes: value}}}

      {"inbox_state", value}, {:ok, current} when value in ["inbox", "clarified"] ->
        {:cont, {:ok, %{current | inbox_state: String.to_existing_atom(value)}}}

      {"planned_on", value}, {:ok, current} ->
        case date(value) do
          {:ok, parsed} -> {:cont, {:ok, %{current | planned_on: parsed}}}
          :error -> {:halt, {:error, :invalid_inverse}}
        end

      {"completed_at", value}, {:ok, current} ->
        case instant(value) do
          {:ok, parsed} -> {:cont, {:ok, %{current | completed_at: parsed}}}
          :error -> {:halt, {:error, :invalid_inverse}}
        end

      {"trashed_at", value}, {:ok, current} ->
        case instant(value) do
          {:ok, parsed} -> {:cont, {:ok, %{current | trashed_at: parsed}}}
          :error -> {:halt, {:error, :invalid_inverse}}
        end

      _field, _acc ->
        {:halt, {:error, :invalid_inverse}}
    end)
  end

  defp date(nil), do: {:ok, nil}
  defp date(%Date{} = value), do: {:ok, value}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, parsed} -> {:ok, parsed}
      _error -> :error
    end
  end

  defp date(_value), do: :error

  defp instant(nil), do: {:ok, nil}
  defp instant(%DateTime{} = value), do: {:ok, value}

  defp instant(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, parsed}
      _error -> :error
    end
  end

  defp instant(_value), do: :error

  defp task_value(task, "title"), do: task.title
  defp task_value(task, "notes"), do: task.notes
  defp task_value(task, "inbox_state"), do: Atom.to_string(task.inbox_state)
  defp task_value(task, "planned_on"), do: task.planned_on
  defp task_value(task, "completed_at"), do: task.completed_at
  defp task_value(task, "trashed_at"), do: task.trashed_at
end
