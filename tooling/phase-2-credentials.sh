#!/usr/bin/env sh
# Source this library from a Phase 2 runner. It validates only presence, shape,
# readability, and path boundaries; it never prints credential values.

phase2_credentials_die() {
  echo "Phase 2 credential validation failed: $*" >&2
  return 1
}

phase2_credentials_require_external_file() {
  _phase2_name=$1
  _phase2_path=$2
  if [ -z "$_phase2_path" ] || [ ! -r "$_phase2_path" ]; then
    phase2_credentials_die "$_phase2_name is missing or unreadable"
    return 1
  fi
  if [ -L "$_phase2_path" ]; then
    phase2_credentials_die "$_phase2_name must not be a symlink"
    return 1
  fi
  _phase2_directory=$(CDPATH='' cd -P "$(dirname "$_phase2_path")" 2>/dev/null && pwd) || {
    phase2_credentials_die "$_phase2_name cannot be resolved"
    return 1
  }
  _phase2_resolved_path=$_phase2_directory/$(basename "$_phase2_path")
  if [ "$_phase2_resolved_path" = "$repository_root" ] ||
    [ "${_phase2_resolved_path#"$repository_root"/}" != "$_phase2_resolved_path" ]; then
    phase2_credentials_die "$_phase2_name must remain outside the repository"
    return 1
  fi
}

phase2_credentials_require_json() {
  _phase2_name=$1
  _phase2_path=$2
  _phase2_schema=$3
  phase2_credentials_require_external_file "$_phase2_name" "$_phase2_path" || return 1
  jq -e "$_phase2_schema" "$_phase2_path" >/dev/null 2>&1 ||
    phase2_credentials_die "$_phase2_name has an invalid credential document"
}

phase2_credentials_validate() {
  command -v jq >/dev/null 2>&1 || phase2_credentials_die "required command 'jq' is unavailable"
  phase2_credentials_require_json KEEPLING_HETZNER_CREDENTIAL_FILE "${KEEPLING_HETZNER_CREDENTIAL_FILE:-}" \
    '.version == 1 and (.token | type == "string" and length > 0 and all(explode[]; . == 45 or (. >= 48 and . <= 57) or (. >= 65 and . <= 90) or . == 95 or (. >= 97 and . <= 122)))' || return 1
  phase2_credentials_require_json KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE "${KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE:-}" \
    '.version == 1 and (.api_token, .zone_id, .record_name | type == "string" and length > 0)' || return 1
  for _phase2_name in KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE; do
    eval "_phase2_path=\${$_phase2_name:-}"
    phase2_credentials_require_json "$_phase2_name" "$_phase2_path" \
      '.version == 1 and (.endpoint, .region, .bucket, .access_key_id, .secret_access_key | type == "string" and length > 0)' || return 1
  done
  phase2_credentials_require_json KEEPLING_TOFU_STATE_CREDENTIAL_FILE "${KEEPLING_TOFU_STATE_CREDENTIAL_FILE:-}" \
    '.version == 1 and (.endpoint, .region, .bucket, .key, .access_key_id, .secret_access_key | type == "string" and length > 0)' || return 1
  phase2_credentials_require_external_file KEEPLING_SSH_PUBLIC_KEY_FILE "${KEEPLING_SSH_PUBLIC_KEY_FILE:-}" || return 1
  phase2_credentials_require_external_file KEEPLING_BACKUP_CIPHER_FILE "${KEEPLING_BACKUP_CIPHER_FILE:-}" || return 1
}

# Converts external JSON references into process-local variables immediately
# before a provider child process is invoked. The caller owns cleanup.
phase2_credentials_load_transient() {
  # Do not let caller-provided or validated Hetzner authority flow into generic
  # child processes. The preflight uses this shell-local value only to write its
  # private curl configuration.
  unset HCLOUD_TOKEN
  phase2_credentials_validate || return 1
  HCLOUD_TOKEN=$(jq -r '.token' "$KEEPLING_HETZNER_CREDENTIAL_FILE")
  KEEPLING_DNS_ZONE_ID=$(jq -r '.zone_id' "$KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE")
  KEEPLING_DNS_RECORD_NAME=$(jq -r '.record_name' "$KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE")
  umask 077
  _phase2_token_file=$(mktemp "${TMPDIR:-/tmp}/keepling-phase2-cloudflare-token.XXXXXX") || return 1
  jq -r '.api_token' "$KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE" >"$_phase2_token_file"
  chmod 600 "$_phase2_token_file"
  CLOUDFLARE_API_TOKEN_FILE=$_phase2_token_file
  export KEEPLING_DNS_ZONE_ID KEEPLING_DNS_RECORD_NAME CLOUDFLARE_API_TOKEN_FILE
}

phase2_credentials_cleanup_transient() {
  [ -n "${_phase2_token_file:-}" ] && rm -f -- "$_phase2_token_file"
  unset HCLOUD_TOKEN KEEPLING_DNS_ZONE_ID KEEPLING_DNS_RECORD_NAME CLOUDFLARE_API_TOKEN_FILE _phase2_token_file
}

if [ "${0##*/}" = "phase-2-credentials.sh" ]; then
  repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
  case "${1:-}" in
    doctor) [ "$#" -eq 1 ] || exit 2; phase2_credentials_validate || exit 1; echo "Phase 2 credential references passed: files are external, readable, and structurally valid" ;;
    *) echo "usage: $0 doctor" >&2; exit 2 ;;
  esac
fi
