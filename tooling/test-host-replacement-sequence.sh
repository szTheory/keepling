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
if [ "$name" = bootstrap ] && [ "${KEEPLING_SEQUENCE_PAUSE:-}" = yes ]; then
  bundle=${KEEPLING_LIVE_ORCHESTRATION_FILE:?}
  workspace=$(awk -F= '$1=="WORKSPACE" {print $2}' "$bundle")
  run_id=$(awk -F= '$1=="RUN_ID" {print $2}' "$bundle")
  digest=$(awk -F= '$1=="IMAGE_DIGEST" {print $2}' "$bundle")
  bundle_sha=$(shasum -a 256 "$bundle" | awk '{print $1}')
  [ "${KEEPLING_SEQUENCE_MALFORMED_PAUSE:-}" != yes ] || digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  printf 'version=1\nRUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\nBUNDLE_SHA256=%s\nSERVER_ID=1\nSERVER_NAME=fixture-host\nIP=192.0.2.2\n' \
    "$run_id" "$workspace" "$digest" "$bundle_sha" >"$workspace/.host-trust.pending"
  printf '%s\n' '192.0.2.2' >"$workspace/candidate-ip.txt"
  chmod 600 "$workspace/.host-trust.pending" "$workspace/candidate-ip.txt"
  exit 75
fi
[ "${KEEPLING_SEQUENCE_FAIL_AT:-}" != "$name" ]
EOF
chmod 700 "$fixture_root/runner"
for name in bootstrap image restore runtime semantic dns teardown; do
  ln -s "$fixture_root/runner" "$fixture_root/$name"
done

prepare_pause_bundle() {
  root=$1
  mkdir -m 700 "$root/workspace"
  for stage in bootstrap image restore runtime semantic dns teardown; do ln -s "$fixture_root/runner" "$root/$stage"; done
  for ref in IMAGE_ARCHIVE_FILE IMAGE_CONTRACT_FILE CANDIDATE_SELECTION_FILE RECOVERY_SELECTION_FILE SERVER_IMAGE_SELECTION_FILE ADMIN_SOURCE_CIDRS_FILE LOGIN_CREDENTIAL_FILE BACKUP_CIPHER_FILE HETZNER_CREDENTIAL_FILE CLOUDFLARE_CREDENTIAL_FILE PRIMARY_BACKUP_CREDENTIAL_FILE MIRROR_BACKUP_CREDENTIAL_FILE TOFU_STATE_CREDENTIAL_FILE SSH_PUBLIC_KEY_FILE SSH_KNOWN_HOSTS_FILE RECOVERY_DUMP_FILE RECOVERY_PROVENANCE_FILE; do
    : >"$root/$ref"
    chmod 600 "$root/$ref"
  done
  cat >"$root/orchestration.env" <<EOF
RUN_ID=hosttrust-run01
WORKSPACE=$root/workspace
IMAGE_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
DNS_TEST_RECORD_NAME=phase2-hosttrust-run01.example.invalid
EOF
  for ref in IMAGE_ARCHIVE_FILE IMAGE_CONTRACT_FILE CANDIDATE_SELECTION_FILE RECOVERY_SELECTION_FILE SERVER_IMAGE_SELECTION_FILE ADMIN_SOURCE_CIDRS_FILE LOGIN_CREDENTIAL_FILE BACKUP_CIPHER_FILE HETZNER_CREDENTIAL_FILE CLOUDFLARE_CREDENTIAL_FILE PRIMARY_BACKUP_CREDENTIAL_FILE MIRROR_BACKUP_CREDENTIAL_FILE TOFU_STATE_CREDENTIAL_FILE SSH_PUBLIC_KEY_FILE SSH_KNOWN_HOSTS_FILE RECOVERY_DUMP_FILE RECOVERY_PROVENANCE_FILE; do
    printf '%s=%s/%s\n' "$ref" "$root" "$ref" >>"$root/orchestration.env"
  done
  for stage in bootstrap image restore runtime semantic dns teardown; do
    upper=$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')
    printf '%s_RUNNER=%s/tooling/phase-2-live-runners/%s\n' "$upper" "$repository_root" "$stage" >>"$root/orchestration.env"
  done
  chmod 600 "$root/orchestration.env"
}

