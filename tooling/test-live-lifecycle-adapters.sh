#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Live lifecycle adapter regression failed: $*" >&2; exit 1; }

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-live-adapters.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
mkdir "$fixture_root/bin"
chmod 700 "$fixture_root" "$fixture_root/bin"

# DNS rehearsal: the fake Cloudflare boundary stores only synthetic state.
jq -n '{id:"fixture-record",type:"A",name:"host.example.invalid",content:"192.0.2.1",ttl:300,proxied:false}' >"$fixture_root/dns-state.json"
printf '%s\n' fixture-token >"$fixture_root/token"
chmod 600 "$fixture_root/token"
cat >"$fixture_root/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
method=GET body= url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request) method=$2; shift 2 ;;
    --data) body=$2; shift 2 ;;
    --header|--data-urlencode) shift 2 ;;
    --silent|--show-error|--fail|--get) shift ;;
    *) url=$1; shift ;;
  esac
done
case "$url" in
  */zones/fixture-zone) jq -n '{success:true,result:{name:"example.invalid"}}' ;;
  */dns_records/fixture-record)
    if [ "$method" = PUT ]; then
      content=$(printf '%s' "$body" | jq -r '.content')
      jq --arg content "$content" '.content=$content' "$KEEPLING_FAKE_DNS_STATE" >"$KEEPLING_FAKE_DNS_STATE.tmp"
      mv "$KEEPLING_FAKE_DNS_STATE.tmp" "$KEEPLING_FAKE_DNS_STATE"
      printf '%s\n' "$content" >>"$KEEPLING_FAKE_DNS_MUTATIONS"
    fi
    jq -n --slurpfile record "$KEEPLING_FAKE_DNS_STATE" '{success:true,result:$record[0]}'
    ;;
  */dns_records) jq -n --slurpfile record "$KEEPLING_FAKE_DNS_STATE" '{success:true,result:$record}' ;;
  *) exit 90 ;;
esac
EOF
cat >"$fixture_root/bin/propagation" <<'EOF'
#!/usr/bin/env sh
set -eu
[ "$#" -eq 3 ]
expected=$3
actual=$(jq -r '.content' "$KEEPLING_FAKE_DNS_STATE")
[ "$actual" = "$expected" ]
printf '%s\n' "$expected" >>"$KEEPLING_FAKE_DNS_PROBES"
if [ "${KEEPLING_FAKE_PROPAGATION_FAIL_TARGET:-}" = "$expected" ]; then exit 91; fi
EOF
cat >"$fixture_root/bin/dig" <<'EOF'
#!/usr/bin/env sh
set -eu
case " $* " in
  *' NS '*) printf '%s\n' ns1.example.invalid. ns2.example.invalid. ;;
  *' A '*) printf '%s\n' 192.0.2.1 ;;
  *) exit 92 ;;
esac
EOF
chmod 700 "$fixture_root/bin/curl" "$fixture_root/bin/propagation" "$fixture_root/bin/dig"

env PATH="$fixture_root/bin:$PATH" DIG_BIN="$fixture_root/bin/dig" \
  KEEPLING_DNS_PROPAGATION_ATTEMPTS=1 KEEPLING_DNS_PROPAGATION_DELAY_SECONDS=0 \
  ./infra/dns/probe-propagation.sh example.invalid host.example.invalid 192.0.2.1 >/dev/null

: >"$fixture_root/mutations"
: >"$fixture_root/probes"
env PATH="$fixture_root/bin:$PATH" \
  KEEPLING_FAKE_DNS_STATE="$fixture_root/dns-state.json" \
  KEEPLING_FAKE_DNS_MUTATIONS="$fixture_root/mutations" \
  KEEPLING_FAKE_DNS_PROBES="$fixture_root/probes" \
  KEEPLING_DNS_ZONE_ID=fixture-zone KEEPLING_DNS_RECORD_NAME=host.example.invalid \
  CLOUDFLARE_API_TOKEN_FILE="$fixture_root/token" KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  KEEPLING_DNS_PROPAGATION_RUNNER="$fixture_root/bin/propagation" \
  ./infra/dns/cloudflare.sh rehearse 192.0.2.44 "$fixture_root/dns-evidence.json" >/dev/null
