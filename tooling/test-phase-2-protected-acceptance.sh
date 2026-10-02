#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
runner=$root/tooling/run-phase-2-protected-acceptance.sh
[ -x "$runner" ] || { printf '%s\n' 'not ok - protected runner must be executable'; exit 1; }
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-protected-acceptance-test.XXXXXX")
chmod 700 "$fixture"
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
mkdir -m 700 "$fixture/runner-temp" "$fixture/bin"
ledger=$fixture/external-calls
: >"$ledger"
chmod 600 "$ledger"
sha=$(printf '%064d' 0 | tr 0 a)
sha2=$(printf '%064d' 0 | tr 0 b)
source_sha=$(printf '%040d' 0 | tr 0 a)
tree_sha=$(printf '%040d' 0 | tr 0 b)
now=$(date +%s)
today_utc=$(date -u +%F)
hosted='{"version":1,"dns_zone_id":"fixture-zone","dns_record_name":"tasks.example.invalid","server_image_id":"12345","admin_source_cidrs":["192.0.2.10/32"],"candidate_source":"rebuilt-archive","recovery_source":"same-run-synthetic-capture","login_source":"same-run-synthetic-capture","b2_primary_endpoint":"https://s3.us-west-004.backblazeb2.com","b2_primary_region":"us-west-004","b2_primary_bucket":"fixture-bucket"}'
hosted_sha=$(printf '%s' "$hosted" | shasum -a 256 | awk '{print $1}')
python3 - "$fixture/authorization.json" "$source_sha" "$tree_sha" "$sha" "$sha2" "$now" "$hosted_sha" "$today_utc" <<'PY'
import json, sys
path, source, tree, a, b, now, hosted_sha, today_utc = sys.argv[1:]
actions = [
    "provider-apply", "provider-inventory", "console-marker", "current-ed25519-host-key",
    "ssh-bootstrap", "image-transfer", "credentialed-restore", "sync-epoch",
    "runtime-login-read-write-undo", "rpo-rto", "dns-sentinel-cutover-propagation",
    "rollback-propagation", "sentinel-deletion-absence", "exact-owned-teardown-provider-absence",
]
document = {
    "version": 1,
    "logical_run_id": "phase2-run-20260930-a1b2c3d4",
    "owner_actor": "jon",
    "issued_at": int(now),
    "change_trigger": f"reviewed-phase2-acceptance-{today_utc}",
    "upstream": {"run_id": 123456, "run_attempt": 1, "artifact_id": 654321, "artifact_digest": "sha256:" + a},
    "source": {
        "commit_sha": source, "tree_sha": tree, "context_tar_sha256": a, "platform": "linux/amd64",
        "archive_sha256": b, "manifest_digest": "sha256:" + a, "config_image_id": "sha256:" + b,
        "deployed_image_id": "sha256:" + b, "rootfs_diff_ids_sha256": a, "synthetic_recovery": True,
    },
    "selection": {"location": "nbg1", "server_type": "cx33", "server_image_id": 12345, "data_volume_gb": 160, "ssh_agent_fingerprint_sha256": a, "dns_zone_id":"fixture-zone", "dns_record_name":"tasks.example.invalid", "admin_source_cidrs":["192.0.2.10/32"], "candidate_source":"rebuilt-archive", "recovery_source":"same-run-synthetic-capture", "login_source":"same-run-synthetic-capture"},
    "limits": {"max_cost_usd": 50, "rpo_seconds": 300, "rto_seconds": 14400},
    "action_classes": actions,
    "hosted_inputs_sha256": hosted_sha,
}
with open(path, "w", encoding="utf-8") as output:
    json.dump(document, output, sort_keys=True, separators=(",", ":"))
    output.write("\n")
PY
chmod 600 "$fixture/authorization.json"
authorization=$(cat "$fixture/authorization.json")
authorization_sha=$(printf '%s' "$authorization" | shasum -a 256 | awk '{print $1}')

run_check() {
  mode=$1 ref=$2 revision=$3 attempt=$4 payload=$5 digest=$6
  hosted_payload=${7:-$hosted}
  hosted_digest=${8:-$hosted_sha}
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF="$ref" GITHUB_SHA="$revision" GITHUB_ACTOR=jon \
    GITHUB_REPOSITORY=keepling/keepling GITHUB_RUN_ID=777 GITHUB_RUN_ATTEMPT="$attempt" RUNNER_TEMP="$fixture/runner-temp" \
    KEEPLING_HOSTED_INPUTS_JSON="$hosted_payload" KEEPLING_HOSTED_INPUTS_SHA256="$hosted_digest" \
    KEEPLING_AUTHORIZATION_JSON="$payload" KEEPLING_AUTHORIZATION_SHA256="$digest" \
    KEEPLING_TEST_EXTERNAL_CALL_LEDGER="$ledger" \
    sh "$runner" "$mode" >"$fixture/out" 2>"$fixture/err"
}

