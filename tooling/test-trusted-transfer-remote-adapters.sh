#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Trusted transfer remote adapter regression failed: $*" >&2; exit 1; }
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-trusted-transfer.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
case_filter=${2:-all}
[ "${1:-}" = --case ] || [ "$#" -eq 0 ] || die 'usage: --case happy-path'

make_fixture() {
  root=$1
  mkdir -p "$root/handoff" "$root/bundle" "$root/bin"
  chmod 700 "$root/handoff" "$root/bundle" "$root/bin"
  printf 'fixture recovery bytes\n' >"$root/handoff/recovery.dump"
  chmod 600 "$root/handoff/recovery.dump"
  dump_sha=$(shasum -a 256 "$root/handoff/recovery.dump" | awk '{print $1}')
  dump_bytes=$(wc -c <"$root/handoff/recovery.dump" | tr -d ' ')
  jq -n --arg sha "$dump_sha" --argjson bytes "$dump_bytes" '{version:1,source_kind:"b2-primary",ciphertext_sha256:("a"*64),plaintext_sha256:$sha,ciphertext_bytes:1,plaintext_bytes:$bytes,verification:{head:true,get:true,package_manifest:true,decrypt:true,plaintext:true}}' >"$root/handoff/recovery.provenance.json"
  chmod 600 "$root/handoff/recovery.provenance.json"
  printf 'image' >"$root/image"; printf 'credential' >"$root/credential"; printf 'compose' >"$root/compose"; printf 'caddy' >"$root/caddy"; printf 'override' >"$root/override"
  printf '#!/usr/bin/env sh\nexit 0\n' >"$root/runner"; chmod 700 "$root/runner"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureIdentity file-comment\n' >"$root/public"; printf 'fixture-known-host' >"$root/known-hosts"; chmod 600 "$root/public" "$root/known-hosts"
  cat >"$root/bin/ssh-add" <<'EOF'
#!/usr/bin/env sh
awk 'NF >= 2 { print $1 " " $2 " agent-comment" }' "$FIXTURE_PUBLIC"
EOF
  cat >"$root/bin/ssh" <<'EOF'
#!/usr/bin/env sh
set -eu
case "$*" in
  *'test ! -e /root/'*) : ;;
  *'env KEEPLING_REMOTE_PREPARE_PROVENANCE_REQUIRED=yes /root/remote-prepare.sh'*) echo remote-prepare >>"$FIXTURE_LEDGER"; echo REMOTE_PREPARE_STAGE=ready ;;
  *'/usr/local/libexec/keepling-runtime-probe --bootstrap'*)
    if [ "${FIXTURE_BOOTSTRAP_PROBE_FAIL:-}" = yes ]; then echo REMOTE_RUNTIME_FAILED_STAGE=bootstrap; exit 1; fi
    if [ -n "${FIXTURE_BOOTSTRAP_AUTH_FAIL:-}" ]; then echo 'Permission denied (publickey).' >&2; exit 255; fi
    if [ -e "$FIXTURE_BOOTSTRAP_FAIL_ONCE" ]; then rm -f "$FIXTURE_BOOTSTRAP_FAIL_ONCE"; echo bootstrap-retry >>"$FIXTURE_LEDGER"; exit 1; fi
    echo bootstrap >>"$FIXTURE_LEDGER"; echo REMOTE_BOOTSTRAP_STAGE=ready ;;
  *'/usr/local/libexec/keepling-runtime-probe'*) echo runtime >>"$FIXTURE_LEDGER"; echo REMOTE_RUNTIME_STAGE=ready ;;
  *'/usr/local/libexec/keepling-semantic-proof'*) echo semantic >>"$FIXTURE_LEDGER"; echo REMOTE_SEMANTIC_STAGE=ready ;;
  *'rm -f -- /root/Caddyfile'*) echo cleanup >>"$FIXTURE_LEDGER" ;;
  *) exit 1 ;;
esac
EOF
  cat >"$root/bin/scp" <<'EOF'
