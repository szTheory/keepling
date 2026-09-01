#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Host replacement sequence regression failed: $*" >&2
  exit 1
}

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-sequence.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

cat >"$fixture_root/runner" <<'EOF'
#!/usr/bin/env sh
set -eu
name=$(basename "$0")
printf '%s\n' "$name" >>"$KEEPLING_SEQUENCE_LEDGER"
[ "${KEEPLING_SEQUENCE_FAIL_AT:-}" != "$name" ]
EOF
chmod 700 "$fixture_root/runner"
for name in bootstrap image restore runtime semantic dns teardown; do
  ln -s "$fixture_root/runner" "$fixture_root/$name"
done

run_sequence() {
  fail_at=$1
  ledger=$2
  : >"$ledger"
  if KEEPLING_SEQUENCE_LEDGER="$ledger" \
    KEEPLING_SEQUENCE_FAIL_AT="$fail_at" \
    KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/bootstrap" \
    KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/image" \
    KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" \
    KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/runtime" \
    KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/semantic" \
    KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" \
    KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >/dev/null 2>&1; then
    [ -z "$fail_at" ] || die "sequence accepted failing stage $fail_at"
  else
    [ -n "$fail_at" ] || die "passing candidate sequence failed"
  fi
}

run_sequence '' "$fixture_root/success"
cat >"$fixture_root/success-expected" <<'EOF'
bootstrap
image
restore
runtime
semantic
dns
teardown
EOF
cmp -s "$fixture_root/success-expected" "$fixture_root/success" ||
  die "passing sequence did not preserve the required gate order"

run_sequence image "$fixture_root/image-failure"
cat >"$fixture_root/image-failure-expected" <<'EOF'
bootstrap
image
teardown
EOF
cmp -s "$fixture_root/image-failure-expected" "$fixture_root/image-failure" ||
  die "image failure did not block later gates and teardown once"

run_sequence semantic "$fixture_root/semantic-failure"
cat >"$fixture_root/semantic-failure-expected" <<'EOF'
bootstrap
image
restore
runtime
semantic
teardown
EOF
cmp -s "$fixture_root/semantic-failure-expected" "$fixture_root/semantic-failure" ||
  die "semantic failure reached DNS or bypassed teardown"

KEEPLING_SEQUENCE_LEDGER="$fixture_root/idempotent-teardown" \
  KEEPLING_SEQUENCE_FAIL_AT='' "$fixture_root/teardown"
KEEPLING_SEQUENCE_LEDGER="$fixture_root/idempotent-teardown" \
  KEEPLING_SEQUENCE_FAIL_AT='' "$fixture_root/teardown"
[ "$(grep -c '^teardown$' "$fixture_root/idempotent-teardown")" -eq 2 ] ||
  die "teardown adapter was not independently repeatable"

echo "Host replacement sequence regression passed: ordered gates, DNS fence, and teardown guarantee"
