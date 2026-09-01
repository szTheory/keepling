#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Deploy verification failed: $*" >&2
  exit 1
}

proof_root=
project=
base_url=
origin_url=
cookie_jar=
session_cookie=
csrf_token=
task_id=
recovery_output=
recovery_login_credential=

compose_run() {
  docker compose -f infra/compose/compose.yml -p "$project" "$@"
}

require_exact_digest() {
  case "$1" in
    sha256:????????????????????????????????????????????????????????????????) return 0 ;;
    *@sha256:????????????????????????????????????????????????????????????????) return 0 ;;
    *) return 1 ;;
  esac
}

rollback_eligibility() {
  candidate_digest=$1
  target_schema=$2
  target_protocol=$3
  schema_minimum=$4
  schema_maximum=$5
  protocol_minimum=$6
  protocol_maximum=$7

  require_exact_digest "$candidate_digest" || {
    echo "forward_fix_required: rollback artifact is not an exact tested digest" >&2
    return 1
  }

  if [ "$target_schema" -lt "$schema_minimum" ] || [ "$target_schema" -gt "$schema_maximum" ]; then
    echo "forward_fix_required: rollback schema range excludes migrated schema $target_schema" >&2
    return 1
  fi

  if [ "$target_protocol" -lt "$protocol_minimum" ] || [ "$target_protocol" -gt "$protocol_maximum" ]; then
    echo "forward_fix_required: rollback protocol range excludes train $target_protocol" >&2
    return 1
  fi

  return 0
}

cleanup_deploy_proof() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ -n "$project" ]; then compose_run down --remove-orphans >/dev/null 2>&1 || true; fi
  if [ -n "$proof_root" ]; then
    case "$proof_root" in
      "${TMPDIR:-/tmp}"/keepling-deploy-proof.*) rm -rf -- "$proof_root" ;;
      *) echo "Deploy verification refused unsafe cleanup: $proof_root" >&2; exit 70 ;;
    esac
  fi
  exit "$result"
}

wait_for_ready() {
  attempt=0
  until curl -fsS "$base_url/health/ready" 2>/dev/null | jq -e '.status == "ready"' >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 60 ] || die "deployment did not recover semantic readiness"
    sleep 1
  done
}

deploy_exact_digest() {
  for command in docker curl jq openssl uuidgen; do
    command -v "$command" >/dev/null 2>&1 || die "required command '$command' is unavailable"
  done

  image_tag=${KEEPLING_IMAGE_TAG:-keepling-server:plan-02-07}
  docker image inspect "$image_tag" >/dev/null 2>&1 || ./tooling/verify-image.sh
  image_id=$(docker image inspect "$image_tag" --format '{{.Id}}')
  require_exact_digest "$image_id" || die "local promotion input is mutable"
  image_architecture=$(docker image inspect "$image_tag" --format '{{.Architecture}}')
  engine_architecture=$(docker info --format '{{.Architecture}}')
  KEEPLING_RUNTIME_ERL_FLAGS=
  case "$image_architecture:$engine_architecture" in
    amd64:arm64 | amd64:aarch64) KEEPLING_RUNTIME_ERL_FLAGS='+JMsingle true' ;;
  esac
  export KEEPLING_RUNTIME_ERL_FLAGS

  proof_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-deploy-proof.XXXXXX")
  project="keepling-deploy-$$"
  http_port=$((58500 + $$ % 200))
  https_port=$((58700 + $$ % 200))
  base_url="http://127.0.0.1:$http_port"
  origin_url="https://127.0.0.1:$http_port"
  cookie_jar="$proof_root/cookies"
  trap cleanup_deploy_proof EXIT HUP INT TERM

  mkdir -p "$proof_root/postgres" "$proof_root/caddy-data" "$proof_root/caddy-config" "$proof_root/secrets"
  umask 077
  printf '%s' 'deploy-proof-postgres-password' >"$proof_root/secrets/postgres-password"
  printf '%s' 'ecto://keepling:deploy-proof-postgres-password@db:5432/keepling' >"$proof_root/secrets/database-url"
  printf '%s' 'deploy-proof-secret-key-base-0000000000000000000000000000000000000000000000000' >"$proof_root/secrets/secret-key-base"
  printf '%s' 'deploy-proof-operator-token-00000000000000000000000000000000000' >"$proof_root/secrets/operator-token"

  export KEEPLING_SERVER_IMAGE="$image_id"
  export KEEPLING_SERVER_DIGEST="$image_id"
  export KEEPLING_HOST=127.0.0.1
  export KEEPLING_POSTGRES_DATA_DIR="$proof_root/postgres"
  export KEEPLING_CADDY_DATA_DIR="$proof_root/caddy-data"
  export KEEPLING_CADDY_CONFIG_DIR="$proof_root/caddy-config"
  export KEEPLING_POSTGRES_PASSWORD_FILE="$proof_root/secrets/postgres-password"
  export KEEPLING_DATABASE_URL_FILE="$proof_root/secrets/database-url"
  export KEEPLING_SECRET_KEY_BASE_FILE="$proof_root/secrets/secret-key-base"
  export KEEPLING_OPERATOR_TOKEN_FILE="$proof_root/secrets/operator-token"
  export KEEPLING_HTTP_BIND="127.0.0.1:$http_port"
  export KEEPLING_HTTPS_BIND="127.0.0.1:$https_port"

  rendered=$(compose_run config)
  printf '%s\n' "$rendered" | grep -F "image: $image_id" >/dev/null || die "promotion did not render the exact tested image"

  compose_run up -d --wait
  migrate_exit=$(compose_run ps -a --format json migrate | jq -r 'if type == "array" then .[0].ExitCode else .ExitCode end')
  [ "$migrate_exit" = 0 ] || die "explicit migration exited $migrate_exit"
  wait_for_ready

  caddy_before=$(compose_run ps -q caddy)
  compose_run up -d --no-deps --force-recreate app >/dev/null
  wait_for_ready
  caddy_after=$(compose_run ps -q caddy)
  [ "$caddy_before" = "$caddy_after" ] || die "app promotion recreated the public edge"

  compose_run stop db >/dev/null
  attempt=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' "$base_url/health/ready" 2>/dev/null || true)" = 503 ]; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 30 ] || die "dependency outage did not surface as 503"; sleep 1
  done
  compose_run start db >/dev/null
  wait_for_ready
}

