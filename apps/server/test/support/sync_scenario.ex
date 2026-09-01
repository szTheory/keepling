defmodule Keepling.SyncScenario do
  @moduledoc """
  Runs storage-neutral synchronization vectors through the reference reducer.

  The runner deliberately consumes the JSON string-keyed representation that
  later TypeScript and Swift implementations will share.
  """

  alias Keepling.Application.Sync.ReferenceModel
  alias Keepling.Application.Sync

  @spec collect_bootstrap(map(), map(), module()) :: {:ok, [map()]} | {:error, term()}
  def collect_bootstrap(context, options, port) do
    collect_bootstrap(context, options, port, [], 0)
  end

  defp collect_bootstrap(_context, _options, _port, _pages, page_count)
       when page_count >= 1_000,
       do: {:error, :bootstrap_page_limit_exceeded}

  defp collect_bootstrap(context, options, port, pages, page_count) do
    case Sync.bootstrap(context, options, port) do
      {:ok, %{next_cursor: nil} = page} ->
        {:ok, pages ++ [page]}

      {:ok, %{next_cursor: cursor} = page} ->
        collect_bootstrap(
          context,
          %{cursor: cursor, limit: Map.get(options, :limit, 50)},
          port,
          pages ++ [page],
          page_count + 1
        )

      other ->
        other
    end
  end

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
    case ReferenceModel.ready_pushes(scenario.state) do
      ready when is_list(ready) -> {:ok, %{scenario | ready_pushes: ready}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_action(scenario, %{"type" => "fence", "reason" => reason}) do
    with {:ok, state} <- ReferenceModel.fence(scenario.state, reason) do
      {:ok, %{scenario | state: state}}
    end
  end

  defp apply_action(scenario, %{"type" => "relaunch"}) do
    durable = :erlang.term_to_binary(scenario.state, [:deterministic])
    {:ok, %{scenario | state: :erlang.binary_to_term(durable, [:safe])}}
  end

  defp apply_action(scenario, %{"type" => "acknowledge", "acknowledgement" => acknowledgement}) do
    with {:ok, state} <- ReferenceModel.acknowledge(scenario.state, acknowledgement) do
      {:ok, %{scenario | state: state}}
    end
  end

  defp apply_action(_scenario, action), do: {:error, {:unknown_action, action["type"]}}
end
