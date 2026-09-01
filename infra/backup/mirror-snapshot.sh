#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/../.." && pwd)

die() {
  echo "Mirror snapshot failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"
}

endpoint_url() {
  case "$1" in
    http://*|https://*) printf '%s' "$1" ;;
    *) printf 'https://%s' "$1" ;;
  esac
}

json_value() {
  _jv_document=$1
  _jv_field=$2
  _jv_file_field=${_jv_field}_file
  _jv_direct=$(jq -r --arg field "$_jv_field" '.[$field] // empty' "$_jv_document")
  if [ -n "$_jv_direct" ]; then
    printf '%s' "$_jv_direct"
    return
  fi
  _jv_secret_file=$(jq -r --arg field "$_jv_file_field" '.[$field] // empty' "$_jv_document")
  [ -n "$_jv_secret_file" ] && [ -r "$_jv_secret_file" ] || die "credential document omits readable $_jv_field"
  case "$_jv_secret_file" in
    "$repository_root"|"$repository_root"/*) die "credential material must remain outside the repository" ;;
  esac
  cat "$_jv_secret_file"
}

with_store() {
  _ws_document=$1
  shift
  [ -r "$_ws_document" ] || die "credential document is unreadable"
  _ws_access_key=$(json_value "$_ws_document" access_key_id)
  _ws_secret_key=$(json_value "$_ws_document" secret_access_key)
  _ws_region=$(json_value "$_ws_document" region)
  AWS_ACCESS_KEY_ID=$_ws_access_key AWS_SECRET_ACCESS_KEY=$_ws_secret_key AWS_DEFAULT_REGION=$_ws_region "$@"
}

store_head() {
  _sh_document=$1 _sh_bucket=$2 _sh_object_key=$3 _sh_endpoint=$4
  if [ -n "${MIRROR_SNAPSHOT_FIXTURE_ROOT:-}" ]; then
    [ -f "$MIRROR_SNAPSHOT_FIXTURE_ROOT/objects/$_sh_object_key" ] || return 1
    cat "$MIRROR_SNAPSHOT_FIXTURE_ROOT/metadata/$_sh_object_key.json"
  else
    with_store "$_sh_document" aws s3api head-object --bucket "$_sh_bucket" --key "$_sh_object_key" --endpoint-url "$_sh_endpoint"
  fi
}

store_put() {
  _sp_document=$1 _sp_bucket=$2 _sp_object_key=$3 _sp_source_file=$4 _sp_snapshot_sha=$5 _sp_endpoint=$6
  if [ -n "${MIRROR_SNAPSHOT_FIXTURE_ROOT:-}" ]; then
    [ ! -e "$MIRROR_SNAPSHOT_FIXTURE_ROOT/objects/$_sp_object_key" ] || die "fixture object already exists"
    mkdir -p "$MIRROR_SNAPSHOT_FIXTURE_ROOT/objects/$(dirname "$_sp_object_key")" \
      "$MIRROR_SNAPSHOT_FIXTURE_ROOT/metadata/$(dirname "$_sp_object_key")"
    cp "$_sp_source_file" "$MIRROR_SNAPSHOT_FIXTURE_ROOT/objects/$_sp_object_key"
    jq -n --arg sha "$_sp_snapshot_sha" '{Metadata:{"snapshot-sha256":$sha,"snapshot-version":"1"}}' \
      >"$MIRROR_SNAPSHOT_FIXTURE_ROOT/metadata/$_sp_object_key.json"
  else
    with_store "$_sp_document" aws s3api put-object \
      --bucket "$_sp_bucket" --key "$_sp_object_key" --body "$_sp_source_file" \
      --metadata "snapshot-sha256=$_sp_snapshot_sha,snapshot-version=1" \
      --endpoint-url "$_sp_endpoint" >/dev/null
  fi
}

store_get() {
  _sg_document=$1 _sg_bucket=$2 _sg_object_key=$3 _sg_destination=$4 _sg_endpoint=$5
  if [ -n "${MIRROR_SNAPSHOT_FIXTURE_ROOT:-}" ]; then
    cp "$MIRROR_SNAPSHOT_FIXTURE_ROOT/objects/$_sg_object_key" "$_sg_destination"
  else
    with_store "$_sg_document" aws s3api get-object \
      --bucket "$_sg_bucket" --key "$_sg_object_key" --endpoint-url "$_sg_endpoint" "$_sg_destination" >/dev/null
  fi
}

publish_snapshot() {
  [ "$#" -eq 2 ] || die "usage: publish VERIFIED_SOURCE_DIRECTORY EVIDENCE_DIRECTORY"
  source_dir=$1
  evidence_dir=$2
  [ -n "${KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE:-}" ] || die "mirror credential reference is missing"
  [ -d "$source_dir" ] && [ -n "$(find "$source_dir" -type f -print -quit)" ] ||
    die "verified source directory must exist and contain recovery objects"
  [ -d "$evidence_dir" ] && [ -z "$(find "$evidence_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
    die "evidence directory must exist and be empty"

  mirror_bucket=$(json_value "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" bucket)
  mirror_endpoint=$(endpoint_url "$(json_value "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" endpoint)")

  private_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-mirror.XXXXXX")
  cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    case "$private_root" in
      "${TMPDIR:-/tmp}"/keepling-mirror.*) rm -rf -- "$private_root" ;;
      *) die "refused unsafe cleanup" ;;
    esac
    exit "$result"
  }
  trap cleanup EXIT HUP INT TERM
  chmod 700 "$private_root"
  mkdir "$private_root/repository"

  (
    cd "$source_dir"
    find . -type f -print0 | sort -z | xargs -0 shasum -a 256
  ) >"$private_root/source-before.sha256"
  cp -R "$source_dir"/. "$private_root/repository/"
  (
    cd "$source_dir"
    find . -type f -print0 | sort -z | xargs -0 shasum -a 256
  ) >"$private_root/source-after.sha256"
  cmp -s "$private_root/source-before.sha256" "$private_root/source-after.sha256" ||
    die "verified recovery source changed while it was captured"
  object_count=$(find "$private_root/repository" -type f | wc -l | tr -d ' ')
  [ "$object_count" -gt 0 ] || die "captured recovery snapshot is empty"

  snapshot_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  (
    cd "$private_root"
    find repository -type f -print0 | sort -z | xargs -0 shasum -a 256
  ) >"$private_root/manifest.sha256"
  COPYFILE_DISABLE=1 tar -C "$private_root" -czf "$private_root/snapshot.tar.gz" repository manifest.sha256
  snapshot_sha=$(shasum -a 256 "$private_root/snapshot.tar.gz" | awk '{print $1}')
  snapshot_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
  object_key="snapshots/$(date -u +%Y/%m/%d)/$(date -u +%Y%m%dT%H%M%SZ)-$snapshot_id-$snapshot_sha.tar.gz"

  if store_head "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" "$mirror_bucket" "$object_key" "$mirror_endpoint" >/dev/null 2>&1; then
    die "unique append-only object key already exists"
  fi
  store_put "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" "$mirror_bucket" "$object_key" \
    "$private_root/snapshot.tar.gz" "$snapshot_sha" "$mirror_endpoint"

  jq -n --arg snapshot_at "$snapshot_at" --arg object_key "$object_key" \
    --arg sha256 "$snapshot_sha" --argjson object_count "$object_count" \
    '{version:1,snapshot_at:$snapshot_at,object_key:$object_key,sha256:$sha256,object_count:$object_count,append_only:true}' \
    >"$evidence_dir/mirror-snapshot.json"
  chmod 600 "$evidence_dir/mirror-snapshot.json"
  rm -rf -- "$private_root"
  trap - EXIT HUP INT TERM
  echo "Mirror snapshot passed: encrypted primary captured under one unique append-only object key"
}

restore_snapshot() {
  [ "$#" -eq 2 ] || die "usage: restore EVIDENCE_FILE EMPTY_DESTINATION"
  evidence_file=$1
  destination=$2
  [ -n "${KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE:-}" ] || die "mirror credential reference is missing"
  [ -r "$evidence_file" ] || die "mirror evidence file is unreadable"
  [ -d "$destination" ] && [ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
    die "restore destination must exist and be empty"
  jq -e '.version == 1 and .append_only == true and (.object_key | startswith("snapshots/")) and (.sha256 | test("^[0-9a-f]{64}$"))' \
    "$evidence_file" >/dev/null || die "mirror evidence is invalid"

  mirror_bucket=$(json_value "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" bucket)
  mirror_endpoint=$(endpoint_url "$(json_value "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" endpoint)")
  object_key=$(jq -r '.object_key' "$evidence_file")
  expected_sha=$(jq -r '.sha256' "$evidence_file")
  archive=$(mktemp "${TMPDIR:-/tmp}/keepling-mirror-restore.XXXXXX")
  trap 'rm -f -- "$archive"' EXIT HUP INT TERM
  head=$(store_head "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" "$mirror_bucket" "$object_key" "$mirror_endpoint")
  printf '%s' "$head" | jq -e --arg sha "$expected_sha" '.Metadata["snapshot-sha256"] == $sha' >/dev/null ||
    die "mirror object metadata does not match retained evidence"
  store_get "$KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE" "$mirror_bucket" "$object_key" "$archive" "$mirror_endpoint"
  [ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$expected_sha" ] || die "mirror archive checksum mismatch"
  tar -C "$destination" -xzf "$archive"
  (cd "$destination" && shasum -a 256 -c manifest.sha256 >/dev/null) || die "mirror file manifest mismatch"
  rm -f -- "$archive"
  trap - EXIT HUP INT TERM
  echo "Mirror restore passed: retained append-only snapshot checksum and file manifest verified"
}

self_test() {
  fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-mirror-self-test.XXXXXX")
  trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
  printf '%s' placeholder >"$fixture/secret"
  chmod 600 "$fixture/secret"
  jq -n --arg file "$fixture/secret" \
    '{version:1,access_key_id_file:$file,secret_access_key_file:$file,endpoint:"example.invalid",region:"auto",bucket:"example"}' \
    >"$fixture/credentials.json"
  [ "$(json_value "$fixture/credentials.json" region)" = auto ] || die "direct credential metadata failed"
  [ "$(json_value "$fixture/credentials.json" access_key_id)" = placeholder ] || die "referenced secret failed"
  [ "$(endpoint_url example.invalid)" = https://example.invalid ] || die "endpoint normalization failed"
  mkdir "$fixture/source" "$fixture/evidence" "$fixture/destination" "$fixture/store"
  printf '%s' encrypted-recovery-fixture >"$fixture/source/recovery-object"
  KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$fixture/credentials.json"
  MIRROR_SNAPSHOT_FIXTURE_ROOT="$fixture/store"
  export KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE MIRROR_SNAPSHOT_FIXTURE_ROOT
  "$0" publish "$fixture/source" "$fixture/evidence" >/dev/null
  "$0" restore "$fixture/evidence/mirror-snapshot.json" "$fixture/destination" >/dev/null
  cmp -s "$fixture/source/recovery-object" "$fixture/destination/repository/recovery-object" ||
    die "published mirror snapshot did not restore exactly"
  echo "Mirror snapshot self-test passed"
}

for command in jq shasum tar find sort xargs uuidgen aws; do require_command "$command"; done

case "${1:-}" in
  self-test) [ "$#" -eq 1 ] || die "usage: $0 self-test"; self_test ;;
  publish) shift; publish_snapshot "$@" ;;
  restore) shift; restore_snapshot "$@" ;;
  *) die "usage: $0 self-test | publish VERIFIED_SOURCE_DIRECTORY EVIDENCE_DIRECTORY | restore EVIDENCE_FILE EMPTY_DESTINATION" ;;
esac
