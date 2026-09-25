#!/usr/bin/env sh
set -eu
portable_stat() {
  format=$1; path=$2
  case "$(uname -s)" in
    Darwin) stat -f "$format" "$path" ;;
    *)
      case "$format" in
        %Lp) stat -c '%a' "$path" ;;
        %Su:%Sg) stat -c '%U:%G' "$path" ;;
        %u) stat -c '%u' "$path" ;;
        *) stat -c "$format" "$path" ;;
      esac ;;
  esac
}

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Host replacement readiness regression failed: $*" >&2
  exit 1
}

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-readiness.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

./tooling/verify-host-replacement.sh --print-live-registry >"$fixture_root/registry"
./tooling/verify-host-replacement.sh --validate-live-registry "$fixture_root/registry"
grep -Fx 'dns|cloudflare-propagation-and-rollback|ready' "$fixture_root/registry" >/dev/null ||
  die "DNS lifecycle adapter was not promoted to readiness"
grep -Fx 'teardown|exact-owned-provider-destroy|ready' "$fixture_root/registry" >/dev/null ||
  die "provider teardown adapter was not promoted to readiness"
printf '%s\n' 'unknown|fixture|missing' >>"$fixture_root/registry"
expect_registry_rejection() {
  if ./tooling/verify-host-replacement.sh --validate-live-registry "$1" >/dev/null 2>&1; then
    die "invalid lifecycle registry was accepted"
  fi
}
expect_registry_rejection "$fixture_root/registry"
./tooling/verify-host-replacement.sh --print-live-registry >"$fixture_root/registry"
cat "$fixture_root/registry" "$fixture_root/registry" >"$fixture_root/duplicate-registry"
expect_registry_rejection "$fixture_root/duplicate-registry"
sed '$d' "$fixture_root/registry" >"$fixture_root/incomplete-registry"
expect_registry_rejection "$fixture_root/incomplete-registry"

mkdir "$fixture_root/bin"
cat >"$fixture_root/bin/curl" <<'EOF'
#!/usr/bin/env sh
touch "$KEEPLING_READINESS_EXTERNAL_MARKER"
exit 99
EOF
chmod 700 "$fixture_root/bin/curl"

expect_failure() {
  name=$1
  pattern=$2
  shift 2
  if "$@" >"$fixture_root/$name.out" 2>&1; then
    die "$name unexpectedly passed"
  fi
  grep -F "$pattern" "$fixture_root/$name.out" >/dev/null ||
    die "$name did not report its bounded failure"
}

expect_failure missing-billable \
  'KEEPLING_ALLOW_BILLABLE_APPLY=yes' \
  ./tooling/verify-host-replacement.sh --live-readiness

expect_failure missing-dns \
  'KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes' \
  env KEEPLING_ALLOW_BILLABLE_APPLY=yes \
  ./tooling/verify-host-replacement.sh --live-readiness

expect_failure missing-trigger \
  'KEEPLING_LIVE_CHANGE_TRIGGER' \
  env KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  ./tooling/verify-host-replacement.sh --live-readiness

expect_failure short-trigger \
  'KEEPLING_LIVE_CHANGE_TRIGGER' \
  env KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  KEEPLING_LIVE_CHANGE_TRIGGER=short \
  ./tooling/verify-host-replacement.sh --live-readiness

marker="$fixture_root/external-command-ran"
for stage in bootstrap image restore runtime semantic dns teardown; do
  cat >"$fixture_root/$stage" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod 700 "$fixture_root/$stage"
done
env PATH="$fixture_root/bin:$PATH" KEEPLING_READINESS_EXTERNAL_MARKER="$marker" \
  KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  KEEPLING_LIVE_CHANGE_TRIGGER=approved-2026-09-19 \
  KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER="$fixture_root/bootstrap" \
  KEEPLING_SEQUENCE_IMAGE_RUNNER="$fixture_root/image" \
  KEEPLING_SEQUENCE_RESTORE_RUNNER="$fixture_root/restore" \
  KEEPLING_SEQUENCE_RUNTIME_RUNNER="$fixture_root/runtime" \
  KEEPLING_SEQUENCE_SEMANTIC_RUNNER="$fixture_root/semantic" \
  KEEPLING_SEQUENCE_DNS_RUNNER="$fixture_root/dns" \
  KEEPLING_SEQUENCE_TEARDOWN_RUNNER="$fixture_root/teardown" \
  ./tooling/verify-host-replacement.sh --live-readiness >"$fixture_root/ready.out"
