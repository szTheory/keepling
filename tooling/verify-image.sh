#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Image verification failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"
}

for command in docker jq curl; do require_command "$command"; done

revision=$(git rev-parse HEAD)
image_tag=${KEEPLING_IMAGE_TAG:-keepling-server:plan-02-07}
image_platform=${KEEPLING_IMAGE_PLATFORM:-linux/arm64}
engine_architecture=$(docker info --format '{{.Architecture}}')
emulation_erl_flags=
case "$image_platform:$engine_architecture" in
  linux/amd64:arm64 | linux/amd64:aarch64) emulation_erl_flags='+JMsingle true' ;;
esac
metadata_file=$(mktemp "${TMPDIR:-/tmp}/keepling-image-build.XXXXXX")
database_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-image-postgres.XXXXXX")
database_name="keepling-image-db-$$"
app_name="keepling-image-app-$$"
database_port=$((57000 + $$ % 500))
operator_token='image-proof-operator-token-00000000000000000000000000000000'
secret_key_base='image-proof-secret-key-base-000000000000000000000000000000000000000000000000'

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  docker rm -f "$app_name" "$database_name" >/dev/null 2>&1 || true
  rm -f -- "$metadata_file"
  case "$database_root" in
    "${TMPDIR:-/tmp}"/keepling-image-postgres.*) rm -rf -- "$database_root" ;;
    *) echo "Image verification refused unsafe temporary database cleanup: $database_root" >&2; exit 70 ;;
  esac
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

docker buildx build \
  --platform "$image_platform" \
  --load \
  --metadata-file "$metadata_file" \
  --build-arg "KEEPLING_BUILD_ERL_FLAGS=$emulation_erl_flags" \
  --build-arg "OCI_REVISION=$revision" \
  --tag "$image_tag" \
  --file infra/images/server/Dockerfile \
  .

manifest_digest=$(jq -r '."containerimage.digest" // empty' "$metadata_file")
case "$manifest_digest" in sha256:????????????????????????????????????????????????????????????????) ;; *) die "build did not return an immutable manifest digest" ;; esac

image_user=$(docker image inspect "$image_tag" --format '{{.Config.User}}')
[ "$image_user" = '10001:10001' ] || die "runtime user is '$image_user', expected 10001:10001"

entrypoint=$(docker image inspect "$image_tag" --format '{{json .Config.Entrypoint}}')
[ "$entrypoint" = '["/app/bin/keepling"]' ] || die "release entrypoint is not /app/bin/keepling"

for label in \
  org.opencontainers.image.revision \
  io.keepling.release \
  io.keepling.protocol.minimum \
  io.keepling.protocol.maximum \
  io.keepling.schema.minimum \
  io.keepling.schema.maximum; do
  value=$(docker image inspect "$image_tag" --format "{{index .Config.Labels \"$label\"}}")
  [ -n "$value" ] || die "required OCI label '$label' is absent"
done

[ "$(docker image inspect "$image_tag" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')" = "$revision" ] || die "image revision label does not match HEAD"

if docker run --rm -e "ERL_FLAGS=$emulation_erl_flags" --entrypoint /bin/sh "$image_tag" -c 'command -v mix >/dev/null || find /app/lib/keepling-* -type f -name "Elixir.KeeplingWeb.TestFaultController.beam" | grep -q .' ; then
  die "runtime contains Mix or test-only controls"
fi

docker run -d --name "$database_name" -p "127.0.0.1:$database_port:5432" \
  --mount "type=bind,source=$database_root,target=/var/lib/postgresql" \
  -e POSTGRES_DB=keepling -e POSTGRES_USER=keepling -e POSTGRES_PASSWORD=keepling-image-proof \
  postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af >/dev/null

attempt=0
until docker exec "$database_name" pg_isready -U keepling -d keepling >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || die "PostgreSQL did not become ready"
  sleep 1
done

database_url="ecto://keepling:keepling-image-proof@host.docker.internal:$database_port/keepling"
docker run --rm \
  -e "ERL_FLAGS=$emulation_erl_flags" \
  -e DATABASE_URL="$database_url" -e SECRET_KEY_BASE="$secret_key_base" -e PHX_HOST=localhost \
  -e KEEPLING_OPERATOR_TOKEN="$operator_token" -e KEEPLING_SERVER_RELEASE=0.1.0 \
  -e KEEPLING_TESTED_OCI_DIGEST="$manifest_digest" -e KEEPLING_UPDATE_LOCATION=https://github.com/szTheory/keepling/releases \
  -e KEEPLING_DEVICE_GRANT_SERVER_INSTANCE=keepling-image-proof \
  --entrypoint /app/bin/keepling "$image_tag" eval 'Application.ensure_loaded(:keepling); {:ok, _, _} = Ecto.Migrator.with_repo(Keepling.Repo, fn repo -> Ecto.Migrator.run(repo, :up, all: true) end)' >/dev/null

docker run -d --name "$app_name" -p 127.0.0.1::4000 \
  -e "ERL_FLAGS=$emulation_erl_flags" \
  -e DATABASE_URL="$database_url" -e SECRET_KEY_BASE="$secret_key_base" -e PHX_HOST=localhost \
  -e KEEPLING_OPERATOR_TOKEN="$operator_token" -e KEEPLING_SERVER_RELEASE=0.1.0 \
  -e KEEPLING_TESTED_OCI_DIGEST="$manifest_digest" -e KEEPLING_UPDATE_LOCATION=https://github.com/szTheory/keepling/releases \
  -e KEEPLING_DEVICE_GRANT_SERVER_INSTANCE=keepling-image-proof \
  "$image_tag" >/dev/null

host_port=$(docker port "$app_name" 4000/tcp | sed -n 's/.*://p')
attempt=0
until curl -fsS "http://127.0.0.1:$host_port/health/live" 2>/dev/null | jq -e '.status == "alive"' >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || die "packaged liveness did not pass"
  sleep 1
done
curl -fsS "http://127.0.0.1:$host_port/health/ready" | jq -e '.status == "ready"' >/dev/null || die "packaged readiness did not pass"

set +e
status_json=$(docker exec \
  -e KEEPLING_OPS_ARGS_BASE64="$(printf status | base64 | tr -d '\n'):$(printf -- --json | base64 | tr -d '\n')" \
  "$app_name" /app/bin/keepling eval 'Keepling.Release.ops_from_env()')
status_exit=$?
set -e
[ "$status_exit" -eq 0 ] || [ "$status_exit" -eq 20 ] || die "packaged ops status returned unexpected exit $status_exit"
status_json=$(printf '%s\n' "$status_json" | sed -n '/^{/p' | tail -n 1)
printf '%s\n' "$status_json" | jq -e '.operation == "status" and (.status == "ok" or .status == "degraded")' >/dev/null || die "packaged ops status was not bounded JSON"

printf '%s\n' "Image verification passed: $image_tag@$manifest_digest is non-root, test-clean, live, ready, and operator-inspectable"
