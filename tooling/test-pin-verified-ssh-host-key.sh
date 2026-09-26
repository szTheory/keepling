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
if [ -n "${FIXTURE_SCAN_RETRY_FILE:-}" ]; then
  count=0
  [ ! -f "$FIXTURE_SCAN_RETRY_FILE" ] || count=$(cat "$FIXTURE_SCAN_RETRY_FILE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$FIXTURE_SCAN_RETRY_FILE"
  [ "$count" -ge 3 ] || exit 0
fi
printf '%s %s %s\n' "$FIXTURE_SCAN_IP" ssh-ed25519 "$FIXTURE_SCAN_KEY"
[ "${FIXTURE_SCAN_DUPLICATE:-no}" != yes ] || printf '%s %s %s\n' "$FIXTURE_SCAN_IP" ssh-ed25519 "$FIXTURE_SCAN_KEY"
EOF
chmod 700 "$root/fixture-bin/ssh-keyscan"
for name in valid mismatch duplicate preexisting; do
  mkdir -m 700 "$root/$name"
  : >"$root/$name/known_hosts"
  chmod 600 "$root/$name/known_hosts"
done
mkdir -m 700 "$root/valid-retry"
: >"$root/valid-retry/known_hosts"
chmod 600 "$root/valid-retry/known_hosts"

FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/valid/known_hosts" >"$root/valid/output" || die 'matching independent fingerprint was rejected'
grep -Fx 'host-trust result=verified' "$root/valid/output" >/dev/null || die 'success result was not closed'
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
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$wrong_fingerprint" "$root/mismatch/known_hosts" >/dev/null 2>&1; then
  die 'mismatched fingerprint was trusted'
fi
[ ! -s "$root/mismatch/known_hosts" ] || die 'mismatch modified known-hosts'

if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" FIXTURE_SCAN_DUPLICATE=yes PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/duplicate/known_hosts" >/dev/null 2>&1; then
  die 'ambiguous scan response was trusted'
fi

printf '%s\n' '192.0.2.22 ssh-ed25519 preexisting' >"$root/preexisting/known_hosts"
if FIXTURE_SCAN_IP=192.0.2.22 FIXTURE_SCAN_KEY="$key_blob" PATH="$root/fixture-bin:$PATH" \
  ./tooling/pin-verified-ssh-host-key.sh 192.0.2.22 "$fingerprint" "$root/preexisting/known_hosts" >/dev/null 2>&1; then
  die 'nonempty trust file was overwritten'
fi

echo 'Host-key pin regression passed: independent fingerprint match, mismatch, ambiguous scan, and write-once pinning'
