#!/bin/sh
set -eu

[ "$#" -eq 9 ] || {
  printf '%s\n' 'REMOTE_PREPARE_FAILED_STAGE=contract RC=40' >&2
  exit 40
}
volume_id=$1
expected_archive_sha=$2
expected_config_image_id=$3
expected_manifest_digest=$4
expected_revision=$5
expected_architecture=$6
expected_rootfs_diff_ids=$7
runtime_host=$8
tested_manifest_digest=$9

failure_stage=contract
failure_code=40
completed=false
load_rc=not-run inspect_rc=not-run observed_id_shape=empty observed_id_match=false
revision_shape=empty revision_match=false architecture_shape=empty architecture_match=false
inventory_before=not-run inventory_after=not-run inventory_delta=not-run
descriptor_state=not-run descriptor_match=false rootfs_shape=empty rootfs_match=false
exec 3>&2
exec >/dev/null 2>&1
report_exit() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$completed" != true ]; then
    printf 'REMOTE_PREPARE_FAILED_STAGE=%s RC=%s BEFORE=%s LOAD=%s AFTER=%s DELTA=%s INSPECT=%s ID_SHAPE=%s ID_MATCH=%s DESC=%s DESC_MATCH=%s REV_SHAPE=%s REV_MATCH=%s ARCH_SHAPE=%s ARCH_MATCH=%s ROOTFS_SHAPE=%s ROOTFS_MATCH=%s\n' \
      "$failure_stage" "$failure_code" "$inventory_before" "$load_rc" "$inventory_after" "$inventory_delta" "$inspect_rc" "$observed_id_shape" "$observed_id_match" \
      "$descriptor_state" "$descriptor_match" "$revision_shape" "$revision_match" "$architecture_shape" "$architecture_match" "$rootfs_shape" "$rootfs_match" >&3
    exit "$failure_code"
  fi
  exit "$result"
}
trap report_exit EXIT HUP INT TERM

case "$expected_archive_sha:$expected_config_image_id:$expected_manifest_digest:$expected_revision:$expected_architecture:$expected_rootfs_diff_ids" in
  *[!a-zA-Z0-9:,._-]*) exit "$failure_code" ;;
esac
case "$volume_id:$runtime_host:$tested_manifest_digest" in
  *[!a-zA-Z0-9:._-]*) exit "$failure_code" ;;
esac
printf '%s' "$volume_id" | grep -Eq '^[1-9][0-9]*$' || exit "$failure_code"
printf '%s' "$expected_archive_sha" | grep -Eq '^[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_config_image_id" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_manifest_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_revision" | grep -Eq '^[0-9a-f]{7,64}$' || exit "$failure_code"
[ "$expected_architecture" = amd64 ] || exit "$failure_code"
printf '%s' "$expected_rootfs_diff_ids" | grep -Eq '^sha256:[0-9a-f]{64}(,sha256:[0-9a-f]{64})*$' || exit "$failure_code"
printf '%s' "$runtime_host" | grep -Eq '^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$' || exit "$failure_code"
if printf '%s' "$runtime_host" | grep -F '..' >/dev/null; then exit "$failure_code"; fi
printf '%s' "$tested_manifest_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"

