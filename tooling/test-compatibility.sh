#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

database_root=''

cleanup_compatibility_database() {
  compatibility_exit=$?
  trap - EXIT HUP INT TERM

  if [ -n "$database_root" ] && [ -d "$database_root/data" ]; then
    ./tooling/runtime-preflight.sh --exec -- \
      pg_ctl -D "$database_root/data" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$database_root"
  fi

  exit "$compatibility_exit"
}

start_compatibility_database() {
  database_port=${KEEPLING_COMPAT_POSTGRES_PORT:-$((56000 + $$ % 1000))}
  database_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-compatibility.XXXXXX")
  mkdir "$database_root/socket"

  ./tooling/runtime-preflight.sh --exec -- \
    initdb --auth-host=trust --auth-local=trust --encoding=UTF8 --no-locale \
      -D "$database_root/data" >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    pg_ctl -D "$database_root/data" \
      -l "$database_root/postgres.log" \
      -o "-h 127.0.0.1 -k $database_root/socket -p $database_port" \
      -w start >/dev/null
  ./tooling/runtime-preflight.sh --exec -- \
    createdb -h 127.0.0.1 -p "$database_port" keepling_compatibility

  database_user=$(id -un)
  export KEEPLING_TEST_DATABASE_URL="ecto://$database_user@127.0.0.1:$database_port/keepling_compatibility"
  export KEEPLING_TEST_SECRET_KEY_BASE='compatibility-test-only-secret-key-base-0000000000000000000000000000000000000000000000'
}

trap cleanup_compatibility_database EXIT HUP INT TERM

pnpm contracts:check
start_compatibility_database

MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
  'cd apps/server && mix ecto.migrate && mix test test/keepling/application/compatibility_test.exs test/keepling_web/compatibility_controller_test.exs'

migration_count=$(
  ./tooling/runtime-preflight.sh --exec -- \
    psql -h 127.0.0.1 -p "$database_port" -U "$database_user" \
      -d keepling_compatibility -Atc 'SELECT count(*) FROM schema_migrations' |
    tail -n 1
)

case "$migration_count" in
  ''|*[!0-9]*)
    echo "Compatibility matrix could not determine the executed migration count" >&2
    exit 1
    ;;
  0)
    echo "Compatibility matrix executed zero migrations" >&2
    exit 1
    ;;
esac

echo "Compatibility matrix passed with $migration_count executable migrations and exact current/previous digest-schema-train evidence"
