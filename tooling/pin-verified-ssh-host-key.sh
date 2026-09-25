#!/usr/bin/env sh
set -eu
umask 077

die() { printf '%s\n' 'Candidate host-key pin refused' >&2; exit 1; }
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
[ "$#" -eq 3 ] || die
ip=$1 expected=$2 known_hosts=$3
printf '%s' "$ip" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1; exit 0} {exit 1}' || die
printf '%s' "$expected" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' || die
case "$known_hosts" in /*) ;; *) die;; esac
case "$known_hosts" in "$repository_root"|"$repository_root"/*) die;; esac
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] || die
mode=$(stat -f '%Lp' "$known_hosts" 2>/dev/null || stat -c '%a' "$known_hosts")
[ "$mode" = 600 ] && [ ! -s "$known_hosts" ] || die

directory=$(CDPATH='' cd -P "$(dirname "$known_hosts")" && pwd) || die
resolved_known_hosts="$directory/$(basename "$known_hosts")"
case "$resolved_known_hosts" in "$repository_root"|"$repository_root"/*) die;; esac
known_hosts=$resolved_known_hosts
candidate=$(mktemp "${TMPDIR:-/tmp}/keepling-host-key-scan.XXXXXX") || die
staged=$(mktemp "$directory/.known-hosts.XXXXXX") || { rm -f -- "$candidate"; die; }
trap 'rm -f -- "$candidate" "$staged"' EXIT HUP INT TERM

attempt=1
while [ "$attempt" -le 5 ]; do
  : >"$candidate"
  ssh-keyscan -T 5 -t ed25519 "$ip" 2>/dev/null |
    awk -v ip="$ip" 'NF==3 && $1==ip && $2=="ssh-ed25519" {print; if (++count > 1) exit 2}' >"$candidate" || true
  [ -s "$candidate" ] && break
  [ "$attempt" -lt 5 ] || break
  sleep 3
  attempt=$((attempt + 1))
done
[ "$(wc -l <"$candidate" | tr -d '[:space:]')" = 1 ] || die
offered=$(ssh-keygen -lf "$candidate" -E sha256 2>/dev/null | awk 'NR==1 {print $2}')
[ "$offered" = "$expected" ] || die
cp "$candidate" "$staged" || die
chmod 600 "$staged"
[ ! -s "$known_hosts" ] || die
mv "$staged" "$known_hosts" || die
trap 'rm -f -- "$candidate"' EXIT HUP INT TERM
printf '%s\n' 'host-trust result=verified'