[ ! -e "$marker" ] || die "readiness inspection dispatched an external adapter"

for stage in bootstrap image primary-restore mirror-restore runtime semantic dns teardown; do
  grep -F "stage=$stage status=ready " "$fixture_root/ready.out" >/dev/null ||
    die "readiness did not report $stage"
done
grep -F 'stage=primary-restore status=ready contract=b2-primary-fetch-and-verify' "$fixture_root/ready.out" >/dev/null ||
  die 'B2 adapter was not promoted to readiness'
grep -F 'stage=mirror-restore status=ready contract=r2-mirror-fetch-and-verify' "$fixture_root/ready.out" >/dev/null ||
  die 'R2 adapter was not promoted to readiness'
grep -F 'stage=image status=ready contract=exact-archive-transfer' "$fixture_root/ready.out" >/dev/null ||
  die 'trusted transfer adapter was not promoted to readiness'
grep -F 'stage=runtime status=ready contract=remote-runtime-readiness' "$fixture_root/ready.out" >/dev/null ||
  die 'runtime adapter was not promoted to readiness'
grep -F 'stage=semantic status=ready contract=remote-login-read-write-undo' "$fixture_root/ready.out" >/dev/null ||
  die 'semantic adapter was not promoted to readiness'
for stage in bootstrap image restore runtime semantic dns teardown; do
  grep -F "stage=sequence-$stage status=ready contract=credentialed-sequence-runner" "$fixture_root/ready.out" >/dev/null ||
    die "readiness did not require the $stage sequence runner"
done

expect_failure missing-sequence-runner \
  'missing stages=sequence-bootstrap,sequence-image,sequence-restore,sequence-runtime,sequence-semantic,sequence-dns,sequence-teardown' \
  env KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  KEEPLING_LIVE_CHANGE_TRIGGER=approved-2026-09-19 \
  ./tooling/verify-host-replacement.sh --live-readiness

expect_failure direct-credentialed-missing-trigger \
  'KEEPLING_LIVE_CHANGE_TRIGGER' \
  env KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  ./tooling/verify-host-replacement.sh --credentialed

