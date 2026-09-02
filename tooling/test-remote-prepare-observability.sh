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
  cccccccccccccccccccccccccccccccccccccccc amd64 host.invalid \
  sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
cat >"$fixture_root/fake-docker" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >>"$DOCKER_CALLS"
[ "$1" = image ] && [ "$2" = inspect ] && [ "$4" = --format ] || exit 91
case "$DOCKER_FAKE_CASE:$5" in
  inspect-nonzero:'{{.Id}}') exit 1 ;;
  id-empty:'{{.Id}}') exit 0 ;;
  id-other:'{{.Id}}') printf '%s\n' invalid ;;
  id-mismatch:'{{.Id}}') printf '%s\n' sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  malicious:'{{.Id}}') printf '%s\n' 'UNTRUSTED DOCKER OUTPUT' ;;
  *:'{{.Id}}') printf '%s\n' sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  revision-mismatch:'{{index .Config.Labels "org.opencontainers.image.revision"}}') printf '%s\n' eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  *:'{{index .Config.Labels "org.opencontainers.image.revision"}}') printf '%s\n' cccccccccccccccccccccccccccccccccccccccc ;;
  architecture-mismatch:'{{.Architecture}}') printf '%s\n' arm64 ;;
  *:'{{.Architecture}}') printf '%s\n' amd64 ;;
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
chmod 700 "$fixture_root/pass" "$fixture_root/restore" "$fixture_root/fake-docker" "$fixture_root/restore-docker-boundary" "$fixture_root/teardown" "$fixture_root/dns"

for pair in volume-device:41 volume-mount:42 filesystem:43 archive-integrity:44 image-load:45 image-inspect:46 image-id-compare:47 image-revision:48 image-architecture:49 runtime-config:50 db-start:51 db-ready:52 restore:53 epoch:54 runtime:55; do
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
  [ "$(grep -Ec '^REMOTE_PREPARE_FAILED_STAGE=[a-z-]+ RC=[0-9]+ LOAD=(not-run|ok|nonzero) INSPECT=(not-run|zero|nonzero) ID_SHAPE=(sha256-64|empty|other) ID_MATCH=(true|false) REV_SHAPE=(hex-7-64|empty|other) REV_MATCH=(true|false) ARCH_SHAPE=(amd64|empty|other) ARCH_MATCH=(true|false)$' "$output")" = 1 ] || die "$failure_stage marker count is not exactly one"
  grep -E "^REMOTE_PREPARE_FAILED_STAGE=$failure_stage RC=$expected_code " "$output" >/dev/null || die "$failure_stage marker is incorrect"
  case "$failure_stage" in
    image-load) grep -F ' LOAD=nonzero ' "$output" >/dev/null || die "load failure classification is incomplete" ;;
    image-inspect) grep -F ' INSPECT=nonzero ID_SHAPE=empty ID_MATCH=false ' "$output" >/dev/null || die "inspect failure classification is incomplete" ;;
    image-id-compare) grep -F ' INSPECT=zero ID_SHAPE=sha256-64 ID_MATCH=false ' "$output" >/dev/null || die "ID mismatch classification is incomplete" ;;
    image-revision) grep -F ' REV_SHAPE=hex-7-64 REV_MATCH=false ' "$output" >/dev/null || die "revision mismatch classification is incomplete" ;;
    image-architecture) grep -F ' ARCH_SHAPE=other ARCH_MATCH=false' "$output" >/dev/null || die "architecture mismatch classification is incomplete" ;;
  esac
  at_sign=$(printf '\100')
  if grep -Eq "/|${at_sign}|token|secret|identifier|192[.]0[.]2" "$output"; then die "$failure_stage output retained disallowed detail"; fi
done

docker_calls=$fixture_root/docker-success-calls
docker_output=$fixture_root/docker-success-output
DOCKER_FAKE_CASE=success DOCKER_CALLS="$docker_calls" FAKE_DOCKER="$fixture_root/fake-docker" \
  "$fixture_root/restore-docker-boundary" >"$docker_output" 2>&1 || die "immutable Docker boundary success fixture failed"
[ "$(wc -l <"$docker_calls" | tr -d ' ')" = 3 ] || die "immutable Docker boundary did not inspect exactly three fields"
[ "$(grep -Ec '^image\|inspect\|sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\|--format\|' "$docker_calls")" = 3 ] || die "Docker inspect did not exclusively target the immutable image ID"
if grep -F 'keepling-server:plan-02-09-amd64' "$docker_calls" >/dev/null; then die "Docker inspect consulted the mutable repository tag"; fi

for boundary_case in inspect-nonzero id-empty id-other id-mismatch revision-mismatch architecture-mismatch malicious; do
  case "$boundary_case" in
    inspect-nonzero) expected_stage=image-inspect; expected_code=46 ;;
    id-empty|id-other|id-mismatch|malicious) expected_stage=image-id-compare; expected_code=47 ;;
    revision-mismatch) expected_stage=image-revision; expected_code=48 ;;
    architecture-mismatch) expected_stage=image-architecture; expected_code=49 ;;
  esac
  teardown_count=$fixture_root/docker-$boundary_case-teardown-count; dns_called=$fixture_root/docker-$boundary_case-dns-called
  output=$fixture_root/docker-$boundary_case-output; docker_calls=$fixture_root/docker-$boundary_case-calls
  printf '0\n' >"$teardown_count"; result=0
  DOCKER_FAKE_CASE="$boundary_case" DOCKER_CALLS="$docker_calls" FAKE_DOCKER="$fixture_root/fake-docker" \
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
  grep -E '^REMOTE_PREPARE_FAILED_STAGE=image-architecture RC=49 .* ARCH_SHAPE=(empty|other) ARCH_MATCH=false$' "$output" >/dev/null || die "architecture $value_case shape was not closed"
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
    volume) args='0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb cccccccccccccccccccccccccccccccccccccccc amd64 host.invalid sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' ;;
    host) args='101 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb cccccccccccccccccccccccccccccccccccccccc amd64 invalid..host sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' ;;
    digest) args='101 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb cccccccccccccccccccccccccccccccccccccccc amd64 host.invalid mutable-tag' ;;
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
