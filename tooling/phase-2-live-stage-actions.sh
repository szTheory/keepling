#!/usr/bin/env sh
# Run-bound action boundary for the seven repository-owned replacement stages.
set -eu
umask 077

script_path=$0
if [ -L "$script_path" ]; then script_path=$(readlink "$script_path"); fi
repository_root=$(CDPATH='' cd -P "$(dirname "$script_path")/.." && pwd)
die() { printf '%s\n' "Phase 2 live stage failed: stage=$stage result=refused reason=$1" >&2; exit 1; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
outside_repo() { case "$1" in "$repository_root"|"$repository_root"/*) return 1;; *) return 0;; esac; }
read_value() { awk -F= -v key="$1" '$1 == key {if (++n != 1) exit 2; print substr($0,length(key)+2)} END {if (n != 1) exit 1}' "$2"; }
valid_private() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  outside_repo "$parent/$(basename "$1")"
}
state_list_or_empty() {
  state_output_target=$1 state_error_target=$2
  if run_tofu state list >"$state_output_target" 2>"$state_error_target"; then
    rm -f -- "$state_error_target"
    return 0
  fi
  if sed -E 's/\x1B\[[0-9;]*m//g' "$state_error_target" | grep -F 'No state file was found' >/dev/null &&
    sed -E 's/\x1B\[[0-9;]*m//g' "$state_error_target" | grep -F 'State management commands require a state file' >/dev/null; then
    : >"$state_output_target"
    rm -f -- "$state_error_target"
    return 0
  fi
  rm -f -- "$state_error_target"
  return 1
}

load_bundle_credentials() {
  export KEEPLING_HETZNER_CREDENTIAL_FILE=$(read_value HETZNER_CREDENTIAL_FILE "$bundle")
  export KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE=$(read_value CLOUDFLARE_CREDENTIAL_FILE "$bundle")
  export KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE=$(read_value PRIMARY_BACKUP_CREDENTIAL_FILE "$bundle")
  export KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE=$(read_value MIRROR_BACKUP_CREDENTIAL_FILE "$bundle")
  export KEEPLING_TOFU_STATE_CREDENTIAL_FILE=$(read_value TOFU_STATE_CREDENTIAL_FILE "$bundle")
  export KEEPLING_SSH_PUBLIC_KEY_FILE=$(read_value SSH_PUBLIC_KEY_FILE "$bundle")
  export KEEPLING_BACKUP_CIPHER_FILE=$(read_value BACKUP_CIPHER_FILE "$bundle")
  . "$repository_root/tooling/phase-2-credentials.sh"
  phase2_credentials_load_transient || die 'credential boundary is invalid'
  trap 'phase2_credentials_cleanup_transient' EXIT HUP INT TERM
}

readiness_adapter() {
  stage=teardown
  bundle=${KEEPLING_LIVE_ORCHESTRATION_FILE:-}
  [ -n "$bundle" ] && valid_private "$bundle" || die 'provider adapter bundle is unavailable'
  load_bundle_credentials
  workspace=$(read_value WORKSPACE "$bundle")
  [ -d "$workspace/tofu-data" ] && [ ! -L "$workspace/tofu-data" ] || die 'private provider state is unavailable'
  tf_data=$(mktemp -d "${TMPDIR:-/tmp}/keepling-provider-adapter.XXXXXX") || die 'private provider adapter workspace is unavailable'
  outside_repo "$tf_data" || die 'provider adapter workspace must remain external'
  chmod 700 "$tf_data"
  adapter_cleanup() { chmod 700 "$tf_data" 2>/dev/null || true; rm -rf -- "$tf_data"; phase2_credentials_cleanup_transient; }
  trap adapter_cleanup EXIT HUP INT TERM
  export TF_DATA_DIR="$tf_data"
  tofu=${TOFU_BIN:-}; case "$tofu" in /*) [ -x "$tofu" ] && [ ! -L "$tofu" ];; *) die 'pinned OpenTofu binary is unavailable';; esac
  run_tofu() { HCLOUD_TOKEN="$HCLOUD_TOKEN" "$repository_root/tooling/phase-2-tofu-state.sh" with-state-env "$tofu" -chdir="$repository_root/infra/tofu/hetzner" "$@"; }
  provider_dir=${HCLOUD_PROVIDER_PLUGIN_DIR:-}; case "$provider_dir" in /*) [ -d "$provider_dir" ] && [ ! -L "$provider_dir" ];; *) die 'pinned provider plugin directory is unavailable';; esac
  image_file=$(read_value SERVER_IMAGE_SELECTION_FILE "$bundle")
  cidr_file=$(read_value ADMIN_SOURCE_CIDRS_FILE "$bundle")
  public_key_file=$(read_value SSH_PUBLIC_KEY_FILE "$bundle")
  cidrs=$(jq -Rn '[inputs]' "$cidr_file") || die 'admin source network list is invalid'
  jq -n --slurpfile selection "$repository_root/infra/tofu/hetzner/selection.json" --slurpfile image "$image_file" \
    --argjson cidrs "$cidrs" --rawfile ssh "$public_key_file" --arg digest "$(read_value IMAGE_DIGEST "$bundle")" \
    --arg run "$(read_value RUN_ID "$bundle")" \
    '{location:$selection[0].location,server_type:$selection[0].server_type,target_architecture:"x86_64",server_image_id:$image[0].image_id,tested_oci_digest:$digest,ssh_public_key:$ssh,replacement_run_id:$run,admin_source_cidrs:$cidrs,data_volume_size_gb:$selection[0].data_volume_gb}' \
    >"$tf_data/variables.tfvars.json" || die 'private provider variables could not be written'
  chmod 600 "$tf_data/variables.tfvars.json"
  "$repository_root/tooling/phase-2-tofu-state.sh" render-init-config "$tf_data/backend.hcl" >/dev/null 2>&1 || die 'private provider backend could not be configured'
  run_tofu init -input=false -reconfigure -lockfile=readonly -plugin-dir="$provider_dir" -backend-config="$tf_data/backend.hcl" >/dev/null 2>&1 || die 'isolated provider state initialization failed'
  [ "$(readlink "$0")" = "$repository_root/tooling/phase-2-live-stage-actions.sh" ] || die 'provider adapter entry is invalid'
  case "${KEEPLING_PROVIDER_ADAPTER_OPERATION:-}" in
    ownership)
      [ "$#" -eq 3 ] || die 'ownership probe arguments are invalid'
      inventory=$1 expected_run=$2 output_file=$3
      run_tofu refresh -input=false -var-file="$tf_data/variables.tfvars.json" >/dev/null 2>&1 || die 'provider ownership refresh failed'
      raw="$tf_data/.provider-output.$$" counts="$tf_data/.provider-counts.$$"
      run_tofu output -json candidate_identity >"$raw" 2>/dev/null || die 'candidate identity output is unavailable'
      run_tofu output -json replacement_ssh_key_identity >"$tf_data/.ssh-output.$$" 2>/dev/null || die 'SSH identity output is unavailable'
      state_list_or_empty "$tf_data/.state-list.$$" "$tf_data/.state-error.$$" || die 'provider state query failed'
      "$repository_root/tooling/verify-host-replacement.sh" --validate-state-addresses "$tf_data/.state-list.$$" >/dev/null || die 'provider state graph is not exact'
      jq -c --slurpfile ssh "$tf_data/.ssh-output.$$" '{id,name,ipv4_address,primary_ip_id,network_id,volume_id,firewall_id,labels,ssh_key_id:$ssh[0].id}' "$raw" >"$tf_data/.normalized-provider.$$"
      printf '{"firewalls":1,"networks":1,"primary_ips":1,"servers":1,"ssh_keys":1,"volumes":1}\n' >"$counts"
      chmod 600 "$raw" "$counts" "$tf_data/.ssh-output.$$" "$tf_data/.normalized-provider.$$"
      "$repository_root/tooling/verify-host-replacement.sh" --normalize-provider-output "$tf_data/.normalized-provider.$$" "$counts" "$output_file" "$expected_run" >/dev/null || die 'provider ownership output was invalid'
      rm -f -- "$raw" "$counts" "$tf_data/.ssh-output.$$" "$tf_data/.normalized-provider.$$" "$tf_data/.state-list.$$"
      ;;
    state)
      [ "$#" -eq 1 ] || die 'state probe arguments are invalid'
      output_file=$1
      state_list_or_empty "$output_file" "$tf_data/.state-error.$$" || die 'provider state query failed'
      chmod 600 "$output_file"
      ;;
    destroy)
      [ "$#" -eq 2 ] || die 'destroy adapter arguments are invalid'
      run_tofu destroy -auto-approve -input=false -var-file="$tf_data/variables.tfvars.json" >/dev/null 2>&1 || die 'provider state destroy failed'
      ;;
    absence)
      [ "$#" -eq 2 ] || die 'absence probe arguments are invalid'
      expected_run=$1 output_file=$2
      api=https://api.hetzner.cloud/v1
      curl_config="$tf_data/.curl-absence.$$"
      (umask 077; printf 'header = "Authorization: Bearer %s"\n' "$HCLOUD_TOKEN" >"$curl_config"; chmod 600 "$curl_config")
      for resource in servers volumes primary_ips networks firewalls ssh_keys; do
        curl --silent --show-error --fail --config "$curl_config" \
          "$api/$resource?label_selector=keepling-run%3D$expected_run" >"$tf_data/.absence-$resource.$$" 2>/dev/null || die 'provider absence query failed'
      done
      jq -n --slurpfile a "$tf_data/.absence-servers.$$" --slurpfile b "$tf_data/.absence-volumes.$$" \
        --slurpfile c "$tf_data/.absence-primary_ips.$$" --slurpfile d "$tf_data/.absence-networks.$$" \
        --slurpfile e "$tf_data/.absence-firewalls.$$" --slurpfile f "$tf_data/.absence-ssh_keys.$$" \
        '{servers:($a[0].servers|length),volumes:($b[0].volumes|length),primary_ips:($c[0].primary_ips|length),networks:($d[0].networks|length),firewalls:($e[0].firewalls|length),ssh_keys:($f[0].ssh_keys|length)}' >"$output_file"
      chmod 600 "$output_file"; rm -f -- "$curl_config" "$tf_data"/.absence-*.$$
      ;;
    *) die 'provider adapter operation is not selected';;
  esac
  exit 0
}

case "${0##*/}" in
  keepling-provider-ownership) KEEPLING_PROVIDER_ADAPTER_OPERATION=ownership readiness_adapter "$@" ;;
  keepling-provider-state) KEEPLING_PROVIDER_ADAPTER_OPERATION=state readiness_adapter "$@" ;;
  keepling-provider-destroy) KEEPLING_PROVIDER_ADAPTER_OPERATION=destroy readiness_adapter "$@" ;;
  keepling-provider-absence) KEEPLING_PROVIDER_ADAPTER_OPERATION=absence readiness_adapter "$@" ;;
