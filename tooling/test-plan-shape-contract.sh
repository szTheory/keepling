#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

result=$(./tooling/verify-host-replacement.sh --plan-shape-self-test)
[ "$result" = "Host replacement plan shape regression passed" ] || {
  echo "Plan shape regression failed: unexpected verifier result" >&2
  exit 1
}

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-plan-shape-cli.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
printf '{malformed\n' >"$fixture_root/malformed.json"
set +e
failure=$(./tooling/verify-host-replacement.sh --validate-plan-shape "$fixture_root/malformed.json" 2>&1)
failure_rc=$?
set -e
[ "$failure_rc" -ne 0 ] || {
  echo "Plan shape regression failed: malformed CLI fixture was accepted" >&2
  exit 1
}
[ "$failure" = "Host replacement verification failed: evaluated plan shape contract is invalid" ] || {
  echo "Plan shape regression failed: rejection was not a fixed sanitized marker" >&2
  exit 1
}

echo "Plan shape regression passed: evaluated creates follow the tracked state-address authority"
