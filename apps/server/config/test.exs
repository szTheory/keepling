import Config

config :keepling, Keepling.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# 06-04-PLAN.md Task 3: a small, finite test-environment export timeout and
# chunk size, so a runaway export test fails fast instead of hanging the
# suite; production keeps the unbounded `:infinity` default in config.exs.
config :keepling, export_query_timeout_ms: 5_000, export_max_rows: 50

config :keepling, KeeplingWeb.Endpoint, server: false

config :logger, level: :warning

config :argon2_elixir,
  m_cost: 8,
  parallelism: 2,
  t_cost: 1

# Browser lifecycle tests intentionally exercise many successful sign-ins against
# one seeded personal account. Keep the production abuse policy unchanged while
# preventing test order from exhausting the shared account bucket.
#
# Raised from 50 in KPL-05-13. That plan added server tests that each sign in,
# which pushed the suite past 50 logins inside the window; the bucket then
# refused the next login and `auth_controller.ex` maps `:rate_limited` to the
# same 401 `authentication_failed` a wrong password gets -- correct for a
# caller, indistinguishable in a test failure. Four MCP tests failed on a
# credential that was never wrong. This is the test bucket only; the production
# abuse policy is untouched.
config :keepling, :rate_limit_policy, %{
  login: %{
    account: {:timer.minutes(5), 400},
    source: {:timer.minutes(5), 400},
    max_backoff_ms: :timer.minutes(5)
  }
}

config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
