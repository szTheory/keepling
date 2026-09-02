#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Remote prepare observability regression failed: $*" >&2; exit 1; }
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-remote-observability.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

cat >"$fixture_root/pass" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat >"$fixture_root/restore" <<'EOF'
#!/usr/bin/env sh
set -eu
KEEPLING_REMOTE_PREPARE_TEST_MODE=yes KEEPLING_REMOTE_PREPARE_TEST_FAILURE_STAGE="$FAILURE_STAGE" \
  ./tooling/remote-prepare-host.sh 101 \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  cccccccccccccccccccccccccccccccccccccccc amd64 host.invalid \
  sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
cat >"$fixture_root/teardown" <<'EOF'
#!/usr/bin/env sh
set -eu
count=$(cat "$TEARDOWN_COUNT")
printf '%s\n' "$((count + 1))" >"$TEARDOWN_COUNT"
EOF
cat >"$fixture_root/dns" <<'EOF'
#!/usr/bin/env sh
: >"$DNS_CALLED"
EOF
chmod 700 "$fixture_root/pass" "$fixture_root/restore" "$fixture_root/teardown" "$fixture_root/dns"

for pair in volume-device:41 volume-mount:42 filesystem:43 archive-integrity:44 image-load:45 image-id:46 image-revision:47 image-architecture:48 runtime-config:49 db-start:50 db-ready:51 restore:52 epoch:53 runtime:54; do
  failure_stage=${pair%%:*}
  expected_code=${pair#*:}
  teardown_count=$fixture_root/$failure_stage-teardown-count
  dns_called=$fixture_root/$failure_stage-dns-called
  output=$fixture_root/$failure_stage-output
  printf '0\n' >"$teardown_count"
  result=0
  FAILURE_STAGE="$failure_stage" TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" \
  KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" \
  KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$output" 2>&1 || result=$?
  [ "$result" -ne 0 ] || die "$failure_stage unexpectedly passed"
  [ "$(cat "$teardown_count")" = 1 ] || die "$failure_stage did not teardown exactly once"
  [ ! -e "$dns_called" ] || die "$failure_stage reached DNS"
  [ "$(grep -Ec '^REMOTE_PREPARE_FAILED_STAGE=[a-z-]+ RC=[0-9]+$' "$output")" = 1 ] || die "$failure_stage marker count is not exactly one"
  grep -Fx "REMOTE_PREPARE_FAILED_STAGE=$failure_stage RC=$expected_code" "$output" >/dev/null || die "$failure_stage marker is incorrect"
  at_sign=$(printf '\100')
  if grep -Eq "/|${at_sign}|token|secret|identifier|192[.]0[.]2" "$output"; then die "$failure_stage output retained disallowed detail"; fi
done

contract_output=$fixture_root/contract-output
result=0
./tooling/remote-prepare-host.sh >"$contract_output" 2>&1 || result=$?
[ "$result" -eq 40 ] || die "malformed contract did not return its bounded code"
[ "$(wc -l <"$contract_output" | tr -d ' ')" = 1 ] || die "malformed contract marker count is not exactly one"
grep -Fx 'REMOTE_PREPARE_FAILED_STAGE=contract RC=40' "$contract_output" >/dev/null || die "malformed contract marker is incorrect"

echo "Remote prepare observability regression passed: every failure is classified once, teardown-first, and DNS-unreachable"