run_check --validate-inputs refs/heads/main "$source_sha" 1 "$authorization" "$authorization_sha" || {
  cat "$fixture/out" "$fixture/err" >&2
  printf '%s\n' 'not ok - complete fresh exact-source authorization should validate'
  exit 1
}
grep -Fqx 'phase2-protected status=authorization result=valid' "$fixture/out" || { cat "$fixture/out" >&2; exit 1; }
printf '%s\n' 'ok - complete fresh exact-source authorization validates without external calls'

expect_refusal() {
  label=$1 ref=$2 revision=$3 attempt=$4 payload=$5 digest=$6
  shift 6
  if run_check --validate-inputs "$ref" "$revision" "$attempt" "$payload" "$digest" "$@"; then
    printf 'not ok - %s must be refused\n' "$label"; exit 1
  fi
  grep -Eq '^phase2-protected status=NON_PASSING reason=[a-z0-9-]+$' "$fixture/err" || { printf 'not ok - %s returned an unbounded diagnostic\n' "$label"; cat "$fixture/err" >&2; exit 1; }
  [ -z "$(find "$fixture/runner-temp" -mindepth 1 -print -quit)" ] || { printf 'not ok - %s created private run state before Gate C\n' "$label"; exit 1; }
  [ ! -s "$ledger" ] || { printf 'not ok - %s called an external adapter\n' "$label"; exit 1; }
  printf 'ok - %s refused before private state or external calls\n' "$label"
}

expect_refusal "non-main dispatch" refs/heads/feature/test "$source_sha" 1 "$authorization" "$authorization_sha"
expect_refusal "source SHA mismatch" refs/heads/main "$tree_sha" 1 "$authorization" "$authorization_sha"
expect_refusal "replayed attempt" refs/heads/main "$source_sha" 2 "$authorization" "$authorization_sha"
expect_refusal "changed authorization digest" refs/heads/main "$source_sha" 1 "$authorization" "$(printf '%064d' 0 | tr 0 c)"
changed_inputs=$(printf '%s' "$hosted" | sed 's/12345/54321/')
changed_inputs_sha=$(printf '%s' "$changed_inputs" | shasum -a 256 | awk '{print $1}')
expect_refusal "changed hosted input bytes" refs/heads/main "$source_sha" 1 "$authorization" "$authorization_sha" "$changed_inputs" "$changed_inputs_sha"
changed_selection_auth=$(python3 - "$fixture/authorization.json" "$changed_inputs_sha" <<'PY'
import json,sys
value=json.load(open(sys.argv[1])); value["hosted_inputs_sha256"]=sys.argv[2]
print(json.dumps(value,sort_keys=True,separators=(",",":")))
PY
)
changed_selection_auth_sha=$(printf '%s' "$changed_selection_auth" | shasum -a 256 | awk '{print $1}')
expect_refusal "authorization selection differs from bound image input" refs/heads/main "$source_sha" 1 "$changed_selection_auth" "$changed_selection_auth_sha" "$changed_inputs" "$changed_inputs_sha"
stale=$(python3 - "$fixture/authorization.json" <<'PY'
import json, sys
document=json.load(open(sys.argv[1])); document["issued_at"]-=86401
print(json.dumps(document,sort_keys=True,separators=(",",":")))
PY
)
stale_sha=$(printf '%s' "$stale" | shasum -a 256 | awk '{print $1}')
expect_refusal "expired owner authorization" refs/heads/main "$source_sha" 1 "$stale" "$stale_sha"
changed_action=$(python3 - "$fixture/authorization.json" <<'PY'
import json, sys
document=json.load(open(sys.argv[1])); document["action_classes"].pop()
print(json.dumps(document,sort_keys=True,separators=(",",":")))
PY
)
changed_action_sha=$(printf '%s' "$changed_action" | shasum -a 256 | awk '{print $1}')
expect_refusal "incomplete protected action list" refs/heads/main "$source_sha" 1 "$changed_action" "$changed_action_sha"
[ ! -s "$ledger" ] || { printf '%s\n' 'not ok - authorization validation reached an external adapter'; exit 1; }
printf '%s\n' 'ok - runner identity and authorization refusal ledger stayed empty'
