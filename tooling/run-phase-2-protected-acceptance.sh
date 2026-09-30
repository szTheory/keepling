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

  env -i PATH="$PATH" LC_ALL=C KEEPLING_AUTHORIZATION_JSON="$KEEPLING_AUTHORIZATION_JSON" \
    GITHUB_ACTOR="${GITHUB_ACTOR:-}" GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME:-}" \
    GITHUB_REF="${GITHUB_REF:-}" GITHUB_SHA="${GITHUB_SHA:-}" \
    GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" python3 - <<'PY' || refuse authorization-invalid
import datetime, json, math, os, re, time

def fail():
    raise SystemExit(1)

payload = os.environ.get("KEEPLING_AUTHORIZATION_JSON", "")
try:
    value = json.loads(payload)
except Exception:
    fail()
if not isinstance(value, dict) or set(value) != {
    "version", "logical_run_id", "owner_actor", "issued_at", "change_trigger",
    "upstream", "source", "selection", "limits", "action_classes",
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
if not isinstance(selection, dict) or set(selection) != {"location", "server_type", "server_image_id", "data_volume_gb", "ssh_agent_fingerprint_sha256"}: fail()
if selection["location"] != "nbg1" or selection["server_type"] != "cx33": fail()
if not isinstance(selection["server_image_id"], int) or isinstance(selection["server_image_id"], bool) or selection["server_image_id"] <= 0: fail()
if selection["data_volume_gb"] != 160 or not isinstance(selection["data_volume_gb"], int) or isinstance(selection["data_volume_gb"], bool): fail()
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
for name in HCLOUD_TOKEN CLOUDFLARE_API_TOKEN KEEPLING_BACKUP_PRIMARY_ACCESS_KEY KEEPLING_BACKUP_PRIMARY_SECRET_KEY; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || refuse mapped-credential-missing
  [ "${#value}" -le 4096 ] || refuse mapped-credential-invalid
done
printf '%s' "$HCLOUD_TOKEN" | grep -Eq '^[A-Za-z0-9_-]{16,512}$' || refuse mapped-credential-invalid
unset HCLOUD_TOKEN CLOUDFLARE_API_TOKEN KEEPLING_BACKUP_PRIMARY_ACCESS_KEY KEEPLING_BACKUP_PRIMARY_SECRET_KEY

# Until all externally stored credential references and current selectors are
# supplied by the protected environment, stop before allocating provider state.
# This read-only status command emits only fixed input class names.
known_hosts=${KEEPLING_KNOWN_HOSTS_FILE:-}
case "$known_hosts" in /*) ;; *) refuse known-hosts-unavailable;; esac
case "$known_hosts" in "$root"|"$root"/*) refuse known-hosts-in-repository;; esac
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ ! -s "$known_hosts" ] || refuse known-hosts-not-empty
known_mode=$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts") || refuse known-hosts-mode-invalid
[ "$known_mode" = 600 ] || refuse known-hosts-mode-invalid
[ -S "${SSH_AUTH_SOCK:-}" ] || refuse ssh-agent-unavailable
ssh_identity=$(env -i PATH="$PATH" SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ssh-add -L 2>/dev/null | awk 'NF >= 2 { print $1 " " $2 }') || refuse ssh-agent-identity-unavailable
[ "$(printf '%s\n' "$ssh_identity" | awk 'NF { count++ } END { print count+0 }')" -eq 1 ] || refuse ssh-agent-identity-ambiguous
printf '%s\n' "$ssh_identity" | grep -Eq '^ssh-ed25519 [A-Za-z0-9+/=]+$' || refuse ssh-agent-identity-invalid
identity_digest=$(printf '%s' "$ssh_identity" | shasum -a 256 | awk '{print $1}') || refuse ssh-agent-identity-invalid
expected_identity_digest=$(python3 -c 'import json,os; print(json.loads(os.environ["KEEPLING_AUTHORIZATION_JSON"])["selection"]["ssh_agent_fingerprint_sha256"])')
[ "$identity_digest" = "$expected_identity_digest" ] || refuse ssh-agent-identity-mismatch

env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" TOFU_BIN="${TOFU_BIN:-}" \
  "$root/tooling/verify-host-replacement.sh" --dry-run >/dev/null 2>&1 || refuse local-dry-run-failed
env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" TOFU_BIN="${TOFU_BIN:-}" \
  CLOUD_INIT_SCHEMA_BIN="${CLOUD_INIT_SCHEMA_BIN:-}" CLOUD_INIT_SCHEMA_VERSION="${CLOUD_INIT_SCHEMA_VERSION:-}" \
  HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" \
  "$root/tooling/phase-2-toolchain-doctor.sh" >/dev/null 2>&1 || refuse pinned-toolchain-unavailable
if ! env -i PATH="$PATH" HOME="$HOME" TMPDIR="$runner_temp" \
  "$root/tooling/phase-2-live-setup.sh" remaining-inputs >/dev/null 2>&1; then
  refuse protected-inputs-incomplete
fi

# The private directory and trap are established only after input, provenance,
# credential-shape, host-key, local dry-run, and toolchain gates pass. The
# archive stays in this directory for the same-job trust wait and continuation.
private_root=$(mktemp -d "$runner_temp/keepling-phase-2-protected.XXXXXX") || refuse private-run-directory-unavailable
chmod 700 "$private_root"
image_tag=keepling-server:plan-02-09-amd64
status_file=$runner_temp/phase-2-protected-status.json
trap_status=NON_PASSING
trap_reason=protected-sequence-incomplete
finish() {
  exit_code=$?
  trap - EXIT HUP INT TERM
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

# Plan 02-24 extends this base with candidate creation, the bounded trust wait,
# continuation, and exact-owned cleanup. Never turn route-ready evidence into a
# live acceptance claim from this preparation runner.
refuse protected-sequence-incomplete