stage() { failure_stage=$1; failure_code=$2; }
validate_recovery_provenance() {
  [ "${KEEPLING_REMOTE_PREPARE_PROVENANCE_REQUIRED:-}" = yes ] || return 0
  dump=/root/recovery.dump provenance=/root/recovery.provenance.json
  [ -f "$dump" ] && [ -f "$provenance" ] && [ ! -L "$dump" ] && [ ! -L "$provenance" ] || return 1
  jq -e '
    type == "object" and .version == 1 and
    if .source_kind == "synthetic-rehearsal" then
      (keys|sort)==["plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and
      (.plaintext_sha256|type == "string" and test("^[0-9a-f]{64}$")) and
      (.plaintext_bytes|type == "number" and . > 0 and floor == .) and
      (.verification|type == "object" and (keys|sort)==["local_capture","local_restore","synthetic"] and .local_capture == true and .local_restore == true and .synthetic == true)
    else
      (.source_kind == "b2-primary" or .source_kind == "r2-mirror") and
      (.plaintext_sha256|type == "string" and test("^[0-9a-f]{64}$")) and
      (.plaintext_bytes|type == "number" and . >= 0 and floor == .) and
      (.verification|.head == true and .get == true and .package_manifest == true and .decrypt == true and .plaintext == true)
    end
  ' "$provenance" >/dev/null 2>&1 || return 1
  [ "$(shasum -a 256 "$dump" | awk '{print $1}')" = "$(jq -r .plaintext_sha256 "$provenance")" ] && [ "$(wc -c <"$dump" | tr -d ' ')" = "$(jq -r .plaintext_bytes "$provenance")" ]
}
id_shape() { if [ -z "$1" ]; then printf empty; elif printf '%s' "$1" | grep -Eq '^sha256:[0-9a-f]{64}$'; then printf sha256-64; else printf other; fi; }
revision_value_shape() { if [ -z "$1" ]; then printf empty; elif printf '%s' "$1" | grep -Eq '^[0-9a-f]{7,64}$'; then printf hex-7-64; else printf other; fi; }
architecture_value_shape() { if [ -z "$1" ]; then printf empty; elif [ "$1" = amd64 ]; then printf amd64; else printf other; fi; }
rootfs_value_shape() { if [ -z "$1" ]; then printf empty; elif printf '%s' "$1" | grep -Eq '^sha256:[0-9a-f]{64}(,sha256:[0-9a-f]{64})*$'; then printf digest-list; else printf other; fi; }
docker_bin=${KEEPLING_REMOTE_PREPARE_DOCKER_BIN:-docker}
docker_command() { "$docker_bin" "$@"; }
normalize_inventory() {
  inventory_raw=$1
  [ "${#inventory_raw}" -le 65536 ] || return 2
  [ -n "$inventory_raw" ] || return 0
  inventory_lines=$(printf '%s\n' "$inventory_raw" | awk 'END { print NR }')
  [ "$inventory_lines" -le 256 ] || return 3
  if printf '%s\n' "$inventory_raw" | grep -Ev '^(sha256:[0-9a-f]{64})?$' >/dev/null; then return 4; fi
  printf '%s\n' "$inventory_raw" | awk 'length' | sort -u
}
inventory_failure_state() { case "$1" in 2) printf oversized ;; 3) printf too-many ;; *) printf invalid ;; esac; }
load_and_verify_image() {
  stage image-inventory-before 56
  if inventory_before_raw=$(docker_command image ls --no-trunc --quiet); then :; else inventory_before=command-failed; exit "$failure_code"; fi
  if inventory_before_ids=$(normalize_inventory "$inventory_before_raw"); then inventory_before=ok; else inventory_rc=$?; inventory_before=$(inventory_failure_state "$inventory_rc"); exit "$failure_code"; fi
  stage image-load 45
  if docker_command load -i /root/image.tar.gz; then load_rc=ok; else load_rc=nonzero; exit "$failure_code"; fi
  stage image-inventory-after 57
  if inventory_after_raw=$(docker_command image ls --no-trunc --quiet); then :; else inventory_after=command-failed; exit "$failure_code"; fi
  if inventory_after_ids=$(normalize_inventory "$inventory_after_raw"); then inventory_after=ok; else inventory_rc=$?; inventory_after=$(inventory_failure_state "$inventory_rc"); exit "$failure_code"; fi
  stage image-delta 58
  observed_loaded_ids=$(printf '%s\n--\n%s\n' "$inventory_before_ids" "$inventory_after_ids" | awk '$0 == "--" { after=1; next } !after && length { before[$0]=1; next } after && length && !before[$0] { print }')
  observed_loaded_count=$(if [ -n "$observed_loaded_ids" ]; then printf '%s\n' "$observed_loaded_ids" | awk 'END { print NR }'; else printf 0; fi)
  case "$observed_loaded_count" in 0) inventory_delta=zero; exit "$failure_code" ;; 1) inventory_delta=one ;; *) inventory_delta=multiple; exit "$failure_code" ;; esac
  observed_loaded_id=$observed_loaded_ids
  stage image-inspect 46
  if image_id=$(docker_command image inspect "$observed_loaded_id" --format '{{.Id}}'); then inspect_rc=zero; else inspect_rc=nonzero; exit "$failure_code"; fi
  observed_id_shape=$(id_shape "$image_id")
  stage image-id-compare 47
  [ "$image_id" = "$expected_config_image_id" ] || exit "$failure_code"
  observed_id_match=true
  stage image-descriptor 59
  if image_descriptor=$(docker_command image inspect "$observed_loaded_id" --format '{{if .Descriptor}}{{.Descriptor.Digest}}{{end}}' 2>/dev/null); then
    if [ -z "$image_descriptor" ]; then
      descriptor_state=absent
    elif printf '%s' "$image_descriptor" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
      descriptor_state=present
      [ "$image_descriptor" = "$expected_manifest_digest" ] || exit "$failure_code"
      descriptor_match=true
    else
      descriptor_state=invalid; exit "$failure_code"
    fi
  else
    descriptor_state=absent
  fi
  stage image-revision 48
  image_revision=$(docker_command image inspect "$observed_loaded_id" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
  revision_shape=$(revision_value_shape "$image_revision")
  [ "$image_revision" = "$expected_revision" ]
  revision_match=true
  stage image-architecture 49
  image_architecture=$(docker_command image inspect "$observed_loaded_id" --format '{{.Architecture}}')
  architecture_shape=$(architecture_value_shape "$image_architecture")
  [ "$image_architecture" = "$expected_architecture" ]
  architecture_match=true
  stage image-rootfs 60
  image_rootfs=$(docker_command image inspect "$observed_loaded_id" --format '{{join .RootFS.Layers ","}}')
  rootfs_shape=$(rootfs_value_shape "$image_rootfs")
  [ "$image_rootfs" = "$expected_rootfs_diff_ids" ] || exit "$failure_code"
  rootfs_match=true
}