run_pause_sequence() {
  root=$1
  malformed=$2
  ledger="$root/ledger"
  : >"$ledger"
  set +e
  KEEPLING_LIVE_ORCHESTRATION_FILE="$root/orchestration.env" \
    KEEPLING_SEQUENCE_LEDGER="$ledger" KEEPLING_SEQUENCE_PAUSE=yes \
    KEEPLING_SEQUENCE_MALFORMED_PAUSE="$malformed" \
    KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$root/bootstrap" \
    KEEPLING_SEQUENCE_IMAGE_RUNNER="$root/image" KEEPLING_SEQUENCE_RESTORE_RUNNER="$root/restore" \
    KEEPLING_SEQUENCE_RUNTIME_RUNNER="$root/runtime" KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$root/semantic" \
    KEEPLING_SEQUENCE_DNS_RUNNER="$root/dns" KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$root/teardown" \
    ./tooling/verify-host-replacement.sh --candidate-sequence >"$root/output" 2>&1
  result=$?
  set -e
  printf '%s' "$result"
}

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

run_sequence bootstrap "$fixture_root/bootstrap-failure"
cat >"$fixture_root/bootstrap-failure-expected" <<'EOF'
bootstrap
teardown
EOF
cmp -s "$fixture_root/bootstrap-failure-expected" "$fixture_root/bootstrap-failure" ||
  die "bootstrap failure did not attempt teardown exactly once"

run_sequence image "$fixture_root/image-failure"
cat >"$fixture_root/image-failure-expected" <<'EOF'
bootstrap
image
teardown
EOF
cmp -s "$fixture_root/image-failure-expected" "$fixture_root/image-failure" ||
  die "image failure did not block later gates and teardown once"

run_sequence restore "$fixture_root/restore-failure"
cat >"$fixture_root/restore-failure-expected" <<'EOF'
bootstrap
image
restore
teardown
EOF
cmp -s "$fixture_root/restore-failure-expected" "$fixture_root/restore-failure" ||
  die "restore failure reached runtime, semantic, or DNS"

run_sequence runtime "$fixture_root/runtime-failure"
cat >"$fixture_root/runtime-failure-expected" <<'EOF'
bootstrap
image
restore
runtime
teardown
EOF
cmp -s "$fixture_root/runtime-failure-expected" "$fixture_root/runtime-failure" ||
  die "runtime failure reached semantic or DNS"

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

run_sequence dns "$fixture_root/dns-failure"
cat >"$fixture_root/dns-failure-expected" <<'EOF'
bootstrap
image
restore
runtime
semantic
dns
teardown
EOF
cmp -s "$fixture_root/dns-failure-expected" "$fixture_root/dns-failure" ||
  die "DNS failure did not stop and attempt teardown exactly once"

run_sequence teardown "$fixture_root/teardown-failure"
cat >"$fixture_root/teardown-failure-expected" <<'EOF'
bootstrap
image
restore
runtime
semantic
dns
teardown
EOF
cmp -s "$fixture_root/teardown-failure-expected" "$fixture_root/teardown-failure" ||
  die "uncertain teardown result was retried"

pause_root="$fixture_root/valid-pause"; mkdir "$pause_root"; prepare_pause_bundle "$pause_root"
pause_status=$(run_pause_sequence "$pause_root" no)
[ "$pause_status" = 75 ] || { cat "$pause_root/output" >&2; die "valid host-trust checkpoint returned $pause_status instead of intentional pause"; }
grep -Fx 'bootstrap' "$pause_root/ledger" >/dev/null || die 'host-trust pause skipped bootstrap'
[ "$(wc -l <"$pause_root/ledger" | tr -d '[:space:]')" = 1 ] || die 'valid host-trust pause attempted later stages or teardown'
grep -F 'verify candidate SSH identity out of band' "$pause_root/output" >/dev/null || die 'valid host-trust pause did not explain its resume action'

bad_pause_root="$fixture_root/invalid-pause"; mkdir "$bad_pause_root"; prepare_pause_bundle "$bad_pause_root"
pause_status=$(run_pause_sequence "$bad_pause_root" yes)
[ "$pause_status" -ne 0 ] || die 'malformed host-trust checkpoint was accepted'
cat >"$bad_pause_root/invalid-pause-expected" <<'EOF'
bootstrap
teardown
EOF
cmp -s "$bad_pause_root/invalid-pause-expected" "$bad_pause_root/ledger" || die 'invalid host-trust checkpoint did not trigger exact teardown once'

echo "Host replacement sequence regression passed: ordered gates, DNS fence, teardown, and run-bound pause/resume fence"