#!/usr/bin/env sh
set -eu
case "$*" in *'recovery.dump'*|*'recovery.provenance.json'*|*'image.tar.gz'*|*'remote-prepare.sh'*) exit 0;; *) exit 0;; esac
EOF
  chmod 700 "$root/bin/ssh-add" "$root/bin/ssh" "$root/bin/scp"
  printf '#!/usr/bin/env sh\nexit 0\n' >"$root/bin/sleep"; chmod 700 "$root/bin/sleep"
  agent_socket=$(mktemp -u "${TMPDIR:-/tmp}/ktt-agent.XXXXXX")
  python3 - "$agent_socket" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(30)
PY
  agent_pid=$!
  for _ in 1 2 3 4 5; do [ -S "$agent_socket" ] && break; sleep 0.05; done
  ln -s "$agent_socket" "$root/agent.sock"
}

run_happy() {
  root="$fixture_root/happy"; make_fixture "$root"; : >"$root/ledger"
  FIXTURE_PUBLIC="$root/public" FIXTURE_LEDGER="$root/ledger" SSH_AUTH_SOCK="$root/agent.sock" \
  KEEPLING_TRANSFER_HANDOFF="$root/handoff" KEEPLING_BUNDLE_DESTINATION="$root/bundle" KEEPLING_BUNDLE_MANIFEST_FILE="$root/manifest" \
  KEEPLING_BUNDLE_IMAGE_SOURCE="$root/image" KEEPLING_BUNDLE_LOGIN_CREDENTIAL_SOURCE="$root/credential" KEEPLING_BUNDLE_COMPOSE_SOURCE="$root/compose" KEEPLING_BUNDLE_CADDY_SOURCE="$root/caddy" KEEPLING_BUNDLE_OVERRIDE_SOURCE="$root/override" KEEPLING_BUNDLE_RUNNER_SOURCE="$root/runner" \
  KEEPLING_TRANSFER_PUBLIC_IDENTITY="$root/public" KEEPLING_TRANSFER_KNOWN_HOSTS="$root/known-hosts" KEEPLING_TRANSFER_SSH_ADD="$root/bin/ssh-add" KEEPLING_TRANSFER_SSH="$root/bin/ssh" KEEPLING_TRANSFER_SCP="$root/bin/scp" KEEPLING_TRANSFER_DESTINATION='root@candidate.invalid' KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID='fixture-run' KEEPLING_TRANSFER_LEDGER="$root/ledger" \
  KEEPLING_REMOTE_VOLUME_ID=101 KEEPLING_REMOTE_ARCHIVE_SHA256="$(shasum -a 256 "$root/image" | awk '{print $1}')" \
  KEEPLING_REMOTE_CONFIG_IMAGE_ID="sha256:$(printf c%.0s $(seq 1 64))" KEEPLING_REMOTE_MANIFEST_DIGEST="sha256:$(printf d%.0s $(seq 1 64))" \
  KEEPLING_REMOTE_REVISION=abcdef0123456789 KEEPLING_REMOTE_ARCHITECTURE=amd64 KEEPLING_REMOTE_ROOTFS_DIFF_IDS="sha256:$(printf e%.0s $(seq 1 64))" \
  KEEPLING_REMOTE_RUNTIME_HOST=candidate.invalid KEEPLING_REMOTE_TESTED_MANIFEST_DIGEST="sha256:$(printf d%.0s $(seq 1 64))" \
    ./tooling/transfer-trusted-candidate.sh >"$root/output" 2>&1 || die 'happy path failed'
  kill "$agent_pid" 2>/dev/null || true; rm -f -- "$agent_socket"
  printf '%s\n' provenance bundle ssh-stage remote-prepare cleanup runtime semantic >"$root/expected"
  cmp -s "$root/expected" "$root/ledger" || { diff -u "$root/expected" "$root/ledger" >&2 || true; die 'happy path event ordering changed'; }
  jq -e '.complete == true and (.files|length) == 8 and ([.files[].mode] | all(. == "600" or . == "700"))' "$root/manifest" >/dev/null || die 'bundle inventory is incomplete'
  ./tooling/verify-privacy.sh "$root/output" >/dev/null || die 'happy output was not private'
}

