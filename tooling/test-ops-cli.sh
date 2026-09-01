#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
ops="$repository_root/tooling/keepling-ops"

fail() {
  echo "Ops CLI test failed: $*" >&2
  exit 1
}

[ -x "$ops" ] || fail "tooling/keepling-ops is missing or not executable"

: "${KEEPLING_TEST_DATABASE_URL:?KEEPLING_TEST_DATABASE_URL is required}"
: "${KEEPLING_TEST_SECRET_KEY_BASE:?KEEPLING_TEST_SECRET_KEY_BASE is required}"

temporary_root=$(mktemp -d /tmp/keepling-ops-cli.XXXXXX)
cleanup() {
  case "$temporary_root" in
    /tmp/keepling-ops-cli.*) rm -rf -- "$temporary_root" ;;
    *) fail "refusing to clean unexpected temporary path" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

release_path="$temporary_root/release"
release_log="$temporary_root/release-build.log"

(
  cd "$repository_root/apps/server"
  MIX_ENV=test mix ecto.create --quiet
  MIX_ENV=test mix ecto.migrate --quiet

  DATABASE_URL="$KEEPLING_TEST_DATABASE_URL" \
    SECRET_KEY_BASE="$KEEPLING_TEST_SECRET_KEY_BASE" \
    PHX_HOST=localhost \
    KEEPLING_SERVER_RELEASE=0.1.0-dev \
    KEEPLING_TESTED_OCI_DIGEST="sha256:$(printf '%064d' 0)" \
    KEEPLING_UPDATE_LOCATION=https://github.com/szTheory/keepling/releases \
    KEEPLING_OPERATOR_TOKEN=0123456789abcdef0123456789abcdef \
    MIX_ENV=prod mix release --overwrite --path "$release_path" >"$release_log" 2>&1
) || {
  sed -n '1,220p' "$release_log" >&2
  fail "release build failed"
}

digest="sha256:$(printf '%064d' 0)"
source_result=
release_result=

run_mode() {
  mode=$1
  expected_exit=$2
  shift 2
  stdout_file="$temporary_root/$mode.stdout"
  stderr_file="$temporary_root/$mode.stderr"

  set +e
  if [ "$mode" = source ]; then
    MIX_ENV=test \
      KEEPLING_TEST_DATABASE_URL="$KEEPLING_TEST_DATABASE_URL" \
      KEEPLING_TEST_SECRET_KEY_BASE="$KEEPLING_TEST_SECRET_KEY_BASE" \
      "$ops" "$@" >"$stdout_file" 2>"$stderr_file"
  else
    DATABASE_URL="$KEEPLING_TEST_DATABASE_URL" \
      SECRET_KEY_BASE="$KEEPLING_TEST_SECRET_KEY_BASE" \
      PHX_HOST=localhost \
      KEEPLING_SERVER_RELEASE=0.1.0-dev \
      KEEPLING_TESTED_OCI_DIGEST="$digest" \
      KEEPLING_UPDATE_LOCATION=https://github.com/szTheory/keepling/releases \
      KEEPLING_OPERATOR_TOKEN=0123456789abcdef0123456789abcdef \
      KEEPLING_RELEASE_BIN="$release_path/bin/keepling" \
      "$ops" "$@" >"$stdout_file" 2>"$stderr_file"
  fi
  actual_exit=$?
  set -e

  [ "$actual_exit" -eq "$expected_exit" ] || {
    sed -n '1,160p' "$stdout_file" >&2
    sed -n '1,160p' "$stderr_file" >&2
    fail "$mode $* exited $actual_exit, expected $expected_exit"
  }
}

assert_closed_json() {
  file=$1
  operation=$2

  node -e '
    const fs = require("fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const keys = Object.keys(value).sort().join(",");
    const expected = "code,exit_code,facts,operation,remediation,retryable,status,version";
    if (keys !== expected || value.operation !== process.argv[2] || value.version !== 1) process.exit(1);
  ' "$file" "$operation" || fail "$operation did not emit the closed JSON result"
}

assert_equivalent() {
  left=$1
  right=$2

  node -e '
    const fs = require("fs");
    const a = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const b = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    if (JSON.stringify(a) !== JSON.stringify(b)) process.exit(1);
  ' "$left" "$right" || fail "source and release JSON results differ"
}

test_verb() {
  operation=$1
  expected_exit=$2
  shift 2

  run_mode source "$expected_exit" "$operation" --json --no-color "$@"
  cp "$temporary_root/source.stdout" "$temporary_root/$operation.source.json"
  assert_closed_json "$temporary_root/$operation.source.json" "$operation"

  run_mode release "$expected_exit" "$operation" --json --no-color "$@"
  cp "$temporary_root/release.stdout" "$temporary_root/$operation.release.json"
  assert_closed_json "$temporary_root/$operation.release.json" "$operation"
  assert_equivalent "$temporary_root/$operation.source.json" "$temporary_root/$operation.release.json"
}

test_verb preflight 10
test_verb status 20
test_verb doctor 20
test_verb backup 50
test_verb restore 50 --confirmed --source-digest "$digest" --target-class empty_isolated
test_verb restore-verify 50 --confirmed --source-digest "$digest" --target-class empty_isolated
test_verb deploy 10 --confirmed --tested-oci-digest "$digest" --target-class replaceable_candidate
test_verb upgrade 10 --confirmed --tested-oci-digest "$digest" --target-class replaceable_candidate
test_verb replace-host 10 --confirmed --tested-oci-digest "$digest" --target-class replaceable_candidate

run_mode source 2 unknown --json --hostile-value private-token-sentinel
assert_closed_json "$temporary_root/source.stdout" unknown
if grep -F 'private-token-sentinel' "$temporary_root/source.stdout" "$temporary_root/source.stderr" >/dev/null; then
  fail "invalid-argument output leaked an untrusted value"
fi

run_mode source 20 status --no-color
if LC_ALL=C grep "$(printf '\033')" "$temporary_root/source.stdout" >/dev/null; then
  fail "--no-color output contains an ANSI escape"
fi
grep -F 'status: backup_rpo_not_met (exit 20)' "$temporary_root/source.stdout" >/dev/null ||
  fail "human output is not concise and stable"

echo "Ops CLI proof passed: 9 verbs, source/release equivalence, closed JSON, stable exits, no-color, and redaction"