esac

[ "$#" -eq 5 ] || { stage=unknown; die 'stage interface requires five arguments'; }
stage=$1 run_id=$2 workspace=$3 digest=$4 bundle=$5
case "$stage" in bootstrap|image|restore|runtime|semantic|dns|teardown) ;; *) die 'unknown stage';; esac
printf '%s' "$run_id" | grep -Eq '^[a-z0-9][a-z0-9-]{7,39}$' || die 'invalid run binding'
printf '%s' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || die 'invalid digest binding'
case "$workspace:$bundle" in /*:/*) ;; *) die 'private absolute inputs required';; esac
outside_repo "$workspace" && outside_repo "$bundle" || die 'private paths must be external'
valid_private "$bundle" || die 'bundle is not private'
[ -d "$workspace" ] && [ ! -L "$workspace" ] && [ "$(mode_of "$workspace")" = 700 ] || die 'workspace is not private'
[ "$(CDPATH='' cd -P "$workspace" && pwd)" = "$workspace" ] || die 'workspace path contains an alias'
[ "$(read_value RUN_ID "$bundle")" = "$run_id" ] || die 'bundle run mismatch'
[ "$(read_value WORKSPACE "$bundle")" = "$workspace" ] || die 'bundle workspace mismatch'
[ "$(read_value IMAGE_DIGEST "$bundle")" = "$digest" ] || die 'bundle digest mismatch'
bundle_sha=$(shasum -a 256 "$bundle" | awk '{print $1}')
case "$bundle_sha" in [0-9a-f][0-9a-f]*) [ "${#bundle_sha}" = 64 ] || die 'bundle digest unavailable';; *) die 'bundle digest unavailable';; esac

expected_previous() { case "$1" in image) printf bootstrap;; restore) printf image;; runtime) printf restore;; semantic) printf runtime;; dns) printf semantic;; *) printf '';; esac; }
marker="$workspace/.stage-$stage.complete"
artifact="$workspace/.stage-$stage.output"
bundle_record="$workspace/.bundle.sha256"
host_trust_pending="$workspace/.host-trust.pending"
host_trust_verified="$workspace/.host-trust.verified"
prev=$(expected_previous "$stage")
previous_sha=none
if [ "$stage" = bootstrap ]; then
  if [ -e "$host_trust_pending" ]; then
    [ -f "$bundle_record" ] && [ ! -L "$bundle_record" ] && [ "$(mode_of "$bundle_record")" = 600 ] || die 'paused bootstrap bundle seal is absent'
    [ "$(cat "$bundle_record")" = "$bundle_sha" ] || die 'bundle changed after bootstrap was paused'
  else
    [ ! -e "$bundle_record" ] || die 'bundle record already exists'
    seal_tmp="$workspace/.bundle.sha256.tmp.$$"
    (umask 077; printf '%s\n' "$bundle_sha" >"$seal_tmp"; chmod 600 "$seal_tmp"; mv "$seal_tmp" "$bundle_record") || { rm -f -- "$seal_tmp"; die 'bundle seal could not be persisted'; }
  fi
else
  [ -f "$bundle_record" ] && [ ! -L "$bundle_record" ] && [ "$(mode_of "$bundle_record")" = 600 ] || die 'bootstrap bundle seal is absent'
  [ "$(cat "$bundle_record")" = "$bundle_sha" ] || die 'bundle changed after bootstrap'
  if [ -n "$prev" ]; then
    previous_sha=$(shasum -a 256 "$workspace/.stage-$prev.complete" | awk '{print $1}')
  fi
fi
artifact_sha=
record_body() { printf 'version=1\nRUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\nSTAGE=%s\nBUNDLE_SHA256=%s\nPREVIOUS_SHA256=%s\nSTAGE_OUTPUT=%s\nSTAGE_OUTPUT_SHA256=%s\n' "$run_id" "$workspace" "$digest" "$stage" "$bundle_sha" "$previous_sha" "${artifact##*/}" "$artifact_sha"; }
marker_matches() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  [ "$(wc -l <"$1" | tr -d '[:space:]')" = 9 ] || return 1
  grep -Fx 'version=1' "$1" >/dev/null &&
    grep -Fx "RUN_ID=$run_id" "$1" >/dev/null &&
    grep -Fx "WORKSPACE=$workspace" "$1" >/dev/null &&
    grep -Fx "IMAGE_DIGEST=$digest" "$1" >/dev/null &&
    grep -Fx "STAGE=$prev" "$1" >/dev/null &&
    grep -Fx "BUNDLE_SHA256=$bundle_sha" "$1" >/dev/null &&
    grep -Fx "STAGE_OUTPUT=.stage-$prev.output" "$1" >/dev/null &&
    [ "$(shasum -a 256 "$workspace/.stage-$prev.output" | awk '{print $1}')" = "$(read_value STAGE_OUTPUT_SHA256 "$1")" ]
}
if [ -n "$prev" ]; then marker_matches "$workspace/.stage-$prev.complete" || die "preceding $prev proof is absent or mismatched"; fi
[ ! -e "$marker" ] || die 'stage was already completed'

