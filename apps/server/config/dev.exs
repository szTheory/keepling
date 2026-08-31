import Config

config :keepling, Keepling.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: false

config :keepling, KeeplingWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: []

config :keepling, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
