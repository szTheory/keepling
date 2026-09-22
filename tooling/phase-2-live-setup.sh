#!/usr/bin/env sh
# Safe, non-mutating preparation for the separately armed Phase 2 rehearsal.
set -eu
umask 077

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)

die() { printf '%s\n' "phase-2-live-setup: $*" >&2; exit 2; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

directory=${XDG_CONFIG_HOME:-"$HOME/.config"}/keepling/phase-2
command_name=check

usage() {
  printf '%s\n' 'usage: tooling/phase-2-live-setup.sh [--directory EXTERNAL_DIRECTORY] check|preflight|remaining-inputs' >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --directory) [ "$#" -ge 2 ] || usage; directory=$2; shift 2 ;;
    check|preflight|remaining-inputs) [ "$command_name" = check ] || usage; command_name=$1; shift ;;
    *) usage ;;
  esac
done

case "$directory" in /*) ;; *) die 'credential-directory-invalid' ;; esac
[ -d "$directory" ] && [ ! -L "$directory" ] || die 'credential-directory-unavailable'
[ "$(mode_of "$directory")" = 700 ] || die 'credential-directory-mode-invalid'
resolved_directory=$(CDPATH='' cd -P "$directory" 2>/dev/null && pwd) || die 'credential-directory-unavailable'
case "$resolved_directory" in "$repository_root"|"$repository_root"/*) die 'credential-directory-must-be-external' ;; esac

env_file=$resolved_directory/env.sh
[ -f "$env_file" ] && [ ! -L "$env_file" ] || die 'credential-env-unavailable'
[ "$(mode_of "$env_file")" = 600 ] || die 'credential-env-mode-invalid'

required_names='KEEPLING_HETZNER_CREDENTIAL_FILE KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE KEEPLING_TOFU_STATE_CREDENTIAL_FILE KEEPLING_SSH_PUBLIC_KEY_FILE KEEPLING_BACKUP_CIPHER_FILE'
required_files='hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json replacement-run.pub backup-cipher.key'

line_count=0
while IFS= read -r line || [ -n "$line" ]; do
  line_count=$((line_count + 1))
  [ "$line_count" -le 7 ] || die 'credential-env-schema-invalid'
  name=$(printf '%s' "$required_names" | awk -v n="$line_count" '{print $n}')
  file=$(printf '%s' "$required_files" | awk -v n="$line_count" '{print $n}')
  prefix="export $name=\""
  case "$line" in "$prefix"*) ;; *) die 'credential-env-schema-invalid' ;; esac
  value=${line#"$prefix"}
  case "$value" in *\") value=${value%\"} ;; *) die 'credential-env-schema-invalid' ;; esac
  case "$value" in
    *'"'*|*'`'*|*'$'*|*'\\'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'!'*|*"'"*) die 'credential-env-schema-invalid' ;;
  esac
  # The materializer writes the caller's directory spelling into env.sh. Keep
  # that exact spelling for the schema comparison (macOS commonly aliases
  # /var through /private/var), while using resolved_directory for the boundary
  # check above.
  expected=$directory/$file
  [ "$value" = "$expected" ] || die 'credential-env-path-mismatch'
  [ -f "$value" ] && [ ! -L "$value" ] || die 'credential-file-unavailable'
  [ "$(mode_of "$value")" = 600 ] || die 'credential-file-mode-invalid'
  case "$value" in "$repository_root"|"$repository_root"/*) die 'credential-file-must-be-external' ;; esac
  case "$line_count" in
    1) value_1=$value ;;
    2) value_2=$value ;;
    3) value_3=$value ;;
    4) value_4=$value ;;
    5) value_5=$value ;;
    6) value_6=$value ;;
    7) value_7=$value ;;
  esac
done <"$env_file"
[ "$line_count" -eq 7 ] || die 'credential-env-schema-invalid'

# Values originate only after closed structural validation above. They are used
# as command environment values, never evaluated or printed.
run_sanitized() {
  env -i \
    PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    TOFU_BIN="${TOFU_BIN:-}" CLOUD_INIT_SCHEMA_BIN="${CLOUD_INIT_SCHEMA_BIN:-}" \
    CLOUD_INIT_SCHEMA_VERSION="${CLOUD_INIT_SCHEMA_VERSION:-}" \
    HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" \
    KEEPLING_HETZNER_CREDENTIAL_FILE="$value_1" \
    KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$value_2" \
    KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$value_3" \
    KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$value_4" \
    KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$value_5" \
    KEEPLING_SSH_PUBLIC_KEY_FILE="$value_6" \
    KEEPLING_BACKUP_CIPHER_FILE="$value_7" \
    "$@"
}

remaining_inputs() {
  printf '%s\n' 'phase2-live-setup status=derived-inputs result=ready classes=materialized-boundary,repository-adapters,bounded-run-identity-workspace'
  printf '%s\n' 'phase2-live-setup status=remaining-inputs result=required code=3 inputs=ssh-agent-authority,candidate-recovery-selection,live-change-trigger,billable-apply-approval,dns-mutation-approval,exact-owned-destroy-approval'
  printf '%s\n' 'phase2-live-setup status=live-acceptance result=non-passing reason=plan-02-09-data-03-ops-02-open'
  return 3
}

case "$command_name" in
  remaining-inputs) remaining_inputs ;;
  check|preflight)
    run_sanitized "$repository_root/tooling/phase-2-credentials.sh" doctor >/dev/null
    run_sanitized "$repository_root/tooling/phase-2-tofu-state.sh" check >/dev/null
    run_sanitized "$repository_root/tooling/phase-2-toolchain-doctor.sh" >/dev/null
    run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --dry-run >/dev/null
    run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --print-live-registry >/dev/null
    if [ "$command_name" = preflight ]; then
      run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --credentialed --preflight >/dev/null
      printf '%s\n' 'phase2-live-setup status=read-only-provider-preflight result=passed'
    else
      printf '%s\n' 'phase2-live-setup status=local-check result=passed'
    fi
    remaining_inputs
    ;;
esac
