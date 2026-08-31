import Config

config :keepling, Keepling.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :keepling, KeeplingWeb.Endpoint, server: false

config :logger, level: :warning

config :argon2_elixir,
  m_cost: 8,
  parallelism: 2,
  t_cost: 1

# Browser lifecycle tests intentionally exercise many successful sign-ins against
# one seeded personal account. Keep the production abuse policy unchanged while
# preventing test order from exhausting the shared account bucket.
config :keepling, :rate_limit_policy, %{
  login: %{
    account: {:timer.minutes(5), 50},
    source: {:timer.minutes(5), 50},
    max_backoff_ms: :timer.minutes(5)
  }
}

config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
