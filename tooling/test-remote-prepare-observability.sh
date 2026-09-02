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
if [ "${TEST_OBSERVED_ID+x}" = x ]; then observed_id=$TEST_OBSERVED_ID; else observed_id=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; fi
if [ "${TEST_OBSERVED_REVISION+x}" = x ]; then observed_revision=$TEST_OBSERVED_REVISION; else observed_revision=cccccccccccccccccccccccccccccccccccccccc; fi
if [ "${TEST_OBSERVED_ARCHITECTURE+x}" = x ]; then observed_architecture=$TEST_OBSERVED_ARCHITECTURE; else observed_architecture=amd64; fi
KEEPLING_REMOTE_PREPARE_TEST_MODE=yes KEEPLING_REMOTE_PREPARE_TEST_FAILURE_STAGE="$FAILURE_STAGE" \
KEEPLING_REMOTE_PREPARE_TEST_INSPECT_RC="${TEST_INSPECT_RC:-zero}" \
KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ID="$observed_id" \
KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_REVISION="$observed_revision" \
KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ARCHITECTURE="$observed_architecture" \
  ./tooling/remote-prepare-host.sh 101 \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee \
  cccccccccccccccccccccccccccccccccccccccc amd64 \
  sha256:1111111111111111111111111111111111111111111111111111111111111111,sha256:2222222222222222222222222222222222222222222222222222222222222222 host.invalid \
  sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
cat >"$fixture_root/fake-docker" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s|%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" >>"$DOCKER_CALLS"
if [ "${1:-}:${2:-}" = image:ls ]; then
  count=$(cat "$DOCKER_LS_COUNT"); count=$((count + 1)); printf '%s\n' "$count" >"$DOCKER_LS_COUNT"
  [ "$DOCKER_FAKE_CASE" != inventory-before-nonzero ] || [ "$count" -ne 1 ] || exit 1
  [ "$DOCKER_FAKE_CASE" != inventory-after-nonzero ] || [ "$count" -ne 2 ] || exit 1
  case "$DOCKER_FAKE_CASE:$count" in
    empty-inventory:1) exit 0 ;;
    empty-inventory:2) printf '%s\n' sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; exit 0 ;;
    already-present:1|already-present:2) printf '%s\n' sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; exit 0 ;;
    no-new:1|no-new:2) printf '%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff; exit 0 ;;
    malformed-before:1) printf '%s\n' invalid; exit 0 ;;
    malformed-after:2) printf '%s\n' invalid; exit 0 ;;
    uppercase-before:1) printf '%s\n' sha256:FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; exit 0 ;;
    whitespace-after:2) printf ' sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'; exit 0 ;;
    malicious-before:1) printf '%s\n' 'UNTRUSTED INVENTORY VALUE'; exit 0 ;;
    oversized-after:2) awk 'BEGIN { for (i=0;i<70000;i++) printf "x"; print "" }'; exit 0 ;;
    too-many-after:2) awk 'BEGIN { for (i=0;i<257;i++) print "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }'; exit 0 ;;
    duplicates:1) printf '%s\n%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff; exit 0 ;;
    duplicates:2) printf '%s\n%s\n%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; exit 0 ;;
    multiple-new:2) printf '%s\n%s\n%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; exit 0 ;;
    *:1) printf '%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff ;;
    *:2) printf '%s\n%s\n' sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  esac
  exit 0