run_bootstrap_transport() {
  root="$fixture_root/bootstrap"; make_fixture "$root"; : >"$root/ledger"
  : >"$root/fail-bootstrap-once"
  FIXTURE_PUBLIC="$root/public" FIXTURE_LEDGER="$root/ledger" FIXTURE_BOOTSTRAP_FAIL_ONCE="$root/fail-bootstrap-once" PATH="$root/bin:$PATH" SSH_AUTH_SOCK="$root/agent.sock" \
  KEEPLING_TRANSFER_PUBLIC_IDENTITY="$root/public" KEEPLING_TRANSFER_KNOWN_HOSTS="$root/known-hosts" \
  KEEPLING_TRANSFER_SSH_ADD="$root/bin/ssh-add" KEEPLING_TRANSFER_SSH="$root/bin/ssh" KEEPLING_TRANSFER_SCP="$root/bin/scp" \
  KEEPLING_TRANSFER_DESTINATION='root@candidate.invalid' KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID='fixture-run' \
  KEEPLING_TRANSFER_LEDGER="$root/ledger" ./tooling/transfer-trusted-candidate.sh bootstrap >"$root/output" 2>&1 || die 'bootstrap proof transport failed'
  kill "$agent_pid" 2>/dev/null || true; rm -f -- "$agent_socket"
  [ "$(cat "$root/output")" = TRUSTED_TRANSFER_STAGE=bootstrap-ready ] || die 'bootstrap transport accepted an open result'
  printf '%s\n' bootstrap-retry bootstrap >"$root/expected"
  cmp -s "$root/expected" "$root/ledger" || die 'bootstrap proof did not retry first-boot readiness'
}

run_bootstrap_auth_rejection() {
  root="$fixture_root/bootstrap-auth"; make_fixture "$root"; : >"$root/ledger"
  if FIXTURE_PUBLIC="$root/public" FIXTURE_LEDGER="$root/ledger" FIXTURE_BOOTSTRAP_AUTH_FAIL=yes SSH_AUTH_SOCK="$root/agent.sock" \
    KEEPLING_TRANSFER_PUBLIC_IDENTITY="$root/public" KEEPLING_TRANSFER_KNOWN_HOSTS="$root/known-hosts" \
    KEEPLING_TRANSFER_SSH_ADD="$root/bin/ssh-add" KEEPLING_TRANSFER_SSH="$root/bin/ssh" KEEPLING_TRANSFER_SCP="$root/bin/scp" \
    KEEPLING_TRANSFER_DESTINATION='root@candidate.invalid' KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID='fixture-run' \
    ./tooling/transfer-trusted-candidate.sh bootstrap >"$root/output" 2>&1; then die 'bootstrap accepted a rejected SSH identity'; fi
  [ "$(cat "$root/output")" = TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-authentication ] || die 'bootstrap failure classification was not closed'
  [ ! -s "$root/ledger" ] || die 'rejected SSH identity reached bootstrap proof'
  kill "$agent_pid" 2>/dev/null || true; rm -f -- "$agent_socket"
}

run_bootstrap_probe_rejection() {
  root="$fixture_root/bootstrap-probe"; make_fixture "$root"; : >"$root/ledger"
  if FIXTURE_PUBLIC="$root/public" FIXTURE_LEDGER="$root/ledger" FIXTURE_BOOTSTRAP_PROBE_FAIL=yes SSH_AUTH_SOCK="$root/agent.sock" \
    KEEPLING_TRANSFER_PUBLIC_IDENTITY="$root/public" KEEPLING_TRANSFER_KNOWN_HOSTS="$root/known-hosts" \
    KEEPLING_TRANSFER_SSH_ADD="$root/bin/ssh-add" KEEPLING_TRANSFER_SSH="$root/bin/ssh" KEEPLING_TRANSFER_SCP="$root/bin/scp" \
    KEEPLING_TRANSFER_DESTINATION='root@candidate.invalid' KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID='fixture-run' \
    ./tooling/transfer-trusted-candidate.sh bootstrap >"$root/output" 2>&1; then die 'bootstrap accepted incomplete cloud-init'; fi
  [ "$(cat "$root/output")" = TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-incomplete ] || die 'bootstrap failure classification was not closed'
  [ ! -s "$root/ledger" ] || die 'failed bootstrap probe reached candidate proof'
  kill "$agent_pid" 2>/dev/null || true; rm -f -- "$agent_socket"
}

