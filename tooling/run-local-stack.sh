#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

die() {
  echo "Local stack check failed: $*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || die "required file '$1' is unavailable"
}

check_config() {
  ./tooling/runtime-preflight.sh --check

  for path in \
    apps/server/mix.exs \
    apps/web/playwright.config.ts \
    apps/web/e2e/support/stack.ts \
    packages/contracts/openapi/keepling.yaml; do
    require_file "$path"
  done

  node --experimental-strip-types --check apps/web/e2e/support/stack.ts
  pnpm --filter @keepling/web exec playwright test --list >/dev/null
  echo "Local stack configuration passed: PostgreSQL 18.6, Phoenix, and Vite use one owned Playwright origin"
}

start_stack() {
  check_config
  test_fault_token=$(node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))")
  KEEPLING_TEST_FAULT_TOKEN=$test_fault_token
  export KEEPLING_TEST_FAULT_TOKEN
  exec node --experimental-strip-types apps/web/e2e/support/stack.ts
}

usage() {
  echo "Usage: $0 --check-config | --start" >&2
  exit 2
}

case "${1:-}" in
  --check-config)
    [ "$#" -eq 1 ] || usage
    check_config
    ;;
  --start)
    [ "$#" -eq 1 ] || usage
    start_stack
    ;;
  *)
    usage
    ;;
esac
