defmodule Keepling.Domain.Task do
  @moduledoc """
  Pure task decisions for Keepling's semantic command boundary.

  The versioned detail bounds are compatibility constants. The task aggregate
  knows nothing about transport, persistence, accounts, or clocks.
  """

  @details_version 1
  @max_title_length 512
  @max_notes_length 50_000
  @detail_fields [:title, :notes]

  alias Keepling.Domain.Merge

  @enforce_keys [:id, :title, :notes, :inbox_state, :revision, :captured_at]
  defstruct [
    :id,
    :title,
    :notes,
    :inbox_state,
    :revision,
    :captured_at,
    completed_at: nil,
    lifecycle_revision: 0,
    planned_on: nil,
    deadline_on: nil,
    trashed_at: nil
  ]

  @type inbox_state :: :inbox | :clarified
  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          notes: String.t(),
          inbox_state: inbox_state(),
          revision: pos_integer(),
          captured_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          lifecycle_revision: non_neg_integer(),
          planned_on: Date.t() | nil,
          deadline_on: Date.t() | nil,
          trashed_at: DateTime.t() | nil
        }

  @type activity :: %{
          type: atom(),
          version: 1,
          from_revision: pos_integer() | nil,
          to_revision: pos_integer(),
          accepted_at: DateTime.t(),
          changed_fields: map()
        }

  @spec details_version() :: 1
  def details_version, do: @details_version

  @spec details_limits() :: %{title: 512, notes: 50_000}
  def details_limits, do: %{title: @max_title_length, notes: @max_notes_length}

  @spec capture(%{task_id: String.t(), title: String.t(), accepted_at: DateTime.t()}) ::
          {:ok, t(), activity()} | {:error, :title_required | :title_too_long}
  def capture(%{task_id: task_id, title: submitted_title, accepted_at: accepted_at}) do
    with {:ok, title} <- normalize_title(submitted_title) do
      task = %__MODULE__{
        id: task_id,
        title: title,
        notes: "",
        inbox_state: :inbox,
        revision: 1,
        captured_at: accepted_at,
        completed_at: nil,
        lifecycle_revision: 0,
        planned_on: nil,
        deadline_on: nil,
        trashed_at: nil
      }

      activity =
        activity(:task_captured, nil, task, accepted_at, %{
          "inbox_state" => %{"from" => nil, "to" => "inbox"},
          "notes" => %{"from" => nil, "to" => ""},
          "title" => %{"from" => nil, "to" => title}
        })

      {:ok, task, activity}
    end
  end

  @spec edit(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, atom() | {:edit_conflict, [String.t()]}}
  def edit(%__MODULE__{} = task, command) do
    with :ok <- require_touched_fields(command),
         {:ok, fields} <- normalize_fields(command.fields),
         {:ok, updated, changes} <- merge_fields(task, command.base_values, fields) do
      finish(task, updated, changes, :task_details_updated, command.accepted_at)
    end
  end

  @spec resolve_conflict(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, atom()}
  def resolve_conflict(%__MODULE__{} = task, command) do
    with true <- command.latest_revision == task.revision,
         {:ok, fields} <- normalize_fields(command.resolved_fields),
         {:ok, updated, changes} <-
           Merge.three_way(task, Map.take(task, Map.keys(fields)), fields, @detail_fields) do
      finish(task, updated, changes, :task_details_updated, command.accepted_at)
    else
      false -> {:error, :stale_conflict}
      {:conflict, _fields} -> {:error, :stale_conflict}
      {:error, :invalid_merge_fields} -> {:error, :invalid_conflict_resolution}
      error -> error
    end
  end

  @spec clarify(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, atom() | {:edit_conflict, [String.t()]}}
  def clarify(%__MODULE__{} = task, command) do
    with {:ok, fields} <- normalize_fields(command.fields),
         {:ok, updated, detail_changes} <- merge_fields(task, command.base_values, fields) do
      {updated, changes} =
        if task.inbox_state == :inbox do
          {%{updated | inbox_state: :clarified},
           Map.put(detail_changes, "inbox_state", %{"from" => "inbox", "to" => "clarified"})}
        else
          {updated, detail_changes}
        end

      finish(task, updated, changes, :task_clarified, command.accepted_at)
    end
  end

  @spec return_to_inbox(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, {:edit_conflict, [String.t()]}}
  def return_to_inbox(%__MODULE__{inbox_state: :inbox} = task, _command),
    do: {:ok, task, nil, :already_satisfied}

  def return_to_inbox(%__MODULE__{} = task, command) do
    if command.expected_revision == task.revision do
      updated = %{task | inbox_state: :inbox}

      finish(
        task,
        updated,
        %{"inbox_state" => %{"from" => "clarified", "to" => "inbox"}},
        :task_returned_to_inbox,
        command.accepted_at
      )
    else
      {:error, {:edit_conflict, ["inbox_state"]}}
    end
  end

  @spec complete(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, {:lifecycle_conflict, [String.t()]}}
  def complete(%__MODULE__{completed_at: completed_at} = task, _command)
      when not is_nil(completed_at),
      do: {:ok, task, nil, :already_satisfied}

  def complete(%__MODULE__{} = task, command) do
    lifecycle_transition(task, command, command.accepted_at, :task_completed)
  end

  @spec reopen(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, {:lifecycle_conflict, [String.t()]}}
  def reopen(%__MODULE__{completed_at: nil} = task, _command),
    do: {:ok, task, nil, :already_satisfied}

  def reopen(%__MODULE__{} = task, command) do
    lifecycle_transition(task, command, nil, :task_reopened)
  end

  @spec trash(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, {:trash_conflict, [String.t()]}}
  def trash(%__MODULE__{} = task, command) do
    trash_transition(task, command, :trash)
  end

  @spec restore(t(), map()) ::
          {:ok, t(), activity() | nil, :accepted | :already_satisfied}
          | {:error, {:trash_conflict, [String.t()]}}
  def restore(%__MODULE__{} = task, command) do
    trash_transition(task, command, :restore)
  end

  defp require_touched_fields(%{fields: fields}) when map_size(fields) > 0, do: :ok
  defp require_touched_fields(_command), do: {:error, :no_fields_touched}

  defp normalize_fields(fields) when is_map(fields) do
    if Enum.all?(Map.keys(fields), &(&1 in @detail_fields)) do
      Enum.reduce_while(fields, {:ok, %{}}, fn
        {:title, value}, {:ok, normalized} ->
          case normalize_title(value) do
            {:ok, title} -> {:cont, {:ok, Map.put(normalized, :title, title)}}
            error -> {:halt, error}
          end

        {:notes, value}, {:ok, normalized} ->
          if is_binary(value) and String.length(value) <= @max_notes_length do
            {:cont, {:ok, Map.put(normalized, :notes, value)}}
          else
            {:halt, {:error, :notes_too_long}}
          end
      end)
    else
      {:error, :invalid_detail_fields}
    end
  end

  defp normalize_fields(_fields), do: {:error, :invalid_detail_fields}

  defp normalize_title(value) when is_binary(value) do
    title = String.trim(value)

    cond do
      title == "" -> {:error, :title_required}
      String.length(title) > @max_title_length -> {:error, :title_too_long}
      true -> {:ok, title}
    end
  end

  defp normalize_title(_value), do: {:error, :title_required}

  defp merge_fields(task, base_values, fields)
       when is_map(base_values) and map_size(base_values) == map_size(fields) do
    case Merge.three_way(task, base_values, fields, @detail_fields) do
      {:ok, updated, changes} -> {:ok, updated, changes}
      {:conflict, fields} -> {:error, {:edit_conflict, fields}}
      {:error, :invalid_merge_fields} -> {:error, :base_values_mismatch}
    end
  end

  defp merge_fields(_task, _base_values, _fields), do: {:error, :base_values_mismatch}

  defp lifecycle_transition(task, command, completed_at, activity_type) do
    if task.lifecycle_revision > command.expected_revision do
      {:error, {:lifecycle_conflict, ["completed_at"]}}
    else
      updated = %{
        task
        | completed_at: completed_at,
          lifecycle_revision: task.revision + 1
      }

      finish(
        task,
        updated,
        %{"completed_at" => %{"from" => task.completed_at, "to" => completed_at}},
        activity_type,
        command.accepted_at
      )
    end
  end

  defp trash_transition(task, command, operation) do
    cond do
      command.expected_revision != task.revision ->
        {:error, {:trash_conflict, ["trashed_at"]}}

      operation == :trash and not is_nil(task.trashed_at) ->
        {:ok, task, nil, :already_satisfied}

      operation == :restore and is_nil(task.trashed_at) ->
        {:ok, task, nil, :already_satisfied}

      true ->
        {trashed_at, activity_type} =
          if operation == :trash,
            do: {command.accepted_at, :task_trashed},
            else: {nil, :task_restored}

        updated = %{task | trashed_at: trashed_at}

        finish(
          task,
          updated,
          %{"trashed_at" => %{"from" => task.trashed_at, "to" => trashed_at}},
          activity_type,
          command.accepted_at
        )
    end
  end

  defp finish(task, _updated, changes, _type, _accepted_at) when map_size(changes) == 0,
    do: {:ok, task, nil, :already_satisfied}

  defp finish(task, updated, changes, type, accepted_at) do
    updated = %{updated | revision: task.revision + 1}
    {:ok, updated, activity(type, task.revision, updated, accepted_at, changes), :accepted}
  end

  defp activity(type, from_revision, task, accepted_at, changed_fields) do
    %{
      type: type,
      version: 1,
      from_revision: from_revision,
      to_revision: task.revision,
      accepted_at: accepted_at,
      changed_fields: changed_fields
    }
  end
end
