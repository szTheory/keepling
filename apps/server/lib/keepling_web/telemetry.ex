defmodule KeeplingWeb.Telemetry do
  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("keepling.sync.decision.count", tags: [:operation, :outcome]),
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("keepling.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("keepling.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("keepling.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("keepling.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("keepling.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection waited before checkout"
      ),
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  @doc "Runs one synchronization transport decision with closed, bounded diagnostics."
  @spec span_sync(:bootstrap | :pull, (-> result)) :: result when result: term()
  def span_sync(operation, fun) when operation in [:bootstrap, :pull] and is_function(fun, 0) do
    result = fun.()
    emit_sync(operation, outcome(result))
    result
  rescue
    error ->
      emit_sync(operation, :exception)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      emit_sync(operation, :exception)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp emit_sync(operation, outcome) do
    :telemetry.execute(
      [:keepling, :sync, :decision],
      %{count: 1},
      %{operation: operation, outcome: outcome}
    )
  end

  defp outcome({:ok, _body}), do: :accepted
  defp outcome({:reset_required, _reason}), do: :reset_required
  defp outcome({:quarantined, _reason}), do: :quarantined
  defp outcome({:error, reason}) when reason in [:invalid_limit, :invalid_pull], do: :rejected
  defp outcome({:error, _reason}), do: :unavailable
  defp outcome(_result), do: :rejected

  defp periodic_measurements, do: []
end
