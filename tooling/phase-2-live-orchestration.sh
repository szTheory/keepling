#!/usr/bin/env sh
# Generated orchestration is closed data and is never sourced.
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
die() { printf '%s\n' "Phase 2 live orchestration refused: $*" >&2; exit 2; }
mode_of() { portable_stat '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
outside_repo() { case "$1" in "$repository_root"|"$repository_root"/*) return 1;; *) return 0;; esac; }
private_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  outside_repo "$parent/$(basename "$1")"
}
read_value() { awk -F= -v key="$1" '$1 == key {if (++n != 1) exit 2; print substr($0,length(key)+2)} END {if (n != 1) exit 1}' "$2"; }
keys='RUN_ID WORKSPACE IMAGE_DIGEST IMAGE_ARCHIVE_FILE IMAGE_CONTRACT_FILE CANDIDATE_SELECTION_FILE RECOVERY_SELECTION_FILE SERVER_IMAGE_SELECTION_FILE ADMIN_SOURCE_CIDRS_FILE LOGIN_CREDENTIAL_FILE BACKUP_CIPHER_FILE HETZNER_CREDENTIAL_FILE CLOUDFLARE_CREDENTIAL_FILE DNS_TEST_RECORD_NAME PRIMARY_BACKUP_CREDENTIAL_FILE MIRROR_BACKUP_CREDENTIAL_FILE TOFU_STATE_CREDENTIAL_FILE SSH_PUBLIC_KEY_FILE SSH_KNOWN_HOSTS_FILE RECOVERY_DUMP_FILE RECOVERY_PROVENANCE_FILE BOOTSTRAP_RUNNER IMAGE_RUNNER RESTORE_RUNNER RUNTIME_RUNNER SEMANTIC_RUNNER DNS_RUNNER TEARDOWN_RUNNER'
validate() {
  allow_workspace=${2:-no}
  config=$1; case "$config" in /*) ;; *) die 'private orchestration file is required';; esac
  private_file "$config" || die 'private orchestration file must be mode 0600, regular, and outside the repository'
  [ "$(wc -c <"$config" | tr -d ' ')" -le 8192 ] || die 'orchestration file is too large'
  grep -Eqv '^[A-Z_]+=[A-Za-z0-9_./:@+-]+$' "$config" && die 'orchestration file has unsafe syntax'
  actual=$(awk -F= '{print $1}' "$config" | sort | tr '\n' ' ' | sed 's/ $//'); expected=$(printf '%s\n' "$keys" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'); [ "$actual" = "$expected" ] || die 'orchestration file schema is not closed'
  run_id=$(read_value RUN_ID "$config") || die 'RUN_ID is required exactly once'; workspace=$(read_value WORKSPACE "$config") || die 'WORKSPACE is required exactly once'; digest=$(read_value IMAGE_DIGEST "$config") || die 'IMAGE_DIGEST is required exactly once'
  printf '%s' "$run_id" | grep -Eq '^[a-z0-9][a-z0-9-]{7,39}$' || die 'RUN_ID is not bounded'
  case "$workspace" in /*) ;; *) die 'WORKSPACE must be absolute';; esac; outside_repo "$workspace" || die 'WORKSPACE must remain outside the repository'
  if [ "$allow_workspace" = yes ]; then
    [ -d "$workspace" ] && [ ! -L "$workspace" ] || die 'run workspace is unavailable'
    [ "$(mode_of "$workspace")" = 700 ] || die 'run workspace must have mode 0700'
  else
    [ ! -e "$workspace" ] || die 'WORKSPACE already exists; stale workspace reuse is forbidden'
  fi
  printf '%s' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || die 'IMAGE_DIGEST must be immutable'
  dns_test_name=$(read_value DNS_TEST_RECORD_NAME "$config") || die 'DNS_TEST_RECORD_NAME is required exactly once'
  printf '%s' "$dns_test_name" | grep -Eq '^phase2-[a-z0-9-]+\.[a-z0-9.-]+$' || die 'DNS_TEST_RECORD_NAME is not a bounded run-scoped name'
  for ref in IMAGE_ARCHIVE_FILE IMAGE_CONTRACT_FILE CANDIDATE_SELECTION_FILE RECOVERY_SELECTION_FILE SERVER_IMAGE_SELECTION_FILE ADMIN_SOURCE_CIDRS_FILE LOGIN_CREDENTIAL_FILE BACKUP_CIPHER_FILE HETZNER_CREDENTIAL_FILE CLOUDFLARE_CREDENTIAL_FILE PRIMARY_BACKUP_CREDENTIAL_FILE MIRROR_BACKUP_CREDENTIAL_FILE TOFU_STATE_CREDENTIAL_FILE SSH_PUBLIC_KEY_FILE SSH_KNOWN_HOSTS_FILE RECOVERY_DUMP_FILE RECOVERY_PROVENANCE_FILE; do value=$(read_value "$ref" "$config") || die "$ref is required exactly once"; private_file "$value" || die "$ref must be a private external regular file"; done
  for stage in bootstrap image restore runtime semantic dns teardown; do name=$(printf '%s_RUNNER' "$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')"); value=$(read_value "$name" "$config") || die "$name is required exactly once"; [ "$value" = "$repository_root/tooling/phase-2-live-runners/$stage" ] || die "$name must be the exact repository-owned runner"; done
}
require_arm() {
  [ "${KEEPLING_ALLOW_BILLABLE_APPLY:-}" = yes ] || die 'billable approval is required'
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = yes ] || die 'DNS approval is required'
  [ "${KEEPLING_ALLOW_PROVIDER_DESTROY:-}" = yes ] || die 'owned-destroy approval is required'
  case "${KEEPLING_LIVE_CHANGE_TRIGGER:-}" in
    [a-z0-9][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-][a-z0-9._-]*) ;;
    *) die 'a bounded named change trigger is required' ;;
  esac
}
[ "$#" -ge 1 ] || die 'usage: phase-2-live-orchestration.sh --validate PRIVATE_BUNDLE | --validate-host-trust-pending PRIVATE_BUNDLE | STAGE'
if [ "$1" = --validate ]; then [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die 'usage: phase-2-live-orchestration.sh --validate PRIVATE_BUNDLE [existing-workspace]'; validate "$2" "${3:-no}"; printf '%s\n' 'phase2-live-orchestration status=bundle-validation result=passed'; exit 0; fi
[ "$1" = --validate-host-trust-pending ] && {
  [ "$#" -eq 2 ] || die 'usage: phase-2-live-orchestration.sh --validate-host-trust-pending PRIVATE_BUNDLE'
  validate "$2" yes
  config=$2
  workspace=$(read_value WORKSPACE "$config")
  run_id=$(read_value RUN_ID "$config")
  digest=$(read_value IMAGE_DIGEST "$config")
  checkpoint="$workspace/.host-trust.pending"
  private_file "$checkpoint" || die 'host trust checkpoint must be private and mode 0600'
  [ "$(wc -l <"$checkpoint" | tr -d '[:space:]')" = 8 ] || die 'host trust checkpoint schema is invalid'
  grep -Eqv '^(version|[A-Z0-9_]+)=[A-Za-z0-9_./:@+-]+$' "$checkpoint" && die 'host trust checkpoint syntax is invalid'
  [ "$(awk -F= '{print $1}' "$checkpoint" | sort | tr '\n' ' ' | sed 's/ $//')" = 'BUNDLE_SHA256 IMAGE_DIGEST IP RUN_ID SERVER_ID SERVER_NAME WORKSPACE version' ] || die 'host trust checkpoint fields are not closed'
  [ "$(read_value version "$checkpoint")" = 1 ] &&
    [ "$(read_value RUN_ID "$checkpoint")" = "$run_id" ] &&
    [ "$(read_value WORKSPACE "$checkpoint")" = "$workspace" ] &&
    [ "$(read_value IMAGE_DIGEST "$checkpoint")" = "$digest" ] &&
    [ "$(read_value BUNDLE_SHA256 "$checkpoint")" = "$(shasum -a 256 "$config" | awk '{print $1}')" ] || die 'host trust checkpoint binding is invalid'
  printf '%s' "$(read_value SERVER_ID "$checkpoint")" | grep -Eq '^[1-9][0-9]*$' || die 'host trust server identity is invalid'
  printf '%s' "$(read_value IP "$checkpoint")" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1; exit 0} {exit 1}' || die 'host trust address is invalid'
  [ -n "$(read_value SERVER_NAME "$checkpoint")" ] || die 'host trust server name is invalid'
  [ "$(cat "$workspace/candidate-ip.txt" 2>/dev/null || true)" = "$(read_value IP "$checkpoint")" ] || die 'host trust address does not match retained candidate proof'
  printf '%s\n' 'phase2-live-orchestration status=host-trust-checkpoint result=valid'
  exit 0
}
[ "$#" -eq 1 ] || die 'usage: phase-2-live-orchestration.sh --validate PRIVATE_BUNDLE | STAGE'
case "$1" in bootstrap|image|restore|runtime|semantic|dns|teardown) ;; *) die 'unknown stage';; esac
require_arm
bundle=${KEEPLING_LIVE_ORCHESTRATION_FILE:-}
if [ "$1" = bootstrap ]; then
  bootstrap_workspace=$(read_value WORKSPACE "$bundle") || die 'WORKSPACE is required exactly once'
  if [ -f "$bootstrap_workspace/.host-trust.pending" ]; then validate "$bundle" yes; else validate "$bundle"; fi
else
  validate "$bundle" yes
fi
workspace=$(read_value WORKSPACE "$bundle")
stage=$1
runner_name=$(printf '%s_RUNNER' "$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')")
runner_value=$(read_value "$runner_name" "$bundle")
[ "$runner_value" = "$repository_root/tooling/phase-2-live-runners/$stage" ] || die 'stage runner is not repository-owned'
case "$stage" in
  bootstrap) ambient_value=${KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER:-} ;;
  image) ambient_value=${KEEPLING_SEQUENCE_IMAGE_RUNNER:-} ;;
  restore) ambient_value=${KEEPLING_SEQUENCE_RESTORE_RUNNER:-} ;;
  runtime) ambient_value=${KEEPLING_SEQUENCE_RUNTIME_RUNNER:-} ;;
  semantic) ambient_value=${KEEPLING_SEQUENCE_SEMANTIC_RUNNER:-} ;;
  dns) ambient_value=${KEEPLING_SEQUENCE_DNS_RUNNER:-} ;;
  teardown) ambient_value=${KEEPLING_SEQUENCE_TEARDOWN_RUNNER:-} ;;
esac
[ -z "$ambient_value" ] || [ "$ambient_value" = "$runner_value" ] || die 'ambient stage runner override refused'

case "$stage" in
  bootstrap)
    if [ ! -e "$workspace" ]; then
      (umask 077 && mkdir -m 700 "$workspace") || die 'private workspace creation failed'
    fi
    ;;
  image|restore|runtime|semantic|dns)
    [ -f "$workspace/.stage-bootstrap.complete" ] || die 'bootstrap completion proof is required'
    ;;
  teardown)
    ;;
esac
run_id=$(read_value RUN_ID "$bundle")
digest=$(read_value IMAGE_DIGEST "$bundle")
"$repository_root/tooling/phase-2-live-stage-actions.sh" "$stage" "$run_id" "$workspace" "$digest" "$bundle"
