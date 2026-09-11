#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

# shellcheck disable=SC1091
. "$repository_root/tooling/runtime-versions.env"

die() {
  echo "Runtime preflight failed: $*" >&2
  exit 1
}

tool_versions_digest() {
  if [ -f "$repository_root/.tool-versions" ]; then
    shasum -a 256 "$repository_root/.tool-versions" | awk '{print $1}'
  else
    echo absent
  fi
}

tool_versions_before=$(tool_versions_digest)

preserve_tool_versions() {
  status=$?
  trap - EXIT HUP INT TERM
  tool_versions_after=$(tool_versions_digest)
  if [ "$tool_versions_before" != "$tool_versions_after" ]; then
    echo "Runtime preflight failed: .tool-versions changed (before $tool_versions_before, after $tool_versions_after)" >&2
    exit 1
  fi
  exit "$status"
}

trap preserve_tool_versions EXIT HUP INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"
}

select_runtime() {
  require_command asdf

  export ASDF_ERLANG_VERSION="$OTP_VERSION"
  export ASDF_ELIXIR_VERSION="$ELIXIR_ASDF_VERSION"

  erlang_root=$(asdf where erlang "$OTP_VERSION" 2>/dev/null) ||
    die "Erlang/OTP selection mismatch: expected $OTP_VERSION, actual not installed; run '$0 --provision'"
  elixir_root=$(asdf where elixir "$ELIXIR_ASDF_VERSION" 2>/dev/null) ||
    die "Elixir selection mismatch: expected $ELIXIR_ASDF_VERSION, actual not installed; run '$0 --provision'"

  # D-10: five Phase 2 jobs and both recovery-drill legs ran only on
  # macos-15 for no reason but historical runner choice. server,
  # sync-property, and backup-restore genuinely need direct pg_ctl/initdb
  # access (backup-restore drives WAL archiving and PITR directly against
  # the data directory), which a GitHub Actions `services:` container does
  # not expose -- so the Linux path installs a real local PostgreSQL server
  # via apt/PGDG rather than brew, and is selected the same way brew's keg
  # is selected on Darwin.
  if [ "$(uname -s)" = "Darwin" ]; then
    require_command brew
    postgresql_root=$(brew --prefix postgresql@18 2>/dev/null) ||
      die "PostgreSQL selection mismatch: expected $POSTGRESQL_VERSION, actual not installed; run '$0 --provision'"
  else
    postgres_major=${POSTGRESQL_VERSION%%.*}
    postgresql_root="/usr/lib/postgresql/$postgres_major"
    [ -d "$postgresql_root" ] ||
      die "PostgreSQL selection mismatch: expected $POSTGRESQL_VERSION, actual not installed; run '$0 --provision'"
  fi

  for executable in postgres psql pg_config; do
    [ -x "$postgresql_root/bin/$executable" ] ||
      die "expected executable '$postgresql_root/bin/$executable' is unavailable"
  done

  PATH="$elixir_root/bin:$erlang_root/bin:$postgresql_root/bin:$PATH"
  export PATH
}

actual_version() {
  label=$1
  expected=$2
  actual=$3
  [ "$actual" = "$expected" ] ||
    die "$label version mismatch: expected $expected, actual ${actual:-unknown}"
}

check_runtime() {
  select_runtime

  elixir_output=$(elixir --version 2>&1) || die "elixir --version failed"
  actual_elixir=$(printf '%s\n' "$elixir_output" | sed -n 's/^Elixir \([^ ]*\).*/\1/p' | tail -n 1)
  actual_otp_release=$(erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' 2>/dev/null) ||
    die "OTP release probe failed"
  expected_otp_release=${OTP_VERSION%%.*}
  otp_version_file="$erlang_root/releases/$actual_otp_release/OTP_VERSION"
  [ -f "$otp_version_file" ] || die "OTP patch metadata is unavailable at $otp_version_file"
  actual_otp=$(sed -n '1p' "$otp_version_file")
  actual_postgres=$(postgres --version 2>&1 | sed -n 's/^postgres (PostgreSQL) \([^ ]*\).*/\1/p')
  actual_psql=$(psql --version 2>&1 | sed -n 's/^psql (PostgreSQL) \([^ ]*\).*/\1/p')
  actual_pg_config=$(pg_config --version 2>&1 | sed -n 's/^PostgreSQL \([^ ]*\).*/\1/p')

  actual_version Elixir "$ELIXIR_VERSION" "$actual_elixir"
  actual_version "Erlang/OTP release" "$expected_otp_release" "$actual_otp_release"
  actual_version "Erlang/OTP patch" "$OTP_VERSION" "$actual_otp"
  actual_version postgres "$POSTGRESQL_VERSION" "$actual_postgres"
  actual_version psql "$POSTGRESQL_VERSION" "$actual_psql"
  actual_version pg_config "$POSTGRESQL_VERSION" "$actual_pg_config"

  echo "Runtime preflight passed: Elixir $ELIXIR_VERSION, OTP $OTP_VERSION, PostgreSQL $POSTGRESQL_VERSION"
}

provision_runtime() {
  require_command asdf

  export ASDF_ERLANG_VERSION="$OTP_VERSION"
  export ASDF_ELIXIR_VERSION="$ELIXIR_ASDF_VERSION"

  # D-10: a fresh CI runner has no asdf plugins registered, so `asdf install`
  # fails before it ever reaches a version-resolution problem. Register each
  # plugin idempotently first -- tolerating an already-registered plugin --
  # so this preflight is safe to re-run and safe on a runner that has never
  # seen asdf before.
  asdf plugin add erlang || true
  asdf plugin add elixir || true
  asdf plugin add postgres || true

  asdf install erlang "$OTP_VERSION"
  asdf install elixir "$ELIXIR_ASDF_VERSION"

  if [ "$(uname -s)" = "Darwin" ]; then
    require_command brew
    brew install postgresql@18
  else
    postgres_major=${POSTGRESQL_VERSION%%.*}
    if ! [ -x "/usr/lib/postgresql/$postgres_major/bin/postgres" ]; then
      require_command sudo
      require_command curl
      sudo install -d /usr/share/postgresql-common/pgdg
      sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc
      codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
      echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" |
        sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
      sudo apt-get update
      sudo apt-get install -y "postgresql-$postgres_major"
    fi
  fi

  check_runtime
}

usage() {
  echo "Usage: $0 --check | --provision | --exec -- COMMAND..." >&2
  exit 2
}

case "${1:-}" in
  --check)
    [ "$#" -eq 1 ] || usage
    check_runtime
    ;;
  --provision)
    [ "$#" -eq 1 ] || usage
    provision_runtime
    ;;
  --exec)
    shift
    [ "${1:-}" = "--" ] || usage
    shift
    [ "$#" -gt 0 ] || usage
    check_runtime
    "$@"
    ;;
  *)
    usage
    ;;
esac
