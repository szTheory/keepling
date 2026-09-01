defmodule Keepling.Accounts.SecurityAudit do
  @moduledoc """
  Persists the closed security-event vocabulary and exposes audit health.

  Required writes roll back their surrounding transaction when persistence
  fails. Best-effort writes preserve availability, but latch degraded health
  until an operator acknowledges the missing audit record. Telemetry and logs
  contain only the closed event type and persistence policy.
  """

  use GenServer

  require Logger

  alias Ecto.Adapters.SQL

  @closed_event_types ~w(
    login_failed
    login_succeeded
    logout
    rate_limited
    reauthenticated
    recovery_issued
    recovery_succeeded
    session_revoked
    device_grant_issued
    device_grant_refreshed
    device_grant_replay_revoked
    device_grant_revoked
  )

  @type health :: %{
          failure_count: non_neg_integer(),
          last_failure_at: String.t() | nil,
          status: :degraded | :healthy
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Returns the latched security-audit persistence health."
  @spec health() :: health()
  def health, do: GenServer.call(__MODULE__, :health)

  @doc "Acknowledges a diagnosed audit gap and restores the health latch."
  @spec acknowledge_degraded_health() :: :ok
  def acknowledge_degraded_health, do: GenServer.call(__MODULE__, :acknowledge)

  @doc "Persists an event or rolls back the caller's current transaction."
  @spec record_required!(module(), String.t(), DateTime.t()) :: :ok | no_return()
  def record_required!(repo, event_type, accepted_at) when event_type in @closed_event_types do
    case invoke_writer(repo, event_type, accepted_at) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        report_failure(:required, event_type, reason)
        repo.rollback(:security_audit_unavailable)
    end
  rescue
    error ->
      report_failure(:required, event_type, error)
      repo.rollback(:security_audit_unavailable)
  end

  @doc "Attempts an event write while deliberately preserving availability."
  @spec record_best_effort(module(), String.t(), DateTime.t()) :: :ok
  def record_best_effort(repo, event_type, accepted_at) when event_type in @closed_event_types do
    case invoke_writer(repo, event_type, accepted_at) do
      {:ok, _result} -> :ok
      {:error, reason} -> report_failure(:best_effort, event_type, reason)
    end

    :ok
  rescue
    error ->
      report_failure(:best_effort, event_type, error)
      :ok
  end

  @impl true
  def init(:ok), do: {:ok, healthy_state()}

  @impl true
  def handle_call(:health, _from, state), do: {:reply, state, state}

  def handle_call(:acknowledge, _from, _state) do
    {:reply, :ok, healthy_state()}
  end

  def handle_call({:degraded, failed_at}, _from, state) do
    degraded = %{
      failure_count: state.failure_count + 1,
      last_failure_at: DateTime.to_iso8601(failed_at),
      status: :degraded
    }

    {:reply, :ok, degraded}
  end

  defp invoke_writer(repo, event_type, accepted_at) do
    writer().insert(repo, event_type, accepted_at)
  end

  defp writer do
    Application.get_env(:keepling, :security_audit_writer, __MODULE__)
  end

  @doc false
  def insert(repo, event_type, accepted_at) do
    SQL.query(
      repo,
      """
      INSERT INTO account_security_audits (
        event_type, event_version, accepted_at, inserted_at
      )
      VALUES ($1, 1, $2, $2)
      """,
      [event_type, accepted_at]
    )
  end

  defp report_failure(policy, event_type, _reason) do
    failed_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Logger.error("security audit persistence degraded",
      event_type: event_type,
      persistence_policy: policy
    )

    :telemetry.execute(
      [:keepling, :security_audit, :persistence],
      %{failure_count: 1},
      %{event_type: event_type, persistence_policy: policy, status: :degraded}
    )

    GenServer.call(__MODULE__, {:degraded, failed_at})
  end

  defp healthy_state do
    %{failure_count: 0, last_failure_at: nil, status: :healthy}
  end
end