if [ "${KEEPLING_REMOTE_PREPARE_DOCKER_BOUNDARY_TEST:-}" = yes ]; then
  load_and_verify_image
  completed=true
  printf '%s\n' 'REMOTE_PREPARE_STAGE=ready' >&3
  exit 0
fi

stage provenance 39
validate_recovery_provenance || exit "$failure_code"

if [ "${KEEPLING_REMOTE_PREPARE_TEST_MODE:-}" = yes ]; then
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ID+x}" = x ]; then observed_test_id=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ID; else observed_test_id=$expected_config_image_id; fi
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_REVISION+x}" = x ]; then observed_test_revision=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_REVISION; else observed_test_revision=$expected_revision; fi
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ARCHITECTURE+x}" = x ]; then observed_test_architecture=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ARCHITECTURE; else observed_test_architecture=$expected_architecture; fi
  for test_stage in volume-device volume-mount filesystem archive-integrity image-load image-inspect image-id-compare image-descriptor image-revision image-architecture image-rootfs runtime-config db-start db-ready restore epoch runtime; do
    case "$test_stage" in
      volume-device) test_code=41 ;; volume-mount) test_code=42 ;; filesystem) test_code=43 ;;
      archive-integrity) test_code=44 ;; image-load) test_code=45 ;; image-inspect) test_code=46 ;;
      image-id-compare) test_code=47 ;; image-revision) test_code=48 ;; image-architecture) test_code=49 ;;
      image-descriptor) test_code=59 ;; image-rootfs) test_code=60 ;;
      runtime-config) test_code=50 ;; db-start) test_code=51 ;; db-ready) test_code=52 ;; restore) test_code=53 ;;
      epoch) test_code=54 ;; runtime) test_code=55 ;;
    esac
    stage "$test_stage" "$test_code"
    case "$test_stage" in
      image-load) if [ "${KEEPLING_REMOTE_PREPARE_TEST_FAILURE_STAGE:-}" = image-load ]; then load_rc=nonzero; else load_rc=ok; fi ;;
      image-inspect)
        if [ "${KEEPLING_REMOTE_PREPARE_TEST_INSPECT_RC:-zero}" = nonzero ]; then
          inspect_rc=nonzero
        else
          inspect_rc=zero; observed_id_shape=$(id_shape "$observed_test_id")
        fi
        ;;
      image-id-compare) [ "$observed_test_id" = "$expected_config_image_id" ] && observed_id_match=true || observed_id_match=false ;;
      image-descriptor) descriptor_state=present; descriptor_match=true ;;
      image-revision) revision_shape=$(revision_value_shape "$observed_test_revision"); [ "$observed_test_revision" = "$expected_revision" ] && revision_match=true || revision_match=false ;;
      image-architecture) architecture_shape=$(architecture_value_shape "$observed_test_architecture"); [ "$observed_test_architecture" = "$expected_architecture" ] && architecture_match=true || architecture_match=false ;;
      image-rootfs) rootfs_shape=digest-list; rootfs_match=true ;;
    esac
    [ "${KEEPLING_REMOTE_PREPARE_TEST_FAILURE_STAGE:-}" != "$test_stage" ] || exit "$failure_code"
  done
  completed=true
  printf '%s\n' 'REMOTE_PREPARE_STAGE=ready' >&3
  exit 0
fi

