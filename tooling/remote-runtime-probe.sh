#!/bin/sh
set -eu

emit() { printf '%s\n' "$1"; }
fail() { emit "REMOTE_RUNTIME_FAILED_STAGE=$1"; exit "${2:-40}"; }

# The fixture runner is deliberately a separate, explicit branch. Production
# has no runner/path override: it checks the locally bound Keepling release.
if [ "${KEEPLING_REMOTE_RUNTIME_BOUNDARY_TEST:-}" = yes ]; then
  runner=${KEEPLING_REMOTE_RUNTIME_RUNNER:-}
  case "$runner" in /*) [ -x "$runner" ] || fail boundary ;; *) fail boundary ;; esac
  output=$(mktemp "${TMPDIR:-/tmp}/keepling-runtime.XXXXXX") || fail boundary
  trap 'rm -f -- "$output"' EXIT HUP INT TERM
  if "$runner" >"$output" 2>/dev/null && [ "$(wc -c <"$output" | tr -d ' ')" -le 256 ] && [ "$(cat "$output")" = 'READY=loopback' ]; then
    emit 'REMOTE_RUNTIME_STAGE=ready'
    exit 0
  fi
  fail readiness 41
fi

[ "$#" -eq 1 ] && [ "$1" = --bootstrap ] || [ "$#" -eq 0 ] || fail boundary
if [ "$#" -eq 1 ]; then
  jq_bin=$(command -v jq 2>/dev/null || true)
  case "$jq_bin" in /*) ;; *) fail dependency;; esac
  sentinel=/var/lib/keepling/bootstrap-complete.json
  runtime=/usr/local/libexec/keepling-runtime-probe
  semantic=/usr/local/libexec/keepling-semantic-proof
  [ "$(stat -c '%U:%G:%a' "$sentinel" 2>/dev/null)" = root:root:600 ] || fail bootstrap
  [ "$(stat -c '%U:%G:%a' "$runtime" 2>/dev/null)" = root:root:755 ] || fail bootstrap
  [ "$(stat -c '%U:%G:%a' "$semantic" 2>/dev/null)" = root:root:755 ] || fail bootstrap
  [ "$(sha256sum "$runtime" | awk '{print $1}')" = "$("$jq_bin" -r .runtime_probe_sha256 "$sentinel")" ] || fail bootstrap
  [ "$(sha256sum "$semantic" | awk '{print $1}')" = "$("$jq_bin" -r .semantic_probe_sha256 "$sentinel")" ] || fail bootstrap
  "$jq_bin" -e '(keys|sort)==["runtime_probe_sha256","semantic_probe_sha256","status","version"] and .version==1 and .status=="complete"' "$sentinel" >/dev/null 2>&1 || fail bootstrap
  emit 'REMOTE_BOOTSTRAP_STAGE=ready'
  exit 0
fi
curl_bin=$(command -v curl 2>/dev/null || true)
jq_bin=$(command -v jq 2>/dev/null || true)
case "$curl_bin:$jq_bin" in /*:/*) ;; *) fail dependency;; esac
# The public readiness projection is closed, and its ready state is computed
# only after DB, schema, protocol, migration, and finalized-epoch checks.
response=$("$curl_bin" --silent --show-error --fail --max-time 5 --noproxy '*' \
  http://127.0.0.1:4000/health/ready 2>/dev/null) || fail readiness 41
[ "${#response}" -le 256 ] || fail readiness 41
printf '%s\n' "$response" | "$jq_bin" -e 'type=="object" and (keys|sort)==["code","status"] and .code=="ready" and .status=="ready"' >/dev/null 2>&1 || fail readiness 41
emit 'REMOTE_RUNTIME_STAGE=ready'
