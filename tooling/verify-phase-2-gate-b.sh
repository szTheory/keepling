#!/usr/bin/env sh
# Prepare source-bound native-x64 image/deploy/recovery evidence for Gate B.
# This is CI-route proof only; it never authorizes or performs provider actions.
set -eu
umask 077

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() { printf '%s\n' "Gate B route refused: $1" >&2; exit 2; }
command_required() { command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
private_external_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  case "$1" in "$repository_root"|"$repository_root"/*) return 1;; esac
}

[ "$#" -eq 1 ] || die 'usage: tooling/verify-phase-2-gate-b.sh ABSOLUTE_SANITIZED_RESULT.json'
result_path=$1
case "$result_path" in /*) ;; *) die 'result path must be absolute';; esac
case "$result_path" in "$repository_root"|"$repository_root"/*) die 'result must remain outside the repository';; esac
[ ! -e "$result_path" ] || die 'result path already exists'

for command in git docker jq python3; do command_required "$command"; done
if command -v sha256sum >/dev/null 2>&1; then :; else command_required shasum; fi
[ "$(uname -m)" = x86_64 ] || die 'runner host is not native x86_64'
[ "${KEEPLING_IMAGE_PLATFORM:-}" = linux/amd64 ] || die 'KEEPLING_IMAGE_PLATFORM must be linux/amd64'
case "$(docker info --format '{{.Architecture}}')" in x86_64|amd64) ;; *) die 'Docker server is not native amd64';; esac

source_sha=$(git rev-parse HEAD 2>/dev/null) || die 'checked-out source revision is unavailable'
printf '%s\n' "$source_sha" | grep -Eq '^[0-9a-f]{40}$' || die 'checked-out source revision is not a full SHA'
git cat-file -e "$source_sha^{commit}" 2>/dev/null || die 'checked-out source commit is unavailable'
tree_sha=$(git rev-parse 'HEAD^{tree}' 2>/dev/null) || die 'checked-out source tree is unavailable'
printf '%s\n' "$tree_sha" | grep -Eq '^[0-9a-f]{40}$' || die 'checked-out source tree is not a full SHA'
git ls-tree -r "$source_sha" | awk '$1 == "160000" { found=1 } END { exit found ? 0 : 1 }' &&
  die 'Git tree contains a submodule/gitlink without pinned context content'

temp_parent=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
[ -d "$temp_parent" ] || die 'runner temporary directory is unavailable'
private_root=$(mktemp -d "$temp_parent/keepling-phase-2-gate-b.XXXXXX") || die 'private temporary directory could not be created'
chmod 700 "$private_root"
context_archive=$private_root/git-tree-context.tar
image_archive=$private_root/final-image.tar.gz
archive_contract=$private_root/archive-contract.json
recovery_root=$private_root/recovery
raw_log=$private_root/chain.log
candidate_result=$private_root/result.json
mkdir -m 700 "$recovery_root"

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -rf -- "$private_root"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

git archive --format=tar "$source_sha" >"$context_archive" 2>"$raw_log" || die 'immutable Git-tree context could not be created'
[ -s "$context_archive" ] || die 'immutable Git-tree context is empty'
chmod 600 "$context_archive" "$raw_log"
context_sha=$(sha256_file "$context_archive")
printf '%s\n' "$context_sha" | grep -Eq '^[0-9a-f]{64}$' || die 'immutable Git-tree context could not be hashed'
[ "$context_sha" != "$source_sha" ] && [ "$context_sha" != "$tree_sha" ] || die 'source, tree, and context identities are not distinct'

image_tag=keepling-server:plan-02-09-amd64
image_platform=linux/amd64
run_private() {
  # All tool output can contain task identity, credentials, or raw service data.
  "$@" >>"$raw_log" 2>&1 || die "private verification step failed: $1"
}

# The hook exists only for hermetic tests. CI never sets it; reject it on hosted
# runners so it cannot replace any part of the route being proven.
hook_root=${KEEPLING_GATE_B_TEST_HOOK_DIR:-}
if [ -n "$hook_root" ]; then
  [ "${GITHUB_ACTIONS:-false}" != true ] || die 'test hooks are forbidden on hosted CI'
  [ -d "$hook_root" ] && [ ! -L "$hook_root" ] || die 'test hook directory is unavailable'
  case "$hook_root" in "$temp_parent"/keepling-phase-2-gate-b-test.*) ;; *) die 'test hook directory is outside its private fixture root';; esac
  [ "$(mode_of "$hook_root")" = 700 ] || die 'test hook directory is not private'
fi

if [ -n "$hook_root" ]; then image_verifier=$hook_root/verify-image.sh; compose_verifier=$hook_root/verify-compose.sh; exporter=$hook_root/export-image.sh; resolver=$hook_root/resolve-archive.sh; deploy_verifier=$hook_root/verify-deploy.sh; privacy_verifier=$hook_root/verify-privacy.sh
else image_verifier=$repository_root/tooling/verify-image.sh; compose_verifier=$repository_root/tooling/verify-compose.sh; exporter=$repository_root/tooling/export-verified-image-archive.sh; resolver=$repository_root/tooling/verify-host-replacement.sh; deploy_verifier=$repository_root/tooling/verify-deploy.sh; privacy_verifier=$repository_root/tooling/verify-privacy.sh; fi

export KEEPLING_IMAGE_TAG=$image_tag KEEPLING_IMAGE_PLATFORM=$image_platform
export KEEPLING_BUILD_CONTEXT_ARCHIVE=$context_archive
run_private "$image_verifier"
unset KEEPLING_BUILD_CONTEXT_ARCHIVE
initial_image_id=$(docker image inspect "$image_tag" --format '{{.Id}}' 2>>"$raw_log") || die 'built image is unavailable after the single build step'
initial_image_platform=$(docker image inspect "$image_tag" --format '{{.Os}}/{{.Architecture}}' 2>>"$raw_log") || die 'built image platform is unavailable'
initial_image_revision=$(docker image inspect "$image_tag" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>>"$raw_log") || die 'built image source label is unavailable'
case "$initial_image_id" in sha256:????????????????????????????????????????????????????????????????) ;; *) die 'built image ID is not immutable';; esac
[ "$initial_image_platform" = linux/amd64 ] || die 'built image is not linux/amd64'
[ "$initial_image_revision" = "$source_sha" ] || die 'built image does not carry the checked-out source revision'
run_private "$compose_verifier"
compose_image_id=$(docker image inspect "$image_tag" --format '{{.Id}}' 2>>"$raw_log") || die 'Compose verification removed the candidate image'
[ "$compose_image_id" = "$initial_image_id" ] || die 'Compose verification replaced or rebuilt the single candidate image'
run_private "$exporter" "$image_tag" "$image_archive"
private_external_file "$image_archive" || die 'exported image archive is not private'
run_private "$resolver" --resolve-image-archive "$image_archive" "$archive_contract"
private_external_file "$archive_contract" || die 'archive contract is not private'

jq -e --arg revision "$source_sha" \
  '.version == 2 and .revision == $revision and .architecture == "amd64" and .os == "linux" and
   (.archive_sha256|test("^[0-9a-f]{64}$")) and (.config_image_id|test("^sha256:[0-9a-f]{64}$")) and
   (.manifest_digest|test("^sha256:[0-9a-f]{64}$")) and (.rootfs_diff_ids|type=="array" and length>0 and all(.[];test("^sha256:[0-9a-f]{64}$")))' \
  "$archive_contract" >/dev/null 2>>"$raw_log" || die 'exported image archive contract is incomplete or source-mismatched'
archive_sha=$(jq -r .archive_sha256 "$archive_contract")
manifest_digest=$(jq -r .manifest_digest "$archive_contract")
config_image_id=$(jq -r .config_image_id "$archive_contract")
rootfs_list=$(jq -cS .rootfs_diff_ids "$archive_contract")
if command -v sha256sum >/dev/null 2>&1; then rootfs_sha=$(printf '%s' "$rootfs_list" | sha256sum | awk '{print $1}')
else rootfs_sha=$(printf '%s' "$rootfs_list" | shasum -a 256 | awk '{print $1}'); fi
[ "$(sha256_file "$image_archive")" = "$archive_sha" ] || die 'final archive checksum does not match its resolved contract'

# Force the deploy verifier to consume the reloaded bytes. A missing or changed
# tag cannot silently trigger verify-image.sh and create a second build.
docker image rm -f "$image_tag" >/dev/null 2>>"$raw_log" || die 'pre-reload image could not be removed'
docker load --input "$image_archive" >>"$raw_log" 2>&1 || die 'final image archive could not be reloaded'
loaded_id=$(docker image inspect "$image_tag" --format '{{.Id}}' 2>>"$raw_log") || die 'reloaded image is unavailable'
loaded_platform=$(docker image inspect "$image_tag" --format '{{.Os}}/{{.Architecture}}' 2>>"$raw_log") || die 'reloaded platform is unavailable'
loaded_revision=$(docker image inspect "$image_tag" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>>"$raw_log") || die 'reloaded source label is unavailable'
loaded_rootfs=$(docker image inspect "$image_tag" --format '{{json .RootFS.Layers}}' 2>>"$raw_log") || die 'reloaded rootfs is unavailable'
[ "$loaded_id" = "$config_image_id" ] || die 'reloaded config image ID differs from the archive contract'
[ "$loaded_platform" = linux/amd64 ] || die 'reloaded image platform differs from linux/amd64'
[ "$loaded_revision" = "$source_sha" ] || die 'reloaded image source label differs from checked-out source'
printf '%s\n' "$loaded_rootfs" | jq -e --slurpfile contract "$archive_contract" '. == $contract[0].rootfs_diff_ids' >/dev/null 2>>"$raw_log" || die 'reloaded rootfs differs from the archive contract'

export KEEPLING_EXPECTED_IMAGE_ID=$config_image_id
export KEEPLING_DEPLOYED_IMAGE_ID_FILE=$private_root/deployed-image-id
run_private "$deploy_verifier" --local --recovery-output "$recovery_root"
unset KEEPLING_EXPECTED_IMAGE_ID
unset KEEPLING_DEPLOYED_IMAGE_ID_FILE
recovery_manifest=$recovery_root/recovery-manifest.json
private_external_file "$recovery_manifest" || die 'synthetic recovery manifest is missing or non-private'
jq -e '(keys|sort)==["dump_sha256","rehearsal_login_credential_sha256","semantic","source_epoch","task_id","version"] and
  .version==1 and (.semantic|.login==true and .read==true and .write==true and .undo==true and .restored_login==true)' \
  "$recovery_manifest" >/dev/null 2>>"$raw_log" || die 'synthetic capture, isolated restore, or semantic recovery proof is incomplete'
deployed_id=$(cat "$private_root/deployed-image-id" 2>/dev/null || true)
[ "$(printf '%s' "$deployed_id" | wc -c | tr -d '[:space:]')" -eq 71 ] || die 'deploy verifier omitted its bounded image identity'
[ "$(mode_of "$private_root/deployed-image-id")" = 600 ] || die 'deploy image identity is not private'
[ "$deployed_id" = "$config_image_id" ] || die 'running Compose app image ID does not match the reloaded archive'

jq -n -S \
  --arg source_commit_sha "$source_sha" --arg source_tree_sha "$tree_sha" \
  --arg context_tar_sha256 "$context_sha" --arg platform "$image_platform" \
  --arg archive_sha256 "$archive_sha" --arg manifest_digest "$manifest_digest" \
  --arg config_image_id "$config_image_id" --arg deployed_image_id "$deployed_id" \
  --arg rootfs_diff_ids_sha256 "$rootfs_sha" \
  '{version:1,status:"CI_ROUTE_READY",source_commit_sha:$source_commit_sha,source_tree_sha:$source_tree_sha,
    context_tar_sha256:$context_tar_sha256,platform:$platform,archive_sha256:$archive_sha256,
    manifest_digest:$manifest_digest,config_image_id:$config_image_id,deployed_image_id:$deployed_image_id,
    rootfs_diff_ids_sha256:$rootfs_diff_ids_sha256,synthetic_recovery:true}' >"$candidate_result"
chmod 600 "$candidate_result"
"$privacy_verifier" "$candidate_result" >>"$raw_log" 2>&1 || die 'sanitized result failed the privacy verifier'
jq -e '(keys|sort)==["archive_sha256","config_image_id","context_tar_sha256","deployed_image_id","manifest_digest","platform","rootfs_diff_ids_sha256","source_commit_sha","source_tree_sha","status","synthetic_recovery","version"] and
  .version==1 and .status=="CI_ROUTE_READY" and .synthetic_recovery==true' "$candidate_result" >/dev/null 2>>"$raw_log" || die 'sanitized evidence schema is invalid'
install -m 600 "$candidate_result" "$result_path" || die 'sanitized result could not be published to runner temp'
printf '%s\n' 'phase-2-gate-b status=CI_ROUTE_READY synthetic_recovery=true'