prove_interrupted_retry() {
  [ -n "$csrf_token" ] || die "user smoke must authenticate before interruption proof"
  edit_mutation=$(uuidgen | tr '[:upper:]' '[:lower:]')
  edit_body=$(jq -cn \
    --arg mutation_id "$edit_mutation" --arg task_id "$task_id" \
    '{version:1,mutation_id:$mutation_id,task_id:$task_id,expected_revision:1,base_values:{title:"Deploy proof task"},fields:{title:"Deploy proof changed"}}')

  compose_run stop app >/dev/null
  interrupted_headers="$proof_root/interrupted-headers"
  interrupted_status=$(curl -s -D "$interrupted_headers" -o /dev/null -w '%{http_code}' \
    -H "Cookie: $session_cookie" -H "Origin: $origin_url" -H "x-csrf-token: $csrf_token" -H 'content-type: application/json' \
    --data-binary "$edit_body" "$base_url/api/v1/commands/edit-task")
  [ "$interrupted_status" = 503 ] || die "interrupted mutation returned $interrupted_status instead of 503"
  grep -Eiq '^Retry-After: 2' "$interrupted_headers" || die "interrupted mutation omitted Retry-After"

  compose_run up -d --no-deps app >/dev/null
  wait_for_ready
  edit_response=$(curl -fsS -H "Cookie: $session_cookie" -H "Origin: $origin_url" -H "x-csrf-token: $csrf_token" -H 'content-type: application/json' \
    --data-binary "$edit_body" "$base_url/api/v1/commands/edit-task")
  printf '%s' "$edit_response" | jq -e '.outcome == "accepted" and .revision == 2 and .undo.handle != null' >/dev/null || die "exact retry did not accept the edit"

  replay_response=$(curl -fsS -H "Cookie: $session_cookie" -H "Origin: $origin_url" -H "x-csrf-token: $csrf_token" -H 'content-type: application/json' \
    --data-binary "$edit_body" "$base_url/api/v1/commands/edit-task")
  [ "$(printf '%s' "$edit_response" | jq -S .)" = "$(printf '%s' "$replay_response" | jq -S .)" ] || die "exact retry did not return the stable receipt"

  undo_handle=$(printf '%s' "$edit_response" | jq -r '.undo.handle')
  undo_mutation=$(uuidgen | tr '[:upper:]' '[:lower:]')
  undo_body=$(jq -cn --arg handle "$undo_handle" --arg mutation_id "$undo_mutation" '{version:1,handle:$handle,mutation_id:$mutation_id}')
  undo_response=$(curl -fsS -H "Cookie: $session_cookie" -H "Origin: $origin_url" -H "x-csrf-token: $csrf_token" -H 'content-type: application/json' \
    --data-binary "$undo_body" "$base_url/api/v1/commands/undo-task")
  printf '%s' "$undo_response" | jq -e '.outcome == "accepted" and .revision == 3 and .snapshot.title == "Deploy proof task"' >/dev/null || die "undo smoke did not restore the original task"
}