credentialed_fixture() {
  name=$1
  expected_status=$2
  failure_mode=${3:-}
  fixture="$fixture_root/credentialed-$name"
  mkdir -p "$fixture/bin" "$fixture/credentials" "$fixture/tmp"
  chmod 700 "$fixture" "$fixture/bin" "$fixture/credentials" "$fixture/tmp"

  ambient_hcloud_sentinel='ambient-hcloud-sentinel-v4m-never-persisted'
  token_sentinel='hetzner-token-sentinel-u9k-never-persisted'
  ambient_hcloud_value=${4-"$ambient_hcloud_sentinel"}
  expected_token=${5-"$token_sentinel"}
  jq -n --arg token "$token_sentinel" '{version:1,token:$token}' >"$fixture/credentials/hetzner.json"
  jq -n '{version:1,api_token:"fixture-cloudflare-token",zone_id:"fixture-zone",record_name:"host.example.invalid"}' >"$fixture/credentials/cloudflare.json"
  jq -n '{version:1,endpoint:"https://example.invalid",region:"fixture",bucket:"fixture",access_key_id:"fixture",secret_access_key:"fixture"}' >"$fixture/credentials/primary.json"
  cp "$fixture/credentials/primary.json" "$fixture/credentials/mirror.json"
  jq -n '{version:1,endpoint:"https://example.invalid",region:"fixture",bucket:"fixture",key:"fixture",access_key_id:"fixture",secret_access_key:"fixture"}' >"$fixture/credentials/state.json"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture fixture' >"$fixture/credentials/replacement.pub"
  printf '%s\n' 'fixture-cipher' >"$fixture/credentials/cipher.key"
  chmod 600 "$fixture/credentials"/*

  cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
portable_stat() { case "$(uname -s)" in Darwin) stat -f "$1" "$2" ;; *) case "$1" in %Lp) stat -c '%a' "$2" ;; %u) stat -c '%u' "$2" ;; esac ;; esac; }

record=$KEEPLING_FAKE_CURL_RECORD
: >"$KEEPLING_FAKE_CURL_MARKER"
[ "${HCLOUD_TOKEN+x}" != x ] || exit 89
has_config=false
for argument in "$@"; do
  [ "$argument" = --config ] && has_config=true
done
if [ "$has_config" = true ]; then
    [ "$#" -eq 6 ] && [ "$1" = --silent ] && [ "$2" = --show-error ] && [ "$3" = --fail ] && [ "$4" = --config ] || exit 90
    config=$5
    url=$6
    case "$config" in "$KEEPLING_EXPECTED_PREFLIGHT_TMP"/keepling-replacement-preflight.*/curl.conf) ;; *) exit 91 ;; esac
    [ -f "$config" ] && [ ! -L "$config" ] || exit 92
    [ "$(portable_stat '%Lp' "$config")" = 600 ] || exit 93
    [ "$(portable_stat '%u' "$config")" = "$(id -u)" ] || exit 94
    [ "${KEEPLING_EXPECTED_HCLOUD_TOKEN+x}" = x ] || exit 95
    expected_token=$KEEPLING_EXPECTED_HCLOUD_TOKEN
    [ -n "$expected_token" ] || exit 95
    expected_header='header = "Authorization: Bearer '"$expected_token"'"'
    exec 3<"$config"
    IFS= read -r header <&3 || exit 95
    if [ "$header" != "$expected_header" ] || IFS= read -r extra <&3; then
      exec 3<&-
      printf '%s\n' "provider=hetzner hcloud_env_absent=true args_safe=true header_exact=false config_path=$config config_regular=true config_owner=true config_mode=600" >>"$record"
      exit 95
    fi
    exec 3<&-
    printf '%s\n' "provider=hetzner hcloud_env_absent=true args_safe=true header_exact=true config_path=$config config_regular=true config_owner=true config_mode=600" >>"$record"
    if [ "${KEEPLING_FAKE_CURL_MODE:-}" = fail ]; then
      exit 96
    fi
    if [ "${KEEPLING_FAKE_CURL_MODE:-}" = signal ]; then
      kill -TERM "$PPID"
      exit 97
    fi
    case "$url" in
      'https://api.hetzner.cloud/v1/server_types?per_page=50') printf '%s\n' '{"server_types":[{"name":"cx33","architecture":"x86"}]}' ;;
      'https://api.hetzner.cloud/v1/servers?per_page=50') printf '%s\n' '{"servers":[]}' ;;
      *) exit 98 ;;
    esac
else
  url=''
  for argument in "$@"; do url=$argument; done
  case "$url" in
    'https://api.cloudflare.com/client/v4/zones/fixture-zone/dns_records')
      printf '%s\n' 'provider=cloudflare hcloud_env_absent=true' >>"$record"
      printf '%s\n' '{"success":true,"result":[{"id":"fixture-record","type":"A","name":"host.example.invalid","content":"192.0.2.1","ttl":300,"proxied":false}]}'
      ;;
    *) exit 99 ;;
  esac
