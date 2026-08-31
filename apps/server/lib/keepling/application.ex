defmodule Keepling.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Keepling.Repo,
      {Keepling.Accounts.RateLimit,
       [clean_period: Keepling.Accounts.RateLimit.clean_period_ms()]},
      KeeplingWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:keepling, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Keepling.PubSub},
      KeeplingWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Keepling.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KeeplingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
