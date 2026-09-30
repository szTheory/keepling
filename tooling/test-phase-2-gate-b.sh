#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
fixture=$(mktemp -d "$runner_temp/keepling-phase-2-gate-b-test.XXXXXX")
chmod 700 "$fixture"
hook=$fixture/hooks
mkdir -m 700 "$hook" "$fixture/mock-bin"
untracked_path="$root/apps/server/lib/keepling/phase_2_gate_b_fixture_$$.ex"
ignored_path="$root/apps/server/_build/phase_2_gate_b_fixture_$$.ex"
die() { printf '%s\n' "Gate B fixture failed: $*" >&2; exit 1; }
cleanup() {
  rm -f -- "$untracked_path" "$ignored_path"
  rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

[ ! -e "$untracked_path" ] && [ ! -e "$ignored_path" ] || die 'unique fixture paths already exist'
mkdir -p "$(dirname "$untracked_path")" "$(dirname "$ignored_path")"
git -C "$root" check-ignore -q "${ignored_path#"$root"/}" || die 'ignored build-input fixture path is not ignored'
printf '%s\n' 'untracked build input must never enter a Git archive' >"$untracked_path"
printf '%s\n' 'ignored build input must never enter a Git archive' >"$ignored_path"

sha_file() { shasum -a 256 "$1" | awk '{print $1}'; }
git -C "$root" archive --format=tar HEAD >"$fixture/baseline.tar"
baseline_sha=$(sha_file "$fixture/baseline.tar")
source_sha=$(git -C "$root" rev-parse HEAD)
real_git=$(command -v git)
real_stat=$(command -v stat)
config_id=sha256:1111111111111111111111111111111111111111111111111111111111111111
manifest_digest=sha256:2222222222222222222222222222222222222222222222222222222222222222
rootfs_id=sha256:3333333333333333333333333333333333333333333333333333333333333333
export FIXTURE_ROOT=$fixture FIXTURE_BASELINE_SHA=$baseline_sha FIXTURE_SOURCE_SHA=$source_sha
export REAL_GIT=$real_git REAL_STAT=$real_stat
export FIXTURE_REAL_PRIVACY=$root/tooling/verify-privacy.sh
export FIXTURE_CONFIG_ID=$config_id FIXTURE_MANIFEST_DIGEST=$manifest_digest FIXTURE_ROOTFS_ID=$rootfs_id
export KEEPLING_IMAGE_PLATFORM=linux/amd64 KEEPLING_IMAGE_TAG=keepling-server:plan-02-09-amd64
export RUNNER_TEMP=$runner_temp KEEPLING_GATE_B_TEST_HOOK_DIR=$hook

cat >"$hook/verify-image.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "${KEEPLING_IMAGE_PLATFORM:-}" = linux/amd64 ] || exit 21
[ "${KEEPLING_IMAGE_TAG:-}" = keepling-server:plan-02-09-amd64 ] || exit 22
[ -f "${KEEPLING_BUILD_CONTEXT_ARCHIVE:-}" ] || exit 23
[ "$(shasum -a 256 "$KEEPLING_BUILD_CONTEXT_ARCHIVE" | awk '{print $1}')" = "$FIXTURE_BASELINE_SHA" ] || exit 24
tar -tf "$KEEPLING_BUILD_CONTEXT_ARCHIVE" >"$FIXTURE_ROOT/context-members"
if grep -E 'phase_2_gate_b_fixture_[0-9]+\.ex$' "$FIXTURE_ROOT/context-members" >/dev/null; then exit 25; fi
docker buildx build --platform linux/amd64 --file infra/images/server/Dockerfile - <"$KEEPLING_BUILD_CONTEXT_ARCHIVE"
count=0; [ ! -f "$FIXTURE_ROOT/build-count" ] || count=$(cat "$FIXTURE_ROOT/build-count")
count=$((count + 1)); printf '%s' "$count" >"$FIXTURE_ROOT/build-count"
printf '%s\n' 'mock image verification passed'
MOCK
cat >"$hook/verify-compose.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ -z "${KEEPLING_BUILD_CONTEXT_ARCHIVE:-}" ] || exit 26
[ "$(cat "$FIXTURE_ROOT/build-count")" = 1 ] || exit 27
printf '%s\n' 'mock compose verification passed'
MOCK
cat >"$hook/export-image.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "$1" = keepling-server:plan-02-09-amd64 ] || exit 28
printf 'mock final image archive\n' >"$2"
chmod "${FIXTURE_ARCHIVE_MODE:-600}" "$2"
MOCK
cat >"$hook/resolve-archive.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "$1" = --resolve-image-archive ] || exit 29
archive_sha=$(shasum -a 256 "$2" | awk '{print $1}')
revision=$FIXTURE_SOURCE_SHA
case "${FIXTURE_BAD_CONTRACT:-}" in
  missing-revision) revision=;;
  revision) revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;;
  missing-archive) archive_sha=;;
  archive) archive_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;;
  config) :;;
  rootfs) :;;
  platform) :;;