fi
EOF
  chmod 700 "$fixture/bin/curl"

  set +e
  env PATH="$fixture/bin:$PATH" TMPDIR="$fixture/tmp" \
    HCLOUD_TOKEN="$ambient_hcloud_value" \
    KEEPLING_FAKE_CURL_RECORD="$fixture/curl-record" \
    KEEPLING_FAKE_CURL_MARKER="$fixture/curl-marker" \
    KEEPLING_EXPECTED_PREFLIGHT_TMP="$fixture/tmp" \
    KEEPLING_EXPECTED_HCLOUD_TOKEN="$expected_token" \
    KEEPLING_FAKE_CURL_MODE="$failure_mode" \
    KEEPLING_HETZNER_CREDENTIAL_FILE="$fixture/credentials/hetzner.json" \
    KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$fixture/credentials/cloudflare.json" \
    KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$fixture/credentials/primary.json" \
    KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$fixture/credentials/mirror.json" \
    KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$fixture/credentials/state.json" \
    KEEPLING_SSH_PUBLIC_KEY_FILE="$fixture/credentials/replacement.pub" \
    KEEPLING_BACKUP_CIPHER_FILE="$fixture/credentials/cipher.key" \
    ./tooling/verify-host-replacement.sh --credentialed --preflight >"$fixture/stdout" 2>"$fixture/stderr"
  status=$?
  set -e
  case "$expected_status:$status" in
    success:0 | failure:[1-9]*) ;;
    *) die "credentialed $name fixture returned unexpected status $status" ;;
  esac

  rm -rf "$fixture/credentials"
  [ -s "$fixture/curl-record" ] || die "credentialed $name fixture did not observe Hetzner curl"
  grep -F 'args_safe=true' "$fixture/curl-record" >/dev/null || die "credentialed $name curl argv was not private-config only"
  if [ "$name" = header-mismatch ]; then
    grep -F 'header_exact=false' "$fixture/curl-record" >/dev/null ||
      die 'credentialed header-mismatch fixture did not reject the private authorization header at fake curl'
  fi
  if [ "$expected_status" = success ]; then
    [ "$(grep -Fc 'provider=hetzner hcloud_env_absent=true' "$fixture/curl-record")" -eq 2 ] ||
      die "credentialed success fixture did not complete both Hetzner reads without inherited authority"
    [ "$(grep -Fc 'header_exact=true' "$fixture/curl-record")" -eq 2 ] ||
      die 'credentialed success fixture did not prove both Hetzner headers exactly matched the external credential'
    [ "$(grep -Fc 'provider=cloudflare hcloud_env_absent=true' "$fixture/curl-record")" -eq 1 ] ||
      die "credentialed success fixture did not complete the Cloudflare helper chain without inherited authority"
  fi
  while IFS= read -r record; do
    case "$record" in
      provider=hetzner\ *)
        config_path=${record#*config_path=}
        config_path=${config_path%% config_regular=*}
        [ ! -e "$config_path" ] || die "credentialed $name retained its private curl configuration"
        ;;
    esac
  done <"$fixture/curl-record"
  for sentinel in "$ambient_hcloud_sentinel" "$token_sentinel" "$expected_token"; do
    if grep -R -F "$sentinel" "$fixture" >/dev/null 2>&1; then
      die "credentialed $name retained a Hetzner sentinel"
    fi
  done
}

credentialed_fixture success success
credentialed_fixture empty-ambient success '' ''
credentialed_fixture failure failure fail
credentialed_fixture signal failure signal
credentialed_fixture header-mismatch failure '' '' 'mismatched-hcloud-token-sentinel-r7q-never-persisted'

