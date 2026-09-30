#!/usr/bin/env sh
set -eu
umask 077

root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$root"

refuse() {
  reason=$1
  case "$reason" in *[!a-z0-9-]*|'') reason=validation-failed;; esac
  printf 'phase2-protected status=NON_PASSING reason=%s\n' "$reason" >&2
  exit 1
}

validate_authorization() {
  [ -n "${KEEPLING_AUTHORIZATION_JSON:-}" ] || refuse authorization-missing
  [ -n "${KEEPLING_AUTHORIZATION_SHA256:-}" ] || refuse authorization-digest-missing
  [ "${#KEEPLING_AUTHORIZATION_JSON}" -le 32768 ] || refuse authorization-too-large
  printf '%s' "$KEEPLING_AUTHORIZATION_SHA256" | grep -Eq '^[0-9a-f]{64}$' || refuse authorization-digest-invalid
  actual_digest=$(printf '%s' "$KEEPLING_AUTHORIZATION_JSON" | shasum -a 256 | awk '{print $1}') || refuse authorization-digest-invalid
  [ "$actual_digest" = "$KEEPLING_AUTHORIZATION_SHA256" ] || refuse authorization-digest-mismatch
  [ -n "${KEEPLING_HOSTED_INPUTS_JSON:-}" ] || refuse hosted-inputs-missing
  [ -n "${KEEPLING_HOSTED_INPUTS_SHA256:-}" ] || refuse hosted-inputs-digest-missing
  [ "${#KEEPLING_HOSTED_INPUTS_JSON}" -le 16384 ] || refuse hosted-inputs-too-large
  printf '%s' "$KEEPLING_HOSTED_INPUTS_SHA256" | grep -Eq '^[0-9a-f]{64}$' || refuse hosted-inputs-digest-invalid
  hosted_digest=$(printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | shasum -a 256 | awk '{print $1}') || refuse hosted-inputs-digest-invalid
  [ "$hosted_digest" = "$KEEPLING_HOSTED_INPUTS_SHA256" ] || refuse hosted-inputs-digest-mismatch

  env -i PATH="$PATH" LC_ALL=C KEEPLING_AUTHORIZATION_JSON="$KEEPLING_AUTHORIZATION_JSON" KEEPLING_HOSTED_INPUTS_JSON="$KEEPLING_HOSTED_INPUTS_JSON" KEEPLING_HOSTED_INPUTS_SHA256="$KEEPLING_HOSTED_INPUTS_SHA256" \
    GITHUB_ACTOR="${GITHUB_ACTOR:-}" GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME:-}" \
    GITHUB_REF="${GITHUB_REF:-}" GITHUB_SHA="${GITHUB_SHA:-}" \
    GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" python3 - <<'PY' || refuse authorization-invalid
import datetime, hashlib, json, math, os, re, time

def fail():
    raise SystemExit(1)

payload = os.environ.get("KEEPLING_AUTHORIZATION_JSON", "")
def no_duplicates(pairs):
    result={}
    for key,item in pairs:
        if key in result: fail()
        result[key]=item
    return result
try:
    value = json.loads(payload, object_pairs_hook=no_duplicates)
except Exception:
    fail()
if not isinstance(value, dict) or set(value) != {
    "version", "logical_run_id", "owner_actor", "issued_at", "change_trigger",
    "upstream", "source", "selection", "limits", "action_classes", "hosted_inputs_sha256",
}:
    fail()
if value["version"] != 1 or not isinstance(value["version"], int) or isinstance(value["version"], bool): fail()
if not isinstance(value["logical_run_id"], str) or not re.fullmatch(r"phase2-run-[0-9]{8}-[a-f0-9]{8,24}", value["logical_run_id"]): fail()
actor = os.environ.get("GITHUB_ACTOR", "")
if not isinstance(value["owner_actor"], str) or value["owner_actor"] != actor or not re.fullmatch(r"[A-Za-z0-9-]{1,39}", actor): fail()
now = int(time.time())
if not isinstance(value["issued_at"], int) or isinstance(value["issued_at"], bool) or value["issued_at"] > now + 300 or now - value["issued_at"] > 86400: fail()
if not isinstance(value["change_trigger"], str) or not re.fullmatch(r"reviewed-phase2-acceptance-[0-9]{4}-[0-9]{2}-[0-9]{2}", value["change_trigger"]): fail()
if value["change_trigger"][-10:] != datetime.datetime.fromtimestamp(value["issued_at"], datetime.timezone.utc).date().isoformat(): fail()

upstream = value["upstream"]
if not isinstance(upstream, dict) or set(upstream) != {"run_id", "run_attempt", "artifact_id", "artifact_digest"}: fail()
for key in ("run_id", "artifact_id"):
    if not isinstance(upstream[key], int) or isinstance(upstream[key], bool) or upstream[key] <= 0: fail()