[ "$(jq -r '.content' "$fixture_root/dns-state.json")" = 192.0.2.1 ] || die "DNS success did not restore the original content"
[ "$(sed -n '1p' "$fixture_root/mutations")" = 192.0.2.44 ] && [ "$(sed -n '2p' "$fixture_root/mutations")" = 192.0.2.1 ] || die "DNS success did not cut over then roll back exactly"
[ "$(wc -l <"$fixture_root/probes" | tr -d ' ')" -eq 2 ] || die "DNS success did not prove both propagation states"
jq -e '.result=="PASS" and .cutover_propagated and .rollback_propagated' "$fixture_root/dns-evidence.json" >/dev/null || die "DNS evidence is incomplete"

: >"$fixture_root/mutations"
: >"$fixture_root/probes"
if env PATH="$fixture_root/bin:$PATH" \
  KEEPLING_FAKE_DNS_STATE="$fixture_root/dns-state.json" \
  KEEPLING_FAKE_DNS_MUTATIONS="$fixture_root/mutations" \
  KEEPLING_FAKE_DNS_PROBES="$fixture_root/probes" KEEPLING_FAKE_PROPAGATION_FAIL_TARGET=192.0.2.45 \
  KEEPLING_DNS_ZONE_ID=fixture-zone KEEPLING_DNS_RECORD_NAME=host.example.invalid \
  CLOUDFLARE_API_TOKEN_FILE="$fixture_root/token" KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  KEEPLING_DNS_PROPAGATION_RUNNER="$fixture_root/bin/propagation" \
  ./infra/dns/cloudflare.sh rehearse 192.0.2.45 "$fixture_root/failed-dns-evidence.json" >/dev/null 2>&1; then
  die "DNS propagation failure was accepted"
fi
[ "$(jq -r '.content' "$fixture_root/dns-state.json")" = 192.0.2.1 ] || die "DNS failure path did not restore the original content"
[ "$(tail -n 1 "$fixture_root/mutations")" = 192.0.2.1 ] || die "DNS failure path did not attempt exact rollback"
[ ! -e "$fixture_root/failed-dns-evidence.json" ] || die "failed DNS rehearsal wrote passing evidence"

: >"$fixture_root/mutations"
if env PATH="$fixture_root/bin:$PATH" \
  KEEPLING_FAKE_DNS_STATE="$fixture_root/dns-state.json" KEEPLING_FAKE_DNS_MUTATIONS="$fixture_root/mutations" KEEPLING_FAKE_DNS_PROBES="$fixture_root/probes" \
  KEEPLING_DNS_ZONE_ID=fixture-zone KEEPLING_DNS_RECORD_NAME=host.example.invalid CLOUDFLARE_API_TOKEN_FILE="$fixture_root/token" \
  KEEPLING_DNS_PROPAGATION_RUNNER="$fixture_root/bin/propagation" \
  ./infra/dns/cloudflare.sh rehearse 192.0.2.44 "$fixture_root/unarmed-dns-evidence.json" >/dev/null 2>&1; then
  die "unarmed DNS rehearsal was accepted"
fi
[ ! -s "$fixture_root/mutations" ] || die "unarmed DNS rehearsal reached mutation"
if env PATH="$fixture_root/bin:$PATH" \
  KEEPLING_FAKE_DNS_STATE="$fixture_root/dns-state.json" KEEPLING_FAKE_DNS_MUTATIONS="$fixture_root/mutations" KEEPLING_FAKE_DNS_PROBES="$fixture_root/probes" \
  KEEPLING_DNS_ZONE_ID=fixture-zone KEEPLING_DNS_RECORD_NAME=host.example.invalid CLOUDFLARE_API_TOKEN_FILE="$fixture_root/token" \
  KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes KEEPLING_DNS_PROPAGATION_RUNNER="$fixture_root/bin/propagation" \
  ./infra/dns/cloudflare.sh rehearse 192.0.2.1 "$fixture_root/equal-dns-evidence.json" >/dev/null 2>&1; then
  die "equal source and target DNS content was accepted"
