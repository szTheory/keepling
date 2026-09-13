#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

phase_seed=${KEEPLING_PHASE2_SEED:-20260901}
case "$phase_seed" in ''|*[!0-9]*) echo "Phase 2 seed must be numeric" >&2; exit 2 ;; esac

list_lanes() {
  echo "repository-integrity       repository boundary checks"
  echo "server                     complete ExUnit suite against disposable PostgreSQL"
  echo "sync-property              seeded reference model and PostgreSQL feed tests"
  echo "contracts-compatibility    generated contracts and current/previous skew matrix"
  echo "image-compose-deploy       disposable OCI, Compose, migration, and retry proof"
  echo "backup-restore             backup policy and three isolated restore fixtures"
  echo "opentofu-host-fixtures     pinned provider graph and hermetic live-boundary regressions"
  echo "privacy                    producer redaction tests and aggregate hostile scan"
  echo "live-host-dns-acceptance   credentialed outer acceptance; explicit NON_PASSING marker"
}

phase_database_root=''
evidence_root=''

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$phase_database_root" ] && [ -d "$phase_database_root/data" ]; then
    ./tooling/runtime-preflight.sh --exec -- \
      pg_ctl -D "$phase_database_root/data" -m fast -w stop >/dev/null 2>&1 || true
  fi
  case "$phase_database_root" in
    '') ;;
    "${TMPDIR:-/tmp}"/keepling-phase2-db.*) rm -rf -- "$phase_database_root" ;;
    *) echo "Phase 2 runner refused unsafe database cleanup" >&2; status=70 ;;
  esac
  case "$evidence_root" in
    '') ;;
    "${TMPDIR:-/tmp}"/keepling-phase2-evidence.*) rm -rf -- "$evidence_root" ;;
    *) echo "Phase 2 runner refused unsafe evidence cleanup" >&2; status=70 ;;
  esac
  exit "$status"
}

start_phase_database() {
  phase_database_port=${KEEPLING_PHASE2_POSTGRES_PORT:-$((55000 + $$ % 1000))}
  phase_database_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-phase2-db.XXXXXX")
  mkdir "$phase_database_root/socket"
  ./tooling/runtime-preflight.sh --exec -- \
    initdb --auth-host=trust --auth-local=trust --encoding=UTF8 --no-locale \
      -D "$phase_database_root/data" >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    pg_ctl -D "$phase_database_root/data" -l "$phase_database_root/postgres.log" \
      -o "-h 127.0.0.1 -k $phase_database_root/socket -p $phase_database_port" \
      -w start >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    createdb -h 127.0.0.1 -p "$phase_database_port" keepling_phase2
  database_user=$(id -un)
  export KEEPLING_TEST_DATABASE_URL="ecto://$database_user@127.0.0.1:$phase_database_port/keepling_phase2"
  export KEEPLING_TEST_SECRET_KEY_BASE='phase-2-test-only-secret-key-base-000000000000000000000000000000000000000000000000'
}

digest_inputs() {
  input_spec=$1
  input_manifest="$evidence_root/input-manifest"
  : >"$input_manifest"
  for input in $(printf '%s' "$input_spec" | tr ',' ' '); do
    [ -f "$input" ] || { echo "Phase 2 lane input is missing: $input" >&2; return 1; }
    printf '%s  %s\n' "$(git hash-object "$input")" "$input" >>"$input_manifest"
  done
  [ -s "$input_manifest" ] || { echo "Phase 2 lane has zero digest inputs" >&2; return 1; }
  shasum -a 256 "$input_manifest" | awk '{print $1}'
}

