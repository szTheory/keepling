#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
runner=$root/tooling/run-phase-2-protected-acceptance.sh
[ -x "$runner" ] || { printf '%s\n' 'not ok - source-bound runner must be executable'; exit 1; }
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-source-bound-preparation.XXXXXX")
chmod 700 "$fixture"
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
mkdir -m 700 "$fixture/runner-temp"
ledger=$fixture/external-calls
: >"$ledger"
sha=$(printf '%064d' 0 | tr 0 a)
source_sha=$(printf '%040d' 0 | tr 0 a)
tree_sha=$(printf '%040d' 0 | tr 0 b)
now=$(date +%s)
hosted='{"version":1,"dns_zone_id":"fixture-zone","dns_record_name":"tasks.example.invalid","server_image_id":"12345","admin_source_cidrs":["192.0.2.10/32"],"candidate_source":"rebuilt-archive","recovery_source":"same-run-synthetic-capture","login_source":"same-run-synthetic-capture","b2_primary_endpoint":"https://s3.us-west-004.backblazeb2.com","b2_primary_region":"us-west-004","b2_primary_bucket":"fixture-bucket"}'
hosted_sha=$(printf '%s' "$hosted" | shasum -a 256 | awk '{print $1}')
python3 - "$fixture/authorization.json" "$source_sha" "$tree_sha" "$sha" "$now" "$hosted_sha" <<'PY'
import json, sys
path, source, tree, digest, now, hosted_sha=sys.argv[1:]
actions=["provider-apply","provider-inventory","console-marker","current-ed25519-host-key","ssh-bootstrap","image-transfer","credentialed-restore","sync-epoch","runtime-login-read-write-undo","rpo-rto","dns-sentinel-cutover-propagation","rollback-propagation","sentinel-deletion-absence","exact-owned-teardown-provider-absence"]
value={"version":1,"logical_run_id":"phase2-run-20260930-a1b2c3d4","owner_actor":"jon","issued_at":int(now),"change_trigger":"reviewed-phase2-acceptance-2026-09-30","upstream":{"run_id":123456,"run_attempt":1,"artifact_id":654321,"artifact_digest":"sha256:"+digest},"source":{"commit_sha":source,"tree_sha":tree,"context_tar_sha256":digest,"platform":"linux/amd64","archive_sha256":digest,"manifest_digest":"sha256:"+digest,"config_image_id":"sha256:"+digest,"deployed_image_id":"sha256:"+digest,"rootfs_diff_ids_sha256":digest,"synthetic_recovery":True},"selection":{"location":"nbg1","server_type":"cx33","server_image_id":12345,"data_volume_gb":160,"ssh_agent_fingerprint_sha256":digest,"dns_zone_id":"fixture-zone","dns_record_name":"tasks.example.invalid","admin_source_cidrs":["192.0.2.10/32"],"candidate_source":"rebuilt-archive","recovery_source":"same-run-synthetic-capture","login_source":"same-run-synthetic-capture"},"limits":{"max_cost_usd":50,"rpo_seconds":300,"rto_seconds":14400},"action_classes":actions,"hosted_inputs_sha256":hosted_sha}
with open(path,"w",encoding="utf-8") as output:
 json.dump(value,output,sort_keys=True,separators=(",",":")); output.write("\n")
PY
chmod 600 "$fixture/authorization.json"
authorization=$(cat "$fixture/authorization.json")
digest=$(printf '%s' "$authorization" | shasum -a 256 | awk '{print $1}')
run() {
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" GITHUB_EVENT_NAME=workflow_dispatch \
    GITHUB_REF=refs/heads/main GITHUB_SHA="$source_sha" GITHUB_ACTOR=jon GITHUB_REPOSITORY=keepling/keepling \
    GITHUB_RUN_ID=777 GITHUB_RUN_ATTEMPT=1 RUNNER_TEMP="$fixture/runner-temp" KEEPLING_HOSTED_INPUTS_JSON="$hosted" KEEPLING_HOSTED_INPUTS_SHA256="$hosted_sha" \
    KEEPLING_AUTHORIZATION_JSON="$authorization" KEEPLING_AUTHORIZATION_SHA256="$digest" \
    KEEPLING_TEST_EXTERNAL_CALL_LEDGER="$ledger" sh "$runner" --validate-inputs "$@"
}
run >"$fixture/out" 2>"$fixture/err" || { cat "$fixture/out" "$fixture/err" >&2; exit 1; }
grep -Fqx 'phase2-protected status=authorization result=valid' "$fixture/out" || exit 1

invalid=$(python3 - "$fixture/authorization.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1])); value["source"]["synthetic_recovery"]=False
print(json.dumps(value,sort_keys=True,separators=(",",":")))
PY
)
invalid_digest=$(printf '%s' "$invalid" | shasum -a 256 | awk '{print $1}')
if env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main GITHUB_SHA="$source_sha" GITHUB_ACTOR=jon GITHUB_REPOSITORY=keepling/keepling \
  GITHUB_RUN_ID=777 GITHUB_RUN_ATTEMPT=1 RUNNER_TEMP="$fixture/runner-temp" KEEPLING_HOSTED_INPUTS_JSON="$hosted" KEEPLING_HOSTED_INPUTS_SHA256="$hosted_sha" \
  KEEPLING_AUTHORIZATION_JSON="$invalid" KEEPLING_AUTHORIZATION_SHA256="$invalid_digest" \
  KEEPLING_TEST_EXTERNAL_CALL_LEDGER="$ledger" sh "$runner" --validate-inputs >"$fixture/out" 2>"$fixture/err"; then
  printf '%s\n' 'not ok - authorization without synthetic recovery identity must refuse'; exit 1
fi
grep -Eq '^phase2-protected status=NON_PASSING reason=[a-z0-9-]+$' "$fixture/err" || { cat "$fixture/err" >&2; exit 1; }
[ ! -s "$ledger" ] && [ -z "$(find "$fixture/runner-temp" -mindepth 1 -print -quit)" ] || { printf '%s\n' 'not ok - source refusal created state or called an adapter'; exit 1; }
printf '%s\n' 'source-bound preparation fixtures passed: exact identities accepted; mismatched recovery refused; no external calls'
