#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

list_lanes() {
  echo "repository-integrity  tooling/check-repository-integrity.sh"
  echo "server-compile        runtime-gated Mix compile"
  echo "contracts             checked-in OpenAPI generation drift"
  echo "web-unit-config       Vitest/jsdom configuration"
  echo "web-e2e-config        Playwright real-stack discovery"
}

run_lanes() {
  ./tooling/check-repository-integrity.sh
  ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix compile --warnings-as-errors'
  pnpm contracts:check
  pnpm --filter @keepling/web test --run --passWithNoTests
  pnpm --filter @keepling/web exec playwright test --list
  echo "Phase 1 available lanes passed"
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