run_lane() {
  lane=$1
  seed=$2
  case_count=$3
  input_spec=$4
  command_text=$5
  shift 5

  if [ "$case_count" -le 0 ]; then
    echo "Phase 2 lane '$lane' performed zero work" >&2
    return 1
  fi
  inputs_sha256=$(digest_inputs "$input_spec")
  lane_log="$evidence_root/$lane.log"
  started_ms=$(node -e 'process.stdout.write(String(Date.now()))')
  printf '%s\n' "lane=$lane status=RUNNING command=$command_text cases=$case_count seed=$seed inputs_sha256=$inputs_sha256"
  if ! "$@" >"$lane_log" 2>&1; then
    if ./tooling/verify-privacy.sh "$lane_log" >/dev/null 2>&1; then
      # HEAD *AND* TAIL. Printing only the first 200 lines is useless for any
      # lane whose log is dominated by build output: `image-compose-deploy`
      # failed for weeks with its actual cause past line 500, so continuous
      # integration showed 200 lines of `Getting <package> (Hex package)` and
      # nothing else. The cause of a failure is almost always near the end.
      lane_log_lines=$(wc -l <"$lane_log" | tr -d '[:space:]')
      if [ "$lane_log_lines" -le 300 ]; then
        cat "$lane_log" >&2
      else
        sed -n '1,100p' "$lane_log" >&2
        echo "... [$((lane_log_lines - 300)) lines omitted from the middle of $lane] ..." >&2
        tail -n 200 "$lane_log" >&2
      fi
    else
      echo "Phase 2 lane output withheld because privacy verification failed" >&2
    fi
    echo "Phase 2 lane failed: $lane" >&2
    return 1
  fi
  ./tooling/verify-privacy.sh "$lane_log" >/dev/null
  finished_ms=$(node -e 'process.stdout.write(String(Date.now()))')
  elapsed_ms=$((finished_ms - started_ms))
  [ "$elapsed_ms" -ge 0 ] || { echo "Phase 2 lane timing was invalid" >&2; return 1; }
  printf '%s\n' "lane=$lane status=PASS command=$command_text cases=$case_count seed=$seed elapsed_ms=$elapsed_ms inputs_sha256=$inputs_sha256"
}

count_tests() {
  grep -rnE '^[[:space:]]*(test|property) "' "$@" | wc -l | tr -d '[:space:]'
}

lane_repository_integrity() { ./tooling/check-repository-integrity.sh; }
lane_server() {
  MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix ecto.migrate && mix compile --warnings-as-errors && mix test --seed "$1"' sh "$phase_seed"
}
lane_sync_property() {
  MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix test --seed "$1" test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs' sh "$phase_seed"
}
lane_contracts_compatibility() { pnpm contracts:check && ./tooling/test-compatibility.sh; }
lane_image_compose_deploy() { ./tooling/verify-image.sh && ./tooling/verify-compose.sh && ./tooling/verify-deploy.sh --local; }
lane_backup_restore() {
  ./tooling/verify-backup.sh --fixture local
  ./tooling/verify-restore.sh --fixture newest-logical
  ./tooling/verify-restore.sh --fixture latest-wal
  KEEPLING_RESTORE_SEED="$phase_seed" ./tooling/verify-restore.sh --fixture historical-pitr
}
lane_opentofu_host_fixtures() {
  ./tooling/test-host-bootstrap.sh
  ./tooling/test-host-bootstrap-diagnostics.sh
  ./tooling/test-provider-ownership.sh
  ./tooling/test-plan-shape-contract.sh
  ./tooling/test-resolved-plan-contract.sh
  ./tooling/test-image-archive-contract.sh
  ./tooling/test-remote-prepare-observability.sh
  ./tooling/test-host-replacement-sequence.sh
}
lane_privacy() {
  MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix test --seed "$1" test/keepling/telemetry_redaction_test.exs test/keepling/ops_redaction_test.exs' sh "$phase_seed"
  ./tooling/verify-privacy.sh --self-test
}

report_deferred_live_acceptance() {
  deferred=.planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md
  grep -F 'Plan 02-09 remains incomplete' "$deferred" >/dev/null || {
    echo "Deferred live acceptance truth is missing" >&2
    return 1
  }
  printf '%s\n' "lane=live-host-dns-acceptance LIVE_ACCEPTANCE_STATUS=NON_PASSING reason=credentialed_outer_acceptance_deferred evidence=$deferred"
}