if upstream["run_attempt"] != 1 or not isinstance(upstream["run_attempt"], int) or isinstance(upstream["run_attempt"], bool): fail()
if not isinstance(upstream["artifact_digest"], str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", upstream["artifact_digest"]): fail()

source = value["source"]
source_keys = {"commit_sha", "tree_sha", "context_tar_sha256", "platform", "archive_sha256", "manifest_digest", "config_image_id", "deployed_image_id", "rootfs_diff_ids_sha256", "synthetic_recovery"}
if not isinstance(source, dict) or set(source) != source_keys: fail()
for key in ("commit_sha", "tree_sha"):
    if not isinstance(source[key], str) or not re.fullmatch(r"[0-9a-f]{40}", source[key]): fail()
for key in ("context_tar_sha256", "archive_sha256", "rootfs_diff_ids_sha256"):
    if not isinstance(source[key], str) or not re.fullmatch(r"[0-9a-f]{64}", source[key]): fail()
for key in ("manifest_digest", "config_image_id", "deployed_image_id"):
    if not isinstance(source[key], str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", source[key]): fail()
if source["platform"] != "linux/amd64" or source["synthetic_recovery"] is not True or source["config_image_id"] != source["deployed_image_id"]: fail()

selection = value["selection"]
if not isinstance(selection, dict) or set(selection) != {"location", "server_type", "server_image_id", "data_volume_gb", "ssh_agent_fingerprint_sha256", "dns_zone_id", "dns_record_name", "admin_source_cidrs", "candidate_source", "recovery_source", "login_source"}: fail()
if selection["location"] != "nbg1" or selection["server_type"] != "cx33": fail()
if not isinstance(selection["server_image_id"], int) or isinstance(selection["server_image_id"], bool) or selection["server_image_id"] <= 0: fail()
if selection["data_volume_gb"] != 160 or not isinstance(selection["data_volume_gb"], int) or isinstance(selection["data_volume_gb"], bool): fail()
try:
    catalog=json.load(open("infra/tofu/hetzner/selection.json",encoding="utf-8"))
    if (catalog.get("location"),catalog.get("server_type"),catalog.get("data_volume_gb")) != (selection["location"],selection["server_type"],selection["data_volume_gb"]): fail()
except Exception: fail()
if not isinstance(selection["ssh_agent_fingerprint_sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", selection["ssh_agent_fingerprint_sha256"]): fail()

limits = value["limits"]
if not isinstance(limits, dict) or set(limits) != {"max_cost_usd", "rpo_seconds", "rto_seconds"}: fail()
if not isinstance(limits["max_cost_usd"], (int, float)) or isinstance(limits["max_cost_usd"], bool) or not math.isfinite(limits["max_cost_usd"]) or limits["max_cost_usd"] <= 0 or limits["max_cost_usd"] > 50: fail()
if limits["rpo_seconds"] != 300 or limits["rto_seconds"] != 14400: fail()
if any(not isinstance(limits[k], int) or isinstance(limits[k], bool) for k in ("rpo_seconds", "rto_seconds")): fail()

expected_actions = [
    "provider-apply", "provider-inventory", "console-marker", "current-ed25519-host-key",
    "ssh-bootstrap", "image-transfer", "credentialed-restore", "sync-epoch",
    "runtime-login-read-write-undo", "rpo-rto", "dns-sentinel-cutover-propagation",
    "rollback-propagation", "sentinel-deletion-absence", "exact-owned-teardown-provider-absence",
]
if value["action_classes"] != expected_actions: fail()
if not isinstance(value["hosted_inputs_sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", value["hosted_inputs_sha256"]): fail()
inputs_raw=os.environ.get("KEEPLING_HOSTED_INPUTS_JSON", "")
if hashlib.sha256(inputs_raw.encode()).hexdigest() != value["hosted_inputs_sha256"] or os.environ.get("KEEPLING_HOSTED_INPUTS_SHA256") != value["hosted_inputs_sha256"]: fail()
def no_duplicates(pairs):
    result={}
    for key,item in pairs:
        if key in result: fail()
        result[key]=item
    return result
try: inputs=json.loads(inputs_raw, object_pairs_hook=no_duplicates)
except Exception: fail()
input_keys={"version","dns_zone_id","dns_record_name","server_image_id","admin_source_cidrs","candidate_source","recovery_source","login_source","b2_primary_endpoint","b2_primary_region","b2_primary_bucket"}
if not isinstance(inputs,dict) or set(inputs)!=input_keys or inputs["version"] != 1 or isinstance(inputs["version"],bool): fail()
if inputs["candidate_source"]!="rebuilt-archive" or inputs["recovery_source"]!="same-run-synthetic-capture" or inputs["login_source"]!="same-run-synthetic-capture": fail()
if not isinstance(inputs["dns_zone_id"],str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}",inputs["dns_zone_id"]): fail()
if not isinstance(inputs["dns_record_name"],str) or not re.fullmatch(r"(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}",inputs["dns_record_name"]): fail()
if not isinstance(inputs["server_image_id"],str) or not re.fullmatch(r"[1-9][0-9]{0,19}",inputs["server_image_id"]): fail()
if not isinstance(inputs["admin_source_cidrs"],list) or not 1<=len(inputs["admin_source_cidrs"])<=32: fail()
try:
    import ipaddress
    if len(set(inputs["admin_source_cidrs"])) != len(inputs["admin_source_cidrs"]): fail()
    for cidr in inputs["admin_source_cidrs"]:
        network=ipaddress.ip_network(cidr,strict=True)
        if str(network)!=cidr or network.prefixlen==0: fail()
except Exception: fail()
selection=value["selection"]
if not isinstance(selection,dict) or set(selection)!={"location","server_type","server_image_id","data_volume_gb","ssh_agent_fingerprint_sha256","dns_zone_id","dns_record_name","admin_source_cidrs","candidate_source","recovery_source","login_source"}: fail()
if selection["server_image_id"] != int(inputs["server_image_id"]): fail()
for key in ("dns_zone_id","dns_record_name","candidate_source","recovery_source","login_source"):
    if selection[key] != inputs[key]: fail()
if selection["admin_source_cidrs"] != inputs["admin_source_cidrs"]: fail()
if os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or os.environ.get("GITHUB_REF") != "refs/heads/main": fail()
if os.environ.get("GITHUB_SHA") != source["commit_sha"]: fail()
if os.environ.get("GITHUB_RUN_ATTEMPT") != "1": fail()
if not re.fullmatch(r"[0-9]+", os.environ.get("GITHUB_RUN_ID", "")): fail()
if not re.fullmatch(r"[-A-Za-z0-9_.]+/[-A-Za-z0-9_.]+", os.environ.get("GITHUB_REPOSITORY", "")): fail()
PY
  printf '%s\n' 'phase2-protected status=authorization result=valid'
}

compare_provenance() {
  env -i PATH="$PATH" LC_ALL=C KEEPLING_AUTHORIZATION_JSON="$KEEPLING_AUTHORIZATION_JSON" python3 - "$1" <<'PY' || return 1
import json, os, sys
actual = json.load(open(sys.argv[1], encoding="utf-8"))
approval = json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])
up = approval["upstream"]
src = approval["source"]
checks = {
    "status": actual.get("status") == "VERIFIED_NATIVE_X64",
    "run_id": actual.get("run_id") == up["run_id"],
    "run_attempt": actual.get("run_attempt") == up["run_attempt"],
    "artifact_id": actual.get("artifact_id") == up["artifact_id"],
    "artifact_digest": actual.get("artifact_digest") == up["artifact_digest"],
    "source_commit_sha": actual.get("source_commit_sha") == src["commit_sha"],
    "source_tree_sha": actual.get("source_tree_sha") == src["tree_sha"],
    "context_tar_sha256": actual.get("context_tar_sha256") == src["context_tar_sha256"],
    "archive_sha256": actual.get("archive_sha256") == src["archive_sha256"],
    "manifest_digest": actual.get("manifest_digest") == src["manifest_digest"],
    "config_image_id": actual.get("config_image_id") == src["config_image_id"],
    "deployed_image_id": actual.get("deployed_image_id") == src["deployed_image_id"],
    "rootfs_diff_ids_sha256": actual.get("rootfs_diff_ids_sha256") == src["rootfs_diff_ids_sha256"],
    "platform": actual.get("platform") == src["platform"],
    "synthetic_recovery": actual.get("synthetic_recovery") is src["synthetic_recovery"],
}
raise SystemExit(0 if all(checks.values()) else 1)
PY
}

validate_authorization
if [ "${1:-}" = --validate-inputs ]; then
  [ "$#" -eq 1 ] || refuse usage
  exit 0
fi
[ "${1:-}" = --run ] && [ "$#" -eq 1 ] || refuse usage
[ "${GITHUB_ACTIONS:-}" = true ] || refuse hosted-runner-required
[ "$(uname -m)" = x86_64 ] || refuse native-x64-required

sha256=$(git rev-parse HEAD 2>/dev/null) || refuse checked-out-source-unavailable
tree=$(git rev-parse 'HEAD^{tree}' 2>/dev/null) || refuse checked-out-tree-unavailable
[ "$sha256" = "$GITHUB_SHA" ] || refuse checked-out-source-mismatch
[ "$tree" = "$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["source"]["tree_sha"])')" ] || refuse checked-out-tree-mismatch
git ls-tree -r "$sha256" | awk '$1 == "160000" { found=1 } END { exit found ? 1 : 0 }' || refuse gitlink-source-context

runner_temp=${RUNNER_TEMP:-}
case "$runner_temp" in /*) ;; *) refuse runner-temp-unavailable;; esac
[ -d "$runner_temp" ] && [ ! -L "$runner_temp" ] || refuse runner-temp-unavailable
runner_temp=$(CDPATH='' cd -P "$runner_temp" && pwd) || refuse runner-temp-unavailable
case "$runner_temp" in "$root"|"$root"/*) refuse runner-temp-in-repository;; esac

provenance_dir=$(mktemp -d "$runner_temp/phase2-provenance.XXXXXX") || refuse provenance-temp-unavailable
chmod 700 "$provenance_dir"
provenance_file=$provenance_dir/provenance.json
if ! env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  GITHUB_REPOSITORY="$GITHUB_REPOSITORY" node "$root/tooling/verify-phase-2-ci-provenance.mjs" \
  --repo "$GITHUB_REPOSITORY" \
  --run-id "$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["upstream"]["run_id"])')" \
  --expected-sha "$GITHUB_SHA" --output "$provenance_file" >/dev/null 2>&1; then
  rm -rf -- "$provenance_dir"
  refuse upstream-provenance-failed
fi
compare_provenance "$provenance_file" || { rm -rf -- "$provenance_dir"; refuse upstream-binding-mismatch; }
rm -rf -- "$provenance_dir"
unset GITHUB_TOKEN

# Only map-backed secret names are accepted here. Secret contents are never
# printed and are not passed to image build, export, or reload processes.
mapped_secret_names='HCLOUD_TOKEN CLOUDFLARE_API_TOKEN KEEPLING_BACKUP_PRIMARY_ACCESS_KEY KEEPLING_BACKUP_PRIMARY_SECRET_KEY KEEPLING_BACKUP_MIRROR_ACCESS_KEY KEEPLING_BACKUP_MIRROR_SECRET_KEY KEEPLING_BACKUP_MIRROR_ENDPOINT KEEPLING_BACKUP_MIRROR_REGION KEEPLING_BACKUP_MIRROR_BUCKET KEEPLING_TOFU_STATE_ACCESS_KEY KEEPLING_TOFU_STATE_SECRET_KEY KEEPLING_TOFU_STATE_ENDPOINT KEEPLING_TOFU_STATE_REGION KEEPLING_TOFU_STATE_BUCKET KEEPLING_BACKUP_CIPHER_PASSPHRASE KEEPLING_SSH_PRIVATE_KEY'
for name in $mapped_secret_names; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || refuse mapped-credential-missing
  [ "${#value}" -le 4096 ] || refuse mapped-credential-invalid
done
printf '%s' "$HCLOUD_TOKEN" | grep -Eq '^[A-Za-z0-9_-]{16,512}$' || refuse mapped-credential-invalid

# Until all externally stored credential references and current selectors are
# supplied by the protected environment, stop before allocating provider state.
# This read-only status command emits only fixed input class names.
known_hosts=${KEEPLING_KNOWN_HOSTS_FILE:-}
case "$known_hosts" in /*) ;; *) refuse known-hosts-unavailable;; esac
case "$known_hosts" in "$root"|"$root"/*) refuse known-hosts-in-repository;; esac
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ ! -s "$known_hosts" ] || refuse known-hosts-not-empty
known_mode=$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts") || refuse known-hosts-mode-invalid
[ "$known_mode" = 600 ] || refuse known-hosts-mode-invalid
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" TOFU_BIN="${TOFU_BIN:-}" \
  "$root/tooling/verify-host-replacement.sh" --dry-run >/dev/null 2>&1 || refuse local-dry-run-failed
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" TOFU_BIN="${TOFU_BIN:-}" \
  CLOUD_INIT_SCHEMA_BIN="${CLOUD_INIT_SCHEMA_BIN:-}" CLOUD_INIT_SCHEMA_VERSION="${CLOUD_INIT_SCHEMA_VERSION:-}" \
  HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" \
  "$root/tooling/phase-2-toolchain-doctor.sh" >/dev/null 2>&1 || refuse pinned-toolchain-unavailable
# Register cleanup before creating the private agent or materializing secrets.
private_root=$(mktemp -d "$runner_temp/keepling-phase-2-protected.XXXXXX") || refuse private-run-directory-unavailable
chmod 700 "$private_root"
image_tag=keepling-server:plan-02-09-amd64
status_file=$runner_temp/phase-2-protected-status.json
trap_status=NON_PASSING
trap_reason=protected-sequence-incomplete
finish() {
  exit_code=$?
  trap - EXIT HUP INT TERM
  # A failed run gets at most one exact-owned provider teardown, and only when
  # the persisted apply fence proves a candidate may exist. A started destroy
  # is never retried after an uncertain result.
  if [ "$exit_code" -ne 0 ] && [ -n "${bundle:-}" ] && [ -f "$bundle" ] && [ ! -L "$bundle" ]; then
    cleanup_workspace=$(awk -F= '$1=="WORKSPACE" {print substr($0,index($0,"=")+1)}' "$bundle")
    if [ -d "$cleanup_workspace" ] && [ -e "$cleanup_workspace/.apply-started" ] && \
      [ ! -e "$cleanup_workspace/.teardown-attempted" ] && [ ! -e "$cleanup_workspace/.teardown-destroy-started" ] && \
      [ ! -e "$cleanup_workspace/.stage-teardown.complete" ]; then
      cleanup_trigger=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["change_trigger"])' 2>/dev/null || true)
      env -i PATH="$PATH" HOME="$HOME" TMPDIR="${RUNNER_TEMP:-/tmp}" \
        KEEPLING_LIVE_ORCHESTRATION_FILE="$bundle" KEEPLING_LIVE_CHANGE_TRIGGER="$cleanup_trigger" \
        KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
        TOFU_BIN="${TOFU_BIN:-}" HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" \
        sh "$root/tooling/phase-2-live-orchestration.sh" teardown >>"${raw_log:-/dev/null}" 2>&1 || true
    fi
  fi
  if [ -n "${SSH_AGENT_PID:-}" ]; then SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-} SSH_AGENT_PID=$SSH_AGENT_PID ssh-agent -k >/dev/null 2>&1 || true; fi
  docker image rm -f "$image_tag" >/dev/null 2>&1 || true
  rm -rf -- "$private_root"
  python3 - "$status_file" "$trap_status" "$trap_reason" <<'PY'
import json, os, sys
path, status, reason = sys.argv[1:]
with open(path, "w", encoding="utf-8") as output:
    json.dump({"version": 1, "status": status, "reason": reason}, output, sort_keys=True, separators=(",", ":"))
    output.write("\n")
os.chmod(path, 0o600)
PY
  exit "$exit_code"
}
trap finish EXIT HUP INT TERM

known_hosts=${KEEPLING_KNOWN_HOSTS_FILE:-}
case "$known_hosts" in /*) ;; *) refuse known-hosts-unavailable;; esac
case "$known_hosts" in "$root"|"$root"/*) refuse known-hosts-in-repository;; esac
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ ! -s "$known_hosts" ] || refuse known-hosts-not-empty
known_mode=$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts") || refuse known-hosts-mode-invalid
[ "$known_mode" = 600 ] || refuse known-hosts-mode-invalid

# Create one isolated in-memory agent only after fresh authorization and the
# protected GitHub environment gate. The private key is piped directly to ssh-add.
agent_socket=$private_root/ssh-agent.sock
eval "$(ssh-agent -a "$agent_socket" -s 2>/dev/null)" >/dev/null || refuse ssh-agent-unavailable
[ -S "$SSH_AUTH_SOCK" ] || refuse ssh-agent-unavailable
printf '%s\n' "$KEEPLING_SSH_PRIVATE_KEY" | ssh-add - >/dev/null 2>&1 || refuse ssh-agent-identity-unavailable
unset KEEPLING_SSH_PRIVATE_KEY
ssh_identity=$(env -i PATH="$PATH" SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ssh-add -L 2>/dev/null | awk 'NF >= 2 { print $1 " " $2 }') || refuse ssh-agent-identity-unavailable
[ "$(printf '%s\n' "$ssh_identity" | awk 'NF { count++ } END { print count+0 }')" -eq 1 ] || refuse ssh-agent-identity-ambiguous
printf '%s\n' "$ssh_identity" | grep -Eq '^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9_.@+-]+)?$' || refuse ssh-agent-identity-invalid
identity_digest=$(printf '%s' "$ssh_identity" | awk '{print $1 " " $2}' | shasum -a 256 | awk '{print $1}') || refuse ssh-agent-identity-invalid
expected_identity_digest=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["selection"]["ssh_agent_fingerprint_sha256"])')
[ "$identity_digest" = "$expected_identity_digest" ] || refuse ssh-agent-identity-mismatch

credential_dir=$private_root/credentials
primary_endpoint=$(printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | jq -er '.b2_primary_endpoint') || refuse hosted-inputs-invalid
primary_region=$(printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | jq -er '.b2_primary_region') || refuse hosted-inputs-invalid
primary_bucket=$(printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | jq -er '.b2_primary_bucket') || refuse hosted-inputs-invalid
env -i PATH="$PATH" LC_ALL=C KEEPLING_HOSTED_INPUTS_JSON="$KEEPLING_HOSTED_INPUTS_JSON" \
  KEEPLING_SSH_PUBLIC_IDENTITY="$ssh_identity" HCLOUD_TOKEN="$HCLOUD_TOKEN" \
  CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
  KEEPLING_BACKUP_PRIMARY_ACCESS_KEY="$KEEPLING_BACKUP_PRIMARY_ACCESS_KEY" KEEPLING_BACKUP_PRIMARY_SECRET_KEY="$KEEPLING_BACKUP_PRIMARY_SECRET_KEY" \
  KEEPLING_HOSTED_B2_PRIMARY_ENDPOINT="$primary_endpoint" KEEPLING_HOSTED_B2_PRIMARY_REGION="$primary_region" KEEPLING_HOSTED_B2_PRIMARY_BUCKET="$primary_bucket" \
  KEEPLING_BACKUP_MIRROR_ACCESS_KEY="$KEEPLING_BACKUP_MIRROR_ACCESS_KEY" KEEPLING_BACKUP_MIRROR_SECRET_KEY="$KEEPLING_BACKUP_MIRROR_SECRET_KEY" \
  KEEPLING_BACKUP_MIRROR_ENDPOINT="$KEEPLING_BACKUP_MIRROR_ENDPOINT" KEEPLING_BACKUP_MIRROR_REGION="$KEEPLING_BACKUP_MIRROR_REGION" KEEPLING_BACKUP_MIRROR_BUCKET="$KEEPLING_BACKUP_MIRROR_BUCKET" \
  KEEPLING_TOFU_STATE_ACCESS_KEY="$KEEPLING_TOFU_STATE_ACCESS_KEY" KEEPLING_TOFU_STATE_SECRET_KEY="$KEEPLING_TOFU_STATE_SECRET_KEY" \
  KEEPLING_TOFU_STATE_ENDPOINT="$KEEPLING_TOFU_STATE_ENDPOINT" KEEPLING_TOFU_STATE_REGION="$KEEPLING_TOFU_STATE_REGION" KEEPLING_TOFU_STATE_BUCKET="$KEEPLING_TOFU_STATE_BUCKET" \
  KEEPLING_BACKUP_CIPHER_PASSPHRASE="$KEEPLING_BACKUP_CIPHER_PASSPHRASE" \
  sh "$root/tooling/materialize-phase-2-hosted-inputs.sh" --directory "$credential_dir" \
    --inputs-json "$KEEPLING_HOSTED_INPUTS_JSON" --ssh-public-identity "$ssh_identity" >/dev/null 2>&1 || refuse hosted-input-materialization-failed
unset HCLOUD_TOKEN CLOUDFLARE_API_TOKEN KEEPLING_BACKUP_PRIMARY_ACCESS_KEY KEEPLING_BACKUP_PRIMARY_SECRET_KEY \
  KEEPLING_BACKUP_MIRROR_ACCESS_KEY KEEPLING_BACKUP_MIRROR_SECRET_KEY KEEPLING_BACKUP_MIRROR_ENDPOINT \
  KEEPLING_BACKUP_MIRROR_REGION KEEPLING_BACKUP_MIRROR_BUCKET KEEPLING_TOFU_STATE_ACCESS_KEY \
  KEEPLING_TOFU_STATE_SECRET_KEY KEEPLING_TOFU_STATE_ENDPOINT KEEPLING_TOFU_STATE_REGION \
  KEEPLING_TOFU_STATE_BUCKET KEEPLING_BACKUP_CIPHER_PASSPHRASE

context_archive=$private_root/source-context.tar
image_archive=$private_root/image.tar.gz
archive_contract=$private_root/archive-contract.json
raw_log=$private_root/private.log
git archive --format=tar "$sha256" >"$context_archive" 2>/dev/null || refuse source-context-export-failed
chmod 600 "$context_archive"
context_digest=$(shasum -a 256 "$context_archive" | awk '{print $1}') || refuse source-context-hash-failed
expected_context=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["source"]["context_tar_sha256"])')
[ "$context_digest" = "$expected_context" ] || refuse source-context-mismatch

env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" RUNNER_TEMP="$runner_temp" \
  KEEPLING_IMAGE_TAG="$image_tag" KEEPLING_IMAGE_PLATFORM=linux/amd64 \
  KEEPLING_BUILD_CONTEXT_ARCHIVE="$context_archive" \
  "$root/tooling/verify-image.sh" >>"$raw_log" 2>&1 || refuse single-image-build-failed
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" RUNNER_TEMP="$runner_temp" \
  KEEPLING_IMAGE_TAG="$image_tag" KEEPLING_IMAGE_PLATFORM=linux/amd64 \
  "$root/tooling/verify-compose.sh" >>"$raw_log" 2>&1 || refuse local-compose-verification-failed
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" \
  "$root/tooling/export-verified-image-archive.sh" "$image_tag" "$image_archive" >>"$raw_log" 2>&1 || refuse image-export-failed
"$root/tooling/verify-host-replacement.sh" --resolve-image-archive "$image_archive" "$archive_contract" >/dev/null 2>>"$raw_log" || refuse archive-reload-contract-failed
chmod 600 "$image_archive" "$archive_contract"

python3 - "$archive_contract" <<'PY' || refuse rebuilt-image-identity-mismatch
import json, os, sys
contract = json.load(open(sys.argv[1], encoding="utf-8"))
approval = json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])
source = approval["source"]
rootfs = contract.get("rootfs_diff_ids")
import hashlib
rootfs_digest = hashlib.sha256(json.dumps(rootfs, separators=(",", ":"), sort_keys=True).encode()).hexdigest()
checks = {
    "revision": contract.get("revision") == source["commit_sha"],
    "architecture": contract.get("architecture") == "amd64",
    "os": contract.get("os") == "linux",
    "archive_sha256": contract.get("archive_sha256") == source["archive_sha256"],
    "manifest_digest": contract.get("manifest_digest") == source["manifest_digest"],
    "config_image_id": contract.get("config_image_id") == source["config_image_id"],
    "rootfs_diff_ids_sha256": rootfs_digest == source["rootfs_diff_ids_sha256"],
}
raise SystemExit(0 if all(checks.values()) else 1)
PY

env -i PATH="$PATH" HOME="$HOME" docker image rm -f "$image_tag" >>"$raw_log" 2>&1 || refuse pre-reload-image-removal-failed
env -i PATH="$PATH" HOME="$HOME" docker load --input "$image_archive" >>"$raw_log" 2>&1 || refuse image-reload-failed
loaded_id=$(env -i PATH="$PATH" HOME="$HOME" docker image inspect "$image_tag" --format '{{.Id}}' 2>>"$raw_log") || refuse reloaded-image-unavailable
expected_id=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["source"]["config_image_id"])')
[ "$loaded_id" = "$expected_id" ] || refuse reloaded-image-mismatch

# Gate C: repeat the exact-byte and owner-selection binding after the immutable
# image was exported, removed, and reloaded.
validate_authorization

candidate_selection=$private_root/candidate-selection.json
recovery_capture=$private_root/recovery-capture
recovery_handoff=$private_root/recovery-handoff
server_image=$private_root/server-image.json
admin_cidrs=$private_root/admin-source-cidrs.txt
mkdir -m 700 "$recovery_capture" "$recovery_handoff"
jq --arg image "$image_archive" '.version=1 | . + {image_archive:$image}' "$archive_contract" >"$candidate_selection" || refuse candidate-selection-write-failed
chmod 600 "$candidate_selection"
server_image_id=$(printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | jq -er '.server_image_id') || refuse hosted-inputs-invalid
jq -n --arg id "$server_image_id" '{version:1,os:"ubuntu-24.04",image_id:$id}' >"$server_image" || refuse server-image-selection-write-failed
chmod 600 "$server_image"
printf '%s' "$KEEPLING_HOSTED_INPUTS_JSON" | jq -er '.admin_source_cidrs[]' >"$admin_cidrs" || refuse admin-cidrs-selection-write-failed
chmod 600 "$admin_cidrs"

# Build a fresh synthetic recovery/login capture only from the exact image that
# was exported, removed, and reloaded in this job.
deployed_image_id=$private_root/deployed-image-id
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" KEEPLING_IMAGE_TAG="$image_tag" \
  KEEPLING_EXPECTED_IMAGE_ID="$loaded_id" KEEPLING_DEPLOYED_IMAGE_ID_FILE="$deployed_image_id" \
  sh "$root/tooling/verify-deploy.sh" --local --recovery-output "$recovery_capture" >>"$raw_log" 2>&1 || refuse same-run-deploy-capture-failed
private_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  mode=$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1") || return 1
  [ "$mode" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  case "$parent/$(basename "$1")" in "$root"|"$root"/*) return 1;; esac
}
private_file "$deployed_image_id" || refuse same-run-deployed-image-proof-unavailable
[ "$(cat "$deployed_image_id")" = "$loaded_id" ] || refuse same-run-deployed-image-mismatch
sh "$root/tooling/prepare-synthetic-recovery.sh" "$recovery_capture" "$recovery_handoff" >>"$raw_log" 2>&1 || refuse same-run-recovery-handoff-failed
chmod 600 "$recovery_handoff"/* || refuse same-run-recovery-mode-invalid
recovery_selection=$recovery_handoff/recovery-selection.json
login_credential=$recovery_handoff/rehearsal-login-credential
recovery_dump=$recovery_handoff/recovery.dump
recovery_provenance=$recovery_handoff/recovery.provenance.json
private_file "$candidate_selection" && private_file "$server_image" && private_file "$admin_cidrs" && \
  private_file "$recovery_selection" && private_file "$login_credential" && private_file "$recovery_dump" && private_file "$recovery_provenance" || refuse generated-selection-private-boundary-invalid

setup_output=$private_root/setup-prepare.log
setup_status=0
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
  "$root/tooling/phase-2-live-setup.sh" --directory "$credential_dir" \
  --candidate-selection "$candidate_selection" --recovery-selection "$recovery_selection" \
  --server-image-selection "$server_image" --admin-source-cidrs "$admin_cidrs" \
  --login-credential "$login_credential" --ssh-known-hosts "$known_hosts" prepare >"$setup_output" 2>&1 || setup_status=$?
[ "$setup_status" -eq 3 ] || refuse private-input-setup-prepare-failed
grep -Fq 'phase2-live-setup status=prepared result=ready' "$setup_output" || refuse private-input-bundle-not-prepared
grep -Fq 'phase2-live-setup status=remaining-inputs result=required code=3' "$setup_output" || refuse private-input-remaining-fence-missing

run_directories=$(find "$credential_dir/runs" -mindepth 1 -maxdepth 1 -type d -print)
[ "$(printf '%s\n' "$run_directories" | awk 'NF {count++} END {print count+0}')" -eq 1 ] || refuse prepared-run-directory-ambiguous
run_directory=$run_directories
bundle=$run_directory/orchestration.env
private_file "$bundle" || refuse generated-orchestration-bundle-unavailable
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" \
  sh "$root/tooling/phase-2-live-orchestration.sh" --validate "$bundle" >"$private_root/bundle-validation.log" 2>&1 || refuse generated-orchestration-bundle-invalid

# Validate every handoff path and content identity against the authorization,
# rebuilt archive, and same-run capture before permitting the first apply.
env -i PATH="$PATH" LC_ALL=C KEEPLING_AUTHORIZATION_JSON="$KEEPLING_AUTHORIZATION_JSON" \
  KEEPLING_HOSTED_INPUTS_JSON="$KEEPLING_HOSTED_INPUTS_JSON" BUNDLE_FILE="$bundle" \
  CANDIDATE_FILE="$candidate_selection" RECOVERY_FILE="$recovery_selection" SERVER_IMAGE_FILE="$server_image" \
  ADMIN_CIDRS_FILE="$admin_cidrs" LOGIN_FILE="$login_credential" IMAGE_ARCHIVE="$image_archive" \
  RECOVERY_DUMP="$recovery_dump" RECOVERY_PROVENANCE="$recovery_provenance" python3 - <<'PY' || refuse generated-input-binding-mismatch
import hashlib,json,os
def read_bundle(path):
    rows={}
    for line in open(path,encoding="utf-8"):
        key,sep,value=line.rstrip("\n").partition("=")
        if not sep or key in rows: raise ValueError("closed bundle")
        rows[key]=value
    return rows
bundle=read_bundle(os.environ["BUNDLE_FILE"])
approval=json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])
inputs=json.loads(os.environ["KEEPLING_HOSTED_INPUTS_JSON"])
candidate=json.load(open(os.environ["CANDIDATE_FILE"],encoding="utf-8"))
recovery=json.load(open(os.environ["RECOVERY_FILE"],encoding="utf-8"))
provenance=json.load(open(os.environ["RECOVERY_PROVENANCE"],encoding="utf-8"))
server_image=json.load(open(os.environ["SERVER_IMAGE_FILE"],encoding="utf-8"))
def sha(path):
    digest=hashlib.sha256()
    with open(path,"rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""): digest.update(block)
    return digest.hexdigest()
auth=approval["selection"]
if auth["server_image_id"]!=int(server_image["image_id"]) or str(server_image["image_id"])!=inputs["server_image_id"]: raise SystemExit(1)
for key in ("dns_zone_id","dns_record_name","candidate_source","recovery_source","login_source","admin_source_cidrs"):
    if auth[key]!=inputs[key]: raise SystemExit(1)
if bundle.get("CANDIDATE_SELECTION_FILE")!=os.environ["CANDIDATE_FILE"] or bundle.get("RECOVERY_SELECTION_FILE")!=os.environ["RECOVERY_FILE"]: raise SystemExit(1)
if bundle.get("SERVER_IMAGE_SELECTION_FILE")!=os.environ["SERVER_IMAGE_FILE"] or bundle.get("ADMIN_SOURCE_CIDRS_FILE")!=os.environ["ADMIN_CIDRS_FILE"] or bundle.get("LOGIN_CREDENTIAL_FILE")!=os.environ["LOGIN_FILE"]: raise SystemExit(1)
if bundle.get("IMAGE_ARCHIVE_FILE")!=os.environ["IMAGE_ARCHIVE"] or candidate.get("image_archive")!=os.environ["IMAGE_ARCHIVE"]: raise SystemExit(1)
if candidate.get("archive_sha256")!=approval["source"]["archive_sha256"] or candidate.get("manifest_digest")!=approval["source"]["manifest_digest"] or candidate.get("config_image_id")!=approval["source"]["config_image_id"]: raise SystemExit(1)
if bundle.get("RECOVERY_DUMP_FILE")!=os.environ["RECOVERY_DUMP"] or bundle.get("RECOVERY_PROVENANCE_FILE")!=os.environ["RECOVERY_PROVENANCE"]: raise SystemExit(1)
if recovery.get("source_kind")!="synthetic-rehearsal" or recovery.get("dump_file")!=os.environ["RECOVERY_DUMP"] or recovery.get("provenance_file")!=os.environ["RECOVERY_PROVENANCE"]: raise SystemExit(1)
if recovery.get("rehearsal_login_credential_file")!=os.environ["LOGIN_FILE"] or bundle.get("LOGIN_CREDENTIAL_FILE")!=recovery["rehearsal_login_credential_file"]: raise SystemExit(1)
if provenance.get("source_kind")!="synthetic-rehearsal" or provenance.get("verification")!={"local_capture":True,"local_restore":True,"synthetic":True}: raise SystemExit(1)
if provenance.get("plaintext_sha256")!=sha(os.environ["RECOVERY_DUMP"]) or provenance.get("plaintext_bytes")!=os.path.getsize(os.environ["RECOVERY_DUMP"]): raise SystemExit(1)
if not bundle.get("DNS_TEST_RECORD_NAME","" ).endswith("."+inputs["dns_record_name"]): raise SystemExit(1)
if sha(os.environ["IMAGE_ARCHIVE"])!=approval["source"]["archive_sha256"]: raise SystemExit(1)
with open(os.environ["ADMIN_CIDRS_FILE"],encoding="ascii") as stream:
    if stream.read().splitlines()!=inputs["admin_source_cidrs"]: raise SystemExit(1)
PY

# This second digest/selection check is the last gate before any provider action.
validate_authorization

bundle_sha=$(shasum -a 256 "$bundle" | awk '{print $1}') || refuse generated-orchestration-bundle-digest-unavailable
source_sha=$GITHUB_SHA
agent_digest=$identity_digest
change_trigger=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["change_trigger"])')
signal_file=$private_root/host-trust-signal.json
run_orchestration() {
  stage_name=$1
  resume_signal=${2:-}
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" SSH_AUTH_SOCK="$SSH_AUTH_SOCK" SSH_AGENT_PID="$SSH_AGENT_PID" \
    GITHUB_ACTIONS=true GITHUB_TOKEN="${GITHUB_TOKEN:-}" GITHUB_REPOSITORY="$GITHUB_REPOSITORY" GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME" \
    GITHUB_REF="$GITHUB_REF" GITHUB_SHA="$GITHUB_SHA" GITHUB_RUN_ID="$GITHUB_RUN_ID" GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT" GITHUB_ACTOR="$GITHUB_ACTOR" \
    KEEPLING_AUTHORIZATION_JSON="$KEEPLING_AUTHORIZATION_JSON" KEEPLING_AUTHORIZATION_SHA256="$KEEPLING_AUTHORIZATION_SHA256" \
    KEEPLING_HOSTED_INPUTS_SHA256="$KEEPLING_HOSTED_INPUTS_SHA256" KEEPLING_PROTECTED_HOST_TRUST_SIGNAL=yes \
    KEEPLING_APPROVED_SOURCE_SHA="$source_sha" KEEPLING_APPROVED_SSH_KEY_SHA256="$agent_digest" \
    KEEPLING_APPROVED_BUNDLE_SHA256="$bundle_sha" KEEPLING_LIVE_CHANGE_TRIGGER="$change_trigger" \
    KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
    KEEPLING_LIVE_ORCHESTRATION_FILE="$bundle" KEEPLING_HOSTED_INPUTS_JSON="$KEEPLING_HOSTED_INPUTS_JSON" \
    KEEPLING_RESUME_HOST_TRUST="$resume_signal" KEEPLING_HOST_TRUST_SIGNAL_FILE="$signal_file" \
    KEEPLING_KNOWN_HOSTS_FILE="$known_hosts" TOFU_BIN="${TOFU_BIN:-}" CLOUD_INIT_SCHEMA_BIN="${CLOUD_INIT_SCHEMA_BIN:-}" \
    CLOUD_INIT_SCHEMA_VERSION="${CLOUD_INIT_SCHEMA_VERSION:-}" HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" \
    sh "$root/tooling/phase-2-live-orchestration.sh" "$stage_name" >>"$raw_log" 2>&1
}

# One run-bound lifecycle: bootstrap pauses for the owner trust gate, then the
# existing same-job signal wait permits one resume before later exact stages.
bootstrap_status=0
run_orchestration bootstrap || bootstrap_status=$?
[ "$bootstrap_status" -eq 75 ] || refuse candidate-bootstrap-did-not-pause-at-host-trust
pending=$run_directory/workspace/.host-trust.pending
private_file "$pending" || refuse host-trust-checkpoint-unavailable
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" GITHUB_TOKEN="${GITHUB_TOKEN:-}" GITHUB_REPOSITORY="$GITHUB_REPOSITORY" \
  GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME" GITHUB_REF="$GITHUB_REF" GITHUB_SHA="$GITHUB_SHA" GITHUB_RUN_ID="$GITHUB_RUN_ID" \
  GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT" GITHUB_ACTOR="$GITHUB_ACTOR" \
  PHASE2_PARENT_RUN_ID="$(awk -F= '$1=="PARENT_RUN_ID" {print $2}' "$pending")" \
  PHASE2_PARENT_RUN_ATTEMPT="$(awk -F= '$1=="PARENT_RUN_ATTEMPT" {print $2}' "$pending")" \
  PHASE2_LOGICAL_RUN_DIGEST="$(awk -F= '$1=="LOGICAL_RUN_DIGEST" {print $2}' "$pending")" \
  PHASE2_CHALLENGE_NONCE="$(awk -F= '$1=="CHALLENGE_NONCE" {print $2}' "$pending")" \
  PHASE2_OWNER_ACTOR="$(awk -F= '$1=="OWNER_ACTOR" {print $2}' "$pending")" \
  PHASE2_TRUST_DEADLINE="$(awk -F= '$1=="TRUST_DEADLINE" {print $2}' "$pending")" \
  PHASE2_PARENT_SOURCE_SHA="$(awk -F= '$1=="PARENT_SOURCE_SHA" {print $2}' "$pending")" \
  sh "$root/tooling/wait-for-phase-2-host-trust.sh" --wait --signal-output "$signal_file" >"$private_root/host-trust-wait.log" 2>&1 || refuse host-trust-owner-signal-unavailable
grep -Fq 'host-trust status=verified signal=single-use' "$private_root/host-trust-wait.log" || refuse host-trust-owner-signal-invalid
run_orchestration bootstrap yes || refuse candidate-host-trust-resume-failed
for stage_name in image restore runtime semantic dns teardown; do
  run_orchestration "$stage_name" || refuse "${stage_name}-stage-failed"
done
trap_status=PASS
trap_reason=all-authorized-stages-passed
printf '%s\n' 'phase2-protected status=PASS result=acceptance-sequence-complete'
