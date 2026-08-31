defmodule Keepling.Application.Commands do
  @moduledoc """
  Shared semantic application boundary used by every outward adapter.
  """

  alias Keepling.Domain.Task

  defmodule Port do
    @moduledoc "Persistence/query port interpreted by an outward adapter."

    @callback execute(map(), map(), (map() -> tuple())) :: tuple()
    @callback list_inbox(map()) :: tuple()
    @callback lookup_result(map(), String.t()) :: tuple()
  end

  @spec dispatch(map(), map(), module()) :: tuple()
  def dispatch(%{type: :capture_task} = command, context, port) do
    port.execute(command, context, fn accepted_command ->
      Task.capture(%{
        accepted_at: accepted_command.accepted_at,
        task_id: accepted_command.task_id,
        title: accepted_command.title
      })
    end)
  end

  @spec list_inbox(map(), module()) :: tuple()
  def list_inbox(context, port), do: port.list_inbox(context)

  @spec lookup_result(map(), String.t(), module()) :: tuple()
  def lookup_result(context, mutation_id, port), do: port.lookup_result(context, mutation_id)
end