stage volume-device 41
device="/dev/disk/by-id/scsi-0HC_Volume_${volume_id}"
attempt=0
while [ ! -b "$device" ]; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || exit "$failure_code"
  sleep 2
done

stage volume-mount 42
mkdir -p /srv/keepling
if ! mountpoint -q /srv/keepling; then mount "$device" /srv/keepling; fi

stage filesystem 43
mkdir -p /srv/keepling/data/postgres /srv/keepling/data/caddy/data /srv/keepling/data/caddy/config \
  /srv/keepling/infra/compose /srv/keepling/infra/caddy /srv/keepling/secrets /srv/keepling/recovery
chmod 700 /srv/keepling/secrets /srv/keepling/recovery
chown -R 999:999 /srv/keepling/data/postgres
chown -R 1000:1000 /srv/keepling/data/caddy

stage archive-integrity 44
[ "$(sha256sum /root/image.tar.gz | awk '{print $1}')" = "$expected_archive_sha" ]
load_and_verify_image

stage runtime-config 50
install -m 0644 /root/compose.yml /srv/keepling/infra/compose/compose.yml
install -m 0600 /root/compose-override.yml /srv/keepling/infra/compose/override.yml
install -m 0644 /root/Caddyfile /srv/keepling/infra/caddy/Caddyfile
install -m 0600 /root/recovery.dump /srv/keepling/recovery/recovery.dump
install -m 0600 /root/new-login-credential /srv/keepling/recovery/new-login-credential
postgres_password=$(openssl rand -hex 32)
printf '%s' "$postgres_password" >/srv/keepling/secrets/postgres-password
at_sign=$(printf '\100')
printf 'ecto://keepling:%s%spostgres:5432/keepling' "$postgres_password" "$at_sign" >/srv/keepling/secrets/database-url
openssl rand -hex 64 >/srv/keepling/secrets/secret-key-base
openssl rand -hex 32 >/srv/keepling/secrets/operator-token
chmod 600 /srv/keepling/secrets/*
cat >/srv/keepling/runtime.env <<EOF
KEEPLING_SERVER_IMAGE=$observed_loaded_id
KEEPLING_SERVER_DIGEST=$tested_manifest_digest
KEEPLING_HOST=$runtime_host
KEEPLING_POSTGRES_DATA_DIR=/srv/keepling/data/postgres
KEEPLING_CADDY_DATA_DIR=/srv/keepling/data/caddy/data
KEEPLING_CADDY_CONFIG_DIR=/srv/keepling/data/caddy/config
KEEPLING_POSTGRES_PASSWORD_FILE=/srv/keepling/secrets/postgres-password
KEEPLING_DATABASE_URL_FILE=/srv/keepling/secrets/database-url
KEEPLING_SECRET_KEY_BASE_FILE=/srv/keepling/secrets/secret-key-base
KEEPLING_OPERATOR_TOKEN_FILE=/srv/keepling/secrets/operator-token
KEEPLING_HTTP_BIND=0.0.0.0:80
KEEPLING_HTTPS_BIND=0.0.0.0:443
EOF
chmod 600 /srv/keepling/runtime.env
cd /srv/keepling
set -a
# shellcheck disable=SC1091 # runtime.env is created immediately above on the replacement host.
. ./runtime.env
set +a

stage db-start 51
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal up -d db
stage db-ready 52
attempt=0
until docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db pg_isready -U keepling -d keepling; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || exit "$failure_code"
  sleep 2
done
stage restore 53
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  pg_restore -U keepling -d keepling --clean --if-exists --no-owner --no-privileges --exit-on-error \
  </srv/keepling/recovery/recovery.dump
stage epoch 54
old_epoch=$(docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  psql -U keepling -d keepling -Atc 'SELECT epoch FROM sync_epochs WHERE singleton_key=TRUE' | tr -d '\r')
new_epoch=$(docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  psql -U keepling -d keepling -Atc 'UPDATE sync_epochs SET epoch=gen_random_uuid(), finalized=TRUE, updated_at=NOW() WHERE singleton_key=TRUE RETURNING epoch' | sed -n '1p' | tr -d '\r')
[ -n "$old_epoch" ] && [ -n "$new_epoch" ] && [ "$old_epoch" != "$new_epoch" ]
printf '%s' "$new_epoch" >/srv/keepling/recovery/rotated-epoch
chmod 600 /srv/keepling/recovery/rotated-epoch
stage runtime 55
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal up -d --wait
completed=true
printf '%s\n' 'REMOTE_PREPARE_STAGE=ready' >&3
