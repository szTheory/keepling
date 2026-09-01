#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/../.." && pwd)

die() {
  echo "Cloudflare DNS adapter failed: $*" >&2
  exit 1
}

require_runtime() {
  for command in curl jq; do
    command -v "$command" >/dev/null 2>&1 || die "required command '$command' is unavailable"
  done
}

require_authority() {
  [ -n "${KEEPLING_DNS_ZONE_ID:-}" ] || die "KEEPLING_DNS_ZONE_ID is missing"
  [ -n "${KEEPLING_DNS_RECORD_NAME:-}" ] || die "KEEPLING_DNS_RECORD_NAME is missing"
  [ -r "${CLOUDFLARE_API_TOKEN_FILE:-}" ] || die "CLOUDFLARE_API_TOKEN_FILE is unreadable"
  case "$CLOUDFLARE_API_TOKEN_FILE" in
    "$repository_root"|"$repository_root"/*) die "DNS token must remain outside the repository" ;;
  esac
}

select_exact_record() {
  jq -ec --arg name "$2" '
    select(.success == true) |
    .result as $records |
    if ($records | length) != 1 then error("expected exactly one A record")
    elif $records[0].type != "A" or $records[0].name != $name then error("record identity mismatch")
    else $records[0] | {id,type,name,content,ttl,proxied}
    end
  ' "$1"
}

capture_record() {
  [ "$#" -eq 1 ] || die "usage: capture OUTPUT_FILE"
  output_file=$1
  [ ! -e "$output_file" ] || die "output file already exists"
  require_authority
  token=$(cat "$CLOUDFLARE_API_TOKEN_FILE")
  response=$(mktemp "${TMPDIR:-/tmp}/keepling-dns-read.XXXXXX")
  trap 'rm -f -- "$response"' EXIT HUP INT TERM
  curl --silent --show-error --fail --get \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data-urlencode 'type=A' \
    --data-urlencode "name=$KEEPLING_DNS_RECORD_NAME" \
    "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records" >"$response"
  umask 077
  select_exact_record "$response" "$KEEPLING_DNS_RECORD_NAME" >"$output_file"
  chmod 600 "$output_file"
  echo "Cloudflare DNS capture passed: exactly one A record retained in the private run workspace"
}

put_record() {
  [ "$#" -eq 3 ] || die "usage: put RECORD_FILE TARGET_IPV4 EXPECTED_CURRENT_IPV4"
  record_file=$1
  next_content=$2
  expected_content=$3
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = "yes" ] || die "live DNS mutation requires KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes"
  require_authority
  jq -e --arg name "$KEEPLING_DNS_RECORD_NAME" '.type == "A" and .name == $name and (.id | type == "string") and (.ttl | type == "number") and (.proxied | type == "boolean")' "$record_file" >/dev/null ||
    die "retained record is invalid"
  valid_ipv4() {
    printf '%s' "$1" | jq -Re '
      split(".") as $parts |
      ($parts | length) == 4 and
      all($parts[]; test("^[0-9]{1,3}$") and (tonumber >= 0 and tonumber <= 255))
    ' >/dev/null
  }
  valid_ipv4 "$next_content" || die "target content must be an IPv4 address"
  valid_ipv4 "$expected_content" || die "expected current content must be an IPv4 address"
  [ "$expected_content" != "$next_content" ] || die "source and target DNS content are equal"

  token=$(cat "$CLOUDFLARE_API_TOKEN_FILE")
  record_id=$(jq -r '.id' "$record_file")
  current=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records/$record_id")
  printf '%s' "$current" | jq -e \
    --arg id "$record_id" --arg name "$KEEPLING_DNS_RECORD_NAME" --arg content "$expected_content" \
    --argjson ttl "$(jq '.ttl' "$record_file")" --argjson proxied "$(jq '.proxied' "$record_file")" \
    '.success == true and .result.id == $id and .result.type == "A" and .result.name == $name and .result.content == $content and .result.ttl == $ttl and .result.proxied == $proxied' \
    >/dev/null || die "current DNS state does not exactly match the expected source"
  body=$(jq -cn --arg name "$KEEPLING_DNS_RECORD_NAME" --arg content "$next_content" \
    --argjson ttl "$(jq '.ttl' "$record_file")" --argjson proxied "$(jq '.proxied' "$record_file")" \
    '{type:"A",name:$name,content:$content,ttl:$ttl,proxied:$proxied}')
  response=$(curl --silent --show-error --fail --request PUT \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body" \
    "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records/$record_id")
  printf '%s' "$response" | jq -e --arg content "$next_content" \
    '.success == true and .result.type == "A" and .result.content == $content' >/dev/null || die "DNS update was not acknowledged exactly"
  echo "Cloudflare DNS update passed: exact retained record identity changed"
}

self_test() {
  fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-dns-self-test.XXXXXX")
  trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
  jq -n '{success:true,result:[{id:"fixture-record",type:"A",name:"host.example.invalid",content:"192.0.2.1",ttl:300,proxied:false}]}' >"$fixture/one.json"
  selected=$(select_exact_record "$fixture/one.json" host.example.invalid)
  printf '%s' "$selected" | jq -e '.content == "192.0.2.1" and .ttl == 300 and .proxied == false' >/dev/null || die "exact record fields were not retained"
  jq -n '{success:true,result:[]}' >"$fixture/none.json"
  ! select_exact_record "$fixture/none.json" host.example.invalid >/dev/null 2>&1 || die "zero records were accepted"
  jq -n '{success:true,result:[{id:"one",type:"A",name:"host.example.invalid"},{id:"two",type:"A",name:"host.example.invalid"}]}' >"$fixture/many.json"
  ! select_exact_record "$fixture/many.json" host.example.invalid >/dev/null 2>&1 || die "ambiguous records were accepted"
  echo "Cloudflare DNS adapter self-test passed"
}

require_runtime
case "${1:-}" in
  self-test) [ "$#" -eq 1 ] || die "usage: $0 self-test"; self_test ;;
  capture) shift; capture_record "$@" ;;
  put) shift; put_record "$@" ;;
  *) die "usage: $0 self-test | capture OUTPUT_FILE | put RECORD_FILE TARGET_IPV4 EXPECTED_CURRENT_IPV4" ;;
esac