fi
if [ "${1:-}" = load ]; then exit 0; fi
[ "${1:-}" = image ] && [ "${2:-}" = inspect ] && [ "${4:-}" = --format ] || exit 91
case "$DOCKER_FAKE_CASE:${5:-}" in
  inspect-nonzero:'{{.Id}}') exit 1 ;;
  inspect-id-empty:'{{.Id}}') exit 0 ;;
  inspect-id-other:'{{.Id}}') printf '%s\n' invalid ;;
  inspect-id-mismatch:'{{.Id}}') printf '%s\n' sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  malicious-inspect:'{{.Id}}') printf '%s\n' 'UNTRUSTED DOCKER OUTPUT' ;;
  *:'{{.Id}}') printf '%s\n' sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  descriptor-absent:'{{if .Descriptor}}{{.Descriptor.Digest}}{{end}}') exit 0 ;;
  descriptor-mismatch:'{{if .Descriptor}}{{.Descriptor.Digest}}{{end}}') printf '%s\n' sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  descriptor-malicious:'{{if .Descriptor}}{{.Descriptor.Digest}}{{end}}') printf '%s\n' 'UNTRUSTED DESCRIPTOR' ;;
  *:'{{if .Descriptor}}{{.Descriptor.Digest}}{{end}}') printf '%s\n' sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  revision-mismatch:'{{index .Config.Labels "org.opencontainers.image.revision"}}') printf '%s\n' eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  *:'{{index .Config.Labels "org.opencontainers.image.revision"}}') printf '%s\n' cccccccccccccccccccccccccccccccccccccccc ;;
  architecture-mismatch:'{{.Architecture}}') printf '%s\n' arm64 ;;
  *:'{{.Architecture}}') printf '%s\n' amd64 ;;
  rootfs-mismatch:'{{join .RootFS.Layers ","}}') printf '%s\n' sha256:3333333333333333333333333333333333333333333333333333333333333333 ;;
  rootfs-malicious:'{{join .RootFS.Layers ","}}') printf '%s\n' 'UNTRUSTED ROOTFS' ;;
  *:'{{join .RootFS.Layers ","}}') printf '%s\n' sha256:1111111111111111111111111111111111111111111111111111111111111111,sha256:2222222222222222222222222222222222222222222222222222222222222222 ;;
  *) exit 92 ;;
esac
EOF
cat >"$fixture_root/restore-docker-boundary" <<'EOF'
#!/usr/bin/env sh
set -eu
KEEPLING_REMOTE_PREPARE_DOCKER_BOUNDARY_TEST=yes KEEPLING_REMOTE_PREPARE_DOCKER_BIN="$FAKE_DOCKER" \
  ./tooling/remote-prepare-host.sh 101 \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee \
  cccccccccccccccccccccccccccccccccccccccc amd64 \
  sha256:1111111111111111111111111111111111111111111111111111111111111111,sha256:2222222222222222222222222222222222222222222222222222222222222222 host.invalid \
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
chmod 700 "$fixture_root/pass" "$fixture_root/restore" "$fixture_root/fake-docker" "$fixture_root/restore-docker-boundary" "$fixture_root/teardown" "$fixture_root/dns"

for pair in volume-device:41 volume-mount:42 filesystem:43 archive-integrity:44 image-load:45 image-inspect:46 image-id-compare:47 image-descriptor:59 image-revision:48 image-architecture:49 image-rootfs:60 runtime-config:50 db-start:51 db-ready:52 restore:53 epoch:54 runtime:55; do
  failure_stage=${pair%%:*}
  expected_code=${pair#*:}
  teardown_count=$fixture_root/$failure_stage-teardown-count
  dns_called=$fixture_root/$failure_stage-dns-called
  output=$fixture_root/$failure_stage-output
  printf '0\n' >"$teardown_count"
  result=0
  test_inspect_rc=zero
  test_observed_id=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  test_observed_revision=cccccccccccccccccccccccccccccccccccccccc
  test_observed_architecture=amd64
  case "$failure_stage" in
    image-inspect) test_inspect_rc=nonzero ;;
    image-id-compare) test_observed_id=sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
    image-revision) test_observed_revision=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
    image-architecture) test_observed_architecture=arm64 ;;
  esac
  FAILURE_STAGE="$failure_stage" TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" \
  TEST_INSPECT_RC="$test_inspect_rc" TEST_OBSERVED_ID="$test_observed_id" \
  TEST_OBSERVED_REVISION="$test_observed_revision" TEST_OBSERVED_ARCHITECTURE="$test_observed_architecture" \
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
  [ "$(grep -Ec '^REMOTE_PREPARE_FAILED_STAGE=[a-z-]+ RC=[0-9]+ BEFORE=(not-run|ok|command-failed|invalid|oversized|too-many) LOAD=(not-run|ok|nonzero) AFTER=(not-run|ok|command-failed|invalid|oversized|too-many) DELTA=(not-run|zero|one|multiple) INSPECT=(not-run|zero|nonzero) ID_SHAPE=(sha256-64|empty|other) ID_MATCH=(true|false) DESC=(not-run|absent|present|invalid) DESC_MATCH=(true|false) REV_SHAPE=(hex-7-64|empty|other) REV_MATCH=(true|false) ARCH_SHAPE=(amd64|empty|other) ARCH_MATCH=(true|false) ROOTFS_SHAPE=(digest-list|empty|other) ROOTFS_MATCH=(true|false)$' "$output")" = 1 ] || die "$failure_stage marker count is not exactly one"
  grep -E "^REMOTE_PREPARE_FAILED_STAGE=$failure_stage RC=$expected_code " "$output" >/dev/null || die "$failure_stage marker is incorrect"
  case "$failure_stage" in
    image-load) grep -F ' LOAD=nonzero ' "$output" >/dev/null || die "load failure classification is incomplete" ;;
    image-inspect) grep -F ' INSPECT=nonzero ID_SHAPE=empty ID_MATCH=false ' "$output" >/dev/null || die "inspect failure classification is incomplete" ;;
    image-id-compare) grep -F ' INSPECT=zero ID_SHAPE=sha256-64 ID_MATCH=false ' "$output" >/dev/null || die "ID mismatch classification is incomplete" ;;
    image-descriptor) grep -F ' DESC=present DESC_MATCH=true ' "$output" >/dev/null || die "descriptor classification is incomplete" ;;
    image-revision) grep -F ' REV_SHAPE=hex-7-64 REV_MATCH=false ' "$output" >/dev/null || die "revision mismatch classification is incomplete" ;;
    image-architecture) grep -F ' ARCH_SHAPE=other ARCH_MATCH=false' "$output" >/dev/null || die "architecture mismatch classification is incomplete" ;;
    image-rootfs) grep -F ' ROOTFS_SHAPE=digest-list ROOTFS_MATCH=true' "$output" >/dev/null || die "rootfs classification is incomplete" ;;
  esac
  at_sign=$(printf '\100')
  if grep -Eq "/|${at_sign}|token|secret|identifier|192[.]0[.]2" "$output"; then die "$failure_stage output retained disallowed detail"; fi
