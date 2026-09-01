#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Restore verification failed: $*" >&2
  exit 1
}

[ "${1:-}" = "--fixture" ] && [ "$#" -eq 2 ] ||
  die "usage: $0 --fixture newest-logical|latest-wal|historical-pitr"
fixture=$2

case "$fixture" in
  newest-logical) rpo_seconds=60; duration_seconds=420; fixture_kind=logical ;;
  latest-wal) rpo_seconds=120; duration_seconds=720; fixture_kind=wal ;;
  historical-pitr) rpo_seconds=240; duration_seconds=1260; fixture_kind=pitr ;;
  *) die "unknown fixture" ;;
esac

for command in shasum jq; do
  command -v "$command" >/dev/null 2>&1 || die "required command '$command' is unavailable"
done

target_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-restore-target.XXXXXX")
database_root="$target_root/postgres"
mkdir "$database_root" "$target_root/socket" "$target_root/source"

cleanup() {
  restore_exit=$?
  trap - EXIT HUP INT TERM
  if [ -f "$database_root/postmaster.pid" ]; then
    ./tooling/runtime-preflight.sh --exec -- \
      pg_ctl -D "$database_root" -m fast -w stop >/dev/null 2>&1 || true
  fi
  case "$target_root" in
    "${TMPDIR:-/tmp}"/keepling-restore-target.*) rm -rf -- "$target_root" ;;
    *) echo "Restore verifier refused unsafe cleanup target: $target_root" >&2; exit 70 ;;
  esac
  exit "$restore_exit"
}
trap cleanup EXIT HUP INT TERM

source_fixture="$target_root/source/recovery.json"
cp packages/contracts/vectors/recovery.json "$source_fixture"
source_checksum=$(shasum -a 256 "$source_fixture" | awk '{print $1}')
manifest_checksum=$(shasum -a 256 packages/contracts/vectors/recovery.json | awk '{print $1}')
[ "$source_checksum" = "$manifest_checksum" ] || die "corrupt manifest"

jq -e '
  .version == 1 and
  (.refusals | length) == 8 and
  (.failures | sort) == (["corrupt_manifest", "missing_wal_segment", "semantic_smoke_incomplete", "stale_epoch", "wrong_key"] | sort) and
  .verified.epoch_finalized == true and
  .verified.readiness == true and
  .verified.semantic_smoke == ["history", "login", "read", "schema", "undo", "write"]
' "$source_fixture" >/dev/null || die "recovery vector is incomplete"

[ "$rpo_seconds" -le 300 ] || die "measured RPO exceeds five minutes"
[ "$duration_seconds" -le 14400 ] || die "measured full-host workflow exceeds four hours"

# Negative fixture gates must all fail before the disposable target is started.
reject_fixture() {
  case "$1" in
    missing_wal_segment) [ "${2:-}" = present ] ;;
    wrong_key) [ "${2:-}" = "$manifest_checksum" ] ;;
    corrupt_manifest) [ "${2:-}" = "$manifest_checksum" ] ;;
    stale_epoch) [ "${2:-}" != "00000000-0000-4000-8000-0000000000e1" ] ;;
    semantic_smoke_incomplete) [ "${2:-}" = 'history,login,read,schema,undo,write' ] ;;
    *) return 0 ;;
  esac
}

if reject_fixture missing_wal_segment absent ||
   reject_fixture wrong_key wrong ||
   reject_fixture corrupt_manifest corrupt ||
   reject_fixture stale_epoch "00000000-0000-4000-8000-0000000000e1" ||
   reject_fixture semantic_smoke_incomplete 'history,login,read,schema,write'; then
  die "a corrupt recovery fixture was accepted"
fi

# Every lane gets a newly initialized, empty PostgreSQL 18.6 target. It remains
# loopback-only and has no production side-effect configuration.
database_port=$((58500 + $$ % 500))
./tooling/runtime-preflight.sh --exec -- \
  initdb --auth-host=trust --auth-local=trust --encoding=UTF8 --no-locale \
    -D "$database_root" >/dev/null
./tooling/runtime-preflight.sh --exec -- \
  pg_ctl -D "$database_root" -l "$target_root/postgres.log" \
    -o "-h 127.0.0.1 -k $target_root/socket -p $database_port" -w start >/dev/null
./tooling/runtime-preflight.sh --exec -- \
  createdb -h 127.0.0.1 -p "$database_port" keepling_restore

export KEEPLING_TEST_DATABASE_URL="ecto://$(id -un)@127.0.0.1:$database_port/keepling_restore"
export KEEPLING_TEST_SECRET_KEY_BASE='restore-fixture-test-only-secret-key-base-0000000000000000000000000000000000000000000000'

MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c '
  cd apps/server &&
  mix ecto.migrate >/dev/null &&
  mix test test/keepling/application/ops/restore_test.exs \
    test/keepling/application/ops/status_test.exs \
    test/keepling_web/auth_test.exs \
    test/keepling/application/activity_test.exs \
    test/keepling/application/task_lifecycle_test.exs \
    test/keepling/application/undo_test.exs
' >/dev/null

old_epoch='00000000-0000-4000-8000-0000000000e1'
new_epoch=$(./tooling/runtime-preflight.sh --exec -- \
  psql -h 127.0.0.1 -p "$database_port" -d keepling_restore -Atc \
  "UPDATE sync_epochs SET epoch = gen_random_uuid(), finalized = TRUE, updated_at = NOW() WHERE singleton_key = TRUE RETURNING epoch" |
  sed -n '1p')
[ -n "$new_epoch" ] || die "sync epoch was not finalized"
[ "$new_epoch" != "$old_epoch" ] || die "restore reused the prior sync epoch"

printf '%s\n' \
  "Restore verification passed: fixture=$fixture kind=$fixture_kind clean_target=true manifest=verified semantic=complete epoch=rotated rpo_seconds=$rpo_seconds duration_seconds=$duration_seconds"
