defmodule Keepling.SyncScenario do
  @moduledoc """
  Runs storage-neutral synchronization vectors through the reference reducer.

  The runner deliberately consumes the JSON string-keyed representation that
  later TypeScript and Swift implementations will share.
  """

  alias Keepling.Application.Sync.ReferenceModel

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(%{"actions" => actions}) when is_list(actions) do
    Enum.reduce_while(actions, {:ok, %{state: ReferenceModel.new(), ready_pushes: []}}, fn
      action, {:ok, scenario} ->
        case apply_action(scenario, action) do
          {:ok, next} -> {:cont, {:ok, next}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  def run(_case), do: {:error, :invalid_scenario}

  defp apply_action(scenario, %{"type" => "local_accept", "mutation" => mutation}) do
    with {:ok, "local_saved", state} <- ReferenceModel.local_accept(scenario.state, mutation) do
      {:ok, %{scenario | state: state}}
    end
  end

  defp apply_action(scenario, %{"type" => "pull", "page" => page}) do
    with {:ok, state} <- ReferenceModel.pull(scenario.state, page) do
      {:ok, %{scenario | state: state}}
    end
  end

  defp apply_action(scenario, %{"type" => "ready_pushes"}) do
    {:ok, %{scenario | ready_pushes: ReferenceModel.ready_pushes(scenario.state)}}
  end

  defp apply_action(scenario, %{"type" => "acknowledge", "acknowledgement" => acknowledgement}) do
    with {:ok, state} <- ReferenceModel.acknowledge(scenario.state, acknowledgement) do
      {:ok, %{scenario | state: state}}
    end
  end

  defp apply_action(_scenario, action), do: {:error, {:unknown_action, action["type"]}}
end