run_lanes() {
  selected_lane=${1:-all}
  trap cleanup EXIT HUP INT TERM
  evidence_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-phase2-evidence.XXXXXX")
  case "$selected_lane" in
    all | server | sync-property | privacy) start_phase_database ;;
  esac

  server_cases=$(count_tests apps/server/test)
  sync_cases=$(count_tests apps/server/test/keepling/application/sync apps/server/test/keepling/adapters/postgres/sync_feed_test.exs)
  privacy_cases=$(count_tests apps/server/test/keepling/telemetry_redaction_test.exs apps/server/test/keepling/ops_redaction_test.exs)
  contract_cases=$(find packages/contracts/schemas packages/contracts/vectors -type f | wc -l | tr -d '[:space:]')

  case "$selected_lane" in
    all | repository-integrity)
      run_lane repository-integrity none 3 \
        'AGENTS.md,docs/architecture/REPOSITORY.md,tooling/check-repository-integrity.sh' \
        './tooling/check-repository-integrity.sh' lane_repository_integrity ;;
  esac
  case "$selected_lane" in
    all | server)
      run_lane server "$phase_seed" "$server_cases" \
        'apps/server/mix.lock,tooling/runtime-versions.env,apps/server/test/test_helper.exs' \
        'mix compile --warnings-as-errors && mix test' lane_server ;;
  esac
  case "$selected_lane" in
    all | sync-property)
      run_lane sync-property "$phase_seed" "$sync_cases" \
        'apps/server/mix.lock,packages/contracts/vectors/sync.json,apps/server/test/keepling/application/sync/reference_model_test.exs,apps/server/test/keepling/adapters/postgres/sync_feed_test.exs' \
        'mix test test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs' lane_sync_property ;;
  esac
  case "$selected_lane" in
    all | contracts-compatibility)
      run_lane contracts-compatibility "$phase_seed" "$contract_cases" \
        'pnpm-lock.yaml,apps/server/mix.lock,packages/contracts/openapi/keepling.yaml,tooling/test-compatibility.sh' \
        'pnpm contracts:check && ./tooling/test-compatibility.sh' lane_contracts_compatibility ;;
  esac
  case "$selected_lane" in
    all | image-compose-deploy)
      run_lane image-compose-deploy none 3 \
        'infra/images/server/Dockerfile,infra/compose/compose.yml,infra/caddy/Caddyfile,tooling/verify-image.sh,tooling/verify-compose.sh,tooling/verify-deploy.sh' \
        './tooling/verify-image.sh && ./tooling/verify-compose.sh && ./tooling/verify-deploy.sh --local' lane_image_compose_deploy ;;
  esac
  case "$selected_lane" in
    all | backup-restore)
      run_lane backup-restore "$phase_seed" 4 \
        'infra/backup/schedule.yml,infra/backup/durable-state-manifest.yml,packages/contracts/vectors/recovery.json,tooling/verify-backup.sh,tooling/verify-restore.sh' \
        './tooling/verify-backup.sh and three ./tooling/verify-restore.sh fixtures' lane_backup_restore ;;
  esac
  case "$selected_lane" in
    all | opentofu-host-fixtures)
      run_lane opentofu-host-fixtures "$phase_seed" 8 \
        'infra/tofu/hetzner/versions.tf,infra/tofu/hetzner/.terraform.lock.hcl,infra/tofu/hetzner/replace_host.tftest.hcl,tooling/verify-host-replacement.sh,tooling/test-image-archive-contract.sh,tooling/test-remote-prepare-observability.sh' \
        'eight hermetic OpenTofu/bootstrap/archive/teardown/DNS-fence fixture commands' lane_opentofu_host_fixtures ;;
  esac
  case "$selected_lane" in
    all | privacy)
      run_lane privacy "$phase_seed" "$((privacy_cases + 10))" \
        'packages/contracts/vectors/redaction.json,apps/server/test/keepling/telemetry_redaction_test.exs,apps/server/test/keepling/ops_redaction_test.exs,tooling/verify-privacy.sh' \
        'mix test telemetry_redaction_test.exs ops_redaction_test.exs && verify-privacy.sh --self-test' lane_privacy ;;
  esac

  if [ "$selected_lane" = all ]; then
    report_deferred_live_acceptance
    printf '%s\n' 'Phase 2 local executable lanes passed; credentialed host/DNS outer acceptance remains NON_PASSING.'
  fi
}

usage() {
  echo "Usage: $0 --list | --run | --lane NAME" >&2
  exit 2
}

case "${1:-}" in
  --list) [ "$#" -eq 1 ] || usage; list_lanes ;;
  --run) [ "$#" -eq 1 ] || usage; run_lanes ;;
  --lane)
    [ "$#" -eq 2 ] || usage
    case "$2" in
      repository-integrity | server | sync-property | contracts-compatibility | image-compose-deploy | backup-restore | opentofu-host-fixtures | privacy) run_lanes "$2" ;;
      live-host-dns-acceptance) report_deferred_live_acceptance; exit 3 ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