prove_user_smoke() {
  setup_output=$(compose_run exec -T app /app/bin/keepling rpc 'case Keepling.Accounts.issue_setup_token() do {:ok, issued} -> IO.puts(issued.token); other -> raise inspect(other) end')
  setup_token=$(printf '%s\n' "$setup_output" | sed -n '/^[A-Za-z0-9_-][A-Za-z0-9_-]*$/p' | tail -n 1)
  [ -n "$setup_token" ] || die "packaged release did not issue a setup capability"

  recovery_login_credential=$(openssl rand -hex 32)
  setup_body=$(jq -cn --arg token "$setup_token" --arg password "$recovery_login_credential" '{version:1,token:$token,password:$password,timezone:"America/New_York"}')
  curl -fsS -H 'content-type: application/json' --data-binary "$setup_body" "$base_url/api/v1/setup" | jq -e '.status == "setup_complete"' >/dev/null || die "user setup smoke failed"

  login_body=$(jq -cn --arg password "$recovery_login_credential" '{version:1,client_kind:"web",label:"Deploy proof",password:$password}')
  login_response=$(curl -fsS -c "$cookie_jar" -H "Origin: $origin_url" -H 'content-type: application/json' \
    --data-binary "$login_body" "$base_url/api/v1/login")
  csrf_token=$(printf '%s' "$login_response" | jq -r '.csrf_token // empty')
  [ -n "$csrf_token" ] || die "login smoke did not return CSRF state"
  session_cookie=$(awk '$6 == "_keepling_key" {print $6 "=" $7}' "$cookie_jar" | tail -n 1)
  [ -n "$session_cookie" ] || die "login smoke did not return the secure session cookie"

  task_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
  capture_mutation=$(uuidgen | tr '[:upper:]' '[:lower:]')
  capture_body=$(jq -cn --arg mutation_id "$capture_mutation" --arg task_id "$task_id" '{version:1,mutation_id:$mutation_id,task_id:$task_id,title:"Deploy proof task"}')
  capture_response=$(curl -fsS -H "Cookie: $session_cookie" -H "Origin: $origin_url" -H "x-csrf-token: $csrf_token" -H 'content-type: application/json' \
    --data-binary "$capture_body" "$base_url/api/v1/commands/capture-task")
  printf '%s' "$capture_response" | jq -e '.outcome == "accepted" and .revision == 1' >/dev/null || die "write smoke did not capture a task"

  curl -fsS -H "Cookie: $session_cookie" "$base_url/api/v1/tasks/$task_id" | jq -e '.id == $id and .title == "Deploy proof task"' --arg id "$task_id" >/dev/null || die "read smoke did not return the captured task"
}

