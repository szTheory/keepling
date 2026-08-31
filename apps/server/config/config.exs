import Config

config :keepling,
  ecto_repos: [Keepling.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Plan 01-03 owns these web modules. Declaring their configuration here keeps
# environment ownership complete without pulling transport code into the core.
config :keepling, KeeplingWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: KeeplingWeb.ErrorJSON], layout: false],
  pubsub_server: Keepling.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
