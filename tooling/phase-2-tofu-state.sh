#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
. "$repository_root/tooling/phase-2-credentials.sh"

die() { echo "Phase 2 OpenTofu state contract failed: $*" >&2; exit 1; }

require_state_document() {
  phase2_credentials_validate || exit 1
  jq -e '.version == 1 and (.key | startswith("keepling/") and endswith(".tfstate"))' \
    "$KEEPLING_TOFU_STATE_CREDENTIAL_FILE" >/dev/null || die "state key must be a Keepling .tfstate key"
}

render_init_config() {
  [ "$#" -eq 1 ] || die "usage: $0 render-init-config EXTERNAL_FILE"
  output=$1
  case "$output" in "$repository_root"|"$repository_root"/*) die "backend config must remain outside the repository" ;; esac
  [ ! -e "$output" ] || die "refusing to overwrite backend config"
  require_state_document
  umask 077
  {
    jq -er '"bucket=\(.bucket|tojson)\nkey=\(.key|tojson)\nregion=\(.region|tojson)\nendpoint=\(.endpoint|tojson)\nskip_credentials_validation=true\nskip_metadata_api_check=true\nskip_region_validation=true\nskip_requesting_account_id=true\nskip_s3_checksum=true\nuse_path_style=true"' \
      "$KEEPLING_TOFU_STATE_CREDENTIAL_FILE"
  } >"$output"
  chmod 600 "$output"
}

with_state_env() {
  [ "$#" -gt 0 ] || die "usage: $0 with-state-env COMMAND [ARG ...]"
  require_state_document
  state_access_key=$(jq -r '.access_key_id' "$KEEPLING_TOFU_STATE_CREDENTIAL_FILE")
  state_secret_key=$(jq -r '.secret_access_key' "$KEEPLING_TOFU_STATE_CREDENTIAL_FILE")
  state_region=$(jq -r '.region' "$KEEPLING_TOFU_STATE_CREDENTIAL_FILE")
  AWS_ACCESS_KEY_ID="$state_access_key" AWS_SECRET_ACCESS_KEY="$state_secret_key" AWS_DEFAULT_REGION="$state_region" "$@"
}

case "${1:-}" in
  check) [ "$#" -eq 1 ] || die "usage: $0 check"; require_state_document; echo "Phase 2 OpenTofu state contract passed: separate external state document with encrypted locking backend inputs" ;;
  render-init-config) shift; render_init_config "$@" ;;
  with-state-env) shift; with_state_env "$@" ;;
  *) die "usage: $0 check | render-init-config EXTERNAL_FILE | with-state-env COMMAND [ARG ...]" ;;
esac