esac
jq_config=$FIXTURE_CONFIG_ID
jq_rootfs=$FIXTURE_ROOTFS_ID
jq_arch=amd64
case "${FIXTURE_BAD_CONTRACT:-}" in
  config) jq_config=sha256:5555555555555555555555555555555555555555555555555555555555555555;;
  rootfs) jq_rootfs=sha256:6666666666666666666666666666666666666666666666666666666666666666;;
  platform) jq_arch=arm64;;
esac
jq -n --arg sha "$archive_sha" --arg revision "$revision" --arg config "$jq_config" \
  --arg manifest "$FIXTURE_MANIFEST_DIGEST" --arg rootfs "$jq_rootfs" --arg arch "$jq_arch" \
  '{version:2,archive_sha256:$sha,config_image_id:$config,manifest_digest:$manifest,revision:$revision,
    architecture:$arch,os:"linux",rootfs_diff_ids:[$rootfs]}' >"$3"
chmod 600 "$3"
MOCK
cat >"$hook/verify-deploy.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "$1" = --local ] && [ "$2" = --recovery-output ] || exit 30
[ "${KEEPLING_EXPECTED_IMAGE_ID:-}" = "$FIXTURE_CONFIG_ID" ] || exit 31
printf '%s\n' "${FIXTURE_DEPLOYED_ID:-$FIXTURE_CONFIG_ID}" >"$KEEPLING_DEPLOYED_IMAGE_ID_FILE"
chmod 600 "$KEEPLING_DEPLOYED_IMAGE_ID_FILE"
[ "${FIXTURE_RECOVERY:-ok}" != missing ] || exit 32
semantic='true'
[ "${FIXTURE_RECOVERY:-ok}" != semantic ] || semantic='false'
jq -n --arg dump "$(printf dump | shasum -a 256 | awk '{print $1}')" \
 --arg credential "$(printf credential | shasum -a 256 | awk '{print $1}')" \
 '{version:1,dump_sha256:$dump,rehearsal_login_credential_sha256:$credential,source_epoch:"fixture-epoch",task_id:"00000000-0000-4000-8000-000000000001",semantic:{login:true,read:true,write:true,undo:true,restored_login:(env.FIXTURE_RECOVERY != "semantic")}}' \
 >"$3/recovery-manifest.json"
chmod 600 "$3/recovery-manifest.json"
MOCK
cat >"$hook/verify-privacy.sh" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "${FIXTURE_PRIVACY:-ok}" = ok ] || exit 33
"$FIXTURE_REAL_PRIVACY" "$1"
MOCK
cat >"$fixture/mock-bin/docker" <<'MOCK'
#!/usr/bin/env sh
set -eu
case "$1:$2" in
  info:*) printf '%s\n' amd64 ;;
  buildx:build)
    case " $* " in *' - '*) ;; *) exit 36;; esac
    case " $* " in *' . '*) exit 37;; esac
    [ "$(cat | shasum -a 256 | awk '{print $1}')" = "$FIXTURE_BASELINE_SHA" ] || exit 38
    ;;
  image:rm) exit 0 ;;
  load:*) exit 0 ;;
  image:inspect)
    case "$5" in
      '{{.Id}}') printf '%s\n' "$FIXTURE_CONFIG_ID" ;;
      '{{.Os}}/{{.Architecture}}') printf '%s\n' "${FIXTURE_DOCKER_PLATFORM:-linux/amd64}" ;;
      *org.opencontainers.image.revision*) printf '%s\n' "${FIXTURE_DOCKER_REVISION:-$FIXTURE_SOURCE_SHA}" ;;
      '{{json .RootFS.Layers}}') printf '["%s"]\n' "${FIXTURE_DOCKER_ROOTFS_ID:-$FIXTURE_ROOTFS_ID}" ;;
      *) exit 34 ;;
    esac ;;
  *) exit 35 ;;
esac
MOCK
cat >"$fixture/mock-bin/git" <<'MOCK'
#!/usr/bin/env sh
set -eu
case "${FIXTURE_GIT_MODE:-}:$1:${2:-}" in
  source:rev-parse:HEAD|tree:rev-parse:HEAD\^\{tree\}) exit 0 ;;
  missing-commit:cat-file:-e) exit 1 ;;
  archive:archive:*) exit 1 ;;
esac
exec "$REAL_GIT" "$@"
MOCK
cat >"$fixture/mock-bin/sha256sum" <<'MOCK'
#!/usr/bin/env sh
set -eu
if [ "$#" -gt 0 ]; then
  for value do file=$value; done
  case "${FIXTURE_CONTEXT_SHA_MODE:-}:$file" in
    missing:*git-tree-context.tar) printf '%s\n' invalid-sha ;;
    *) shasum -a 256 "$file" ;;
  esac
else
  shasum -a 256
