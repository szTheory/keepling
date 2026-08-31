defmodule Keepling.Accounts.RateLimit do
  @moduledoc """
  Application-owned authentication abuse policy over Hammer's ETS backend.

  Bucket keys contain only a closed namespace and a SHA-256 digest of the sole
  account class or a coarsened network source. Raw addresses, credentials,
  fingerprints, bearer values, and arbitrary identifiers never enter ETS,
  audit rows, or telemetry metadata.
  """

  use Hammer, backend: :ets

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @clean_period_ms :timer.minutes(5)
  @flows [:setup, :login, :recovery]

  @default_policies %{
    setup: %{
      account: {:timer.minutes(15), 5},
      source: {:timer.minutes(15), 20},
      max_backoff_ms: :timer.minutes(15)
    },
    login: %{
      account: {:timer.minutes(5), 10},
      source: {:timer.minutes(5), 50},
      max_backoff_ms: :timer.minutes(5)
    },
    recovery: %{
      account: {:timer.minutes(15), 5},
      source: {:timer.minutes(15), 20},
      max_backoff_ms: :timer.minutes(15)
    }
  }

  @spec clean_period_ms() :: pos_integer()
  def clean_period_ms, do: @clean_period_ms

  @spec admit(:setup | :login | :recovery, :inet.ip_address(), keyword()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def admit(flow, source, opts \\ []) when flow in @flows do
    policy = Keyword.get(opts, :policy, configured_policy(flow))

    with :ok <- hit_bucket(account_bucket(flow), policy.account, policy.max_backoff_ms),
         :ok <- hit_bucket(source_bucket(flow, source), policy.source, policy.max_backoff_ms) do
      :ok
    else
      {:error, :rate_limited, retry_after_ms} = limited ->
        emit_decision(flow, :limited)
        record_limited_audit()
        min_backoff = max(retry_after_ms, 1)
        put_elem(limited, 2, min(min_backoff, policy.max_backoff_ms))
    end
  end

  @spec emit_decision(:setup | :login | :recovery, :accepted | :invalid | :limited) :: :ok
  def emit_decision(flow, outcome)
      when flow in @flows and outcome in [:accepted, :invalid, :limited] do
    :telemetry.execute(
      [:keepling, :authentication, :decision],
      %{count: 1},
      %{flow: flow, outcome: outcome}
    )

    :ok
  end

  defp configured_policy(flow) do
    :keepling
    |> Application.get_env(:rate_limit_policy, %{})
    |> Map.get(flow, Map.fetch!(@default_policies, flow))
  end

  defp hit_bucket(key, {scale_ms, limit}, max_backoff_ms)
       when is_integer(scale_ms) and scale_ms > 0 and is_integer(limit) and limit > 0 do
    case hit(key, scale_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, min(max(retry_after_ms, 1), max_backoff_ms)}
    end
  end

  defp account_bucket(flow) do
    {"#{flow}:account", digest(:closed_personal_account)}
  end

  defp source_bucket(flow, source) do
    {"#{flow}:source", source |> coarsen_source() |> digest()}
  end

  defp coarsen_source({a, b, c, _d}) when is_integer(a) and is_integer(b) and is_integer(c),
    do: {:ipv4_24, a, b, c}

  defp coarsen_source({a, b, c, d, _e, _f, _g, _h})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d),
       do: {:ipv6_64, a, b, c, d}

  defp coarsen_source(_source), do: :unknown_source

  defp digest(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp record_limited_audit do
    accepted_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query(
      Repo,
      """
      INSERT INTO account_security_audits (
        event_type, event_version, accepted_at, inserted_at
      )
      VALUES ('rate_limited', 1, $1, $1)
      """,
      [accepted_at]
    )

    :ok
  rescue
    _error -> :ok
  end
end
