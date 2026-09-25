#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Exact-owned provider teardown failed: $*" >&2; exit 1; }

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

"$ownership_probe" "$inventory" "$expected_run_id" "$observed" >/dev/null 2>&1 || die "provider ownership re-read failed"
validate_inventory "$observed" || die "provider ownership re-read is incomplete or mismatched"
[ "$(jq -S . "$inventory")" = "$(jq -S . "$observed")" ] || die "provider ownership re-read does not match retained exact identities"
"$state_probe" "$state_before" >/dev/null 2>&1 || die "provider state preflight failed"
./tooling/verify-host-replacement.sh --validate-state-addresses "$state_before" >/dev/null || die "provider state does not contain the exact owned graph"

"$destroy_runner" "$inventory" "$expected_run_id" >/dev/null 2>&1 || die "provider destroy runner failed"
"$state_probe" "$state_after" >/dev/null 2>&1 || die "provider state absence probe failed"
[ ! -s "$state_after" ] || die "provider state retained resources after destroy"
"$absence_probe" "$expected_run_id" "$counts_after" >/dev/null 2>&1 || die "provider absence probe failed"
jq -e '
  keys == ["firewalls","networks","primary_ips","servers","ssh_keys","volumes"] and
  ([.servers,.volumes,.primary_ips,.networks,.firewalls,.ssh_keys] | all(. == 0))
' "$counts_after" >/dev/null 2>&1 || die "provider absence proof retained or ambiguously counted resources"

evidence_tmp=$(mktemp "$evidence_directory/.provider-teardown.XXXXXX")
chmod 600 "$evidence_tmp"
jq -n '{version:1,result:"PASS",ownership_reread:true,state_destroyed:true,provider_absence:true}' >"$evidence_tmp"
mv "$evidence_tmp" "$evidence_file"
trap - EXIT HUP INT TERM
rm -rf -- "$workspace"
echo "Exact-owned provider teardown passed: retained identities were re-read, destroyed through exact state, and proven absent"
