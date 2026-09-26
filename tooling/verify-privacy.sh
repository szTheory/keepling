#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Privacy verification failed: $*" >&2
  exit 1
}

vector=packages/contracts/vectors/redaction.json
[ -f "$vector" ] || die "redaction vector is missing"
command -v jq >/dev/null 2>&1 || die "required command 'jq' is unavailable"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-privacy.XXXXXX")
cleanup() {
  case "$temporary_root" in
    "${TMPDIR:-/tmp}"/keepling-privacy.*) rm -rf -- "$temporary_root" ;;
    *) die "refusing unsafe cleanup" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

sentinels="$temporary_root/sentinels"
jq -er '.hostile_sentinels | type == "array" and length > 0' "$vector" >/dev/null ||
  die "hostile sentinel vector is empty"
jq -r '.hostile_sentinels[]' "$vector" >"$sentinels"

scan_paths() {
  [ "$#" -gt 0 ] || die "at least one diagnostic artifact path is required"
  files="$temporary_root/files"
  : >"$files"

  for candidate in "$@"; do
    [ -e "$candidate" ] || die "diagnostic artifact path is missing"
    if [ -d "$candidate" ]; then
      find "$candidate" -type f -print >>"$files"
    elif [ -f "$candidate" ]; then
      printf '%s\n' "$candidate" >>"$files"
    else
      die "diagnostic artifact path is not a regular file or directory"
    fi
  done

  artifact_count=$(awk 'NF {count += 1} END {print count + 0}' "$files")
  [ "$artifact_count" -gt 0 ] || die "diagnostic artifact set is empty"

  while IFS= read -r artifact; do
    if LC_ALL=C grep -aF -f "$sentinels" "$artifact" >/dev/null 2>&1; then
      die "hostile sentinel found in a diagnostic artifact"
    fi
  done <"$files"

  sentinel_count=$(wc -l <"$sentinels" | tr -d '[:space:]')
  printf '%s\n' "Privacy verification passed: artifacts=$artifact_count sentinels=$sentinel_count"
}

self_test() {
  clean="$temporary_root/clean"
  hostile="$temporary_root/hostile"
  mkdir "$clean" "$hostile"

  for name in logs metrics traces stdout stderr results.json manifest.json plan.tfplan backup.out doctor-bundle.txt; do
    printf '%s\n' 'bounded_status=verified count=1 elapsed_ms=1' >"$clean/$name"
  done
  scan_paths "$clean" >/dev/null

  sentinel_count=$(wc -l <"$sentinels" | tr -d '[:space:]')
  index=0
  for name in logs metrics traces stdout stderr results.json manifest.json plan.tfplan backup.out doctor-bundle.txt; do
    index=$((index + 1))
    sentinel_index=$(( (index - 1) % sentinel_count + 1 ))
    sentinel=$(sed -n "${sentinel_index}p" "$sentinels")
    printf '%s\n' "$sentinel" >"$hostile/$name"
    if (scan_paths "$hostile/$name" >/dev/null 2>&1); then
      die "self-test accepted a hostile diagnostic surface"
    fi
  done

  known_bad_access_log="$temporary_root/known-bad-access-log.Caddyfile"
  known_bad_plaintext_route="$temporary_root/known-bad-plaintext-route.Caddyfile"
  printf '%s\n' 'https://localhost {' '  log {' '    output stdout' '  }' '  reverse_proxy app:4000' '}' >"$known_bad_access_log"
  printf '%s\n' ':80 {' '  reverse_proxy app:4000' '}' >"$known_bad_plaintext_route"
  for fixture in "$known_bad_access_log" "$known_bad_plaintext_route"; do
    if caddy_config_is_safe "$fixture"; then
      die "self-test accepted an unsafe Caddy configuration"
    fi
  done

  printf '%s\n' 'Privacy verifier self-test passed: surfaces=12 clean=accepted hostile=rejected caddy=unsafe-rejected'
}

caddy_config_is_safe() {
  config=$1
  [ -f "$config" ] || die "Caddy configuration is missing"
  if grep -Eq '^[[:space:]]*log[[:space:]]*\{' "$config"; then
    return 1
  fi
  awk '
    /^[[:space:]]*:80[[:space:]]*\{/ { in_http = 1; next }
    in_http && /^[[:space:]]*\}/ { in_http = 0; next }
    in_http && /^[[:space:]]*(reverse_proxy|import|handle|route)[[:space:]]/ { unsafe = 1 }
    END { exit unsafe ? 1 : 0 }
  ' "$config"
}

