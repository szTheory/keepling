#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Exact-owned provider teardown failed: $*" >&2; exit 1; }
mode_of() {
  case "$(uname -s)" in
    Darwin) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}

[ "$#" -eq 3 ] || die "usage: $0 INVENTORY EXPECTED_RUN_ID EVIDENCE_FILE"
inventory=$1
expected_run_id=$2
evidence_file=$3
case "$expected_run_id" in [a-z0-9][a-z0-9-][a-z0-9-][a-z0-9-][a-z0-9-][a-z0-9-][a-z0-9-][a-z0-9-]* ) ;; *) die "expected run identity is invalid" ;; esac
[ "${#expected_run_id}" -le 40 ] || die "expected run identity is invalid"
[ "${KEEPLING_ALLOW_PROVIDER_DESTROY:-}" = yes ] || die "provider teardown requires KEEPLING_ALLOW_PROVIDER_DESTROY=yes"
[ "${KEEPLING_ALLOW_BILLABLE_APPLY:-}" = yes ] || die "provider teardown requires KEEPLING_ALLOW_BILLABLE_APPLY=yes"
case "${KEEPLING_LIVE_CHANGE_TRIGGER:-}" in [a-z0-9][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-]* ) ;; *) die "a bounded named KEEPLING_LIVE_CHANGE_TRIGGER is required" ;; esac
[ -r "$inventory" ] && [ ! -L "$inventory" ] || die "private provider inventory is unreadable"
[ ! -e "$evidence_file" ] || die "teardown evidence target must be new"
case "$inventory:$evidence_file" in
  "$repository_root":*|"$repository_root"/*:*|*:"$repository_root"|*:"$repository_root"/*) die "provider inventory and evidence must remain outside the repository" ;;
esac
evidence_directory=$(dirname "$evidence_file")
[ -d "$evidence_directory" ] || die "teardown evidence directory is missing"
progress_file="$evidence_directory/.teardown-progress.log"
if [ -e "$progress_file" ] || [ -L "$progress_file" ]; then
  [ -f "$progress_file" ] && [ ! -L "$progress_file" ] && [ "$(mode_of "$progress_file")" = 600 ] || die "private teardown progress record is unsafe"
else
  (umask 077; : >"$progress_file"; chmod 600 "$progress_file") || die "private teardown progress record could not be created"
fi
record_progress() { printf 'step=%s\n' "$1" >>"$progress_file" || die "private teardown progress could not be updated"; }
record_progress attempt-start

validate_inventory() {
  jq -e --arg run_id "$expected_run_id" '
    keys == ["labels","resources","version"] and .version == 1 and
    .labels == {"keepling-run":$run_id,"managed-by":"opentofu","purpose":"host-replacement"} and
    (.resources | keys == ["firewall_id","network_id","primary_ip_id","server_id","ssh_key_id","volume_id"]) and
    ([.resources[]] | all(type == "string" and test("^[1-9][0-9]*$")))
  ' "$1" >/dev/null 2>&1
}
validate_inventory "$inventory" || die "private provider inventory does not prove exact run ownership"

ownership_probe=${KEEPLING_PROVIDER_OWNERSHIP_PROBE:-}
state_probe=${KEEPLING_PROVIDER_STATE_PROBE:-}
destroy_runner=${KEEPLING_PROVIDER_DESTROY_RUNNER:-}
absence_probe=${KEEPLING_PROVIDER_ABSENCE_PROBE:-}
for runner in "$ownership_probe" "$state_probe" "$destroy_runner" "$absence_probe"; do
  [ -x "$runner" ] || die "provider teardown runner is unavailable"
done

workspace=$(mktemp -d "${TMPDIR:-/tmp}/keepling-provider-teardown.XXXXXX")
trap 'rm -rf -- "$workspace"' EXIT HUP INT TERM
chmod 700 "$workspace"
observed=$workspace/observed.json
state_before=$workspace/state-before
state_after=$workspace/state-after
counts_after=$workspace/counts-after.json

record_progress ownership-reread-start
"$ownership_probe" "$inventory" "$expected_run_id" "$observed" || { record_progress ownership-reread-failed; die "provider ownership re-read failed"; }
record_progress ownership-reread-passed
validate_inventory "$observed" || die "provider ownership re-read is incomplete or mismatched"
[ "$(jq -S . "$inventory")" = "$(jq -S . "$observed")" ] || die "provider ownership re-read does not match retained exact identities"
record_progress state-preflight-start
"$state_probe" "$state_before" || { record_progress state-preflight-failed; die "provider state preflight failed"; }
record_progress state-preflight-passed
./tooling/verify-host-replacement.sh --validate-state-addresses "$state_before" >/dev/null || { record_progress state-graph-failed; die "provider state does not contain the exact owned graph"; }
record_progress state-graph-passed

destroy_started="$evidence_directory/.teardown-destroy-started"
[ ! -e "$destroy_started" ] || die "provider destruction was already started"

record_progress destroy-runner-start
KEEPLING_PROVIDER_DESTROY_FENCE_FILE="$evidence_directory/.teardown-destroy-started" \
  "$destroy_runner" "$inventory" "$expected_run_id" >/dev/null 2>&1 || { record_progress destroy-runner-failed; die "provider destroy runner failed"; }
record_progress destroy-runner-passed
"$state_probe" "$state_after" || { record_progress state-absence-failed; die "provider state absence probe failed"; }
record_progress state-absence-passed
[ ! -s "$state_after" ] || die "provider state retained resources after destroy"
record_progress provider-absence-start
"$absence_probe" "$expected_run_id" "$counts_after" || { record_progress provider-absence-failed; die "provider absence probe failed"; }
jq -e '
  keys == ["firewalls","networks","primary_ips","servers","ssh_keys","volumes"] and
  ([.servers,.volumes,.primary_ips,.networks,.firewalls,.ssh_keys] | all(. == 0))
' "$counts_after" >/dev/null 2>&1 || { record_progress provider-absence-failed; die "provider absence proof retained or ambiguously counted resources"; }
record_progress provider-absence-passed

evidence_tmp=$(mktemp "$evidence_directory/.provider-teardown.XXXXXX")
chmod 600 "$evidence_tmp"
jq -n '{version:1,result:"PASS",ownership_reread:true,state_destroyed:true,provider_absence:true}' >"$evidence_tmp"
mv "$evidence_tmp" "$evidence_file"
trap - EXIT HUP INT TERM
rm -rf -- "$workspace"
echo "Exact-owned provider teardown passed: retained identities were re-read, destroyed through exact state, and proven absent"