fi
[ ! -s "$fixture_root/mutations" ] || die "equal source and target reached mutation"

# A paused synthetic host-trust checkpoint must stop on an independently
# supplied but incorrect ED25519 fingerprint before the SSH boundary.
host_fixture="$fixture_root/paused-host-trust"
mkdir -m 700 "$host_fixture"
host_fixture=$(CDPATH='' cd -P "$host_fixture" && pwd)
host_workspace="$host_fixture/workspace"
mkdir -m 700 "$host_workspace" "$host_fixture/bin"
host_run=hosttrust1
host_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
known_hosts="$host_fixture/known_hosts"
: >"$known_hosts"
chmod 600 "$known_hosts"
jq -n '{resources:{server_id:7101}}' >"$host_workspace/provider-inventory.json"
printf '%s\n' '192.0.2.55' >"$host_workspace/candidate-ip.txt"
chmod 600 "$host_workspace/provider-inventory.json" "$host_workspace/candidate-ip.txt"
cat >"$host_fixture/orchestration.env" <<EOF
RUN_ID=$host_run
WORKSPACE=$host_workspace
IMAGE_DIGEST=$host_digest
SSH_KNOWN_HOSTS_FILE=$known_hosts
EOF
chmod 600 "$host_fixture/orchestration.env"
host_bundle_sha=$(shasum -a 256 "$host_fixture/orchestration.env" | awk '{print $1}')
printf '%s\n' "$host_bundle_sha" >"$host_workspace/.bundle.sha256"
chmod 600 "$host_workspace/.bundle.sha256"
cat >"$host_workspace/.host-trust.pending" <<EOF
version=1
RUN_ID=$host_run
WORKSPACE=$host_workspace
IMAGE_DIGEST=$host_digest
BUNDLE_SHA256=$host_bundle_sha
SERVER_ID=7101
SERVER_NAME=fixture-host
IP=192.0.2.55
EOF
chmod 600 "$host_workspace/.host-trust.pending"
ssh-keygen -q -t ed25519 -N '' -f "$host_fixture/current-host-key"
ssh-keygen -q -t ed25519 -N '' -f "$host_fixture/wrong-console-key"
wrong_console_fingerprint=$(ssh-keygen -E sha256 -lf "$host_fixture/wrong-console-key.pub" | awk '{print $2}')
scan_log="$host_fixture/keyscan-called"
cat >"$host_fixture/bin/ssh-keyscan" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' called >>"$FIXTURE_SCAN_LOG"
printf '%s %s %s\n' "$5" ssh-ed25519 "$FIXTURE_SCAN_KEY"
EOF
for command_name in ssh scp ssh-add; do
  cat >"$host_fixture/bin/$command_name" <<'EOF'
#!/usr/bin/env sh
set -eu
: >"$FIXTURE_POST_TRUST_MARKER"
exit 99
EOF
done
chmod 700 "$host_fixture/bin/ssh-keyscan" "$host_fixture/bin/ssh" "$host_fixture/bin/scp" "$host_fixture/bin/ssh-add"
: >"$host_fixture/stage-ledger"
chmod 600 "$host_fixture/stage-ledger"
host_result=0
env KEEPLING_LIVE_STAGE_FIXTURE=yes KEEPLING_STAGE_FIXTURE_LEDGER="$host_fixture/stage-ledger" \
  KEEPLING_RESUME_HOST_TRUST=yes FIXTURE_SCAN_LOG="$scan_log" \
  FIXTURE_SCAN_KEY="$(awk '{print $2}' "$host_fixture/current-host-key.pub")" \
  FIXTURE_POST_TRUST_MARKER="$host_fixture/post-trust-command-called" PATH="$host_fixture/bin:$PATH" \
  ./tooling/phase-2-live-stage-actions.sh bootstrap "$host_run" "$host_workspace" "$host_digest" \
  "$host_fixture/orchestration.env" >"$host_fixture/result" 2>&1 || host_result=$?
