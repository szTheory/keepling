defmodule Keepling.Domain.Task do
  @moduledoc """
  Pure task decisions for Keepling's semantic command boundary.

  The task aggregate knows nothing about transport, persistence, accounts, or
  clocks. Callers provide accepted time and preselected identities explicitly.
  """

  @max_title_length 512

  @enforce_keys [:id, :title, :inbox_state, :revision, :captured_at]
  defstruct [:id, :title, :inbox_state, :revision, :captured_at]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          inbox_state: :inbox,
          revision: pos_integer(),
          captured_at: DateTime.t()
        }

  @type activity :: %{
          type: :task_captured,
          version: 1,
          from_revision: nil,
          to_revision: 1,
          accepted_at: DateTime.t(),
          changed_fields: map()
        }

  @spec capture(%{task_id: String.t(), title: String.t(), accepted_at: DateTime.t()}) ::
          {:ok, t(), activity()} | {:error, :title_required | :title_too_long}
  def capture(%{task_id: task_id, title: submitted_title, accepted_at: accepted_at}) do
    title = String.trim(submitted_title)

    cond do
      title == "" ->
        {:error, :title_required}

      String.length(title) > @max_title_length ->
        {:error, :title_too_long}

      true ->
        task = %__MODULE__{
          id: task_id,
          title: title,
          inbox_state: :inbox,
          revision: 1,
          captured_at: accepted_at
        }

        activity = %{
          type: :task_captured,
          version: 1,
          from_revision: nil,
          to_revision: 1,
          accepted_at: accepted_at,
          changed_fields: %{
            "inbox_state" => %{"from" => nil, "to" => "inbox"},
            "title" => %{"from" => nil, "to" => title}
          }
        }

        {:ok, task, activity}
    end
  end
end
