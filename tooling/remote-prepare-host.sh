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
exec 3>&2
exec >/dev/null 2>&1
report_exit() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$completed" != true ]; then
    printf 'REMOTE_PREPARE_FAILED_STAGE=%s RC=%s\n' "$failure_stage" "$failure_code" >&3
    exit "$failure_code"
  fi
  exit "$result"
}
trap report_exit EXIT HUP INT TERM

case "$expected_archive_sha:$expected_image_id:$expected_revision:$expected_architecture" in
  *[!a-zA-Z0-9:._-]*) exit "$failure_code" ;;
esac
printf '%s' "$expected_archive_sha" | grep -Eq '^[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_image_id" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit "$failure_code"
printf '%s' "$expected_revision" | grep -Eq '^[0-9a-f]{7,64}$' || exit "$failure_code"
[ "$expected_architecture" = amd64 ] || exit "$failure_code"

stage() { failure_stage=$1; failure_code=$2; }

if [ "${KEEPLING_REMOTE_PREPARE_TEST_MODE:-}" = yes ]; then
  for test_stage in volume-device volume-mount filesystem archive-integrity image-load image-id image-revision image-architecture runtime-config db-start db-ready restore epoch runtime; do
    case "$test_stage" in
      volume-device) test_code=41 ;; volume-mount) test_code=42 ;; filesystem) test_code=43 ;;
      archive-integrity) test_code=44 ;; image-load) test_code=45 ;; image-id) test_code=46 ;;
      image-revision) test_code=47 ;; image-architecture) test_code=48 ;; runtime-config) test_code=49 ;;
      db-start) test_code=50 ;; db-ready) test_code=51 ;; restore) test_code=52 ;;
      epoch) test_code=53 ;; runtime) test_code=54 ;;
    esac
    stage "$test_stage" "$test_code"
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
docker load -i /root/image.tar.gz
stage image-id 46
image_id=$(docker image inspect keepling-server:plan-02-09-amd64 --format '{{.Id}}')
[ "$image_id" = "$expected_image_id" ]
stage image-revision 47
image_revision=$(docker image inspect keepling-server:plan-02-09-amd64 --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
[ "$image_revision" = "$expected_revision" ]
stage image-architecture 48
image_architecture=$(docker image inspect keepling-server:plan-02-09-amd64 --format '{{.Architecture}}')
[ "$image_architecture" = "$expected_architecture" ]

stage runtime-config 49
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

stage db-start 50
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal up -d db
stage db-ready 51
attempt=0
until docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db pg_isready -U keepling -d keepling; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || exit "$failure_code"
  sleep 2
done
stage restore 52
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  pg_restore -U keepling -d keepling --clean --if-exists --no-owner --no-privileges --exit-on-error \
  </srv/keepling/recovery/recovery.dump
stage epoch 53
old_epoch=$(docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  psql -U keepling -d keepling -Atc 'SELECT epoch FROM sync_epochs WHERE singleton_key=TRUE' | tr -d '\r')
new_epoch=$(docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal exec -T db \
  psql -U keepling -d keepling -Atc 'UPDATE sync_epochs SET epoch=gen_random_uuid(), finalized=TRUE, updated_at=NOW() WHERE singleton_key=TRUE RETURNING epoch' | sed -n '1p' | tr -d '\r')
[ -n "$old_epoch" ] && [ -n "$new_epoch" ] && [ "$old_epoch" != "$new_epoch" ]
printf '%s' "$new_epoch" >/srv/keepling/recovery/rotated-epoch
chmod 600 /srv/keepling/recovery/rotated-epoch
stage runtime 54
docker compose -f infra/compose/compose.yml -f infra/compose/override.yml -p keepling-rehearsal up -d --wait
completed=true
printf '%s\n' 'REMOTE_PREPARE_STAGE=ready' >&3