[ "$host_result" -ne 0 ] || die "missing console run marker was accepted"
grep -Fx 'Phase 2 live stage failed: stage=bootstrap result=refused reason=console-run-marker-mismatch' "$host_fixture/result" >/dev/null || { sed -n '1,20p' "$host_fixture/result" >&2; die "missing console run marker did not return its closed reason"; }
[ ! -e "$scan_log" ] || die "missing run marker invoked ssh-keyscan"
[ ! -s "$known_hosts" ] || die "missing run marker changed known_hosts"
[ -e "$host_workspace/.host-trust.pending" ] || die "missing run marker discarded the paused checkpoint"

host_result=0
env KEEPLING_LIVE_STAGE_FIXTURE=yes KEEPLING_STAGE_FIXTURE_LEDGER="$host_fixture/stage-ledger" \
  KEEPLING_RESUME_HOST_TRUST=yes KEEPLING_CONSOLE_RUN_MARKER=wrong-run-marker FIXTURE_SCAN_LOG="$scan_log" \
  FIXTURE_SCAN_KEY="$(awk '{print $2}' "$host_fixture/current-host-key.pub")" \
  FIXTURE_POST_TRUST_MARKER="$host_fixture/post-trust-command-called" \
  PATH="$host_fixture/bin:$PATH" \
  ./tooling/phase-2-live-stage-actions.sh bootstrap "$host_run" "$host_workspace" "$host_digest" \
  "$host_fixture/orchestration.env" >"$host_fixture/result" 2>&1 || host_result=$?
[ "$host_result" -ne 0 ] || die "paused host-trust mismatch was accepted"
grep -Fx 'Phase 2 live stage failed: stage=bootstrap result=refused reason=console-run-marker-mismatch' "$host_fixture/result" >/dev/null || {
  sed -n '1,20p' "$host_fixture/result" >&2
  die "wrong console run marker did not return its closed reason"
}
[ ! -e "$scan_log" ] || die "wrong run marker invoked ssh-keyscan"
[ ! -s "$known_hosts" ] || die "host-trust mismatch changed known_hosts"
[ ! -e "$host_workspace/.host-trust.verified" ] || die "host-trust mismatch persisted verified identity"
[ -e "$host_workspace/.host-trust.pending" ] || die "host-trust mismatch discarded the paused checkpoint"
[ ! -e "$host_workspace/.stage-bootstrap.complete" ] || die "host-trust mismatch completed bootstrap"
[ ! -s "$host_fixture/stage-ledger" ] || die "host-trust mismatch advanced to a later stage"
[ ! -e "$host_fixture/post-trust-command-called" ] || die "host-trust mismatch reached SSH tooling"
if grep -F 'wrong-run-marker' "$host_fixture/result" >/dev/null; then die "run-marker refusal echoed supplied marker"; fi

# Matching run marker still does not establish host trust: a wrong ED25519
# fingerprint must fail through the existing independent exact-IP scan path.
host_result=0
env KEEPLING_LIVE_STAGE_FIXTURE=yes KEEPLING_STAGE_FIXTURE_LEDGER="$host_fixture/stage-ledger" \
  KEEPLING_RESUME_HOST_TRUST=yes KEEPLING_CONSOLE_RUN_MARKER="$host_run" \
  KEEPLING_HOST_KEY_FINGERPRINT="$wrong_console_fingerprint" FIXTURE_SCAN_LOG="$scan_log" \
  FIXTURE_SCAN_KEY="$(awk '{print $2}' "$host_fixture/current-host-key.pub")" \
  FIXTURE_POST_TRUST_MARKER="$host_fixture/post-trust-command-called" PATH="$host_fixture/bin:$PATH" \
  ./tooling/phase-2-live-stage-actions.sh bootstrap "$host_run" "$host_workspace" "$host_digest" \
  "$host_fixture/orchestration.env" >"$host_fixture/result" 2>&1 || host_result=$?
