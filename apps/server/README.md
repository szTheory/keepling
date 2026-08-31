# Keepling Server

**Technology:** standalone Phoenix application with Ecto/PostgreSQL; not an umbrella

This boundary will own domain/application modules, canonical persistence, authentication/authorization, command/query/synchronization adapters, release migrations, and the MCP adapter. Domain rules must remain independent of Phoenix transport, MCP, and client implementations.

The repository root owns Git history, planning, and runtime selection. Run every
Elixir, OTP, Mix, or PostgreSQL command from the repository root through the
runtime wrapper; do not add application-level `.tool-versions`, `.git`, or
`.planning` files.

## Local configuration

Keepling never commits database credentials or endpoint signing secrets. Set the
development values before starting the application:

```sh
export KEEPLING_DEV_DATABASE_URL='ecto://USER:PASSWORD@HOST/keepling_dev'
export KEEPLING_DEV_SECRET_KEY_BASE="$({ ./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix phx.gen.secret'; } | tail -n 1)"
```

Tests that start the application use `KEEPLING_TEST_DATABASE_URL` and
`KEEPLING_TEST_SECRET_KEY_BASE`. Production uses `DATABASE_URL`,
`SECRET_KEY_BASE`, and `PHX_HOST`. Missing required values fail with the key and
active Mix environment named, without printing their contents.

## Commands

Verify the exact repository-owned toolchain:

```sh
./tooling/runtime-preflight.sh --check
```

Fetch the locked dependencies and create the development database:

```sh
./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix deps.get --check-locked && mix ecto.create'
```

Compile the standalone core:

```sh
./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix compile --warnings-as-errors'
```

Compile the test configuration now:

```sh
./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && MIX_ENV=test mix compile --warnings-as-errors'
```

Plan 01-03 owns the Endpoint, router, migrations/seeds, and ExUnit support. Once
that prerequisite lands, the complete test command is:

```sh
./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test'
```