fi
MOCK
cat >"$fixture/mock-bin/uname" <<'MOCK'
#!/usr/bin/env sh
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) exit 1 ;;
esac
MOCK
cat >"$fixture/mock-bin/stat" <<'MOCK'
#!/usr/bin/env sh
set -eu
[ "$1" = -c ] && [ "$2" = '%a' ] || exit 40
exec "$REAL_STAT" -f '%Lp' "$3"
MOCK
for protected_tool in ssh tofu terraform hcloud cloudflare curl gh; do
  cat >"$fixture/mock-bin/$protected_tool" <<'MOCK'
#!/usr/bin/env sh
printf '%s\n' "${0##*/} $*" >>"$FIXTURE_ROOT/external-call-ledger"
exit 99
MOCK
  chmod 700 "$fixture/mock-bin/$protected_tool"
done
chmod 700 "$hook"/*.sh "$fixture/mock-bin/"*
mkdir -m 700 "$fixture/recovery-outside-check"

export PATH="$fixture/mock-bin:$PATH"
run_case() {
  name=$1 expected=$2
  shift 2
  result=$fixture/$name.json
  if env "$@" "$root/tooling/verify-phase-2-gate-b.sh" "$result" >"$fixture/$name.stdout" 2>"$fixture/$name.stderr"; then
    status=0
  else status=$?; fi
  if [ "$expected" = pass ]; then
    [ "$status" -eq 0 ] || die "$name should pass, got $status: $(cat "$fixture/$name.stderr")"
    [ -f "$result" ] || die "$name did not create sanitized evidence"
    jq -e --arg source "$source_sha" --arg tree "$(git -C "$root" rev-parse 'HEAD^{tree}')" \
      --arg context "$baseline_sha" --arg id "$config_id" \
      '.status=="CI_ROUTE_READY" and .source_commit_sha==$source and .source_tree_sha==$tree and
       .context_tar_sha256==$context and .config_image_id==$id and .deployed_image_id==$id and .synthetic_recovery==true' \
      "$result" >/dev/null || die "$name result did not bind source/tree/context/image/recovery"
    [ "$(cat "$fixture/$name.stdout")" = 'phase-2-gate-b status=CI_ROUTE_READY synthetic_recovery=true' ] || die "$name emitted an unbounded status"
  else
    [ "$status" -ne 0 ] || die "$name should fail closed"
    [ ! -e "$result" ] || die "$name wrote passing evidence after refusal"
  fi
}

run_case positive pass
[ "$(sha_file "$fixture/baseline.tar")" = "$baseline_sha" ] || die 'build inputs changed the immutable Git archive digest'
run_case broad-archive-mode fail FIXTURE_ARCHIVE_MODE=644
run_case bad-revision fail FIXTURE_BAD_CONTRACT=revision
run_case missing-revision fail FIXTURE_BAD_CONTRACT=missing-revision
run_case bad-archive fail FIXTURE_BAD_CONTRACT=archive
run_case missing-archive-checksum fail FIXTURE_BAD_CONTRACT=missing-archive
run_case bad-config fail FIXTURE_BAD_CONTRACT=config
run_case bad-rootfs fail FIXTURE_BAD_CONTRACT=rootfs
run_case bad-archive-platform fail FIXTURE_BAD_CONTRACT=platform
run_case bad-deployed-id fail FIXTURE_DEPLOYED_ID=sha256:4444444444444444444444444444444444444444444444444444444444444444
run_case bad-recovery fail FIXTURE_RECOVERY=semantic
run_case missing-recovery fail FIXTURE_RECOVERY=missing
run_case privacy-refusal fail FIXTURE_PRIVACY=refuse
run_case wrong-reloaded-label fail FIXTURE_DOCKER_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run_case wrong-reloaded-platform fail FIXTURE_DOCKER_PLATFORM=linux/arm64
run_case wrong-reloaded-rootfs fail FIXTURE_DOCKER_ROOTFS_ID=sha256:7777777777777777777777777777777777777777777777777777777777777777
run_case missing-source-sha fail FIXTURE_GIT_MODE=source
run_case missing-tree-sha fail FIXTURE_GIT_MODE=tree
run_case missing-commit fail FIXTURE_GIT_MODE=missing-commit
run_case missing-context-archive fail FIXTURE_GIT_MODE=archive
run_case missing-context-sha fail FIXTURE_CONTEXT_SHA_MODE=missing

# Host architecture must fail before any image/export/deploy hook runs.
cat >"$fixture/mock-bin/uname" <<'MOCK'
#!/usr/bin/env sh
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' aarch64 ;;
  *) exit 1 ;;
esac
MOCK
chmod 700 "$fixture/mock-bin/uname"
run_case wrong-host fail
rm "$fixture/mock-bin/uname"

[ "$(cat "$fixture/build-count")" -eq 16 ] || die 'unexpected number of image builds occurred in cases reaching the image verifier'
[ "$(sha_file "$fixture/baseline.tar")" = "$baseline_sha" ] || die 'fixture inputs changed the immutable context digest'
[ ! -s "$fixture/external-call-ledger" ] || die 'fixture recorded a forbidden external action'
printf '%s\n' 'Gate B route fixtures passed: cases=22 positive=1 refused=21 external_calls=0'
