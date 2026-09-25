#!/usr/bin/env sh
# Safe preparation for a separately armed rehearsal. No stage is dispatched.
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
umask 077
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
die() { printf '%s\n' "phase-2-live-setup: $*" >&2; exit 2; }
mode_of() { portable_stat '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
outside_repo() { case "$1" in "$repository_root"|"$repository_root"/*) return 1;; *) return 0;; esac; }
private_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  outside_repo "$parent/$(basename "$1")"
}
directory=${XDG_CONFIG_HOME:-"$HOME/.config"}/keepling/phase-2; command_name=check; candidate=; recovery=; admin_cidrs=; server_image=; login_credential=; known_hosts=
usage() { printf '%s\n' 'usage: tooling/phase-2-live-setup.sh [--directory EXTERNAL_DIRECTORY] [--candidate-selection FILE --recovery-selection FILE --server-image-selection FILE --admin-source-cidrs FILE --login-credential FILE --ssh-known-hosts FILE] check|preflight|remaining-inputs|prepare' >&2; exit 2; }
while [ "$#" -gt 0 ]; do case "$1" in --directory) [ "$#" -ge 2 ] || usage; directory=$2; shift 2;; --candidate-selection) [ "$#" -ge 2 ] || usage; candidate=$2; shift 2;; --recovery-selection) [ "$#" -ge 2 ] || usage; recovery=$2; shift 2;; --admin-source-cidrs) [ "$#" -ge 2 ] || usage; admin_cidrs=$2; shift 2;; --server-image-selection) [ "$#" -ge 2 ] || usage; server_image=$2; shift 2;; --login-credential) [ "$#" -ge 2 ] || usage; login_credential=$2; shift 2;; --ssh-known-hosts) [ "$#" -ge 2 ] || usage; known_hosts=$2; shift 2;; check|preflight|remaining-inputs|prepare) [ "$command_name" = check ] || usage; command_name=$1; shift;; *) usage;; esac; done
case "$directory" in /*) ;; *) die credential-directory-invalid;; esac; [ -d "$directory" ] && [ ! -L "$directory" ] || die credential-directory-unavailable; [ "$(mode_of "$directory")" = 700 ] || die credential-directory-mode-invalid; resolved=$(CDPATH='' cd -P "$directory" && pwd) || die credential-directory-unavailable; outside_repo "$resolved" || die credential-directory-must-be-external
env_file=$resolved/env.sh; private_file "$env_file" || die credential-env-unavailable
names='KEEPLING_HETZNER_CREDENTIAL_FILE KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE KEEPLING_TOFU_STATE_CREDENTIAL_FILE KEEPLING_SSH_PUBLIC_KEY_FILE KEEPLING_BACKUP_CIPHER_FILE'; files='hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json replacement-run.pub backup-cipher.key'; n=0
while IFS= read -r line || [ -n "$line" ]; do n=$((n+1)); [ "$n" -le 7 ] || die credential-env-schema-invalid; name=$(printf '%s' "$names" | awk -v n="$n" '{print $n}'); file=$(printf '%s' "$files" | awk -v n="$n" '{print $n}'); prefix="export $name=\""; case "$line" in "$prefix"*) ;; *) die credential-env-schema-invalid;; esac; value=${line#"$prefix"}; case "$value" in *\") value=${value%\"};; *) die credential-env-schema-invalid;; esac; case "$value" in *'"'*|*'`'*|*'$'*|*'\\'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'!'*|*"'"*) die credential-env-schema-invalid;; esac; [ "$value" = "$directory/$file" ] || die credential-env-path-mismatch; private_file "$value" || die credential-file-unavailable; eval "value_$n=\$value"; done <"$env_file"; [ "$n" -eq 7 ] || die credential-env-schema-invalid
run_sanitized() { env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" TOFU_BIN="${TOFU_BIN:-}" CLOUD_INIT_SCHEMA_BIN="${CLOUD_INIT_SCHEMA_BIN:-}" CLOUD_INIT_SCHEMA_VERSION="${CLOUD_INIT_SCHEMA_VERSION:-}" HCLOUD_PROVIDER_PLUGIN_DIR="${HCLOUD_PROVIDER_PLUGIN_DIR:-}" KEEPLING_HETZNER_CREDENTIAL_FILE="$value_1" KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$value_2" KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$value_3" KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$value_4" KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$value_5" KEEPLING_SSH_PUBLIC_KEY_FILE="$value_6" KEEPLING_BACKUP_CIPHER_FILE="$value_7" "$@"; }
remaining() { printf '%s\n' 'phase2-live-setup status=derived-inputs result=ready classes=materialized-boundary,repository-adapters,bounded-run-identity-workspace'; printf '%s\n' 'phase2-live-setup status=remaining-inputs result=required code=3 inputs=ssh-agent-authority,candidate-recovery-selection,live-change-trigger,billable-apply-approval,dns-mutation-approval,exact-owned-destroy-approval'; printf '%s\n' 'phase2-live-setup status=live-acceptance result=non-passing reason=plan-02-09-data-03-ops-02-open'; return 3; }
prepare() {
  [ -n "$candidate" ] && [ -n "$recovery" ] && [ -n "$admin_cidrs" ] && [ -n "$server_image" ] && [ -n "$login_credential" ] && [ -n "$known_hosts" ] || die candidate-recovery-network-selection-required; private_file "$candidate" && private_file "$recovery" && private_file "$admin_cidrs" && private_file "$server_image" && private_file "$login_credential" && private_file "$known_hosts" || die selection-unavailable
  [ ! -s "$known_hosts" ] || die ssh-known-hosts-must-be-empty-before-provisioning
  jq -e '(keys|sort)==["image_id","os","version"] and .version==1 and .os=="ubuntu-24.04" and (.image_id|type=="string" and test("^[1-9][0-9]*$"))' "$server_image" >/dev/null 2>&1 || die server-image-selection-invalid
  python3 - "$admin_cidrs" <<'PY' >/dev/null 2>&1 || die admin-source-cidrs-invalid
import ipaddress,sys
lines=open(sys.argv[1],encoding="ascii").read().splitlines()
if not lines or len(lines)>32 or len(set(lines)) != len(lines): raise SystemExit(1)
for line in lines:
    network=ipaddress.ip_network(line,strict=True)
    if network.prefixlen == 0: raise SystemExit(1)
PY
  jq -e '(keys|sort)==["architecture","archive_sha256","config_image_id","image_archive","manifest_digest","os","revision","rootfs_diff_ids","version"] and .version==1 and (.image_archive|type=="string" and test("^/[A-Za-z0-9_./:@+-]+$")) and (.archive_sha256|test("^[0-9a-f]{64}$")) and (.config_image_id|test("^sha256:[0-9a-f]{64}$")) and (.manifest_digest|test("^sha256:[0-9a-f]{64}$")) and .architecture=="amd64" and .os=="linux" and (.revision|test("^[0-9a-f]{7,64}$")) and (.rootfs_diff_ids|type=="array" and length>0 and all(.[];test("^sha256:[0-9a-f]{64}$")))' "$candidate" >/dev/null 2>&1 || die candidate-selection-invalid
  source_kind=$(jq -r .source_kind "$recovery")
  provenance=$(jq -r .provenance_file "$recovery")
  if [ "$source_kind" = synthetic-rehearsal ]; then
    jq -e '(keys|sort)==["dump_file","provenance_file","rehearsal_login_credential_file","source_kind","version"] and .version==1 and .source_kind=="synthetic-rehearsal" and (.dump_file,.provenance_file,.rehearsal_login_credential_file|type=="string" and test("^/[A-Za-z0-9_./:@+-]+$"))' "$recovery" >/dev/null 2>&1 || die recovery-selection-invalid
    synthetic_login=$(jq -r .rehearsal_login_credential_file "$recovery")
    [ "$login_credential" = "$synthetic_login" ] && private_file "$synthetic_login" || die synthetic-login-selection-mismatch
    jq -e '(keys|sort)==["plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and .version==1 and .source_kind=="synthetic-rehearsal" and (.plaintext_sha256|test("^[0-9a-f]{64}$")) and (.plaintext_bytes|type=="number" and floor==. and .>0) and (.verification|type=="object" and (keys|sort)==["local_capture","local_restore","synthetic"] and .local_capture==true and .local_restore==true and .synthetic==true)' "$provenance" >/dev/null 2>&1 || die recovery-provenance-invalid
  else
    jq -e '(keys|sort)==["dump_file","provenance_file","source_kind","version"] and .version==1 and (.source_kind=="b2-primary" or .source_kind=="r2-mirror") and (.dump_file,.provenance_file|type=="string" and test("^/[A-Za-z0-9_./:@+-]+$"))' "$recovery" >/dev/null 2>&1 || die recovery-selection-invalid
    jq -e --arg source "$source_kind" '(keys|sort)==["ciphertext_bytes","ciphertext_sha256","plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and .version==1 and .source_kind==$source and (.plaintext_sha256|test("^[0-9a-f]{64}$")) and (.plaintext_bytes|type=="number" and floor==. and .>=0) and (.verification.head==true and .verification.get==true and .verification.package_manifest==true and .verification.decrypt==true and .verification.plaintext==true)' "$provenance" >/dev/null 2>&1 || die recovery-provenance-invalid
  fi
  archive=$(jq -r .image_archive "$candidate"); dump=$(jq -r .dump_file "$recovery"); provenance=$(jq -r .provenance_file "$recovery"); private_file "$archive" && private_file "$dump" && private_file "$provenance" || die selection-reference-invalid
  [ "$(shasum -a 256 "$dump" | awk '{print $1}')" = "$(jq -r .plaintext_sha256 "$provenance")" ] && [ "$(wc -c <"$dump" | tr -d ' ')" = "$(jq -r .plaintext_bytes "$provenance")" ] || die recovery-selection-mismatch
  [ -S "${SSH_AUTH_SOCK:-}" ] || die ssh-agent-authority-required
  identity=$(awk 'NF >= 2 { print $1 " " $2; exit }' "$value_6")
  [ -n "$identity" ] && [ "$(ssh-add -L 2>/dev/null | awk 'NF >= 2 { print $1 " " $2 }' | grep -Fxc "$identity" || true)" = 1 ] || die ssh-agent-authority-mismatch
  runs=$resolved/runs; [ ! -e "$runs" ] && { mkdir "$runs"; chmod 700 "$runs"; } || { [ -d "$runs" ] && [ ! -L "$runs" ] && [ "$(mode_of "$runs")" = 700 ]; } || die run-directory-parent-invalid
  run_id="replace-$(date -u +%Y%m%d)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; run=$runs/$run_id; mkdir "$run" || die run-directory-exists; chmod 700 "$run"; tmp_contract=$run/.candidate-contract; cleanup() { status=$?; rm -f -- "$run/.bundle.tmp" "$run/.known-hosts.tmp" "$tmp_contract"; [ "$status" -eq 0 ] || rmdir "$run" 2>/dev/null || true; exit "$status"; }; trap cleanup EXIT HUP INT TERM
  "$repository_root/tooling/verify-host-replacement.sh" --resolve-image-archive "$archive" "$tmp_contract" >/dev/null 2>&1 || die candidate-archive-invalid; jq -e --slurpfile c "$candidate" '. == ($c[0]|del(.image_archive)|.version=2)' "$tmp_contract" >/dev/null 2>&1 || die candidate-selection-mismatch; digest=$(jq -r .manifest_digest "$tmp_contract")
  original_host=$(jq -er '.record_name|select(type=="string" and test("^[A-Za-z0-9.-]+$"))' "$value_2") || die cloudflare-host-invalid
  dns_test_host="phase2-$run_id.$original_host"
  { printf 'RUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\nIMAGE_ARCHIVE_FILE=%s\nIMAGE_CONTRACT_FILE=%s\nCANDIDATE_SELECTION_FILE=%s\nRECOVERY_SELECTION_FILE=%s\nSERVER_IMAGE_SELECTION_FILE=%s\nADMIN_SOURCE_CIDRS_FILE=%s\nLOGIN_CREDENTIAL_FILE=%s\nBACKUP_CIPHER_FILE=%s\n' "$run_id" "$run/workspace" "$digest" "$archive" "$tmp_contract" "$candidate" "$recovery" "$server_image" "$admin_cidrs" "$login_credential" "$value_7"; printf 'HETZNER_CREDENTIAL_FILE=%s\nCLOUDFLARE_CREDENTIAL_FILE=%s\nDNS_TEST_RECORD_NAME=%s\nPRIMARY_BACKUP_CREDENTIAL_FILE=%s\nMIRROR_BACKUP_CREDENTIAL_FILE=%s\nTOFU_STATE_CREDENTIAL_FILE=%s\nSSH_PUBLIC_KEY_FILE=%s\nSSH_KNOWN_HOSTS_FILE=%s\nRECOVERY_DUMP_FILE=%s\nRECOVERY_PROVENANCE_FILE=%s\n' "$value_1" "$value_2" "$dns_test_host" "$value_3" "$value_4" "$value_5" "$value_6" "$known_hosts" "$dump" "$provenance"; for stage in bootstrap image restore runtime semantic dns teardown; do printf '%s_RUNNER=%s/tooling/phase-2-live-runners/%s\n' "$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')" "$repository_root" "$stage"; done; } >"$run/.bundle.tmp"; chmod 600 "$run/.bundle.tmp"; "$repository_root/tooling/phase-2-live-orchestration.sh" --validate "$run/.bundle.tmp" >/dev/null || die generated-bundle-invalid; mv "$run/.bundle.tmp" "$run/orchestration.env"; trap - EXIT HUP INT TERM; printf '%s\n' 'phase2-live-setup status=prepared result=ready'; remaining
}
case "$command_name" in remaining-inputs) remaining;; check|preflight) run_sanitized "$repository_root/tooling/phase-2-credentials.sh" doctor >/dev/null; run_sanitized "$repository_root/tooling/phase-2-tofu-state.sh" check >/dev/null; run_sanitized "$repository_root/tooling/phase-2-toolchain-doctor.sh" >/dev/null; run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --dry-run >/dev/null; run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --print-live-registry >/dev/null; if [ "$command_name" = preflight ]; then run_sanitized "$repository_root/tooling/verify-host-replacement.sh" --credentialed --preflight >/dev/null; printf '%s\n' 'phase2-live-setup status=read-only-provider-preflight result=passed'; else printf '%s\n' 'phase2-live-setup status=local-check result=passed'; fi; remaining;; prepare) prepare;; esac
