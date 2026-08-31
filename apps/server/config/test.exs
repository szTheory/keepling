import Config

config :keepling, Keepling.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :keepling, KeeplingWeb.Endpoint, server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
