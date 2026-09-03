defmodule Keepling.Application do
  @moduledoc false

  use Application

  @client_kinds ~w(electron iphone)

  @impl true
  def start(_type, _args) do
    :keepling
    |> Application.fetch_env!(:compatibility)
    |> Keepling.Application.Compatibility.validate_config!()

    :keepling
    |> Application.get_env(:device_grants)
    |> validate_device_grants!()

    children = [
      Keepling.Repo,
      Keepling.Accounts.SecurityAudit,
      {Keepling.Accounts.RateLimit,
       [clean_period: Keepling.Accounts.RateLimit.clean_period_ms()]},
      KeeplingWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:keepling, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Keepling.PubSub},
      KeeplingWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Keepling.Supervisor)
  end

  @doc """
  Pre-supervision validation of the `:keepling, :device_grants` block
  (O-18). Three of the five locked namespace-tuple fields -- issuer, origin,
  and stable server instance -- come from this configuration, and
  `Keepling.Accounts.DeviceGrant` reads it on every authorization and
  exchange. An absent or malformed block previously produced a silent 400 at
  `/oauth/authorize` on a running server; it now refuses to boot with a
  named, actionable error.

  These values are server-derived only. No request input reaches this
  function -- it reads application configuration exclusively.
  """
  @spec validate_device_grants!(term()) :: :ok
  def validate_device_grants!(config) when is_list(config) do
    non_empty_string!(config[:issuer], "device grant issuer")
    absolute_url!(config[:issuer], "device grant issuer")
    non_empty_string!(config[:origin], "device grant origin")
    absolute_url!(config[:origin], "device grant origin")
    non_empty_string!(config[:server_instance], "device grant server instance")
    redirect_uris!(config[:redirect_uris])
    :ok
  end

  def validate_device_grants!(_config) do
    raise ArgumentError,
          "device grant configuration is required: set :keepling, :device_grants " <>
            "(issuer, origin, server_instance, redirect_uris) in config/runtime.exs"
  end

  defp non_empty_string!(value, label) do
    unless is_binary(value) and String.trim(value) != "" do
      raise ArgumentError, "#{label} must be a non-empty string"
    end
  end

  defp absolute_url!(value, label) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        raise ArgumentError, "#{label} must be an absolute http(s) URL"
    end
  end

  defp redirect_uris!(redirect_uris) when is_map(redirect_uris) do
    unless Enum.sort(Map.keys(redirect_uris)) == @client_kinds do
      raise ArgumentError,
            "device grant redirect allowlist must name exactly #{Enum.join(@client_kinds, ", ")}"
    end

    for {client_kind, uris} <- redirect_uris do
      unless is_list(uris) and uris != [] do
        raise ArgumentError,
              "device grant redirect allowlist for #{client_kind} must list at least one URI"
      end

      for uri <- uris do
        case URI.new(uri) do
          {:ok, %URI{scheme: "keepling", host: host, path: path}}
          when is_binary(host) and host != "" and is_binary(path) and path != "" ->
            :ok

          _ ->
            raise ArgumentError,
                  "device grant redirect allowlist entry #{inspect(uri)} for #{client_kind} " <>
                    "must be an exact private-use keepling://host/path URI"
        end
      end
    end

    :ok
  end

  defp redirect_uris!(_redirect_uris) do
    raise ArgumentError, "device grant redirect allowlist must be a map of client kind to URIs"
  end

  @impl true
  def config_change(changed, _new, removed) do
    KeeplingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