done

docker_calls=$fixture_root/docker-success-calls
docker_output=$fixture_root/docker-success-output
docker_ls_count=$fixture_root/docker-success-ls-count; printf '0\n' >"$docker_ls_count"
DOCKER_FAKE_CASE=success DOCKER_CALLS="$docker_calls" DOCKER_LS_COUNT="$docker_ls_count" FAKE_DOCKER="$fixture_root/fake-docker" \
  "$fixture_root/restore-docker-boundary" >"$docker_output" 2>&1 || die "immutable Docker boundary success fixture failed"
[ "$(wc -l <"$docker_calls" | tr -d ' ')" = 8 ] || die "immutable Docker boundary command count is incorrect"
[ "$(grep -Ec '^image\|inspect\|sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\|--format\|' "$docker_calls")" = 5 ] || die "Docker inspect did not exclusively target the selected immutable target"
if grep -F 'keepling-server:plan-02-09-amd64' "$docker_calls" >/dev/null; then die "Docker inspect consulted the mutable repository tag"; fi

for success_case in empty-inventory duplicates descriptor-absent; do
  docker_calls=$fixture_root/docker-$success_case-calls; docker_output=$fixture_root/docker-$success_case-output
  docker_ls_count=$fixture_root/docker-$success_case-ls-count; printf '0\n' >"$docker_ls_count"
  DOCKER_FAKE_CASE="$success_case" DOCKER_CALLS="$docker_calls" DOCKER_LS_COUNT="$docker_ls_count" FAKE_DOCKER="$fixture_root/fake-docker" \
    "$fixture_root/restore-docker-boundary" >"$docker_output" 2>&1 || die "Docker boundary $success_case fixture failed"
  grep -Fx 'REMOTE_PREPARE_STAGE=ready' "$docker_output" >/dev/null || die "Docker boundary $success_case did not become ready"
done