[ "$host_result" -ne 0 ] || die "paused host-trust fingerprint mismatch was accepted"
grep -Fx 'Phase 2 live stage failed: stage=bootstrap result=refused reason=host-trust-fingerprint-mismatch' "$host_fixture/result" >/dev/null || die "fingerprint mismatch did not return its closed reason"
[ "$(wc -l <"$scan_log" | tr -d ' ')" -eq 1 ] || die "matching run marker did not reach exactly one independent scan"
[ ! -s "$known_hosts" ] || die "host-trust fingerprint mismatch changed known_hosts"
[ -e "$host_workspace/.host-trust.pending" ] || die "fingerprint mismatch discarded the paused checkpoint"
[ ! -e "$host_fixture/post-trust-command-called" ] || die "fingerprint mismatch reached SSH tooling"
if grep -F "$wrong_console_fingerprint" "$host_fixture/result" >/dev/null; then die "host-trust mismatch disclosed the supplied fingerprint"; fi

# Exact-owned teardown: probes are synthetic and the destroy runner is a marker.
run_id=ownership-proof
jq -n --arg run_id "$run_id" '{version:1,resources:{server_id:"101",primary_ip_id:"102",network_id:"103",volume_id:"104",firewall_id:"105",ssh_key_id:"106"},labels:{"managed-by":"opentofu","keepling-run":$run_id,purpose:"host-replacement"}}' >"$fixture_root/inventory.json"
cat >"$fixture_root/bin/ownership-probe" <<'EOF'
#!/usr/bin/env sh
set -eu
cp "$1" "$3"
if [ "${KEEPLING_FAKE_UNOWNED:-}" = yes ]; then
  jq '.labels["keepling-run"]="another-run"' "$3" >"$3.tmp" && mv "$3.tmp" "$3"
fi
EOF
cat >"$fixture_root/bin/state-probe" <<'EOF'
#!/usr/bin/env sh
set -eu
if [ -e "$KEEPLING_FAKE_DESTROY_MARKER" ]; then : >"$1"; else
  printf '%s\n' hcloud_firewall.replacement hcloud_firewall_attachment.replacement hcloud_network.replacement hcloud_network_subnet.replacement hcloud_primary_ip.replacement hcloud_server.replacement hcloud_ssh_key.replacement hcloud_volume.replacement hcloud_volume_attachment.replacement >"$1"
