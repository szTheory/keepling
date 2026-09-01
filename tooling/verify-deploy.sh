#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Deploy verification failed: $*" >&2
  exit 1
}

# RED contract: the GREEN implementation must provide each black-box behavior
# before this verifier can promote any artifact.
for required_function in \
  require_exact_digest \
  rollback_eligibility \
  deploy_exact_digest \
  prove_interrupted_retry \
  prove_user_smoke; do
  command -v "$required_function" >/dev/null 2>&1 ||
    die "RED: missing deployment behavior '$required_function'"
done

[ "${1:-}" = "--local" ] || die "usage: $0 --local"

require_exact_digest 'keepling-server:latest' && die "mutable tags must be rejected"
require_exact_digest 'ghcr.io/sztheory/keepling-server@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

rollback_eligibility \
  'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  14 1 1 14 1 1 || die "compatible tested rollback was rejected"

if rollback_eligibility \
  'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  15 1 1 14 1 1; then
  die "schema-incompatible rollback was permitted"
fi

deploy_exact_digest
prove_interrupted_retry
prove_user_smoke

echo "Deploy verification passed: exact digest migration, readiness, interruption retry, user smoke, and rollback policy are proven"
