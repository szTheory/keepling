defmodule Keepling.ConcurrencyCase do
  @moduledoc """
  ExUnit support for deterministic races on independent PostgreSQL backends.

  `with_connection/2` deliberately checks out an unboxed Sandbox connection in
  the calling process. Call it from separate tasks and synchronize those tasks
  with a barrier so a concurrency test cannot accidentally become sequential.
  Tests using this helper must clean up any committed rows they create.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Keepling.ConcurrencyCase.Barrier

  using do
    quote do
      import Keepling.ConcurrencyCase
    end
  end

  @doc """
  Starts a reusable barrier that releases each generation after `parties` arrive.
  """
  def start_barrier(parties) when is_integer(parties) and parties > 1 do
    {:ok, barrier} = Barrier.start_link(parties)
    barrier
  end

  @doc """
  Waits until every party in the current barrier generation has arrived.
  """
  def await(barrier, timeout \\ 5_000) do
    GenServer.call(barrier, :arrive, timeout)
  end

  @doc """
  Runs `fun` on a real independently checked-out connection.

  The callback receives PostgreSQL's backend PID, which lets tests prove that
  competing operations do not share one Sandbox connection.
  """
  def with_connection(repo \\ Keepling.Repo, fun) when is_function(fun, 1) do
    Sandbox.unboxed_run(repo, fn ->
      %{rows: [[backend_pid]]} =
        Ecto.Adapters.SQL.query!(repo, "SELECT pg_backend_pid()", [])

      fun.(backend_pid)
    end)
  end
end

defmodule Keepling.ConcurrencyCase.Barrier do
  @moduledoc false

  use GenServer

  def start_link(parties) do
    GenServer.start_link(__MODULE__, parties)
  end

  @impl true
  def init(parties) do
    {:ok, %{parties: parties, waiting: []}}
  end

  @impl true
  def handle_call(:arrive, from, %{parties: parties, waiting: waiting} = state) do
    waiting = [from | waiting]

    if length(waiting) == parties do
      Enum.each(waiting, &GenServer.reply(&1, :ok))
      {:noreply, %{state | waiting: []}}
    else
      {:noreply, %{state | waiting: waiting}}
    end
  end
end
