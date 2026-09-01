import Config

config :keepling,
  ecto_repos: [Keepling.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  task_view_query_timeout_ms: 10_000

config :keepling, :compatibility, %{
  "server_release" => "0.1.0-dev",
  "tested_oci_digest" => "sha256:" <> String.duplicate("0", 64),
  "distribution" => "dogfood",
  "current_protocol_train" => 1,
  "previous_protocol_train" => nil,
  "previous_superseded_at" => nil,
  "deprecation_deadline" => nil,
  "emergency_override" => nil,
  "supported_protocols" => %{
    "read" => %{"minimum" => 1, "maximum" => 1},
    "write" => %{"minimum" => 1, "maximum" => 1},
    "sync" => %{"minimum" => 1, "maximum" => 1}
  },
  "schema_range" => %{"minimum" => 1, "maximum" => 1},
  "platform_minimum_builds" => %{"electron" => 0, "iphone" => 0},
  "update_location" => "https://github.com/szTheory/keepling/releases"
}

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

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :tzdata, :autoupdate, :disabled

config :argon2_elixir,
  argon2_type: 2,
  m_cost: 16,
  parallelism: 4,
  t_cost: 3

import_config "#{config_env()}.exs"