credentialed_invalid_token_fixture() (
  name=$1
  malformed_token=$2
  malformed_sentinel=$3
  injected_path=$4
  fixture="$fixture_root/credentialed-invalid-$name"
  mkdir -p "$fixture/bin" "$fixture/credentials" "$fixture/tmp"
  chmod 700 "$fixture" "$fixture/bin" "$fixture/credentials" "$fixture/tmp"

  jq -n --arg token "$malformed_token" '{version:1,token:$token}' >"$fixture/credentials/hetzner.json"
  jq -n '{version:1,api_token:"fixture-cloudflare-token",zone_id:"fixture-zone",record_name:"host.example.invalid"}' >"$fixture/credentials/cloudflare.json"
  jq -n '{version:1,endpoint:"https://example.invalid",region:"fixture",bucket:"fixture",access_key_id:"fixture",secret_access_key:"fixture"}' >"$fixture/credentials/primary.json"
  cp "$fixture/credentials/primary.json" "$fixture/credentials/mirror.json"
  jq -n '{version:1,endpoint:"https://example.invalid",region:"fixture",bucket:"fixture",key:"fixture",access_key_id:"fixture",secret_access_key:"fixture"}' >"$fixture/credentials/state.json"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture fixture' >"$fixture/credentials/replacement.pub"
  printf '%s\n' 'fixture-cipher' >"$fixture/credentials/cipher.key"
  chmod 600 "$fixture/credentials"/*

  cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
: >"$KEEPLING_FAKE_CURL_MARKER"
exit 88
EOF
  chmod 700 "$fixture/bin/curl"

  set +e
  env PATH="$fixture/bin:$PATH" TMPDIR="$fixture/tmp" \
    HCLOUD_TOKEN='ambient-hcloud-sentinel-v4m-never-persisted' \
    KEEPLING_FAKE_CURL_RECORD="$fixture/curl-record" \
    KEEPLING_FAKE_CURL_MARKER="$fixture/curl-marker" \
    KEEPLING_HETZNER_CREDENTIAL_FILE="$fixture/credentials/hetzner.json" \
    KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$fixture/credentials/cloudflare.json" \
    KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$fixture/credentials/primary.json" \
    KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$fixture/credentials/mirror.json" \
    KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$fixture/credentials/state.json" \
    KEEPLING_SSH_PUBLIC_KEY_FILE="$fixture/credentials/replacement.pub" \
    KEEPLING_BACKUP_CIPHER_FILE="$fixture/credentials/cipher.key" \
    ./tooling/verify-host-replacement.sh --credentialed --preflight >"$fixture/stdout" 2>"$fixture/stderr"
  status=$?
  set -e
  [ "$status" -ne 0 ] || die "credentialed invalid $name fixture unexpectedly passed"
  grep -Fx 'Phase 2 credential validation failed: KEEPLING_HETZNER_CREDENTIAL_FILE has an invalid credential document' "$fixture/stderr" >/dev/null ||
    die "credentialed invalid $name fixture did not report the bounded validation failure"
  grep -F "$malformed_sentinel" "$fixture/stdout" "$fixture/stderr" >/dev/null 2>&1 &&
    die "credentialed invalid $name fixture exposed its malformed credential"
  [ ! -e "$fixture/curl-marker" ] || die "credentialed invalid $name fixture dispatched fake curl"
  [ ! -e "$fixture/curl-record" ] || die "credentialed invalid $name fixture created a curl record"
  find "$fixture/tmp" -name 'keepling-replacement-preflight.*' -o -name curl.conf | grep -q . &&
    die "credentialed invalid $name fixture created a private curl workspace"
  [ ! -e "$injected_path" ] || die "credentialed invalid $name fixture created an injected path"

  rm -rf "$fixture/credentials"
  for retained_value in "$malformed_sentinel" "$injected_path"; do
    grep -R -F "$retained_value" "$fixture" >/dev/null 2>&1 &&
      die "credentialed invalid $name fixture retained malformed credential content"
  done
  printf '%s\n' "$name" >>"$malformed_token_case_record"
  exit 0
)

quote_injected_path="$fixture_root/quote-injected-target"
backslash_injected_path="$fixture_root/backslash-injected-target"
newline_injected_path="$fixture_root/newline-injected-target"
trailing_newline_injected_path="$fixture_root/trailing-newline-injected-target"
malformed_token_case_record="$fixture_root/malformed-token-cases"
: >"$malformed_token_case_record"
chmod 600 "$malformed_token_case_record"
credentialed_invalid_token_fixture quote 'quote-token-sentinel"' 'quote-token-sentinel' "$quote_injected_path"
credentialed_invalid_token_fixture backslash 'backslash-token-sentinel\' 'backslash-token-sentinel' "$backslash_injected_path"
credentialed_invalid_token_fixture newline "newline-token-sentinel
output = $newline_injected_path" 'newline-token-sentinel' "$newline_injected_path"
credentialed_invalid_token_fixture trailing-newline "trailing-newline-token-sentinel
" 'trailing-newline-token-sentinel' "$trailing_newline_injected_path"

[ -f "$malformed_token_case_record" ] && [ ! -L "$malformed_token_case_record" ] ||
  die 'malformed token case completion record is not a regular fixture-owned file'
[ "$(wc -l <"$malformed_token_case_record" | tr -d '[:space:]')" -eq 4 ] ||
  die 'malformed token case completion record does not contain exactly four rows'
while IFS= read -r closed_case; do
  case "$closed_case" in
    quote | backslash | newline | trailing-newline) ;;
    *) die 'malformed token case completion record contains an unexpected label' ;;
  esac
done <"$malformed_token_case_record"
for required_case in quote backslash newline trailing-newline; do
  required_case_count=$(grep -Fxc "$required_case" "$malformed_token_case_record" || true)
  [ "$required_case_count" -eq 1 ] ||
    die 'malformed token case completion record has a duplicate or missing required label'
done

echo "Host replacement readiness fixtures passed: shared arm gate and every source lifecycle contract are explicit without external dispatch"