for boundary_case in inventory-before-nonzero inventory-after-nonzero empty-inventory duplicates descriptor-absent already-present no-new malformed-before malformed-after uppercase-before whitespace-after malicious-before oversized-after too-many-after multiple-new inspect-nonzero inspect-id-empty inspect-id-other inspect-id-mismatch descriptor-mismatch descriptor-malicious revision-mismatch architecture-mismatch rootfs-mismatch rootfs-malicious malicious-inspect; do
  case "$boundary_case" in
    inventory-before-nonzero) expected_stage=image-inventory-before; expected_code=56; expected_detail='BEFORE=command-failed' ;;
    malformed-before|uppercase-before|malicious-before) expected_stage=image-inventory-before; expected_code=56; expected_detail='BEFORE=invalid' ;;
    inventory-after-nonzero) expected_stage=image-inventory-after; expected_code=57; expected_detail='AFTER=command-failed' ;;
    malformed-after|whitespace-after) expected_stage=image-inventory-after; expected_code=57; expected_detail='AFTER=invalid' ;;
    oversized-after) expected_stage=image-inventory-after; expected_code=57; expected_detail='AFTER=oversized' ;;
    too-many-after) expected_stage=image-inventory-after; expected_code=57; expected_detail='AFTER=too-many' ;;
    already-present|no-new) expected_stage=image-delta; expected_code=58; expected_detail='DELTA=zero' ;;
    multiple-new) expected_stage=image-delta; expected_code=58; expected_detail='DELTA=multiple' ;;
    inspect-nonzero) expected_stage=image-inspect; expected_code=46; expected_detail='INSPECT=nonzero' ;;
    inspect-id-empty|inspect-id-other|inspect-id-mismatch|malicious-inspect) expected_stage=image-id-compare; expected_code=47; expected_detail='ID_MATCH=false' ;;
    descriptor-mismatch|descriptor-malicious) expected_stage=image-descriptor; expected_code=59; expected_detail='DESC_MATCH=false' ;;
    revision-mismatch) expected_stage=image-revision; expected_code=48; expected_detail='REV_MATCH=false' ;;
    architecture-mismatch) expected_stage=image-architecture; expected_code=49; expected_detail='ARCH_MATCH=false' ;;
    rootfs-mismatch|rootfs-malicious) expected_stage=image-rootfs; expected_code=60; expected_detail='ROOTFS_MATCH=false' ;;
    empty-inventory|duplicates|descriptor-absent) continue ;;
  esac
  teardown_count=$fixture_root/docker-$boundary_case-teardown-count; dns_called=$fixture_root/docker-$boundary_case-dns-called
  output=$fixture_root/docker-$boundary_case-output; docker_calls=$fixture_root/docker-$boundary_case-calls
  printf '0\n' >"$teardown_count"; result=0
  docker_ls_count=$fixture_root/docker-$boundary_case-ls-count; printf '0\n' >"$docker_ls_count"
  DOCKER_FAKE_CASE="$boundary_case" DOCKER_CALLS="$docker_calls" DOCKER_LS_COUNT="$docker_ls_count" FAKE_DOCKER="$fixture_root/fake-docker" \
  TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore-docker-boundary" KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" \
  KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$output" 2>&1 || result=$?
  [ "$result" -ne 0 ] || die "Docker boundary $boundary_case unexpectedly passed"
  [ "$(cat "$teardown_count")" = 1 ] || die "Docker boundary $boundary_case did not teardown exactly once"
  [ ! -e "$dns_called" ] || die "Docker boundary $boundary_case reached DNS"
  [ "$(grep -Ec "^REMOTE_PREPARE_FAILED_STAGE=$expected_stage RC=$expected_code " "$output")" = 1 ] || die "Docker boundary $boundary_case classification was incorrect"
  grep -F "$expected_detail" "$output" >/dev/null || die "Docker boundary $boundary_case detail was incorrect"
  if grep -Eq 'UNTRUSTED|keepling-server:plan-02-09-amd64' "$output"; then die "Docker boundary $boundary_case retained untrusted or mutable detail"; fi
done

for shape_case in empty other malicious; do
  case "$shape_case" in empty) observed_id='' ;; other) observed_id=not-a-digest ;; malicious) observed_id='UNTRUSTED VALUE WITH SPACES' ;; esac
  teardown_count=$fixture_root/$shape_case-teardown-count; dns_called=$fixture_root/$shape_case-dns-called; output=$fixture_root/$shape_case-output
  printf '0\n' >"$teardown_count"; result=0
  FAILURE_STAGE=image-id-compare TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" TEST_OBSERVED_ID="$observed_id" \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/pass" \
  KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" \
  KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$output" 2>&1 || result=$?
  [ "$result" -ne 0 ] && [ "$(cat "$teardown_count")" = 1 ] && [ ! -e "$dns_called" ] || die "$shape_case did not fail teardown-first"
  grep -E '^REMOTE_PREPARE_FAILED_STAGE=image-id-compare RC=47 .* ID_SHAPE=(empty|other) ID_MATCH=false ' "$output" >/dev/null || die "$shape_case ID shape was not closed"
  if [ -n "$observed_id" ] && grep -Fq "$observed_id" "$output"; then die "$shape_case raw ID output was retained"; fi
  [ "$(wc -c <"$output" | tr -d ' ')" -le 512 ] || die "$shape_case output is unbounded"
done