capture_recovery_package() {
  [ -n "$recovery_output" ] || return 0
  [ -d "$recovery_output" ] && [ -z "$(find "$recovery_output" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
    die "recovery output must be an empty directory"
  case "$recovery_output" in
    "$repository_root" | "$repository_root"/*) die "recovery output must remain outside the repository" ;;
  esac

  compose_run exec -T db pg_dump -U keepling -d keepling -Fc >"$recovery_output/recovery.dump"
  chmod 600 "$recovery_output/recovery.dump"
  [ -n "$recovery_login_credential" ] || die "recovery login credential was not retained from the proven setup"
  # This sidecar is rehearsal authority, not backup payload. The caller must
  # keep it outside object storage and delete it with the private run workspace.
  printf '%s' "$recovery_login_credential" >"$recovery_output/rehearsal-login-credential"
  chmod 600 "$recovery_output/rehearsal-login-credential"
  dump_sha=$(shasum -a 256 "$recovery_output/recovery.dump" | awk '{print $1}')
  credential_sha=$(shasum -a 256 "$recovery_output/rehearsal-login-credential" | awk '{print $1}')
  source_epoch=$(compose_run exec -T db psql -U keepling -d keepling -Atc \
    'SELECT epoch FROM sync_epochs WHERE singleton_key=TRUE' | tr -d '\r')
  jq -n --arg dump_sha "$dump_sha" --arg credential_sha "$credential_sha" --arg task_id "$task_id" --arg source_epoch "$source_epoch" \
    '{version:1,dump_sha256:$dump_sha,rehearsal_login_credential_sha256:$credential_sha,task_id:$task_id,source_epoch:$source_epoch,semantic:{login:true,read:true,write:true,undo:true,restored_login:false}}' \
    >"$recovery_output/recovery-manifest.json"
  chmod 600 "$recovery_output/recovery-manifest.json"
}

prove_recovery_login_fixture() {
  [ -n "$recovery_output" ] || return 0
  restored_database=keepling_recovery_proof
  compose_run exec -T db dropdb --if-exists -U keepling "$restored_database" >/dev/null
  compose_run exec -T db createdb -U keepling -O keepling "$restored_database" >/dev/null
  compose_run exec -T db pg_restore -U keepling -d "$restored_database" \
    --no-owner --no-privileges --exit-on-error <"$recovery_output/recovery.dump"
  compose_run run --rm -T --no-deps \
    -e "DATABASE_URL=ecto://keepling:deploy-proof-postgres-password@db:5432/$restored_database" \
    -v "$recovery_output/rehearsal-login-credential:/run/keepling-rehearsal-login-credential:ro" \
    app eval '
      {:ok, _} = Application.ensure_all_started(:keepling)
      credential = File.read!("/run/keepling-rehearsal-login-credential")
      {:ok, _session} = Keepling.Accounts.login(credential)
    ' >/dev/null
  if compose_run run --rm -T --no-deps \
    -e "DATABASE_URL=ecto://keepling:deploy-proof-postgres-password@db:5432/$restored_database" \
    -v "$recovery_output/rehearsal-login-credential:/run/keepling-rehearsal-login-credential:ro" \
    app eval '
      {:ok, _} = Application.ensure_all_started(:keepling)
      wrong_credential = File.read!("/run/keepling-rehearsal-login-credential") <> "-wrong"
      {:ok, _session} = Keepling.Accounts.login(wrong_credential)
    ' >/dev/null 2>&1; then
    die "restored database accepted a credential that was not used by the proven setup"
  fi
  compose_run exec -T db dropdb --if-exists -U keepling "$restored_database" >/dev/null

  manifest_tmp="$recovery_output/recovery-manifest.tmp"
  jq '.semantic.restored_login = true' "$recovery_output/recovery-manifest.json" >"$manifest_tmp"
  chmod 600 "$manifest_tmp"
  mv "$manifest_tmp" "$recovery_output/recovery-manifest.json"
}

# Assert the GREEN implementation exposes every black-box behavior before it can
# promote any artifact.
for required_function in \
  require_exact_digest \
  rollback_eligibility \
  deploy_exact_digest \
  prove_interrupted_retry \
  prove_user_smoke \
  prove_recovery_login_fixture; do
  command -v "$required_function" >/dev/null 2>&1 ||
    die "RED: missing deployment behavior '$required_function'"
done

[ "${1:-}" = "--local" ] || die "usage: $0 --local [--recovery-output EMPTY_DIRECTORY]"
case "$#" in
  1) ;;
  3)
    [ "$2" = "--recovery-output" ] || die "usage: $0 --local [--recovery-output EMPTY_DIRECTORY]"
    recovery_output=$3
    ;;
  *) die "usage: $0 --local [--recovery-output EMPTY_DIRECTORY]" ;;
esac

require_exact_digest 'keepling-server:latest' && die "mutable tags must be rejected"
require_exact_digest 'ghcr.io/sztheory/keepling-server@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

rollback_eligibility \
  'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  14 1 1 14 1 1 || die "compatible tested rollback was rejected"

if rollback_eligibility \
  'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  15 1 1 14 1 1; then
  die "schema-incompatible rollback was permitted"
fi

deploy_exact_digest
prove_user_smoke
prove_interrupted_retry
capture_recovery_package
prove_recovery_login_fixture

echo "Deploy verification passed: exact digest migration, readiness, interruption retry, user smoke, and rollback policy are proven"