if [ "$stage" = teardown ]; then
  [ ! -e "$workspace/.teardown-attempted" ] || die 'teardown was already attempted'
  (umask 077 && mkdir -m 700 "$workspace/.teardown-attempted") || die 'teardown fence could not be persisted'
fi

# Fixture mode deliberately performs no external operation. The stage wrappers,
# run binding, ordering, and atomic records are the subject of hermetic tests.
if [ "${KEEPLING_LIVE_STAGE_FIXTURE:-}" = yes ]; then
  [ -n "${KEEPLING_STAGE_FIXTURE_LEDGER:-}" ] || die 'fixture ledger is required'
  case "$KEEPLING_STAGE_FIXTURE_LEDGER" in /*) ;; *) die 'fixture ledger must be absolute';; esac
  outside_repo "$KEEPLING_STAGE_FIXTURE_LEDGER" || die 'fixture ledger must be external'
  [ -f "$KEEPLING_STAGE_FIXTURE_LEDGER" ] && [ ! -L "$KEEPLING_STAGE_FIXTURE_LEDGER" ] || die 'fixture ledger is unavailable'
  printf 'result=fixture stage=%s\n' "$stage" >"$artifact"; chmod 600 "$artifact"
  printf '%s %s %s %s\n' "$stage" "$run_id" "$workspace" "$digest" >>"$KEEPLING_STAGE_FIXTURE_LEDGER"
  [ "${KEEPLING_STAGE_FIXTURE_FAIL_AT:-}" != "$stage" ] || { printf '%s\n' "stage=$stage result=failed"; exit 1; }
  artifact_sha=$(shasum -a 256 "$artifact" | awk '{print $1}')
  tmp="$workspace/.stage-$stage.tmp.$$"
  (umask 077; record_body >"$tmp"; chmod 600 "$tmp"; mv "$tmp" "$marker") || { rm -f -- "$tmp"; die 'atomic stage record failed'; }
  printf '%s\n' "stage=$stage result=passed"
  exit 0
fi

# Live operations are selected in source, never from bundle data or ambient
# runner overrides. Local fixtures take the no-command branch above.
load_bundle_credentials
run_tofu() { HCLOUD_TOKEN="$HCLOUD_TOKEN" "$repository_root/tooling/phase-2-tofu-state.sh" with-state-env "$tofu" -chdir="$repository_root/infra/tofu/hetzner" "$@"; }
init_tofu() {
  tofu=${TOFU_BIN:-}; case "$tofu" in /*) [ -x "$tofu" ] && [ ! -L "$tofu" ];; *) die 'pinned OpenTofu binary is unavailable';; esac
  [ "$("$tofu" version -json 2>/dev/null | jq -r '.terraform_version')" = 1.12.6 ] || die 'pinned OpenTofu version is unavailable'
  provider_dir=${HCLOUD_PROVIDER_PLUGIN_DIR:-}; case "$provider_dir" in /*) [ -d "$provider_dir" ] && [ ! -L "$provider_dir" ];; *) die 'pinned provider plugin directory is unavailable';; esac
  export TF_DATA_DIR="$workspace/tofu-data"
  if [ ! -d "$TF_DATA_DIR" ]; then mkdir -m 700 "$TF_DATA_DIR" || die 'private OpenTofu data directory could not be created'; fi
  [ "$(mode_of "$TF_DATA_DIR")" = 700 ] || die 'private OpenTofu data directory permissions are invalid'
  state_config="$workspace/backend.hcl"
  if [ ! -e "$state_config" ]; then "$repository_root/tooling/phase-2-tofu-state.sh" render-init-config "$state_config" >/dev/null 2>&1 || die 'private state backend could not be configured'; fi
  run_tofu init -reconfigure -lockfile=readonly -plugin-dir="$provider_dir" -backend-config="$state_config" >/dev/null 2>&1 || die 'isolated OpenTofu backend initialization failed'
}
write_tfvars() {
  selection_file="$repository_root/infra/tofu/hetzner/selection.json"
  image_file=$(read_value SERVER_IMAGE_SELECTION_FILE "$bundle")
  cidr_file=$(read_value ADMIN_SOURCE_CIDRS_FILE "$bundle")
  public_key_file=$(read_value SSH_PUBLIC_KEY_FILE "$bundle")
  cidrs=$(jq -Rn '[inputs]' "$cidr_file") || die 'admin source network list is invalid'
  jq -n --slurpfile selection "$selection_file" --slurpfile image "$image_file" --argjson cidrs "$cidrs" --rawfile ssh "$public_key_file" --arg digest "$digest" --arg run "$run_id" \
    '{location:$selection[0].location,server_type:$selection[0].server_type,target_architecture:"x86_64",server_image_id:$image[0].image_id,tested_oci_digest:$digest,ssh_public_key:$ssh,replacement_run_id:$run,admin_source_cidrs:$cidrs,data_volume_size_gb:$selection[0].data_volume_gb}' >"$TF_DATA_DIR/variables.tfvars.json" || die 'private OpenTofu variables could not be written'
  chmod 600 "$TF_DATA_DIR/variables.tfvars.json"
}
complete_stage() {
  [ -f "$artifact" ] && [ ! -L "$artifact" ] || die 'stage output artifact is absent'
  [ "$(mode_of "$artifact")" = 600 ] || die 'stage output artifact permissions are invalid'
  artifact_sha=$(shasum -a 256 "$artifact" | awk '{print $1}')
  tmp="$workspace/.stage-$stage.tmp.$$"
  (umask 077; record_body >"$tmp"; chmod 600 "$tmp"; mv "$tmp" "$marker") || { rm -f -- "$tmp"; die 'atomic stage record failed'; }
  printf '%s\n' "stage=$stage result=passed"
}

pause_for_host_trust() {
  printf 'version=1\nRUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\nBUNDLE_SHA256=%s\nSERVER_ID=%s\nSERVER_NAME=%s\nIP=%s\n' \
    "$run_id" "$workspace" "$digest" "$bundle_sha" "$server_id" "$server_name" "$bootstrap_ip" >"$host_trust_pending.tmp.$$"
  chmod 600 "$host_trust_pending.tmp.$$"
  mv "$host_trust_pending.tmp.$$" "$host_trust_pending"
  printf '%s\n' 'phase2-live status=paused reason=host-key-verification-required'
  printf 'candidate server: %s (%s)\n' "$server_name" "$bootstrap_ip"
  printf '%s\n' 'In the Hetzner VNC console run: ssh-keygen -E sha256 -lf /etc/ssh/ssh_host_ed25519_key.pub'
  printf '%s\n' 'Resume with: tooling/verify-host-replacement.sh --credentialed --resume-host-trust'
}
resume_host_trust() {
  [ -f "$host_trust_pending" ] && [ ! -L "$host_trust_pending" ] && [ "$(mode_of "$host_trust_pending")" = 600 ] || die 'host trust checkpoint is unavailable'
  [ ! -e "$host_trust_verified" ] || die 'host trust is already verified'
  [ "$(awk -F= '$1=="RUN_ID" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")" = "$run_id" ] || die 'host trust checkpoint run binding is invalid'
  [ "$(awk -F= '$1=="WORKSPACE" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")" = "$workspace" ] || die 'host trust checkpoint workspace binding is invalid'
  [ "$(awk -F= '$1=="IMAGE_DIGEST" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")" = "$digest" ] || die 'host trust checkpoint image binding is invalid'
  [ "$(awk -F= '$1=="BUNDLE_SHA256" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")" = "$bundle_sha" ] || die 'host trust checkpoint bundle binding is invalid'
  server_id=$(awk -F= '$1=="SERVER_ID" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")
  server_name=$(awk -F= '$1=="SERVER_NAME" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")
  bootstrap_ip=$(awk -F= '$1=="IP" {print substr($0,index($0,"=")+1)}' "$host_trust_pending")
  printf '%s' "$bootstrap_ip" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1; exit 0} {exit 1}' || die 'host trust checkpoint address is invalid'
  [ -n "$server_id" ] && [ -n "$server_name" ] || die 'host trust checkpoint identity is invalid'
  [ "$(jq -er '.resources.server_id' "$workspace/provider-inventory.json")" = "$server_id" ] || die 'host trust checkpoint server id does not match retained ownership'
  [ "$(cat "$workspace/candidate-ip.txt")" = "$bootstrap_ip" ] || die 'host trust checkpoint address does not match retained candidate proof'

  # Refresh through the configured provider state and ensure the candidate did
  # not change while the run was paused.
  init_tofu
  run_tofu refresh -input=false -var-file="$TF_DATA_DIR/variables.tfvars.json" >/dev/null 2>&1 || die 'candidate ownership refresh failed during host trust resume'
  current_identity="$workspace/.candidate-identity.$$"
  run_tofu output -json candidate_identity >"$current_identity" 2>/dev/null || die 'candidate identity is unavailable during host trust resume'
  chmod 600 "$current_identity"
  jq -e --arg id "$server_id" --arg name "$server_name" --arg ip "$bootstrap_ip" --arg run "$run_id" \
    --slurpfile inventory "$workspace/provider-inventory.json" \
    '(.id|tostring)==$id and .name==$name and .ipv4_address==$ip and
     (.primary_ip_id|tostring)==$inventory[0].resources.primary_ip_id and
     (.network_id|tostring)==$inventory[0].resources.network_id and
     (.volume_id|tostring)==$inventory[0].resources.volume_id and
     (.firewall_id|tostring)==$inventory[0].resources.firewall_id and
     (.ssh_key_id|tostring)==$inventory[0].resources.ssh_key_id and
     .labels=={"managed-by":"opentofu","keepling-run":$run,"purpose":"host-replacement"}' \
    "$current_identity" >/dev/null ||
    die 'candidate identity changed while the run was paused'
  rm -f -- "$current_identity"

  supplied=${KEEPLING_HOST_KEY_FINGERPRINT:-}
  if [ -z "$supplied" ] && [ -r /dev/tty ]; then
    printf '%s' 'Enter the SHA256 fingerprint verified in the Hetzner VNC console: ' >/dev/tty
    IFS= read -r supplied </dev/tty || die 'host fingerprint input was not received'
  fi
  printf '%s' "$supplied" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' || die 'a valid console-verified SHA256 fingerprint is required'
  known_hosts=$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")
  [ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(mode_of "$known_hosts")" = 600 ] || die 'private known-hosts file is invalid'
  [ ! -s "$known_hosts" ] || die 'known-hosts file changed while host trust was paused'
  "$repository_root/tooling/pin-verified-ssh-host-key.sh" "$bootstrap_ip" "$supplied" "$known_hosts" >/dev/null || die 'candidate SSH host fingerprint did not match the Hetzner VNC fingerprint'
  offered=$supplied
  trusted_sha=$(shasum -a 256 "$known_hosts" | awk '{print $1}')
  printf 'version=1\nRUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\nBUNDLE_SHA256=%s\nSERVER_ID=%s\nIP=%s\nFINGERPRINT=%s\nKNOWN_HOSTS_SHA256=%s\n' \
    "$run_id" "$workspace" "$digest" "$bundle_sha" "$server_id" "$bootstrap_ip" "$offered" "$trusted_sha" >"$host_trust_verified.tmp.$$"
  chmod 600 "$host_trust_verified.tmp.$$"
  mv "$host_trust_verified.tmp.$$" "$host_trust_verified"
  rm -f -- "$host_trust_pending"
}
require_host_trust() {
  [ -f "$host_trust_verified" ] && [ ! -L "$host_trust_verified" ] && [ "$(mode_of "$host_trust_verified")" = 600 ] || die 'verified candidate host identity is absent'
  known_hosts=$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")
  expected=$(awk -F= '$1=="KNOWN_HOSTS_SHA256" {print $2}' "$host_trust_verified")
  [ "$(awk -F= '$1=="RUN_ID" {print $2}' "$host_trust_verified")" = "$run_id" ] || die 'verified host identity run binding is invalid'
  [ "$(awk -F= '$1=="WORKSPACE" {print substr($0,index($0,"=")+1)}' "$host_trust_verified")" = "$workspace" ] || die 'verified host identity workspace binding is invalid'
  [ "$(awk -F= '$1=="BUNDLE_SHA256" {print $2}' "$host_trust_verified")" = "$bundle_sha" ] || die 'verified host identity bundle binding is invalid'
  [ -n "$expected" ] && [ "$(shasum -a 256 "$known_hosts" | awk '{print $1}')" = "$expected" ] || die 'verified candidate host identity changed'
  [ "$(awk -F= '$1=="IP" {print $2}' "$host_trust_verified")" = "$(cat "$workspace/candidate-ip.txt")" ] || die 'verified host identity address changed'
  [ -n "$(ssh-keygen -F "$(cat "$workspace/candidate-ip.txt")" -f "$known_hosts" 2>/dev/null)" ] || die 'verified candidate host key is not pinned to its address'
}

case "$stage" in
  bootstrap)
    if [ -e "$host_trust_pending" ]; then
      if [ "${KEEPLING_RESUME_HOST_TRUST:-}" = yes ]; then
        resume_host_trust
        bootstrap_ip=$(cat "$workspace/candidate-ip.txt")
        bootstrap_known_hosts=$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")
        export KEEPLING_TRANSFER_PUBLIC_IDENTITY="$(read_value SSH_PUBLIC_KEY_FILE "$bundle")" KEEPLING_TRANSFER_KNOWN_HOSTS="$bootstrap_known_hosts"
        export KEEPLING_TRANSFER_SSH_ADD="$(command -v ssh-add)" KEEPLING_TRANSFER_SSH="$(command -v ssh)" KEEPLING_TRANSFER_SCP="$(command -v scp)"
        export KEEPLING_TRANSFER_DESTINATION="root@$bootstrap_ip" KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID="$run_id"
        transfer_output="$workspace/.transfer-output.$$"
        if ! "$repository_root/tooling/transfer-trusted-candidate.sh" bootstrap >"$transfer_output" 2>&1; then
          case "$(cat "$transfer_output")" in
            TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-dependency) die 'candidate bootstrap is missing a required runtime dependency' ;;
            TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-incomplete) die 'candidate host bootstrap did not complete successfully' ;;
            TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-contract) die 'candidate bootstrap probe contract was rejected' ;;
            TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-authentication) die 'candidate SSH authentication was rejected by the host' ;;
            TRUSTED_TRANSFER_FAILED_STAGE=bootstrap-host-identity) die 'candidate host identity changed after verification' ;;
            *) die 'candidate bootstrap probes are not installed and verified' ;;
          esac
        fi
        [ "$(cat "$transfer_output")" = TRUSTED_TRANSFER_STAGE=bootstrap-ready ] || die 'candidate bootstrap did not return its closed success result'
        rm -f -- "$transfer_output"
        printf '%s\n' 'result=passed proof=exact-owned-candidate-and-host-identity' >"$artifact"; chmod 600 "$artifact"
        complete_stage
        exit 0
      else
        server_name=$(awk -F= '$1=="SERVER_NAME" {print $2}' "$host_trust_pending")
        bootstrap_ip=$(awk -F= '$1=="IP" {print $2}' "$host_trust_pending")
        printf '%s\n' 'phase2-live status=paused reason=host-key-verification-required'
        printf 'candidate server: %s (%s)\n' "$server_name" "$bootstrap_ip"
        printf '%s\n' 'The SSH fingerprint is displayed on the Hetzner VNC login screen; VM login is not required.'
        printf '%s\n' 'Resume with: tooling/verify-host-replacement.sh --credentialed --resume-host-trust'
        exit 75
      fi
    fi
    jq -e '.status=="benchmark-verified" and .benchmark.status=="passed" and .benchmark.cleanup_verified==true and .benchmark.projected_restore_seconds<=.acceptance_limits.maximum_full_host_seconds' infra/tofu/hetzner/selection.json >/dev/null 2>&1 || die 'measured restore selection is not ready'
    init_tofu; write_tfvars
    state_list="$TF_DATA_DIR/.state-before.$$"
    state_list_or_empty "$state_list" "$TF_DATA_DIR/.state-error.$$" || die 'provider state inspection failed'
    [ ! -s "$state_list" ] || die 'provider state is not empty for this run'
    chmod 600 "$state_list"
    plan="$workspace/candidate.tfplan" plan_json="$workspace/candidate-plan.json"
    run_tofu plan -input=false -lock-timeout=30s -var-file="$TF_DATA_DIR/variables.tfvars.json" -out="$plan" >/dev/null 2>&1 || die 'source candidate plan failed'
    run_tofu show -json "$plan" >"$plan_json" 2>/dev/null || die 'candidate plan could not be inspected'
    chmod 600 "$plan" "$plan_json"
    "$repository_root/tooling/verify-host-replacement.sh" --validate-plan-shape "$plan_json" >/dev/null || die 'candidate plan exceeded the exact empty host graph'
    (umask 077; : >"$workspace/.apply-started.tmp.$$"; chmod 600 "$workspace/.apply-started.tmp.$$"; mv "$workspace/.apply-started.tmp.$$" "$workspace/.apply-started") || die 'apply fence could not be persisted'
    run_tofu apply -input=false -auto-approve "$plan" >/dev/null 2>&1 || die 'candidate apply failed; teardown requires exact retained inventory'
    state_list="$workspace/provider-state.list"
    run_tofu state list >"$state_list" 2>/dev/null || die 'candidate state output is unavailable'
    chmod 600 "$state_list"
    "$repository_root/tooling/verify-host-replacement.sh" --validate-state-addresses "$state_list" >/dev/null || die 'applied candidate state graph is not exact'
    raw="$workspace/provider-output.json" ssh_output="$workspace/ssh-output.json" normalized="$workspace/provider-normalized.json" counts="$workspace/provider-counts.json"
    run_tofu output -json candidate_identity >"$raw" 2>/dev/null || die 'candidate provider identity is unavailable'
    run_tofu output -json replacement_ssh_key_identity >"$ssh_output" 2>/dev/null || die 'candidate SSH identity is unavailable'
    jq -c --slurpfile ssh "$ssh_output" '{id,name,ipv4_address,primary_ip_id,network_id,volume_id,firewall_id,labels,ssh_key_id:$ssh[0].id}' "$raw" >"$normalized"
    printf '{"firewalls":1,"networks":1,"primary_ips":1,"servers":1,"ssh_keys":1,"volumes":1}\n' >"$counts"
    chmod 600 "$raw" "$ssh_output" "$normalized" "$counts"
    "$repository_root/tooling/verify-host-replacement.sh" --normalize-provider-output "$normalized" "$counts" "$workspace/provider-inventory.json" "$run_id" >/dev/null || die 'provider inventory could not be retained exactly'
    jq -er '.ipv4_address | select(type=="string")' "$raw" >"$workspace/candidate-ip.txt" || die 'candidate address is unavailable'
    chmod 600 "$workspace/candidate-ip.txt"
    bootstrap_ip=$(cat "$workspace/candidate-ip.txt")
    server_id=$(jq -er '.id|tostring' "$raw") || die 'candidate server identity is unavailable'
    server_name=$(jq -er '.name|select(type=="string" and length>0)' "$raw") || die 'candidate server name is unavailable'
    rm -f -- "$state_list" "$plan" "$plan_json" "$raw" "$ssh_output" "$normalized" "$counts"
    pause_for_host_trust
    exit 75
    ;;
  image)
    require_host_trust
    ip=$(cat "$workspace/candidate-ip.txt")
    printf '%s' "$ip" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1; exit 0} {exit 1}' || die 'candidate IPv4 proof is invalid'
    known_hosts=$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")
    [ -s "$known_hosts" ] && ssh-keygen -F "$ip" -f "$known_hosts" >/dev/null 2>&1 || die 'candidate host key has not been trusted for this exact IP'
    handoff="$workspace/recovery-handoff" transfer_bundle="$workspace/candidate-bundle"; mkdir -m 700 "$handoff" "$transfer_bundle"
    cp "$(read_value RECOVERY_DUMP_FILE "$bundle")" "$handoff/recovery.dump"; cp "$(read_value RECOVERY_PROVENANCE_FILE "$bundle")" "$handoff/recovery.provenance.json"; chmod 600 "$handoff/recovery.dump" "$handoff/recovery.provenance.json"
    manifest="$workspace/candidate-bundle-manifest.json"
    host=$(read_value DNS_TEST_RECORD_NAME "$bundle")
    override="$workspace/compose-override.yml"
    printf 'services:\n  app:\n    image: %s\n    environment:\n      KEEPLING_HOST: %s\n      KEEPLING_SERVER_DIGEST: %s\n      KEEPLING_SERVER_INSTANCE: %s\n  caddy:\n    environment:\n      KEEPLING_HOST: %s\n    ports: !override\n      - "80:80"\n      - "443:443"\nvolumes:\n  postgres_data:\n    driver_opts:\n      device: /srv/keepling/data/postgres\n  caddy_data:\n    driver_opts:\n      device: /srv/keepling/data/caddy/data\n  caddy_config:\n    driver_opts:\n      device: /srv/keepling/data/caddy/config\n' "$digest" "$host" "$digest" "$run_id" "$host" >"$override"; chmod 600 "$override"
    export KEEPLING_TRANSFER_HANDOFF="$handoff" KEEPLING_BUNDLE_DESTINATION="$transfer_bundle" KEEPLING_BUNDLE_MANIFEST_FILE="$manifest"
    export KEEPLING_BUNDLE_IMAGE_SOURCE="$(read_value IMAGE_ARCHIVE_FILE "$bundle")" KEEPLING_BUNDLE_LOGIN_CREDENTIAL_SOURCE="$(read_value LOGIN_CREDENTIAL_FILE "$bundle")"
    export KEEPLING_BUNDLE_COMPOSE_SOURCE="$repository_root/infra/compose/compose.yml" KEEPLING_BUNDLE_CADDY_SOURCE="$repository_root/infra/caddy/Caddyfile" KEEPLING_BUNDLE_OVERRIDE_SOURCE="$override" KEEPLING_BUNDLE_RUNNER_SOURCE="$repository_root/tooling/remote-prepare-host.sh"
    export KEEPLING_TRANSFER_PUBLIC_IDENTITY="$(read_value SSH_PUBLIC_KEY_FILE "$bundle")" KEEPLING_TRANSFER_KNOWN_HOSTS="$known_hosts"
    export KEEPLING_TRANSFER_SSH_ADD="$(command -v ssh-add)" KEEPLING_TRANSFER_SSH="$(command -v ssh)" KEEPLING_TRANSFER_SCP="$(command -v scp)"
    export KEEPLING_TRANSFER_DESTINATION="root@$ip" KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID="$run_id"
    transfer_output="$workspace/.transfer-output.$$"
    "$repository_root/tooling/transfer-trusted-candidate.sh" image-transfer >"$transfer_output" 2>&1 || die 'exact image archive transfer failed'
    [ "$(cat "$transfer_output")" = TRUSTED_TRANSFER_STAGE=image-ready ] || die 'image transfer did not return its closed success result'
    rm -f -- "$transfer_output"
    printf '%s\n' 'result=passed proof=archive-digest-transferred' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
  restore)
    require_host_trust
    contract=$(read_value IMAGE_CONTRACT_FILE "$bundle")
    volume_id=$(jq -er '.volume_id|select(type=="string" and test("^[1-9][0-9]*$"))' "$workspace/provider-inventory.json") || die 'retained volume identity is invalid'
    host=$(read_value DNS_TEST_RECORD_NAME "$bundle") || die 'candidate runtime host is unavailable'
    export KEEPLING_REMOTE_VOLUME_ID="$volume_id"
    export KEEPLING_REMOTE_ARCHIVE_SHA256="$(jq -er '.archive_sha256' "$contract")"
    export KEEPLING_REMOTE_CONFIG_IMAGE_ID="$(jq -er '.config_image_id' "$contract")"
    export KEEPLING_REMOTE_MANIFEST_DIGEST="$(jq -er '.manifest_digest' "$contract")"
    export KEEPLING_REMOTE_REVISION="$(jq -er '.revision' "$contract")"
    export KEEPLING_REMOTE_ARCHITECTURE="$(jq -er '.architecture' "$contract")"
    export KEEPLING_REMOTE_ROOTFS_DIFF_IDS="$(jq -er '[.rootfs_diff_ids[]]|join(",")' "$contract")"
    export KEEPLING_REMOTE_RUNTIME_HOST="$host" KEEPLING_REMOTE_TESTED_MANIFEST_DIGEST="$digest"
    export KEEPLING_TRANSFER_HANDOFF="$workspace/recovery-handoff" KEEPLING_BUNDLE_DESTINATION="$workspace/candidate-bundle" KEEPLING_BUNDLE_MANIFEST_FILE="$workspace/candidate-bundle-manifest.json"
    export KEEPLING_TRANSFER_PUBLIC_IDENTITY="$(read_value SSH_PUBLIC_KEY_FILE "$bundle")" KEEPLING_TRANSFER_KNOWN_HOSTS="$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")"
    export KEEPLING_TRANSFER_SSH_ADD="$(command -v ssh-add)" KEEPLING_TRANSFER_SSH="$(command -v ssh)" KEEPLING_TRANSFER_SCP="$(command -v scp)" KEEPLING_TRANSFER_DESTINATION="root@$(cat "$workspace/candidate-ip.txt")" KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID="$run_id"
    transfer_output="$workspace/.transfer-output.$$"; "$repository_root/tooling/transfer-trusted-candidate.sh" restore >"$transfer_output" 2>&1 || die 'isolated restore and epoch finalization failed'
    [ "$(cat "$transfer_output")" = TRUSTED_TRANSFER_STAGE=restore-ready ] || die 'restore did not return its closed success result'; rm -f -- "$transfer_output"
    printf '%s\n' 'result=passed proof=restore-and-epoch-finalized' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
  runtime)
    require_host_trust
    export KEEPLING_TRANSFER_HANDOFF="$workspace/recovery-handoff" KEEPLING_BUNDLE_DESTINATION="$workspace/candidate-bundle" KEEPLING_BUNDLE_MANIFEST_FILE="$workspace/candidate-bundle-manifest.json"
    export KEEPLING_TRANSFER_PUBLIC_IDENTITY="$(read_value SSH_PUBLIC_KEY_FILE "$bundle")" KEEPLING_TRANSFER_KNOWN_HOSTS="$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")"
    export KEEPLING_TRANSFER_SSH_ADD="$(command -v ssh-add)" KEEPLING_TRANSFER_SSH="$(command -v ssh)" KEEPLING_TRANSFER_SCP="$(command -v scp)" KEEPLING_TRANSFER_DESTINATION="root@$(cat "$workspace/candidate-ip.txt")" KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID="$run_id"
    transfer_output="$workspace/.transfer-output.$$"; "$repository_root/tooling/transfer-trusted-candidate.sh" runtime >"$transfer_output" 2>&1 || die 'candidate runtime readiness proof failed'
    [ "$(cat "$transfer_output")" = TRUSTED_TRANSFER_STAGE=runtime-ready ] || die 'runtime probe did not return its closed success result'; rm -f -- "$transfer_output"
    printf '%s\n' 'result=passed proof=readiness-ready' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
  semantic)
    require_host_trust
    export KEEPLING_TRANSFER_HANDOFF="$workspace/recovery-handoff" KEEPLING_BUNDLE_DESTINATION="$workspace/candidate-bundle" KEEPLING_BUNDLE_MANIFEST_FILE="$workspace/candidate-bundle-manifest.json"
    export KEEPLING_TRANSFER_PUBLIC_IDENTITY="$(read_value SSH_PUBLIC_KEY_FILE "$bundle")" KEEPLING_TRANSFER_KNOWN_HOSTS="$(read_value SSH_KNOWN_HOSTS_FILE "$bundle")"
    export KEEPLING_TRANSFER_SSH_ADD="$(command -v ssh-add)" KEEPLING_TRANSFER_SSH="$(command -v ssh)" KEEPLING_TRANSFER_SCP="$(command -v scp)" KEEPLING_TRANSFER_DESTINATION="root@$(cat "$workspace/candidate-ip.txt")" KEEPLING_TRANSFER_PORT=22 KEEPLING_TRANSFER_RUN_ID="$run_id"
    transfer_output="$workspace/.transfer-output.$$"; "$repository_root/tooling/transfer-trusted-candidate.sh" semantic >"$transfer_output" 2>&1 || die 'candidate login/read/write/undo proof failed'
    [ "$(cat "$transfer_output")" = TRUSTED_TRANSFER_STAGE=semantic-ready ] || die 'semantic proof did not return its closed success result'; rm -f -- "$transfer_output"
    printf '%s\n' 'result=passed proof=login-read-write-undo' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
  dns)
    ip=$(cat "$workspace/candidate-ip.txt")
    dns_evidence="$workspace/dns-evidence.json"
    KEEPLING_DNS_RECORD_NAME=$(read_value DNS_TEST_RECORD_NAME "$bundle"); export KEEPLING_DNS_RECORD_NAME
    "$repository_root/infra/dns/cloudflare.sh" rehearse-temporary "$(read_value DNS_TEST_RECORD_NAME "$bundle")" "$ip" "$dns_evidence" >/dev/null 2>&1 || die 'isolated DNS cutover or rollback propagation proof failed'
    jq -e 'keys==["cutover_propagated","elapsed_seconds","https_readiness","result","rollback_propagated","temporary_record_deleted","version"] and .version==1 and .result=="PASS" and .cutover_propagated==true and .rollback_propagated==true and .https_readiness==true and .temporary_record_deleted==true' "$dns_evidence" >/dev/null 2>&1 || die 'DNS evidence did not prove isolated cutover, readiness, rollback, and deletion'
    printf '%s\n' 'result=passed proof=cutover-and-rollback-propagated' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
  teardown)
    teardown_evidence="$workspace/teardown-evidence.json"
    if [ ! -s "$workspace/provider-inventory.json" ]; then
      [ ! -e "$workspace/.apply-started" ] || die 'partial provider apply has no exact retained inventory; no broad destroy was attempted'
      printf '{"version":1,"result":"NO_RESOURCE","provider_mutation":false}\n' >"$teardown_evidence"; chmod 600 "$teardown_evidence"
    else
      adapter_dir="$workspace/provider-adapters"; mkdir -m 700 "$adapter_dir"
      ln -s "$repository_root/tooling/phase-2-live-stage-actions.sh" "$adapter_dir/keepling-provider-ownership"
      ln -s "$repository_root/tooling/phase-2-live-stage-actions.sh" "$adapter_dir/keepling-provider-state"
      ln -s "$repository_root/tooling/phase-2-live-stage-actions.sh" "$adapter_dir/keepling-provider-destroy"
      ln -s "$repository_root/tooling/phase-2-live-stage-actions.sh" "$adapter_dir/keepling-provider-absence"
      KEEPLING_PROVIDER_OWNERSHIP_PROBE="$adapter_dir/keepling-provider-ownership" KEEPLING_PROVIDER_STATE_PROBE="$adapter_dir/keepling-provider-state" \
      KEEPLING_PROVIDER_DESTROY_RUNNER="$adapter_dir/keepling-provider-destroy" KEEPLING_PROVIDER_ABSENCE_PROBE="$adapter_dir/keepling-provider-absence" \
        "$repository_root/tooling/destroy-owned-provider.sh" "$workspace/provider-inventory.json" "$run_id" "$teardown_evidence" >/dev/null 2>&1 || die 'exact-owned teardown or absence proof failed'
    fi
    jq -e '(.result=="NO_RESOURCE" and .provider_mutation==false) or (.result=="PASS" and .ownership_reread==true and .state_destroyed==true and .provider_absence==true)' "$teardown_evidence" >/dev/null 2>&1 || die 'teardown evidence is incomplete'
    printf '%s\n' 'result=passed proof=single-attempt-owned-teardown' >"$artifact"; chmod 600 "$artifact"; complete_stage
    ;;
esac
