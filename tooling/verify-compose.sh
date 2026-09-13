#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Compose verification failed: $*" >&2
  exit 1
}

for command in docker curl jq; do command -v "$command" >/dev/null 2>&1 || die "required command '$command' is unavailable"; done

image_tag=${KEEPLING_IMAGE_TAG:-keepling-server:plan-02-07}
docker image inspect "$image_tag" >/dev/null 2>&1 || ./tooling/verify-image.sh
image_id=$(docker image inspect "$image_tag" --format '{{.Id}}')
case "$image_id" in sha256:????????????????????????????????????????????????????????????????) ;; *) die "local image ID is not immutable" ;; esac

proof_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-compose-proof.XXXXXX")
project="keepling-proof-$$"
http_port=$((58000 + $$ % 500))
compose='docker compose -f infra/compose/compose.yml'

cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  # A Compose service failing with nothing but `didn't complete successfully:
  # exit 1` is undiagnosable, and teardown destroys the only copy of why. Dump
  # every service's log before removing anything, but only on failure.
  [ "$result" -eq 0 ] || $compose -p "$project" logs --no-color --timestamps >&2 2>/dev/null || true
  $compose -p "$project" down --remove-orphans >/dev/null 2>&1 || true
  # THE STACK WRITES INTO THE BIND MOUNTS AS ROOT. PostgreSQL's data directory
  # and Caddy's data and config directories come back owned by uid 0, so on a
  # Linux engine the invoking user cannot remove them and `rm -rf` below fails
  # -- which, under `set -e`, failed the whole lane AFTER every assertion in it
  # had already passed. Docker Desktop hid this by translating bind-mount
  # ownership. Hand ownership back using the same privilege that took it, with
  # the PostgreSQL image this stack already pins by digest, so no new image
  # enters the supply chain just to delete files.
  docker run --rm --user 0:0 --mount "type=bind,source=$proof_root,target=/proof" \
    postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af \
    chown -R "$(id -u):$(id -g)" /proof >/dev/null 2>&1 || true
  case "$proof_root" in
    "${TMPDIR:-/tmp}"/keepling-compose-proof.*) rm -rf -- "$proof_root" ;;
    *) echo "Compose verification refused unsafe cleanup: $proof_root" >&2; exit 70 ;;
  esac
  exit "$result"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$proof_root/postgres" "$proof_root/caddy-data" "$proof_root/caddy-config" "$proof_root/secrets"
umask 077
printf '%s' 'compose-proof-postgres-password' >"$proof_root/secrets/postgres-password"
printf '%s' 'ecto://keepling:compose-proof-postgres-password@db:5432/keepling' >"$proof_root/secrets/database-url"
printf '%s' 'compose-proof-secret-key-base-000000000000000000000000000000000000000000000000' >"$proof_root/secrets/secret-key-base"
printf '%s' 'compose-proof-operator-token-000000000000000000000000000000000' >"$proof_root/secrets/operator-token"

# THE PROOF SECRETS MUST BE WORLD-READABLE, and that is not a weakening of
# anything. `umask 077` above writes them 0600 owned by the invoking user; the
# release image runs as uid 10001, which on a Linux engine is simply a
# different user, so the entrypoint's `cat /run/secrets/database_url` failed
# with "Permission denied" and the release died at "DATABASE_URL is required".
# Docker Desktop hid this by translating bind-mount ownership. These four
# values are literals written three lines up, in a temporary directory this
# script deletes on exit -- there is no secret here to protect, only a file
# mode that stopped the proof from running. A real deployment's secrets are
# Compose secrets sourced from the operator's own files, untouched by this.
chmod 0444 "$proof_root"/secrets/*

export KEEPLING_SERVER_IMAGE="$image_id"
export KEEPLING_SERVER_DIGEST="$image_id"
export KEEPLING_POSTGRES_DATA_DIR="$proof_root/postgres"
export KEEPLING_CADDY_DATA_DIR="$proof_root/caddy-data"
export KEEPLING_CADDY_CONFIG_DIR="$proof_root/caddy-config"
export KEEPLING_POSTGRES_PASSWORD_FILE="$proof_root/secrets/postgres-password"
export KEEPLING_DATABASE_URL_FILE="$proof_root/secrets/database-url"
export KEEPLING_SECRET_KEY_BASE_FILE="$proof_root/secrets/secret-key-base"
export KEEPLING_OPERATOR_TOKEN_FILE="$proof_root/secrets/operator-token"
export KEEPLING_HTTP_BIND="127.0.0.1:$http_port"
export KEEPLING_HTTPS_BIND="127.0.0.1:$((http_port + 1))"

rendered=$($compose -p "$project" config)
printf '%s\n' "$rendered" | grep -Eq 'published: "?5432"?' && die "PostgreSQL port 5432 is published"
printf '%s\n' "$rendered" | grep -F 'internal: true' >/dev/null || die "database network is not internal"
printf '%s\n' "$rendered" | grep -F "$image_id" >/dev/null || die "app does not use the exact image ID"

$compose -p "$project" up -d --wait

attempt=0
until curl -fsS "http://127.0.0.1:$http_port/health/ready" 2>/dev/null | jq -e '.status == "ready"' >/dev/null 2>&1; do
  attempt=$((attempt + 1)); [ "$attempt" -lt 60 ] || die "edge did not reach semantic readiness"; sleep 1
done

migration_count=$($compose -p "$project" exec -T db psql -U keepling -d keepling -Atc 'SELECT count(*) FROM schema_migrations')
case "$migration_count" in ''|*[!0-9]*|0) die "migrations did not persist" ;; esac

$compose -p "$project" stop app >/dev/null
retry_headers=$(mktemp "${TMPDIR:-/tmp}/keepling-compose-headers.XXXXXX")
set +e
http_status=$(curl -sS -D "$retry_headers" -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port/health/ready")
set -e
[ "$http_status" = 503 ] || die "edge returned $http_status during app replacement, expected 503"
grep -Eiq '^Retry-After: 2' "$retry_headers" || die "edge omitted bounded Retry-After guidance"
rm -f -- "$retry_headers"

$compose -p "$project" up -d --no-deps app
attempt=0
until curl -fsS "http://127.0.0.1:$http_port/health/ready" 2>/dev/null | jq -e '.status == "ready"' >/dev/null 2>&1; do
  attempt=$((attempt + 1)); [ "$attempt" -lt 60 ] || die "app recreation did not recover readiness"; sleep 1
done

surviving_count=$($compose -p "$project" exec -T db psql -U keepling -d keepling -Atc 'SELECT count(*) FROM schema_migrations')
[ "$surviving_count" = "$migration_count" ] || die "database state changed across app recreation"

$compose -p "$project" stop db >/dev/null
attempt=0
until [ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port/health/ready" 2>/dev/null || true)" = 503 ]; do
  attempt=$((attempt + 1)); [ "$attempt" -lt 30 ] || die "database outage did not become a stable edge 503"; sleep 1
done
$compose -p "$project" start db >/dev/null

$compose -p "$project" stop app >/dev/null
app_exit=$($compose -p "$project" ps -a --format json app | jq -r 'if type == "array" then .[0].ExitCode else .ExitCode end')
[ "$app_exit" = 0 ] || [ "$app_exit" = 143 ] || die "app did not stop gracefully (exit $app_exit)"

printf '%s\n' "Compose verification passed: private PostgreSQL, named host state, readiness, edge 503 guidance, graceful stop, and app recreation are proven"
