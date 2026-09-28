#!/usr/bin/env sh
set -eu
umask 077

refuse() { printf 'host-trust result=refused reason=%s\n' "$1" >&2; exit 1; }
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
[ "$#" -eq 3 ] || refuse invalid-invocation
ip=$1 expected=$2 known_hosts=$3
printf '%s' "$ip" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1; exit 0} {exit 1}' || refuse invalid-candidate-address
printf '%s' "$expected" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' || refuse invalid-expected-fingerprint
case "$known_hosts" in /*) ;; *) refuse unsafe-known-hosts;; esac
case "$known_hosts" in "$repository_root"|"$repository_root"/*) refuse unsafe-known-hosts;; esac
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] || refuse unsafe-known-hosts
mode=$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts") || refuse unsafe-known-hosts
[ "$mode" = 600 ] && [ ! -s "$known_hosts" ] || refuse unsafe-known-hosts

directory=$(CDPATH='' cd -P "$(dirname "$known_hosts")" 2>/dev/null && pwd) || refuse unsafe-known-hosts
known_hosts="$directory/$(basename "$known_hosts")"
case "$known_hosts" in "$repository_root"|"$repository_root"/*) refuse unsafe-known-hosts;; esac
candidate=$(mktemp "${TMPDIR:-/tmp}/keepling-host-key-scan.XXXXXX") || refuse scan-unavailable
scanned=$(mktemp "${TMPDIR:-/tmp}/keepling-host-key-raw.XXXXXX") || { rm -f -- "$candidate"; refuse scan-unavailable; }
staged=$(mktemp "$directory/.known-hosts.XXXXXX") || { rm -f -- "$candidate" "$scanned"; refuse unsafe-known-hosts; }
trap 'rm -f -- "$candidate" "$scanned" "$staged"' EXIT HUP INT TERM

attempt=1
while [ "$attempt" -le 5 ]; do
  : >"$candidate"
  : >"$scanned"
  scan_status=0
  ssh-keyscan -T 5 -t ed25519 "$ip" >"$scanned" 2>/dev/null || scan_status=$?
  filter_status=0
  awk -v ip="$ip" '
    NF == 3 && $1 == ip && $2 == "ssh-ed25519" {
      print
      count++
      if (count > 1) exit 2
    }
  ' "$scanned" >"$candidate" || filter_status=$?
  count=$(wc -l <"$candidate" | tr -d '[:space:]')
  [ "$count" -le 1 ] || refuse scan-ambiguous
  [ "$filter_status" -ne 2 ] || refuse scan-ambiguous
  if [ "$count" = 1 ] && [ "$scan_status" -eq 0 ] && [ "$filter_status" -eq 0 ]; then break; fi
  : >"$candidate"
  [ "$attempt" -lt 5 ] || refuse scan-unavailable
  sleep 3
  attempt=$((attempt + 1))
done

offered=$(ssh-keygen -lf "$candidate" -E sha256 2>/dev/null | awk '
  NF >= 4 && $NF == "(ED25519)" && length($2) == 50 &&
  substr($2, 1, 7) == "SHA256:" && substr($2, 8) ~ /^[A-Za-z0-9+\/]+$/ {
    fingerprint = $2
    count++
  }
  END { if (count == 1) print fingerprint; else exit 1 }
' 2>/dev/null) || refuse scan-invalid-key
[ "$offered" = "$expected" ] || refuse fingerprint-mismatch

cp "$candidate" "$staged" || refuse pin-write-failed
chmod 600 "$staged" || refuse pin-write-failed
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts")" = 600 ] && [ ! -s "$known_hosts" ] || refuse unsafe-known-hosts
mv "$staged" "$known_hosts" || refuse pin-write-failed
trap 'rm -f -- "$candidate" "$scanned"' EXIT HUP INT TERM
printf '%s\n' 'host-trust result=verified'
