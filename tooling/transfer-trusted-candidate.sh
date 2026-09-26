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

# A deliberately narrow, operator-invoked handoff.  All paths and executables
# are supplied by the caller so this adapter has no DNS, provider, or SSH
# discovery fallback.
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
die() { printf '%s\n' "TRUSTED_TRANSFER_FAILED_STAGE=$1" >&2; exit "${2:-40}"; }
operation=${1:-full}
[ "$#" -le 1 ] || die usage
case "$operation" in full|bootstrap|image-transfer|restore|runtime|semantic) ;; *) die usage;; esac
mode_of() { portable_stat '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
outside_repo() { case "$1" in "$repository_root"|"$repository_root"/*) return 1;; *) return 0;; esac; }
absolute_regular_private() {
  case "$1" in /*) ;; *) return 1;; esac
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  outside_repo "$parent/$(basename "$1")"
}
record() { [ -n "${KEEPLING_TRANSFER_LEDGER:-}" ] && printf '%s\n' "$1" >>"$KEEPLING_TRANSFER_LEDGER"; }

handoff=${KEEPLING_TRANSFER_HANDOFF:-}
bundle=${KEEPLING_BUNDLE_DESTINATION:-}
manifest=${KEEPLING_BUNDLE_MANIFEST_FILE:-}
if [ "$operation" != bootstrap ]; then
  case "$handoff:$bundle:$manifest" in /*:/*:/*) ;; *) die provenance;; esac
  [ -d "$handoff" ] && [ ! -L "$handoff" ] && [ "$(mode_of "$handoff")" = 700 ] && outside_repo "$handoff" || die provenance
  [ "$(find "$handoff" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 2 ] || die provenance
  dump="$handoff/recovery.dump" provenance="$handoff/recovery.provenance.json"
  for file in "$dump" "$provenance"; do
    [ -f "$file" ] && [ ! -L "$file" ] && [ "$(mode_of "$file")" = 600 ] || die provenance
  done
  jq -e '
  type == "object" and .version == 1 and
  if .source_kind == "synthetic-rehearsal" then
    (keys|sort) == ["plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and
    (.plaintext_sha256|type == "string" and test("^[0-9a-f]{64}$")) and
    (.plaintext_bytes|type == "number" and . > 0 and . <= 1099511627776 and floor == .) and
    (.verification|type == "object" and (keys|sort) == ["local_capture","local_restore","synthetic"] and
      .local_capture == true and .local_restore == true and .synthetic == true)
  else
    (keys|sort) == ["ciphertext_bytes","ciphertext_sha256","plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and
    (.source_kind == "b2-primary" or .source_kind == "r2-mirror") and
    (.ciphertext_sha256|type == "string" and test("^[0-9a-f]{64}$")) and
    (.plaintext_sha256|type == "string" and test("^[0-9a-f]{64}$")) and
    (.ciphertext_bytes|type == "number" and . >= 0 and . <= 1099511627776 and floor == .) and
    (.plaintext_bytes|type == "number" and . >= 0 and . <= 1099511627776 and floor == .) and
    (.verification|type == "object" and (keys|sort) == ["decrypt","get","head","package_manifest","plaintext"] and
      .head == true and .get == true and .package_manifest == true and .decrypt == true and .plaintext == true)
  end
' "$provenance" >/dev/null 2>&1 || die provenance
  [ "$(shasum -a 256 "$dump" | awk '{print $1}')" = "$(jq -r .plaintext_sha256 "$provenance")" ] || die provenance
  [ "$(wc -c <"$dump" | tr -d ' ')" = "$(jq -r .plaintext_bytes "$provenance")" ] || die provenance
  record provenance
fi

if [ "$operation" = image-transfer ] || [ "$operation" = full ]; then
  [ -d "$bundle" ] && [ -z "$(find "$bundle" -mindepth 1 -maxdepth 1 -print -quit)" ] && outside_repo "$bundle" || die bundle
  export KEEPLING_BUNDLE_RECOVERY_SOURCE="$dump" KEEPLING_BUNDLE_PROVENANCE_SOURCE="$provenance"
  "$repository_root/tooling/verify-host-replacement.sh" --stage-bundle >/dev/null 2>&1 || die bundle
  record bundle
elif [ "$operation" != bootstrap ]; then
  [ -d "$bundle" ] && [ ! -L "$bundle" ] && outside_repo "$bundle" && [ -f "$manifest" ] && [ ! -L "$manifest" ] || die bundle
  jq -e 'type=="object" and .version==1 and .complete==true and (.files|type=="array" and length==8) and ([.files[].name]|sort)==["Caddyfile","compose-override.yml","compose.yml","image.tar.gz","new-login-credential","recovery.dump","recovery.provenance.json","remote-prepare.sh"] and all(.files[]; .mode=="600" or .mode=="700")' "$manifest" >/dev/null 2>&1 || die bundle
  for name in Caddyfile compose-override.yml compose.yml image.tar.gz new-login-credential recovery.dump recovery.provenance.json remote-prepare.sh; do
    file="$bundle/$name"; [ -f "$file" ] && [ ! -L "$file" ] || die bundle
    expected_sha=$(jq -r --arg name "$name" '.files[] | select(.name==$name) | .sha256' "$manifest")
    expected_mode=$(jq -r --arg name "$name" '.files[] | select(.name==$name) | .mode' "$manifest")
    [ "$(shasum -a 256 "$file" | awk '{print $1}')" = "$expected_sha" ] && [ "$(mode_of "$file")" = "$expected_mode" ] || die bundle
  done
fi

agent=${SSH_AUTH_SOCK:-}
[ -S "$agent" ] || die ssh-stage
identity=${KEEPLING_TRANSFER_PUBLIC_IDENTITY:-} known_hosts=${KEEPLING_TRANSFER_KNOWN_HOSTS:-}
absolute_regular_private "$identity" && absolute_regular_private "$known_hosts" || die ssh-stage
ssh_add=${KEEPLING_TRANSFER_SSH_ADD:-} ssh=${KEEPLING_TRANSFER_SSH:-} scp=${KEEPLING_TRANSFER_SCP:-}
for executable in "$ssh_add" "$ssh" "$scp"; do case "$executable" in /*) [ -x "$executable" ] && [ ! -L "$executable" ] ;; *) die ssh-stage;; esac; done
identity=$(awk 'NF >= 2 { print $1 " " $2; exit }' "$identity")
[ -n "$identity" ] || die ssh-stage
identity_lines=$($ssh_add -L 2>/dev/null || true)
[ "$(printf '%s\n' "$identity_lines" | awk 'NF >= 2 { print $1 " " $2 }' | grep -Fxc "$identity")" = 1 ] || die ssh-stage
destination=${KEEPLING_TRANSFER_DESTINATION:-} port=${KEEPLING_TRANSFER_PORT:-} run=${KEEPLING_TRANSFER_RUN_ID:-}
printf '%s' "$destination" | grep -Eq '^[a-z_][a-z0-9_-]{0,30}@[a-z0-9][a-z0-9.-]{0,251}$' || die ssh-stage
printf '%s' "$port" | grep -Eq '^[1-9][0-9]{0,4}$' && [ "$port" -le 65535 ] || die ssh-stage
printf '%s' "$run" | grep -Eq '^[a-z0-9][a-z0-9-]{7,39}$' || die ssh-stage
ssh_opts="-o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=$agent -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts -o GlobalKnownHostsFile=/dev/null -o ForwardAgent=no -i $identity -p $port"
scp_opts="-o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=$agent -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts -o GlobalKnownHostsFile=/dev/null -o ForwardAgent=no -i $identity -P $port"
cleanup_started=false
staging_names='Caddyfile compose-override.yml compose.yml image.tar.gz new-login-credential recovery.dump recovery.provenance.json remote-prepare.sh'
cleanup() {
  if [ "$cleanup_started" = true ]; then
    "$ssh" $ssh_opts "$destination" rm -f -- /root/Caddyfile /root/compose-override.yml /root/compose.yml /root/image.tar.gz /root/new-login-credential /root/recovery.dump /root/recovery.provenance.json /root/remote-prepare.sh >/dev/null 2>&1 || true
    record cleanup
  fi
}
trap cleanup EXIT HUP INT TERM
if [ "$operation" = bootstrap ]; then
  # The VNC fingerprint is printed after Keepling's bootstrap runcmd. Use the
  # app-specific sentinel/probe below; global cloud-init may report unrelated
  # provider datasource warnings even after Keepling is correctly provisioned.
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    if output=$("$ssh" $ssh_opts "$destination" /usr/local/libexec/keepling-runtime-probe --bootstrap 2>&1); then
      [ "$output" = REMOTE_BOOTSTRAP_STAGE=ready ] || die bootstrap
      break
    fi
    case "$output" in
      REMOTE_RUNTIME_FAILED_STAGE=dependency) die bootstrap-dependency ;;
      REMOTE_RUNTIME_FAILED_STAGE=bootstrap) die bootstrap-incomplete ;;
      REMOTE_RUNTIME_FAILED_STAGE=boundary) die bootstrap-contract ;;
    esac
    printf '%s\n' "$output" | grep -Eiq 'permission denied|authentication failed' && die bootstrap-authentication
    printf '%s\n' "$output" | grep -Eiq 'host key verification failed|remote host identification has changed' && die bootstrap-host-identity
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || die bootstrap
    sleep 10
  done
  printf '%s\n' 'TRUSTED_TRANSFER_STAGE=bootstrap-ready'
  exit 0
fi
if [ "$operation" = image-transfer ] || [ "$operation" = full ]; then
  for name in $staging_names; do "$ssh" $ssh_opts "$destination" test ! -e "/root/$name" >/dev/null 2>&1 || die ssh-stage; done
  cleanup_started=true
  for name in $staging_names; do
    "$scp" $scp_opts "$bundle/$name" "$destination:/root/$name" >/dev/null 2>&1 || die ssh-stage
  done
  record ssh-stage
  if [ "$operation" = image-transfer ]; then
    cleanup_started=false; trap - EXIT HUP INT TERM
    printf '%s\n' 'TRUSTED_TRANSFER_STAGE=image-ready'
    exit 0
  fi
fi
if [ "$operation" = restore ] || [ "$operation" = full ]; then
  volume_id=${KEEPLING_REMOTE_VOLUME_ID:-} archive_sha=${KEEPLING_REMOTE_ARCHIVE_SHA256:-}
  config_id=${KEEPLING_REMOTE_CONFIG_IMAGE_ID:-} manifest_digest=${KEEPLING_REMOTE_MANIFEST_DIGEST:-}
  revision=${KEEPLING_REMOTE_REVISION:-} architecture=${KEEPLING_REMOTE_ARCHITECTURE:-}
  rootfs_diff_ids=${KEEPLING_REMOTE_ROOTFS_DIFF_IDS:-} runtime_host=${KEEPLING_REMOTE_RUNTIME_HOST:-}
  tested_digest=${KEEPLING_REMOTE_TESTED_MANIFEST_DIGEST:-}
  printf '%s' "$volume_id" | grep -Eq '^[1-9][0-9]*$' || die remote-prepare
  printf '%s' "$archive_sha" | grep -Eq '^[0-9a-f]{64}$' || die remote-prepare
  printf '%s' "$config_id" | grep -Eq '^sha256:[0-9a-f]{64}$' || die remote-prepare
  printf '%s' "$manifest_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || die remote-prepare
  printf '%s' "$revision" | grep -Eq '^[0-9a-f]{7,64}$' || die remote-prepare
  [ "$architecture" = amd64 ] || die remote-prepare
  printf '%s' "$rootfs_diff_ids" | grep -Eq '^sha256:[0-9a-f]{64}(,sha256:[0-9a-f]{64})*$' || die remote-prepare
  printf '%s' "$runtime_host" | grep -Eq '^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$' || die remote-prepare
  printf '%s' "$tested_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || die remote-prepare
  output=$("$ssh" $ssh_opts "$destination" env KEEPLING_REMOTE_PREPARE_PROVENANCE_REQUIRED=yes /root/remote-prepare.sh \
    "$volume_id" "$archive_sha" "$config_id" "$manifest_digest" "$revision" "$architecture" \
    "$rootfs_diff_ids" "$runtime_host" "$tested_digest" 2>/dev/null) || die remote-prepare
  [ "$output" = REMOTE_PREPARE_STAGE=ready ] || die remote-prepare
  cleanup_started=true
  "$ssh" $ssh_opts "$destination" rm -f -- /root/Caddyfile /root/compose-override.yml /root/compose.yml /root/image.tar.gz /root/new-login-credential /root/recovery.dump /root/recovery.provenance.json /root/remote-prepare.sh >/dev/null 2>&1 || die remote-prepare
  cleanup_started=false
  [ "$operation" = full ] || { cleanup_started=false; trap - EXIT HUP INT TERM; printf '%s\n' 'TRUSTED_TRANSFER_STAGE=restore-ready'; exit 0; }
fi
if [ "$operation" = runtime ] || [ "$operation" = full ]; then
  output=$("$ssh" $ssh_opts "$destination" /usr/local/libexec/keepling-runtime-probe 2>/dev/null) || die runtime
  [ "$output" = REMOTE_RUNTIME_STAGE=ready ] || die runtime
  [ "$operation" = full ] || { cleanup_started=false; trap - EXIT HUP INT TERM; printf '%s\n' 'TRUSTED_TRANSFER_STAGE=runtime-ready'; exit 0; }
fi
if [ "$operation" = semantic ] || [ "$operation" = full ]; then
  output=$("$ssh" $ssh_opts "$destination" /usr/local/libexec/keepling-semantic-proof 2>/dev/null) || die semantic
  [ "$output" = REMOTE_SEMANTIC_STAGE=ready ] || die semantic
  [ "$operation" = full ] || { cleanup_started=false; trap - EXIT HUP INT TERM; printf '%s\n' 'TRUSTED_TRANSFER_STAGE=semantic-ready'; exit 0; }
fi
trap - EXIT HUP INT TERM
cleanup
printf '%s\n' 'TRUSTED_TRANSFER_STAGE=ready'
