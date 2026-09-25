#!/usr/bin/env sh
set -eu

die() { echo "DNS propagation probe failed: $*" >&2; exit 1; }

[ "$#" -eq 3 ] || die "usage: $0 ZONE_NAME RECORD_NAME EXPECTED_IPV4"
zone_name=$1
record_name=$2
expected_ipv4=$3
dig_bin=${DIG_BIN:-dig}
command -v "$dig_bin" >/dev/null 2>&1 || die "dig is unavailable"
printf '%s' "$zone_name:$record_name" | grep -Eq '^[A-Za-z0-9.-]+:[A-Za-z0-9.-]+$' || die "DNS names are invalid"
printf '%s' "$expected_ipv4" | jq -Re '
  split(".") as $parts | ($parts | length) == 4 and
  all($parts[]; test("^[0-9]{1,3}$") and (tonumber >= 0 and tonumber <= 255))
' >/dev/null || die "expected content must be an IPv4 address"

attempts=${KEEPLING_DNS_PROPAGATION_ATTEMPTS:-12}
delay_seconds=${KEEPLING_DNS_PROPAGATION_DELAY_SECONDS:-5}
case "$attempts:$delay_seconds" in *[!0-9:]*) die "propagation bounds are invalid" ;; esac
[ "$attempts" -ge 1 ] && [ "$attempts" -le 120 ] && [ "$delay_seconds" -le 60 ] || die "propagation bounds are unsafe"

authorities=$($dig_bin +time=3 +tries=1 +short NS "$zone_name" | sed 's/[.]$//' | sort -u)
[ -n "$authorities" ] || die "authoritative nameservers are unavailable"
[ "$(printf '%s\n' "$authorities" | awk 'NF {count++} END {print count+0}')" -le 16 ] || die "authoritative nameserver set is unbounded"
printf '%s\n' "$authorities" | grep -Ev '^[A-Za-z0-9.-]+$' >/dev/null && die "authoritative nameserver identity is invalid"
recursive_resolvers=${KEEPLING_DNS_RECURSIVE_RESOLVERS:-'1.1.1.1 8.8.8.8'}

attempt=1
while [ "$attempt" -le "$attempts" ]; do
  matched=true
  for resolver in $authorities $recursive_resolvers; do
    answer=$($dig_bin +time=3 +tries=1 +short A "$record_name" "@$resolver" 2>/dev/null || true)
    [ "$answer" = "$expected_ipv4" ] || matched=false
  done
  if [ "$matched" = true ]; then
    echo "DNS propagation probe passed: authoritative and recursive resolvers agree"
    exit 0
  fi
  [ "$attempt" -eq "$attempts" ] || sleep "$delay_seconds"
  attempt=$((attempt + 1))
done
die "authoritative and recursive resolvers did not converge within the bounded window"
