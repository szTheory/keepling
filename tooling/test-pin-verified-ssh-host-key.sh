#!/usr/bin/env sh
set -eu
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { printf 'Host-key pin regression failed: %s\n' "$1" >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-key-test.XXXXXX")
root=$(CDPATH='' cd -P "$root" && pwd)
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
mkdir -m 700 "$root/fixture-bin"
ssh-keygen -q -t ed25519 -N '' -f "$root/host"
fingerprint=$(ssh-keygen -lf "$root/host.pub" -E sha256 | awk '{print $2}')
key_blob=$(awk '{print $2}' "$root/host.pub")
cat >"$root/fixture-bin/ssh-keyscan" <<'EOF'
#!/usr/bin/env sh
set -eu
case "${FIXTURE_SCAN_MODE:-match}" in
  empty) exit 0 ;;
  failed) exit 7 ;;
esac
if [ -n "${FIXTURE_SCAN_RETRY_FILE:-}" ]; then
  count=0
  [ ! -f "$FIXTURE_SCAN_RETRY_FILE" ] || count=$(cat "$FIXTURE_SCAN_RETRY_FILE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$FIXTURE_SCAN_RETRY_FILE"
  [ "$count" -ge 3 ] || exit 0
fi
printf '%s %s %s\n' "$FIXTURE_SCAN_IP" ssh-ed25519 "$FIXTURE_SCAN_KEY"
[ "${FIXTURE_SCAN_MODE:-match}" != duplicate ] || printf '%s %s %s\n' "$FIXTURE_SCAN_IP" ssh-ed25519 "$FIXTURE_SCAN_KEY"
EOF
cat >"$root/fixture-bin/sleep" <<'EOF'
#!/usr/bin/env sh
set -eu
exit 0
EOF
chmod 700 "$root/fixture-bin/ssh-keyscan" "$root/fixture-bin/sleep"
for name in valid mismatch duplicate preexisting valid-retry unavailable invalid-expected unsafe-path; do
  mkdir -m 700 "$root/$name"
  : >"$root/$name/known_hosts"
  chmod 600 "$root/$name/known_hosts"
done

assert_refusal() {
  reason=$1 output=$2
  grep -Fx "host-trust result=refused reason=$reason" "$output" >/dev/null || die "refusal reason $reason was not closed"
  [ "$(wc -l <"$output" | tr -d '[:space:]')" = 1 ] || die 'refusal diagnostics contained more than one line'
  if grep -F "$fingerprint" "$output" >/dev/null || grep -F "$key_blob" "$output" >/dev/null; then
    die 'refusal diagnostics disclosed a fingerprint or key blob'
  fi
}

FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/valid/known_hosts" >"$root/valid/output" 2>&1 || die 'matching independent fingerprint was rejected'
grep -Fx 'host-trust result=verified' "$root/valid/output" >/dev/null || die 'success result was not closed'
[ "$(wc -l <"$root/valid/output" | tr -d '[:space:]')" = 1 ] || die 'success output contained more than one closed result'
if grep -F "$fingerprint" "$root/valid/output" >/dev/null; then die 'success output disclosed the fingerprint'; fi
grep -F '192.0.2.22 ssh-ed25519 ' "$root/valid/known_hosts" >/dev/null || die 'exact candidate address was not pinned'

FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" FIXTURE_SCAN_RETRY_FILE="$root/retries" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/valid-retry/known_hosts" >/dev/null || die 'transient candidate boot delay was not retried'
[ "$(cat "$root/retries")" = 3 ] || die 'host-key scan did not use the expected bounded retry'

encoded_fingerprint=${fingerprint#SHA256:}
first_character=${encoded_fingerprint%${encoded_fingerprint#?}}
replacement=A
[ "$first_character" = A ] && replacement=B
wrong_fingerprint="SHA256:$replacement${encoded_fingerprint#?}"
if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$wrong_fingerprint" "$root/mismatch/known_hosts" >"$root/mismatch/output" 2>&1; then
  die 'mismatched fingerprint was trusted'
fi
assert_refusal fingerprint-mismatch "$root/mismatch/output"
[ ! -s "$root/mismatch/known_hosts" ] || die 'mismatch modified known-hosts'

if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" FIXTURE_SCAN_MODE=duplicate PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/duplicate/known_hosts" >"$root/duplicate/output" 2>&1; then
  die 'ambiguous scan response was trusted'
fi
assert_refusal scan-ambiguous "$root/duplicate/output"
[ ! -s "$root/duplicate/known_hosts" ] || die 'ambiguous scan modified known-hosts'

if FIXTURE_SCAN_MODE=empty PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/unavailable/known_hosts" >"$root/unavailable/output" 2>&1; then
  die 'unavailable scan was accepted'
fi
assert_refusal scan-unavailable "$root/unavailable/output"
[ ! -s "$root/unavailable/known_hosts" ] || die 'unavailable scan modified known-hosts'

if ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 'not-a-fingerprint' "$root/invalid-expected/known_hosts" >"$root/invalid-expected/output" 2>&1; then
  die 'invalid expected fingerprint was accepted'
fi
grep -Fx 'host-trust result=refused reason=invalid-expected-fingerprint' "$root/invalid-expected/output" >/dev/null || die 'invalid expected fingerprint did not return a closed reason'
[ "$(wc -l <"$root/invalid-expected/output" | tr -d '[:space:]')" = 1 ] || die 'invalid-input diagnostics contained more than one line'
if grep -F 'not-a-fingerprint' "$root/invalid-expected/output" >/dev/null; then die 'invalid-input diagnostics echoed caller input'; fi

if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/unsafe-path" >"$root/unsafe-path/output" 2>&1; then
  die 'unsafe known-hosts path was accepted'
fi
grep -Fx 'host-trust result=refused reason=unsafe-known-hosts' "$root/unsafe-path/output" >/dev/null || die 'unsafe path did not return a closed reason'
[ "$(wc -l <"$root/unsafe-path/output" | tr -d '[:space:]')" = 1 ] || die 'unsafe-path diagnostics contained more than one line'

printf '%s\n' '192.0.2.22 ssh-ed25519 preexisting' >"$root/preexisting/known_hosts"
if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/preexisting/known_hosts" >"$root/preexisting/output" 2>&1; then
  die 'nonempty trust file was overwritten'
fi
grep -Fx 'host-trust result=refused reason=unsafe-known-hosts' "$root/preexisting/output" >/dev/null || die 'unsafe file did not return a closed reason'
grep -Fx '192.0.2.22 ssh-ed25519 preexisting' "$root/preexisting/known_hosts" >/dev/null || die 'unsafe known-hosts refusal changed the original file'
[ "$(stat -f '%Lp' "$root/valid/known_hosts" 2>/dev/null || stat -c '%a' "$root/valid/known_hosts")" = 600 ] || die 'successful pin changed the required mode'

echo 'Host-key pin regression passed: closed match, invalid input, unavailable/ambiguous scan, mismatch, and write-once refusal'