fi
EOF
cat >"$fixture_root/bin/destroy" <<'EOF'
#!/usr/bin/env sh
set -eu
[ -n "${KEEPLING_PROVIDER_DESTROY_FENCE_FILE:-}" ]
[ ! -e "$KEEPLING_PROVIDER_DESTROY_FENCE_FILE" ]
(umask 077 && mkdir -m 700 "$KEEPLING_PROVIDER_DESTROY_FENCE_FILE")
printf '%s\n' called >>"$KEEPLING_FAKE_DESTROY_COUNT"
: >"$KEEPLING_FAKE_DESTROY_MARKER"
EOF
cat >"$fixture_root/bin/absence" <<'EOF'
#!/usr/bin/env sh
set -eu
[ -e "$KEEPLING_FAKE_DESTROY_MARKER" ]
jq -n '{servers:0,volumes:0,primary_ips:0,networks:0,firewalls:0,ssh_keys:0}' >"$2"
EOF
chmod 700 "$fixture_root/bin/ownership-probe" "$fixture_root/bin/state-probe" "$fixture_root/bin/destroy" "$fixture_root/bin/absence"
: >"$fixture_root/destroy-count"
teardown_env() {
  env KEEPLING_ALLOW_PROVIDER_DESTROY=yes KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_LIVE_CHANGE_TRIGGER=approved-fixture \
    KEEPLING_PROVIDER_OWNERSHIP_PROBE="$fixture_root/bin/ownership-probe" \
    KEEPLING_PROVIDER_STATE_PROBE="$fixture_root/bin/state-probe" \
    KEEPLING_PROVIDER_DESTROY_RUNNER="$fixture_root/bin/destroy" \
    KEEPLING_PROVIDER_ABSENCE_PROBE="$fixture_root/bin/absence" \
    KEEPLING_FAKE_DESTROY_MARKER="$fixture_root/destroyed" \
    KEEPLING_FAKE_DESTROY_COUNT="$fixture_root/destroy-count" "$@"
}
teardown_env ./tooling/destroy-owned-provider.sh "$fixture_root/inventory.json" "$run_id" "$fixture_root/teardown-evidence.json" >/dev/null
[ -d "$fixture_root/.teardown-destroy-started" ] || die "provider destroy boundary was not fenced"
[ "$(stat -f '%Lp' "$fixture_root/.teardown-progress.log" 2>/dev/null || stat -c '%a' "$fixture_root/.teardown-progress.log")" = 600 ] || die "teardown progress record was not private"
grep -Fx 'step=provider-absence-passed' "$fixture_root/.teardown-progress.log" >/dev/null || die "teardown progress did not record the final proof"
grep -Eq "$run_id|192[.]0[.]2|token" "$fixture_root/.teardown-progress.log" && die "teardown progress retained private identity or credential context"
[ "$(wc -l <"$fixture_root/destroy-count" | tr -d ' ')" -eq 1 ] || die "exact-owned teardown did not destroy exactly once"
jq -e '.result=="PASS" and .ownership_reread and .state_destroyed and .provider_absence' "$fixture_root/teardown-evidence.json" >/dev/null || die "teardown evidence is incomplete"
grep -Eq '101|ownership-proof|192[.]0[.]2|token' "$fixture_root/teardown-evidence.json" && die "teardown evidence retained provider identity or sensitive context"

rm -f "$fixture_root/destroyed"
rm -rf "$fixture_root/.teardown-destroy-started"
: >"$fixture_root/destroy-count"
if KEEPLING_FAKE_UNOWNED=yes teardown_env ./tooling/destroy-owned-provider.sh "$fixture_root/inventory.json" "$run_id" "$fixture_root/unowned-evidence.json" >/dev/null 2>&1; then
  die "ownership mismatch was accepted for destroy"
fi
[ ! -s "$fixture_root/destroy-count" ] || die "ownership mismatch reached destroy"
[ ! -e "$fixture_root/.teardown-destroy-started" ] || die "ownership mismatch consumed the destructive-start fence"
[ ! -e "$fixture_root/unowned-evidence.json" ] || die "ownership mismatch wrote passing evidence"

if env KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_LIVE_CHANGE_TRIGGER=approved-fixture \
  KEEPLING_PROVIDER_OWNERSHIP_PROBE="$fixture_root/bin/ownership-probe" KEEPLING_PROVIDER_STATE_PROBE="$fixture_root/bin/state-probe" \
  KEEPLING_PROVIDER_DESTROY_RUNNER="$fixture_root/bin/destroy" KEEPLING_PROVIDER_ABSENCE_PROBE="$fixture_root/bin/absence" \
  KEEPLING_FAKE_DESTROY_MARKER="$fixture_root/destroyed" KEEPLING_FAKE_DESTROY_COUNT="$fixture_root/destroy-count" \
  ./tooling/destroy-owned-provider.sh "$fixture_root/inventory.json" "$run_id" "$fixture_root/unarmed-teardown-evidence.json" >/dev/null 2>&1; then
  die "unarmed provider teardown was accepted"
fi
[ ! -s "$fixture_root/destroy-count" ] || die "unarmed provider teardown reached destroy"

echo "Live lifecycle adapter regression passed: DNS rollback is guaranteed and provider destroy is exact-owned and absence-proven"