caddy_boundary() {
  command -v docker >/dev/null 2>&1 || die "required command 'docker' is unavailable"
  command -v curl >/dev/null 2>&1 || die "required command 'curl' is unavailable"

  caddy_image='caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648'
  caddy_config_is_safe "$repository_root/infra/caddy/Caddyfile" || die "Caddy configuration permits diagnostics or plaintext application routing"
  suffix="privacy-$$"
  network="keepling-$suffix"
  proxy="keepling-proxy-$suffix"
  fixture="keepling-fixture-$suffix"
  http_port=$((59000 + $$ % 500))
  https_port=$((http_port + 1))
  boundary_root="$temporary_root/caddy-boundary"
  proxy_output="$boundary_root/proxy-output"
  fixture_output="$boundary_root/fixture-output"
  fixture_config="$boundary_root/fixture.Caddyfile"
  mkdir "$boundary_root"

  boundary_cleanup() {
    docker rm -f "$proxy" "$fixture" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
  }
  trap 'boundary_cleanup; cleanup' EXIT HUP INT TERM

  cat >"$fixture_config" <<'EOF'
{
  admin off
  auto_https off
}

:4000 {
  log {
    output stdout
    format json
  }
  respond "fixture\n" 200
}
EOF

  docker network create "$network" >/dev/null
  docker run -d --rm --name "$fixture" --network "$network" --network-alias app \
    -v "$fixture_config:/etc/caddy/Caddyfile:ro" "$caddy_image" \
    caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
  docker run -d --rm --name "$proxy" --network "$network" \
    -p "127.0.0.1:$http_port:80" -p "127.0.0.1:$https_port:443" \
    -v "$repository_root/infra/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
    -e KEEPLING_HOST=localhost "$caddy_image" \
    caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null

  attempt=0
  until curl -ksS --connect-timeout 1 --resolve "localhost:$https_port:127.0.0.1" \
    "https://localhost:$https_port/health/ready" -o /dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || die "Caddy HTTPS listener did not start"
    sleep 1
  done

  authorization="Bearer $(sed -n '4p' "$sentinels")"
  cookie="session=$(sed -n '5p' "$sentinels")"
  query_value=$(sed -n '1p' "$sentinels")
  identifier=$(sed -n '6p' "$sentinels")
  curl -ksS --connect-timeout 3 --resolve "localhost:$https_port:127.0.0.1" \
    -H "Authorization: $authorization" -H "Cookie: $cookie" \
    "https://localhost:$https_port/fixture?task=$query_value&id=$identifier" \
    -o "$boundary_root/https-response" || die "authenticated HTTPS request did not reach Caddy"

  docker logs "$proxy" >"$proxy_output" 2>&1 || die "could not collect Caddy diagnostics"
  scan_paths "$proxy_output" >/dev/null
  docker logs "$fixture" >"$fixture_output" 2>&1 || die "could not inspect fixture traffic"
  https_requests=$(grep -c '"uri":"/fixture' "$fixture_output" || true)
  [ "$https_requests" -eq 1 ] || die "fixture did not observe exactly one authenticated HTTPS request"

  http_headers="$boundary_root/http-headers"
  http_status=$(curl -sS --connect-timeout 3 -D "$http_headers" -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$http_port/fixture?task=$query_value&id=$identifier" || true)
  case "$http_status" in 301|302|307|308) ;; *) die "plaintext HTTP was not redirect-only" ;; esac
  docker logs "$fixture" >"$fixture_output" 2>&1 || die "could not inspect fixture traffic after HTTP request"
  fixture_requests=$(grep -c '"uri":"/fixture' "$fixture_output" || true)
  [ "$fixture_requests" -eq "$https_requests" ] || die "plaintext HTTP reached the fixture upstream"

  docker rm -f "$fixture" >/dev/null
  set +e
  unavailable_status=$(curl -ksS --connect-timeout 3 --resolve "localhost:$https_port:127.0.0.1" \
    -D "$boundary_root/unavailable-headers" -o /dev/null -w '%{http_code}' \
    "https://localhost:$https_port/health/ready")
  unavailable_result=$?
  set -e
  [ "$unavailable_result" -eq 0 ] || die "HTTPS edge was unavailable while upstream was stopped"
  [ "$unavailable_status" = 503 ] || die "HTTPS edge returned $unavailable_status while upstream was unavailable"
  grep -Eiq '^Retry-After: 2' "$boundary_root/unavailable-headers" || die "HTTPS edge omitted bounded Retry-After guidance"
  docker logs "$proxy" >"$proxy_output" 2>&1 || die "could not recollect Caddy diagnostics"
  scan_paths "$proxy_output" >/dev/null

  printf '%s\n' 'Caddy boundary verification passed: https=private http=redirect-only upstream=one retry_after=2'
}

case "${1:-}" in
  --self-test)
    [ "$#" -eq 1 ] || die "usage: $0 --self-test | PATH [PATH ...]"
    self_test
    ;;
  --caddy-boundary)
    [ "$#" -eq 1 ] || die "usage: $0 --self-test | --caddy-boundary | PATH [PATH ...]"
    caddy_boundary
    ;;
  '') die "usage: $0 --self-test | --caddy-boundary | PATH [PATH ...]" ;;
  *) scan_paths "$@" ;;
esac