for value_case in empty other malicious; do
  case "$value_case" in empty) observed_revision='' ;; other) observed_revision=invalid ;; malicious) observed_revision='UNTRUSTED REVISION VALUE' ;; esac
  teardown_count=$fixture_root/revision-$value_case-teardown-count; dns_called=$fixture_root/revision-$value_case-dns-called; output=$fixture_root/revision-$value_case-output
  printf '0\n' >"$teardown_count"; result=0
  FAILURE_STAGE=image-revision TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" TEST_OBSERVED_REVISION="$observed_revision" \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" \
  KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$output" 2>&1 || result=$?
  [ "$result" -ne 0 ] && [ "$(cat "$teardown_count")" = 1 ] && [ ! -e "$dns_called" ] || die "revision $value_case did not fail teardown-first"
  grep -E '^REMOTE_PREPARE_FAILED_STAGE=image-revision RC=48 .* REV_SHAPE=(empty|other) REV_MATCH=false ' "$output" >/dev/null || die "revision $value_case shape was not closed"
  if [ -n "$observed_revision" ] && grep -Fq "$observed_revision" "$output"; then die "revision $value_case raw output was retained"; fi
done

for value_case in empty other malicious; do
  case "$value_case" in empty) observed_architecture='' ;; other) observed_architecture=arm64 ;; malicious) observed_architecture='UNTRUSTED ARCH VALUE' ;; esac
  teardown_count=$fixture_root/architecture-$value_case-teardown-count; dns_called=$fixture_root/architecture-$value_case-dns-called; output=$fixture_root/architecture-$value_case-output
  printf '0\n' >"$teardown_count"; result=0
  FAILURE_STAGE=image-architecture TEARDOWN_COUNT="$teardown_count" DNS_CALLED="$dns_called" TEST_OBSERVED_ARCHITECTURE="$observed_architecture" \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" \
  KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/pass" KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$output" 2>&1 || result=$?
  [ "$result" -ne 0 ] && [ "$(cat "$teardown_count")" = 1 ] && [ ! -e "$dns_called" ] || die "architecture $value_case did not fail teardown-first"
  grep -E '^REMOTE_PREPARE_FAILED_STAGE=image-architecture RC=49 .* ARCH_SHAPE=(empty|other) ARCH_MATCH=false ROOTFS_SHAPE=empty ROOTFS_MATCH=false$' "$output" >/dev/null || die "architecture $value_case shape was not closed"
  if [ -n "$observed_architecture" ] && grep -Fq "$observed_architecture" "$output"; then die "architecture $value_case raw output was retained"; fi
done

contract_output=$fixture_root/contract-output
result=0
./tooling/remote-prepare-host.sh >"$contract_output" 2>&1 || result=$?
[ "$result" -eq 40 ] || die "malformed contract did not return its bounded code"
[ "$(wc -l <"$contract_output" | tr -d ' ')" = 1 ] || die "malformed contract marker count is not exactly one"
grep -Fx 'REMOTE_PREPARE_FAILED_STAGE=contract RC=40' "$contract_output" >/dev/null || die "malformed contract marker is incorrect"

for invalid_contract in volume host digest; do
  case "$invalid_contract" in
    volume) args='0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee cccccccccccccccccccccccccccccccccccccccc amd64 sha256:1111111111111111111111111111111111111111111111111111111111111111 host.invalid sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' ;;
    host) args='101 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee cccccccccccccccccccccccccccccccccccccccc amd64 sha256:1111111111111111111111111111111111111111111111111111111111111111 invalid..host sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' ;;
    digest) args='101 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee cccccccccccccccccccccccccccccccccccccccc amd64 sha256:1111111111111111111111111111111111111111111111111111111111111111 host.invalid mutable-tag' ;;
  esac
  contract_output=$fixture_root/$invalid_contract-contract-output
  result=0
  # shellcheck disable=SC2086 # Deliberately expands the fixed, whitespace-separated fixture arguments.
  KEEPLING_REMOTE_PREPARE_TEST_MODE=yes ./tooling/remote-prepare-host.sh $args >"$contract_output" 2>&1 || result=$?
  [ "$result" -eq 40 ] || die "$invalid_contract contract did not fail closed"
  [ "$(wc -l <"$contract_output" | tr -d ' ')" = 1 ] || die "$invalid_contract contract marker count is not exactly one"
  grep -E '^REMOTE_PREPARE_FAILED_STAGE=contract RC=40 ' "$contract_output" >/dev/null || die "$invalid_contract contract marker is incorrect"
done

echo "Remote prepare observability regression passed: every failure is classified once, teardown-first, and DNS-unreachable"
