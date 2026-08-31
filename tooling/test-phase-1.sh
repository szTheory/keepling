#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

list_lanes() {
  echo "repository-integrity  tooling/check-repository-integrity.sh"
  echo "server-compile        runtime-gated Mix compile"
  echo "server-tests          complete ExUnit suite against disposable PostgreSQL"
  echo "production-routes     production router excludes test-only controls"
  echo "contracts             checked-in OpenAPI generation drift"
  echo "web-typecheck         TypeScript project references"
  echo "web-units             complete Vitest/jsdom suite"
  echo "web-e2e               complete Playwright real-stack suite"
}

phase_database_root=''

cleanup_phase_database() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$phase_database_root" ] && [ -d "$phase_database_root/data" ]; then
    ./tooling/runtime-preflight.sh --exec -- \
      pg_ctl -D "$phase_database_root/data" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$phase_database_root"
  fi
  exit "$status"
}

start_phase_database() {
  phase_database_port=${KEEPLING_PHASE1_POSTGRES_PORT:-55431}
  phase_database_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-phase1.XXXXXX")
  mkdir "$phase_database_root/socket"
  ./tooling/runtime-preflight.sh --exec -- \
    initdb --auth-host=trust --auth-local=trust --encoding=UTF8 --no-locale \
      -D "$phase_database_root/data" >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    pg_ctl -D "$phase_database_root/data" \
      -l "$phase_database_root/postgres.log" \
      -o "-h 127.0.0.1 -k $phase_database_root/socket -p $phase_database_port" \
      -w start >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    createdb -h 127.0.0.1 -p "$phase_database_port" keepling_phase1

  database_user=$(id -un)
  export KEEPLING_TEST_DATABASE_URL="ecto://$database_user@127.0.0.1:$phase_database_port/keepling_phase1"
  export KEEPLING_TEST_SECRET_KEY_BASE='phase-1-test-only-secret-key-base-000000000000000000000000000000000000000000000000'
}

assert_production_routes() {
  production_routes=$(
    DATABASE_URL='ecto://keepling@127.0.0.1/keepling_production_route_check' \
    SECRET_KEY_BASE='phase-1-production-route-check-only-000000000000000000000000000000000000000000000000' \
    PHX_HOST='localhost' \
    MIX_ENV=prod \
      ./tooling/runtime-preflight.sh --exec -- sh -c \
        'cd apps/server && mix compile --warnings-as-errors >/dev/null && mix phx.routes'
  )
  if printf '%s\n' "$production_routes" | grep -E '/api/v1/test|test/session' >/dev/null; then
    echo 'Phase 1 production route inspection found a test-only control' >&2
    return 1
  fi
}

run_lanes() {
  trap cleanup_phase_database EXIT HUP INT TERM
  ./tooling/check-repository-integrity.sh
  start_phase_database
  MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix ecto.migrate && mix compile --warnings-as-errors && mix test'
  assert_production_routes
  pnpm contracts:check
  pnpm --filter @keepling/web typecheck
  pnpm --filter @keepling/web test --run --passWithNoTests
  pnpm --filter @keepling/web test:e2e
  echo "Phase 1 server, contract, browser, privacy, and production-isolation lanes passed"
}

usage() {
  echo "Usage: $0 --list | --run" >&2
  exit 2
}

case "${1:-}" in
  --list)
    [ "$#" -eq 1 ] || usage
    list_lanes
    ;;
  --run)
    [ "$#" -eq 1 ] || usage
    run_lanes
    ;;
  *)
    usage
    ;;
esac