run_rejections() {
  root="$fixture_root/reject"; make_fixture "$root"; : >"$root/ledger"
  chmod 755 "$root/handoff"
  if SSH_AUTH_SOCK="$root/agent.sock" KEEPLING_TRANSFER_HANDOFF="$root/handoff" KEEPLING_TRANSFER_LEDGER="$root/ledger" ./tooling/transfer-trusted-candidate.sh >/dev/null 2>&1; then die 'unsafe handoff accepted'; fi
  [ ! -s "$root/ledger" ] || die 'local refusal reached a later boundary'
}

run_handoff_matrix() {
  for case_name in missing-dump extra-member symlink-dump malformed-provenance hash-mismatch; do
    root="$fixture_root/$case_name"; make_fixture "$root"; : >"$root/ledger"
    case "$case_name" in
      missing-dump) rm -f -- "$root/handoff/recovery.dump" ;;
      extra-member) : >"$root/handoff/extra"; chmod 600 "$root/handoff/extra" ;;
      symlink-dump) rm -f -- "$root/handoff/recovery.dump"; ln -s /dev/null "$root/handoff/recovery.dump" ;;
      malformed-provenance) printf '{}' >"$root/handoff/recovery.provenance.json"; chmod 600 "$root/handoff/recovery.provenance.json" ;;
      hash-mismatch) jq '.plaintext_sha256 = ("b" * 64)' "$root/handoff/recovery.provenance.json" >"$root/replacement"; chmod 600 "$root/replacement"; mv "$root/replacement" "$root/handoff/recovery.provenance.json" ;;
    esac
    if SSH_AUTH_SOCK="$root/agent.sock" KEEPLING_TRANSFER_HANDOFF="$root/handoff" KEEPLING_TRANSFER_LEDGER="$root/ledger" ./tooling/transfer-trusted-candidate.sh >/dev/null 2>&1; then die "$case_name was accepted"; fi
    [ ! -s "$root/ledger" ] || die "$case_name reached a transfer boundary"
    kill "$agent_pid" 2>/dev/null || true; rm -f -- "$agent_socket"
  done
}

run_remote_proofs() {
  mkdir -p "$fixture_root/bin"; chmod 700 "$fixture_root/bin"
  jq -n '{version:1,status:"complete",runtime_probe_sha256:("a"*64),semantic_probe_sha256:("b"*64)}' >"$fixture_root/bootstrap-sentinel.json"
  jq -e '(keys|sort)==["runtime_probe_sha256","semantic_probe_sha256","status","version"] and .version==1 and .status=="complete"' \
    "$fixture_root/bootstrap-sentinel.json" >/dev/null || die 'bootstrap sentinel validation rejected the exact installed contract'
  jq '.version = 2' "$fixture_root/bootstrap-sentinel.json" >"$fixture_root/bootstrap-sentinel-invalid.json"
  if jq -e '(keys|sort)==["runtime_probe_sha256","semantic_probe_sha256","status","version"] and .version==1 and .status=="complete"' \
    "$fixture_root/bootstrap-sentinel-invalid.json" >/dev/null; then die 'bootstrap sentinel validation accepted an invalid version'; fi
  printf 'READY=loopback\n' >"$fixture_root/runtime-runner"; printf '#!/usr/bin/env sh\ncat "$1"\n' >"$fixture_root/cat-runner"; chmod 700 "$fixture_root/cat-runner"
  KEEPLING_REMOTE_RUNTIME_BOUNDARY_TEST=yes KEEPLING_REMOTE_RUNTIME_RUNNER="$fixture_root/cat-runner" "$repository_root/tooling/remote-runtime-probe.sh" "$fixture_root/runtime-runner" >/dev/null 2>&1 && die 'runtime runner accepted an argument protocol'
  cat >"$fixture_root/runtime-ok" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' READY=loopback
EOF
  chmod 700 "$fixture_root/runtime-ok"
  KEEPLING_REMOTE_RUNTIME_BOUNDARY_TEST=yes KEEPLING_REMOTE_RUNTIME_RUNNER="$fixture_root/runtime-ok" ./tooling/remote-runtime-probe.sh >/dev/null || die 'runtime proof failed'
  cat >"$fixture_root/runtime-bad" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' READY=loopback extra
EOF
  chmod 700 "$fixture_root/runtime-bad"
  if KEEPLING_REMOTE_RUNTIME_BOUNDARY_TEST=yes KEEPLING_REMOTE_RUNTIME_RUNNER="$fixture_root/runtime-bad" ./tooling/remote-runtime-probe.sh >"$fixture_root/runtime-bad.out" 2>&1; then die 'runtime proof accepted an open readiness result'; fi
  grep -Fx 'REMOTE_RUNTIME_FAILED_STAGE=readiness' "$fixture_root/runtime-bad.out" >/dev/null || die 'runtime failure class was not closed'
  cat >"$fixture_root/bin/curl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"$FIXTURE_LEDGER"
case "${FIXTURE_READINESS:-ready}" in
  ready) printf '%s\n' '{"code":"ready","status":"ready"}' ;;
  *) printf '%s\n' '{"code":"database_unavailable","status":"not_ready"}' ;;
