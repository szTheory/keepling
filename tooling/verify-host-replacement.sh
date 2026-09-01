#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
TOFU_BIN=${TOFU_BIN:-tofu}

die() {
  echo "Host replacement verification failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"
}

require_credentials() {
  [ -n "${HCLOUD_TOKEN:-}" ] || die "HCLOUD_TOKEN is missing"
  [ -n "${KEEPLING_DNS_ZONE_ID:-}" ] || die "KEEPLING_DNS_ZONE_ID is missing"
  [ -n "${KEEPLING_DNS_RECORD_NAME:-}" ] || die "KEEPLING_DNS_RECORD_NAME is missing"
  require_credential_file() {
    variable=$1
    path=$2
    [ -r "$path" ] || die "$variable is unreadable"
    case "$path" in "$repository_root"|"$repository_root"/*) die "$variable must remain outside the repository" ;; esac
  }
  require_credential_file KEEPLING_SSH_PUBLIC_KEY_FILE "${KEEPLING_SSH_PUBLIC_KEY_FILE:-}"
  require_credential_file KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE "${KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE:-}"
  require_credential_file KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE "${KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE:-}"
  require_credential_file KEEPLING_BACKUP_CIPHER_FILE "${KEEPLING_BACKUP_CIPHER_FILE:-}"
  require_credential_file CLOUDFLARE_API_TOKEN_FILE "${CLOUDFLARE_API_TOKEN_FILE:-}"
}

verify_selection() {
  selection=infra/tofu/hetzner/selection.json
  jq -e '
    .version == 1 and
    .location == "nbg1" and
    (.server_type | test("^(cx|cpx|ccx)[0-9]+$")) and
    .architecture == "x86_64" and
    .data_volume_gb >= 80 and
    .acceptance_limits.maximum_full_host_seconds == 14400 and
    .acceptance_limits.maximum_rpo_seconds == 300 and
    .catalog_cost.estimated_rehearsal_hourly_gross > 0
  ' "$selection" >/dev/null || die "catalog selection contract is invalid"
}

dry_run() {
  [ "$($TOFU_BIN version -json | jq -r '.terraform_version')" = "1.12.6" ] ||
    die "OpenTofu 1.12.6 is required"
  "$TOFU_BIN" -chdir=infra/tofu/hetzner fmt -check -recursive
  "$TOFU_BIN" -chdir=infra/tofu/hetzner init -backend=false >/dev/null
  "$TOFU_BIN" -chdir=infra/tofu/hetzner validate >/dev/null
  "$TOFU_BIN" -chdir=infra/tofu/hetzner test >/dev/null
  ./infra/dns/cloudflare.sh self-test >/dev/null
  ./infra/backup/mirror-snapshot.sh self-test >/dev/null
  ./tooling/verify-backup.sh --fixture local >/dev/null
  verify_selection
  echo "Host replacement dry-run passed: provider graph, exact DNS identity, append-only mirror, and cost guard are deterministic"
}

credentialed_preflight() {
  require_credentials
  verify_selection
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/keepling-replacement-preflight.XXXXXX")
  trap 'rm -rf -- "$workspace"' EXIT HUP INT TERM
  chmod 700 "$workspace"

  catalog=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    'https://api.hetzner.cloud/v1/server_types?per_page=50')
  selected_type=$(jq -r '.server_type' infra/tofu/hetzner/selection.json)
  printf '%s' "$catalog" | jq -e --arg selected "$selected_type" \
    '[.server_types[] | select(.name == $selected and .architecture == "x86")] | length == 1' >/dev/null ||
    die "selected x86 catalog entry is unavailable"

  resources=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    'https://api.hetzner.cloud/v1/servers?per_page=50')
  printf '%s' "$resources" | jq -e '.servers | length == 0' >/dev/null ||
    die "provider project is not empty; replacement ownership would be ambiguous"

  ./infra/dns/cloudflare.sh capture "$workspace/original-dns.json" >/dev/null
  jq -e '.content == "192.0.2.1" and .proxied == false and .ttl == 300' "$workspace/original-dns.json" >/dev/null ||
    die "safe pending-zone baseline changed"

  echo "Host replacement credentialed preflight passed: authority is readable, provider project is empty, catalog candidate exists, and exact DNS rollback state is capturable"
}

credentialed_apply() {
  require_credentials
  [ "${KEEPLING_ALLOW_BILLABLE_APPLY:-}" = yes ] ||
    die "billable provisioning requires KEEPLING_ALLOW_BILLABLE_APPLY=yes after an explicit checkpoint"
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = yes ] ||
    die "DNS mutation requires KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes after an explicit checkpoint"
  jq -e '.status == "benchmark-verified" and .benchmark.projected_restore_seconds <= .acceptance_limits.maximum_full_host_seconds' \
    infra/tofu/hetzner/selection.json >/dev/null ||
    die "billable apply is refused until a disposable candidate records a passing storage/restore benchmark"
  [ -r "${KEEPLING_TOFU_STATE_CREDENTIAL_FILE:-}" ] ||
    die "separately scoped mutable OpenTofu state authority is required"
  die "credentialed apply is intentionally sealed until the billable benchmark checkpoint is approved"
}

for command in curl jq; do require_command "$command"; done
[ -x "$TOFU_BIN" ] || command -v "$TOFU_BIN" >/dev/null 2>&1 || die "OpenTofu command is unavailable"

case "${1:-}" in
  --dry-run) [ "$#" -eq 1 ] || die "usage: $0 --dry-run"; dry_run ;;
  --credentialed)
    case "${2:-}" in
      --preflight) [ "$#" -eq 2 ] || die "usage: $0 --credentialed --preflight"; credentialed_preflight ;;
      '') credentialed_apply ;;
      *) die "usage: $0 --credentialed [--preflight]" ;;
    esac
    ;;
  *) die "usage: $0 --dry-run | --credentialed [--preflight]" ;;
esac
