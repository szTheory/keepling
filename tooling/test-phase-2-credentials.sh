#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-phase2-credentials.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
mkdir "$fixture/config" "$fixture/keys"
printf '%s\n' 'ssh-ed25519 fixture' >"$fixture/keys/replacement.pub"
printf '%s\n' 'fixture-cipher' >"$fixture/keys/cipher"

write_store() {
  jq -n --arg endpoint https://example.invalid --arg region us-east-1 --arg bucket fixture-bucket \
    --arg access fixture-access --arg secret fixture-secret \
    '{version:1,endpoint:$endpoint,region:$region,bucket:$bucket,access_key_id:$access,secret_access_key:$secret}' >"$1"
}

file_mode() {
  case "$(uname -s)" in
    Darwin) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}
jq -n --arg token fixture-hetzner-token '{version:1,token:$token}' >"$fixture/config/hetzner.json"
jq -n --arg token fixture-cloudflare-token --arg zone fixture-zone --arg name fixture.example.invalid \
  '{version:1,api_token:$token,zone_id:$zone,record_name:$name}' >"$fixture/config/cloudflare.json"
write_store "$fixture/config/primary.json"
write_store "$fixture/config/mirror.json"
jq -n --arg endpoint https://example.invalid --arg region us-east-1 --arg bucket fixture-state --arg key keepling/phase-2/terraform.tfstate \
  --arg access fixture-state-access --arg secret fixture-state-secret \
  '{version:1,endpoint:$endpoint,region:$region,bucket:$bucket,key:$key,access_key_id:$access,secret_access_key:$secret}' >"$fixture/config/state.json"

export KEEPLING_HETZNER_CREDENTIAL_FILE="$fixture/config/hetzner.json"
export KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$fixture/config/cloudflare.json"
export KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$fixture/config/primary.json"
export KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$fixture/config/mirror.json"
export KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$fixture/config/state.json"
export KEEPLING_SSH_PUBLIC_KEY_FILE="$fixture/keys/replacement.pub"
export KEEPLING_BACKUP_CIPHER_FILE="$fixture/keys/cipher"

output=$(./tooling/phase-2-credentials.sh doctor)
case "$output" in *fixture-*-token*|*fixture-secret*) echo "credential doctor leaked a value" >&2; exit 1 ;; esac
. "$repository_root/tooling/phase-2-credentials.sh"
phase2_credentials_load_transient
[ "$HCLOUD_TOKEN" = fixture-hetzner-token ] || { echo "credential loader did not set transient Hetzner authority" >&2; exit 1; }
[ "$(cat "$CLOUDFLARE_API_TOKEN_FILE")" = fixture-cloudflare-token ] || { echo "credential loader did not create transient DNS authority" >&2; exit 1; }
[ "$(file_mode "$CLOUDFLARE_API_TOKEN_FILE")" = 600 ] || { echo "transient DNS authority mode is not 0600" >&2; exit 1; }
phase2_credentials_cleanup_transient
[ -z "${HCLOUD_TOKEN:-}" ] && [ -z "${CLOUDFLARE_API_TOKEN_FILE:-}" ] || { echo "credential loader did not clear transient authority" >&2; exit 1; }
if KEEPLING_HETZNER_CREDENTIAL_FILE="$repository_root/infra/credentials/templates/hetzner.json.example" \
  ./tooling/phase-2-credentials.sh doctor >/dev/null 2>&1; then
  echo "credential doctor accepted a repository path" >&2
  exit 1
fi
ln -s "$repository_root/infra/credentials/templates/hetzner.json.example" "$fixture/config/repo-link.json"
if KEEPLING_HETZNER_CREDENTIAL_FILE="$fixture/config/repo-link.json" ./tooling/phase-2-credentials.sh doctor >/dev/null 2>&1; then
  echo "credential doctor accepted a repository symlink" >&2
  exit 1
fi
if KEEPLING_SSH_PUBLIC_KEY_FILE="$fixture/keys/missing.pub" ./tooling/phase-2-credentials.sh doctor >/dev/null 2>&1; then
  echo "credential doctor accepted a missing key file" >&2
  exit 1
fi
printf '%s' '{"version":1}' >"$fixture/config/hetzner.json"
! ./tooling/phase-2-credentials.sh doctor >/dev/null 2>&1 || { echo "credential doctor accepted malformed JSON" >&2; exit 1; }
jq -n --arg token fixture-hetzner-token '{version:1,token:$token}' >"$fixture/config/hetzner.json"

./tooling/phase-2-tofu-state.sh check >/dev/null
config="$fixture/backend.conf"
./tooling/phase-2-tofu-state.sh render-init-config "$config"
[ "$(file_mode "$config")" = 600 ] || { echo "backend config mode is not 0600" >&2; exit 1; }
grep -Fqx 'key="keepling/phase-2/terraform.tfstate"' "$config"
for option in skip_credentials_validation skip_metadata_api_check skip_region_validation skip_requesting_account_id skip_s3_checksum use_path_style; do
  grep -Fqx "$option=true" "$config" || { echo "R2 backend compatibility option $option is missing" >&2; exit 1; }
done
! grep -F 'fixture-state-access' "$config" >/dev/null
! grep -F 'fixture-state-secret' "$config" >/dev/null
./tooling/phase-2-tofu-state.sh with-state-env sh -c \
  '[ "$AWS_ACCESS_KEY_ID" = fixture-state-access ] && [ "$AWS_SECRET_ACCESS_KEY" = fixture-state-secret ] && [ "$AWS_DEFAULT_REGION" = us-east-1 ]'
! ./tooling/phase-2-tofu-state.sh render-init-config "$repository_root/backend.conf" >/dev/null 2>&1 || {
  echo "state tool accepted a repository output path" >&2; exit 1
}
runner_source=$(cat "$repository_root/tooling/test-phase-2.sh")
for required_input in \
  KEEPLING_HETZNER_CREDENTIAL_FILE \
  KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE \
  KEEPLING_SSH_PUBLIC_KEY_FILE \
  KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE \
  KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE \
  KEEPLING_BACKUP_CIPHER_FILE \
  KEEPLING_TOFU_STATE_CREDENTIAL_FILE \
  KEEPLING_LIVE_CHANGE_TRIGGER; do
  printf '%s\n' "$runner_source" | grep -F "$required_input" >/dev/null || {
    echo "live acceptance input contract omits $required_input" >&2; exit 1
  }
done
printf '%s\n' "$runner_source" | grep -Fqx '  ./tooling/verify-host-replacement.sh --credentialed' >/dev/null || {
  echo "live acceptance does not invoke the credentialed verifier" >&2; exit 1
}
echo "Phase 2 credential fixtures passed: valid, malformed, path-boundary, redaction, and backend construction cases"
