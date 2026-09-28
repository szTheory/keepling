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

capture_record() (
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
)

read_record() {
  record_id=$1
  token=$2
  curl --silent --show-error --fail \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records/$record_id"
}

record_matches() {
  response=$1
  record_file=$2
  expected_content=$3
  jq -e \
    --arg id "$(jq -r '.id' "$record_file")" \
    --arg name "$KEEPLING_DNS_RECORD_NAME" \
    --arg content "$expected_content" \
    --argjson ttl "$(jq '.ttl' "$record_file")" \
    --argjson proxied "$(jq '.proxied' "$record_file")" \
    '.success == true and .result.id == $id and .result.type == "A" and .result.name == $name and .result.content == $content and .result.ttl == $ttl and .result.proxied == $proxied' \
    >/dev/null
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
  current=$(read_record "$record_id" "$token")
  printf '%s' "$current" | record_matches /dev/stdin "$record_file" "$expected_content" ||
    die "current DNS state does not exactly match the expected source"
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

rehearse_record() (
  [ "$#" -eq 2 ] || die "usage: rehearse TARGET_IPV4 EVIDENCE_FILE"
  target_content=$1
  evidence_file=$2
  [ ! -e "$evidence_file" ] || die "evidence file already exists"
  evidence_directory=$(dirname "$evidence_file")
  [ -d "$evidence_directory" ] || die "evidence directory is missing"
  case "$evidence_file" in
    "$repository_root"|"$repository_root"/*) die "DNS rehearsal evidence must remain outside the repository" ;;
  esac
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = yes ] ||
    die "live DNS mutation requires KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes"
  propagation_runner=${KEEPLING_DNS_PROPAGATION_RUNNER:-$repository_root/infra/dns/probe-propagation.sh}
  [ -x "$propagation_runner" ] || die "DNS propagation runner is unavailable"
  require_authority

  workspace=$(mktemp -d "${TMPDIR:-/tmp}/keepling-dns-rehearsal.XXXXXX")
  chmod 700 "$workspace"
  original_record=$workspace/original.json
  dns_state=unknown
  zone_name=
  started=$(date +%s)
  # Invoked indirectly by the signal/exit trap below.
  # shellcheck disable=SC2329
  cleanup_rehearsal() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$dns_state" = target ]; then
      original_content=$(jq -r '.content' "$original_record")
      if put_record "$original_record" "$original_content" "$target_content" >/dev/null 2>&1; then
        dns_state=original
        [ -n "$zone_name" ] && "$propagation_runner" "$zone_name" "$KEEPLING_DNS_RECORD_NAME" "$original_content" >/dev/null 2>&1 || result=1
      else
        result=1
      fi
    elif [ "$dns_state" = original ] && [ -n "$zone_name" ]; then
      original_content=$(jq -r '.content' "$original_record")
      "$propagation_runner" "$zone_name" "$KEEPLING_DNS_RECORD_NAME" "$original_content" >/dev/null 2>&1 || result=1
    fi
    rm -rf -- "$workspace"
    exit "$result"
  }
  trap cleanup_rehearsal EXIT HUP INT TERM

  capture_record "$original_record" >/dev/null
  original_content=$(jq -r '.content' "$original_record")
  [ "$original_content" != "$target_content" ] || die "source and target DNS content are equal"
  token=$(cat "$CLOUDFLARE_API_TOKEN_FILE")
  zone_response=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID")
  zone_name=$(printf '%s' "$zone_response" | jq -er '
    select(.success == true) | .result.name |
    select(type == "string" and test("^[A-Za-z0-9.-]+$") and length <= 253)
  ') || die "Cloudflare zone identity is invalid"

  put_record "$original_record" "$target_content" "$original_content" >/dev/null
  dns_state=target
  current=$(read_record "$(jq -r '.id' "$original_record")" "$token")
  printf '%s' "$current" | record_matches /dev/stdin "$original_record" "$target_content" ||
    die "staged DNS state was not re-read exactly"
  "$propagation_runner" "$zone_name" "$KEEPLING_DNS_RECORD_NAME" "$target_content" >/dev/null ||
    die "staged DNS content did not propagate"

  put_record "$original_record" "$original_content" "$target_content" >/dev/null
  dns_state=original
  current=$(read_record "$(jq -r '.id' "$original_record")" "$token")
  printf '%s' "$current" | record_matches /dev/stdin "$original_record" "$original_content" ||
    die "rollback DNS state was not re-read exactly"
  "$propagation_runner" "$zone_name" "$KEEPLING_DNS_RECORD_NAME" "$original_content" >/dev/null ||
    die "rollback DNS content did not propagate"

  elapsed=$(( $(date +%s) - started ))
  evidence_tmp=$(mktemp "$evidence_directory/.dns-rehearsal.XXXXXX")
  chmod 600 "$evidence_tmp"
  jq -n --argjson elapsed "$elapsed" \
    '{version:1,result:"PASS",cutover_propagated:true,rollback_propagated:true,elapsed_seconds:$elapsed}' >"$evidence_tmp"
  mv "$evidence_tmp" "$evidence_file"
  dns_state=verified
  trap - EXIT HUP INT TERM
  rm -rf -- "$workspace"
  echo "Cloudflare DNS rehearsal passed: staged propagation and exact rollback propagation were verified"
)

rehearse_temporary_record() (
  [ "$#" -eq 3 ] || die "usage: rehearse-temporary HOST TARGET_IPV4 EVIDENCE_FILE"
  host=$1 target_content=$2 evidence_file=$3
  [ ! -e "$evidence_file" ] || die "evidence file already exists"
  case "$host" in phase2-*[a-z0-9]) ;; *) die "temporary host is not run-scoped" ;; esac
  printf '%s' "$host" | grep -Eq '^phase2-[a-z0-9-]+\.[a-z0-9.-]+$' || die "temporary host is invalid"
  valid_ipv4() { printf '%s' "$1" | jq -Re 'split(".") as $p | ($p|length)==4 and all($p[];test("^[0-9]{1,3}$") and tonumber<=255)' >/dev/null; }
  valid_ipv4 "$target_content" || die "target content must be an IPv4 address"
  [ "$target_content" != 192.0.2.1 ] || die "candidate cannot equal reserved sentinel"
  evidence_directory=$(dirname "$evidence_file")
  [ -d "$evidence_directory" ] || die "evidence directory is missing"
  case "$evidence_file" in "$repository_root"|"$repository_root"/*) die "DNS evidence must remain outside the repository";; esac
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = yes ] || die "live DNS mutation requires KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes"
  propagation_runner=${KEEPLING_DNS_PROPAGATION_RUNNER:-$repository_root/infra/dns/probe-propagation.sh}
  [ -x "$propagation_runner" ] || die "DNS propagation runner is unavailable"
  require_authority
  token=$(cat "$CLOUDFLARE_API_TOKEN_FILE")
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/keepling-dns-temporary.XXXXXX"); chmod 700 "$workspace"
  record_file=$workspace/record.json; dns_state=absent; zone_name=; started=$(date +%s)
  cleanup_temporary() {
    result=$?; trap - EXIT HUP INT TERM
    if [ -s "$record_file" ] && { [ "$dns_state" = sentinel ] || [ "$dns_state" = target ] || [ "$dns_state" = target-restored ]; }; then
      id=$(jq -r '.id' "$record_file")
      current=$(read_record "$id" "$token" 2>/dev/null || true)
      current_content=$(printf '%s' "$current" | jq -er --arg id "$id" --arg name "$host" --arg target "$target_content" '.result | select(.id==$id and .type=="A" and .name==$name and (.ttl==60) and (.proxied==false) and (.content=="192.0.2.1" or .content==$target)) | .content' 2>/dev/null || true)
      case "$current_content" in
        "$target_content")
          put_record "$record_file" 192.0.2.1 "$target_content" >/dev/null 2>&1 || result=1
          [ -n "$zone_name" ] && "$propagation_runner" "$zone_name" "$host" 192.0.2.1 >/dev/null 2>&1 || result=1 ;;
        192.0.2.1) ;;
        *) result=1 ;;
      esac
      current=$(read_record "$id" "$token" 2>/dev/null || true)
      if printf '%s' "$current" | record_matches /dev/stdin "$record_file" 192.0.2.1 >/dev/null 2>&1; then
        deleted=$(curl --silent --show-error --fail --request DELETE --header "Authorization: Bearer $token" --header 'Content-Type: application/json' "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records/$id" 2>/dev/null) || { result=1; deleted=; }
        if [ -n "$deleted" ]; then printf '%s' "$deleted" | jq -e --arg id "$id" '.success==true and .result.id==$id' >/dev/null 2>&1 && dns_state=deleted || result=1; fi
      else result=1; fi
      if [ "$dns_state" = deleted ]; then
        remaining=$(curl --silent --show-error --fail --get --header "Authorization: Bearer $token" --header 'Content-Type: application/json' --data-urlencode type=A --data-urlencode "name=$host" "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records" 2>/dev/null || true)
        printf '%s' "$remaining" | jq -e '.success==true and (.result|length)==0' >/dev/null 2>&1 || result=1
      fi
    fi
    rm -rf -- "$workspace"; exit "$result"
  }
  trap cleanup_temporary EXIT HUP INT TERM
  list=$(curl --silent --show-error --fail --get --header "Authorization: Bearer $token" --header 'Content-Type: application/json' --data-urlencode type=A --data-urlencode "name=$host" "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records") || die "temporary DNS collision query failed"
  printf '%s' "$list" | jq -e '.success==true and (.result|length)==0' >/dev/null || die "temporary DNS name is already occupied or ambiguous"
  zone_response=$(curl --silent --show-error --fail --header "Authorization: Bearer $token" "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID")
  zone_name=$(printf '%s' "$zone_response" | jq -er '.result.name|select(type=="string" and test("^[A-Za-z0-9.-]+$") and length<=253)') || die "Cloudflare zone identity is invalid"
  body=$(jq -cn --arg name "$host" '{type:"A",name:$name,content:"192.0.2.1",ttl:60,proxied:false}')
  created=$(curl --silent --show-error --fail --request POST --header "Authorization: Bearer $token" --header 'Content-Type: application/json' --data "$body" "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records") || die "temporary DNS creation failed"
  printf '%s' "$created" | jq -e --arg name "$host" '.success==true and .result.type=="A" and .result.name==$name and .result.content=="192.0.2.1" and .result.ttl==60 and .result.proxied==false and (.result.id|type=="string")' >/dev/null || die "temporary DNS creation was not exact"
  printf '%s' "$created" | jq '.result|{id,type,name,content,ttl,proxied}' >"$record_file"; chmod 600 "$record_file"; dns_state=sentinel
  "$propagation_runner" "$zone_name" "$host" 192.0.2.1 >/dev/null || die "temporary sentinel did not propagate"
  put_record "$record_file" "$target_content" 192.0.2.1 >/dev/null; dns_state=target
  "$propagation_runner" "$zone_name" "$host" "$target_content" >/dev/null || die "temporary candidate did not propagate"
  current=$(read_record "$(jq -r '.id' "$record_file")" "$token")
  printf '%s' "$current" | record_matches /dev/stdin "$record_file" "$target_content" || die "temporary candidate state did not re-read exactly"
  curl --silent --show-error --fail --max-time 30 "https://$host/health/ready" >/dev/null || die "temporary HTTPS readiness check failed"
  put_record "$record_file" 192.0.2.1 "$target_content" >/dev/null; dns_state=target-restored
  "$propagation_runner" "$zone_name" "$host" 192.0.2.1 >/dev/null || die "temporary sentinel rollback did not propagate"
  id=$(jq -r '.id' "$record_file"); current=$(read_record "$id" "$token")
  printf '%s' "$current" | jq -e --arg id "$id" --arg name "$host" '.success==true and .result.id==$id and .result.name==$name and .result.content=="192.0.2.1"' >/dev/null || die "temporary sentinel rollback did not re-read exactly"
  deleted=$(curl --silent --show-error --fail --request DELETE --header "Authorization: Bearer $token" --header 'Content-Type: application/json' "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records/$id")
  printf '%s' "$deleted" | jq -e --arg id "$id" '.success==true and .result.id==$id' >/dev/null || die "temporary DNS deletion was not acknowledged"
  dns_state=deleted
  remaining=$(curl --silent --show-error --fail --get --header "Authorization: Bearer $token" --header 'Content-Type: application/json' --data-urlencode type=A --data-urlencode "name=$host" "https://api.cloudflare.com/client/v4/zones/$KEEPLING_DNS_ZONE_ID/dns_records")
  printf '%s' "$remaining" | jq -e '.success==true and (.result|length)==0' >/dev/null || die "temporary DNS deletion was not verified"
  elapsed=$(( $(date +%s) - started )); jq -n --argjson elapsed "$elapsed" '{version:1,result:"PASS",cutover_propagated:true,rollback_propagated:true,temporary_record_deleted:true,https_readiness:true,elapsed_seconds:$elapsed}' >"$evidence_file"; chmod 600 "$evidence_file"
  trap - EXIT HUP INT TERM; rm -rf -- "$workspace"
  echo "Cloudflare temporary DNS rehearsal passed: run-scoped cutover, HTTPS readiness, rollback, and deletion verified"
)

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
  rehearse) shift; rehearse_record "$@" ;;
  rehearse-temporary) shift; rehearse_temporary_record "$@" ;;
  *) die "usage: $0 self-test | capture OUTPUT_FILE | put RECORD_FILE TARGET_IPV4 EXPECTED_CURRENT_IPV4 | rehearse TARGET_IPV4 EVIDENCE_FILE | rehearse-temporary HOST TARGET_IPV4 EVIDENCE_FILE" ;;
esac