esac
EOF
  chmod 700 "$fixture_root/bin/curl"; : >"$fixture_root/runtime-ledger"
  FIXTURE_LEDGER="$fixture_root/runtime-ledger" FIXTURE_READINESS=ready PATH="$fixture_root/bin:$PATH" \
    KEEPLING_REMOTE_RUNTIME_RUNNER="$fixture_root/runtime-bad" ./tooling/remote-runtime-probe.sh >"$fixture_root/runtime-prod.out" || die 'candidate-local readiness production boundary failed'
  [ "$(cat "$fixture_root/runtime-prod.out")" = REMOTE_RUNTIME_STAGE=ready ] || die 'production readiness output was not closed'
  grep -F 'http://127.0.0.1:4000/health/ready' "$fixture_root/runtime-ledger" >/dev/null || die 'runtime probe left candidate loopback'
  if FIXTURE_LEDGER="$fixture_root/runtime-ledger" FIXTURE_READINESS=not-ready PATH="$fixture_root/bin:$PATH" ./tooling/remote-runtime-probe.sh >"$fixture_root/runtime-prod-bad.out" 2>&1; then die 'production readiness accepted an unavailable database'; fi
  grep -Fx 'REMOTE_RUNTIME_FAILED_STAGE=readiness' "$fixture_root/runtime-prod-bad.out" >/dev/null || die 'production readiness failure class was not closed'
  printf 'credential' >"$fixture_root/remote-credential"; chmod 600 "$fixture_root/remote-credential"
  cat >"$fixture_root/semantic-ok" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' 'LOGIN=ok READ=ok WRITE=ok UNDO=ok'
EOF
  chmod 700 "$fixture_root/semantic-ok"
  KEEPLING_REMOTE_SEMANTIC_BOUNDARY_TEST=yes KEEPLING_REMOTE_RECOVERY_CREDENTIAL="$fixture_root/remote-credential" KEEPLING_REMOTE_SEMANTIC_RUNNER="$fixture_root/semantic-ok" ./tooling/remote-semantic-proof.sh >/dev/null || die 'semantic proof failed'
  cat >"$fixture_root/semantic-bad" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' 'LOGIN=ok READ=ok WRITE=ok UNDO=skipped'
EOF
  chmod 700 "$fixture_root/semantic-bad"
  if KEEPLING_REMOTE_SEMANTIC_BOUNDARY_TEST=yes KEEPLING_REMOTE_RECOVERY_CREDENTIAL="$fixture_root/remote-credential" KEEPLING_REMOTE_SEMANTIC_RUNNER="$fixture_root/semantic-bad" ./tooling/remote-semantic-proof.sh >"$fixture_root/semantic-bad.out" 2>&1; then die 'semantic proof accepted missing undo'; fi
  grep -Fx 'REMOTE_SEMANTIC_FAILED_STAGE=proof' "$fixture_root/semantic-bad.out" >/dev/null || die 'semantic failure class was not closed'
}

case "$case_filter" in happy-path) run_happy;; all) run_happy; run_bootstrap_transport; run_bootstrap_auth_rejection; run_bootstrap_probe_rejection; run_rejections; run_handoff_matrix; run_remote_proofs;; *) die 'unknown case';; esac
echo 'Trusted transfer remote adapter fixtures passed: hermetic private boundary and ordered proof'
