#!/bin/sh
set -eu

[ "$#" -eq 7 ] || {
  printf '%s\n' 'REMOTE_PREPARE_FAILED_STAGE=contract RC=40' >&2
  exit 40
}
volume_id=$1
expected_archive_sha=$2
expected_image_id=$3
expected_revision=$4
expected_architecture=$5
runtime_host=$6
tested_manifest_digest=$7

failure_stage=contract
failure_code=40
completed=false
load_rc=not-run inspect_rc=not-run observed_id_shape=empty observed_id_match=false
revision_shape=empty revision_match=false architecture_shape=empty architecture_match=false
exec 3>&2
exec >/dev/null 2>&1
report_exit() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$completed" != true ]; then
    printf 'REMOTE_PREPARE_FAILED_STAGE=%s RC=%s LOAD=%s INSPECT=%s ID_SHAPE=%s ID_MATCH=%s REV_SHAPE=%s REV_MATCH=%s ARCH_SHAPE=%s ARCH_MATCH=%s\n' \
      "$failure_stage" "$failure_code" "$load_rc" "$inspect_rc" "$observed_id_shape" "$observed_id_match" \
      "$revision_shape" "$revision_match" "$architecture_shape" "$architecture_match" >&3
    exit "$failure_code"
  fi
  exit "$result"
}
trap report_exit EXIT HUP INT TERM

case "$expected_archive_sha:$expected_image_id:$expected_revision:$expected_architecture" in
  *[!a-zA-Z0-9:._-]*) exit "$failure_code" ;;
esac
case "$volume_id:$runtime_host:$tested_manifest_digest" in
  *[!a-zA-Z0-9:._-]*) exit "$failure_code" ;;
esac
printf '%s' "$volume_id" | grep -Eq '^[1-9][0-9]*$' || exit "$failure_code"
printf '%s' "$expected_archive_sha" | grep -Eq '^[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_image_id" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_revision" | grep -Eq '^[0-9a-f]{7,64}$' || exit "$failure_code"
[ "$expected_architecture" = amd64 ] || exit "$failure_code"
printf '%s' "$runtime_host" | grep -Eq '^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$' || exit "$failure_code"
if printf '%s' "$runtime_host" | grep -F '..' >/dev/null; then exit "$failure_code"; fi
printf '%s' "$tested_manifest_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"

stage() { failure_stage=$1; failure_code=$2; }
id_shape() { if [ -z "$1" ]; then printf empty; elif printf '%s' "$1" | grep -Eq '^sha256:[0-9a-f]{64}$'; then printf sha256-64; else printf other; fi; }
revision_value_shape() { if [ -z "$1" ]; then printf empty; elif printf '%s' "$1" | grep -Eq '^[0-9a-f]{7,64}$'; then printf hex-7-64; else printf other; fi; }
architecture_value_shape() { if [ -z "$1" ]; then printf empty; elif [ "$1" = amd64 ]; then printf amd64; else printf other; fi; }
docker_bin=${KEEPLING_REMOTE_PREPARE_DOCKER_BIN:-docker}
docker_command() { "$docker_bin" "$@"; }
verify_loaded_image() {
  stage image-inspect 46
  if image_id=$(docker_command image inspect "$expected_image_id" --format '{{.Id}}'); then inspect_rc=zero; else inspect_rc=nonzero; exit "$failure_code"; fi
  observed_id_shape=$(id_shape "$image_id")
  stage image-id-compare 47
  [ "$image_id" = "$expected_image_id" ]
  observed_id_match=true
  stage image-revision 48
  image_revision=$(docker_command image inspect "$expected_image_id" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
  revision_shape=$(revision_value_shape "$image_revision")
  [ "$image_revision" = "$expected_revision" ]
  revision_match=true
  stage image-architecture 49
  image_architecture=$(docker_command image inspect "$expected_image_id" --format '{{.Architecture}}')
  architecture_shape=$(architecture_value_shape "$image_architecture")
  [ "$image_architecture" = "$expected_architecture" ]
  architecture_match=true
}

if [ "${KEEPLING_REMOTE_PREPARE_DOCKER_BOUNDARY_TEST:-}" = yes ]; then
  load_rc=ok
  verify_loaded_image
  completed=true
  printf '%s\n' 'REMOTE_PREPARE_STAGE=ready' >&3
  exit 0
fi

if [ "${KEEPLING_REMOTE_PREPARE_TEST_MODE:-}" = yes ]; then
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ID+x}" = x ]; then observed_test_id=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ID; else observed_test_id=$expected_image_id; fi
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_REVISION+x}" = x ]; then observed_test_revision=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_REVISION; else observed_test_revision=$expected_revision; fi
  if [ "${KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ARCHITECTURE+x}" = x ]; then observed_test_architecture=$KEEPLING_REMOTE_PREPARE_TEST_OBSERVED_ARCHITECTURE; else observed_test_architecture=$expected_architecture; fi
  for test_stage in volume-device volume-mount filesystem archive-integrity image-load image-inspect image-id-compare image-revision image-architecture runtime-config db-start db-ready restore epoch runtime; do
    case "$test_stage" in
      volume-device) test_code=41 ;; volume-mount) test_code=42 ;; filesystem) test_code=43 ;;
      archive-integrity) test_code=44 ;; image-load) test_code=45 ;; image-inspect) test_code=46 ;;
      image-id-compare) test_code=47 ;; image-revision) test_code=48 ;; image-architecture) test_code=49 ;;
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
      image-id-compare) [ "$observed_test_id" = "$expected_image_id" ] && observed_id_match=true || observed_id_match=false ;;
      image-revision) revision_shape=$(revision_value_shape "$observed_test_revision"); [ "$observed_test_revision" = "$expected_revision" ] && revision_match=true || revision_match=false ;;
      image-architecture) architecture_shape=$(architecture_value_shape "$observed_test_architecture"); [ "$observed_test_architecture" = "$expected_architecture" ] && architecture_match=true || architecture_match=false ;;
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
stage image-load 45
if docker_command load -i /root/image.tar.gz; then load_rc=ok; else load_rc=nonzero; exit "$failure_code"; fi
verify_loaded_image

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
KEEPLING_SERVER_IMAGE=$image_id
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
