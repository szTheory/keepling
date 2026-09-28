#!/usr/bin/env sh
# Hermetic boundary/ledger regression for isolated recovery-source adapters.
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
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd); cd "$repository_root"
root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-recovery-source.XXXXXX")
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
die() { echo "Recovery source adapter regression failed: $*" >&2; exit 1; }

make_fakes() {
  mkdir -p "$root/bin"
  for command in aws bundle runner dns mutation; do
    printf '#!/usr/bin/env sh\nprintf "%%s\\n" %s >>"$KEEPLING_BACKUP_FIXTURE_LEDGER"\nexit 99\n' "$command" >"$root/bin/$command"
    chmod 700 "$root/bin/$command"
  done
  cat >"$root/bin/tar" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' archive >>"$KEEPLING_BACKUP_FIXTURE_LEDGER"
exec /usr/bin/tar "$@"
EOF
  cat >"$root/bin/cipher" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' cipher >>"$KEEPLING_BACKUP_FIXTURE_LEDGER"
[ "${KEEPLING_TEST_CIPHER_FAIL:-0}" = 0 ] || exit 1
cp "$2" "$3"
EOF
  cat >"$root/bin/mv" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' publish >>"$KEEPLING_BACKUP_FIXTURE_LEDGER"
case "${KEEPLING_TEST_PROVENANCE_PUBLISH_FAIL:-0}:$2" in 1:*/recovery.provenance.json) exit 1;; esac
exec /bin/mv "$@"
EOF
  chmod 700 "$root/bin/tar" "$root/bin/cipher" "$root/bin/mv"
  printf '%s' cipher-reference >"$root/cipher-file"; chmod 600 "$root/cipher-file"
}
refresh_package() {
  base=$1 members=${2:-'manifest.sha256 recovery.dump.enc'}
  # Members are fixed literals supplied by this test, never test input.
  /usr/bin/tar -C "$base" -czf "$base/package.tar.gz" $members
  refresh_selected_object "$base"
}
refresh_selected_object() {
  base=$1
  archive_sha=$(shasum -a 256 "$base/package.tar.gz" | awk '{print $1}')
  cp "$base/package.tar.gz" "$base/store/objects/recovery/2026/package.tar.gz"
  jq --arg sha "$archive_sha" '.Metadata["ciphertext-sha256"]=$sha' "$base/store/metadata/recovery/2026/package.tar.gz.json" >"$base/changed"; /bin/mv "$base/changed" "$base/store/metadata/recovery/2026/package.tar.gz.json"
  jq --arg sha "$archive_sha" '.ciphertext_sha256=$sha' "$base/input/selection.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/selection.json"
}
make_case() {
  kind=$1 label=$2; base="$root/$label"
  mkdir -p "$base/store/objects/recovery/2026" "$base/store/metadata/recovery/2026" "$base/input" "$base/workspace"; chmod 700 "$base/workspace"
  printf '%s' verified-recovery-dump >"$base/plain"; plain_sha=$(shasum -a 256 "$base/plain" | awk '{print $1}')
  cp "$base/plain" "$base/recovery.dump.enc"; enc_sha=$(shasum -a 256 "$base/recovery.dump.enc" | awk '{print $1}')
  printf '%s  recovery.dump.enc\n' "$enc_sha" >"$base/manifest.sha256"
  /usr/bin/tar -C "$base" -czf "$base/package.tar.gz" manifest.sha256 recovery.dump.enc; archive_sha=$(shasum -a 256 "$base/package.tar.gz" | awk '{print $1}')
  cp "$base/package.tar.gz" "$base/store/objects/recovery/2026/package.tar.gz"
  jq -n --arg kind "$kind" --arg sha "$archive_sha" '{Metadata:{"source-kind":$kind,"ciphertext-sha256":$sha}}' >"$base/store/metadata/recovery/2026/package.tar.gz.json"
  jq -n --arg kind "$kind" --arg sha "$archive_sha" --arg plain "$plain_sha" '{version:1,source_kind:$kind,object_key:"recovery/2026/package.tar.gz",ciphertext_sha256:$sha,plaintext_sha256:$plain,encryption_format:"tar-gzip-encrypted-v1",backup_id:"fixture-backup-1"}' >"$base/input/selection.json"
  jq -n '{version:1,endpoint:"https://fixture.invalid",region:"auto",bucket:"fixture",access_key_id:"fixture-key",secret_access_key:"fixture-secret"}' >"$base/input/credential.json"; : >"$base/ledger"
}
run_adapter() {
  kind=$1 base=$2 workspace=${3:-"$2/workspace"} credential_path=${4:-"$2/input/credential.json"} selection_path=${5:-"$2/input/selection.json"}
  case "$kind" in
    b2-primary) adapter=./tooling/recovery-source-b2.sh; fixture=KEEPLING_BACKUP_PRIMARY_FIXTURE_ROOT; credential=KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE; selection=KEEPLING_BACKUP_PRIMARY_SELECTION_FILE;;
    r2-mirror) adapter=./tooling/recovery-source-r2.sh; fixture=KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT; credential=KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE; selection=KEEPLING_BACKUP_MIRROR_SELECTION_FILE;;
    *) die "unknown source $kind";;
  esac
  env PATH="$root/bin:$PATH" KEEPLING_BACKUP_FIXTURE_LEDGER="$base/ledger" KEEPLING_BACKUP_PRIMARY_FIXTURE_ROOT="$root/cross-source-marker" KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT="$root/cross-source-marker" "$fixture=$base/store" "$credential=$credential_path" "$selection=$selection_path" KEEPLING_BACKUP_CIPHER_EXECUTABLE="$root/bin/cipher" KEEPLING_BACKUP_CIPHER_FILE="$root/cipher-file" ${case_extra_env:-} "$adapter" fetch "$workspace" >"$base/output" 2>&1
}
ledger_is() {
  base=$1 expected=$2; actual=$(tr '\n' ' ' <"$base/ledger" | sed 's/ $//')
  [ "$actual" = "$expected" ] || die "$base ledger was '$actual', expected '$expected'"
  ! grep -Eq '^(aws|bundle|runner|dns|mutation)$' "$base/ledger" || die "$base crossed a forbidden boundary"
}
no_artifacts() {
  base=$1
  [ ! -e "$base/workspace/recovery.dump" ] && [ ! -e "$base/workspace/recovery.provenance.json" ] || die "$base left final artifact"
  [ -z "$(find "$base/workspace" -mindepth 1 -maxdepth 1 -print -quit)" ] || die "$base leaked a temporary artifact"
}
success() {
  kind=$1 label=$2; make_case "$kind" "$label"; base="$root/$label"; run_adapter "$kind" "$base" || { cat "$base/output" >&2; die "$label failed"; }
  ledger_is "$base" 'head get package-manifest archive archive archive decrypt cipher publish publish'
  cmp -s "$base/plain" "$base/workspace/recovery.dump" || die "$label changed dump bytes"
  [ "$(portable_stat '%Lp' "$base/workspace/recovery.dump")" = 600 ] && [ "$(portable_stat '%Lp' "$base/workspace/recovery.provenance.json")" = 600 ] || die "$label artifact mode"
  jq -e --arg kind "$kind" '(keys|sort)==["ciphertext_bytes","ciphertext_sha256","plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and .source_kind==$kind and .verification=={head:true,get:true,package_manifest:true,decrypt:true,plaintext:true}' "$base/workspace/recovery.provenance.json" >/dev/null || die "$label provenance contract"
  ! grep -Eq 'fixture-secret|package.tar.gz|fixture-backup-1|verified-recovery-dump' "$base/output" "$base/workspace/recovery.provenance.json" || die "$label leaked private input"
}
failed() { kind=$1 label=$2 expected=$3; make_case "$kind" "$label"; base="$root/$label"; if run_adapter "$kind" "$base"; then die "$label unexpectedly succeeded"; fi; ledger_is "$base" "$expected"; no_artifacts "$base"; }

selection_refusals() {
  kind=$1 prefix=$2
  for object_key in 'recovery/./package.tar.gz' 'recovery/../package.tar.gz' 'recovery//package.tar.gz' '/recovery/package.tar.gz' 'recovery\\package.tar.gz' 'recovery/2026/../../outside'; do
    label="$prefix-selection-refusal-$(printf '%s' "$object_key" | shasum -a 256 | cut -c1-8)"
    make_case "$kind" "$label"; base="$root/$label"
    jq --arg key "$object_key" '.object_key=$key' "$base/input/selection.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/selection.json"
    if run_adapter "$kind" "$base"; then die "$label accepted unsafe object key"; fi
    ledger_is "$base" ''; no_artifacts "$base"
  done
  make_case "$kind" "$prefix-malformed-selection"; base="$root/$prefix-malformed-selection"
  jq 'del(.backup_id)' "$base/input/selection.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/selection.json"
  if run_adapter "$kind" "$base"; then die "$prefix malformed selection accepted"; fi
  ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-symlink-selection"; base="$root/$prefix-symlink-selection"
  /bin/mv "$base/input/selection.json" "$base/input/selection-target.json"; ln -s selection-target.json "$base/input/selection.json"
  if run_adapter "$kind" "$base"; then die "$prefix symlink selection accepted"; fi
  ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-repository-selection"; base="$root/$prefix-repository-selection"
  if run_adapter "$kind" "$base" "$base/workspace" "$base/input/credential.json" "$repository_root/AGENTS.md"; then die "$prefix repository selection accepted"; fi
  ledger_is "$base" ''; no_artifacts "$base"
}

workspace_refusals() {
  kind=$1 prefix=$2
  make_case "$kind" "$prefix-symlink-workspace"; base="$root/$prefix-symlink-workspace"; ln -s "$base/workspace" "$base/workspace-link"
  if run_adapter "$kind" "$base" "$base/workspace-link"; then die "$prefix symlink workspace accepted"; fi
  ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-repository-workspace"; base="$root/$prefix-repository-workspace"
  if run_adapter "$kind" "$base" "$repository_root"; then die "$prefix repository workspace accepted"; fi
  ledger_is "$base" ''
}

basic_refusals() {
  kind=$1 prefix=$2 other=$3
  make_case "$kind" "$prefix-wrong-source"; base="$root/$prefix-wrong-source"; jq --arg source "$other" '.source_kind=$source' "$base/input/selection.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/selection.json"
  if run_adapter "$kind" "$base"; then die "$prefix wrong source accepted"; fi; ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-missing-credential"; base="$root/$prefix-missing-credential"; rm -f "$base/input/credential.json"
  if run_adapter "$kind" "$base"; then die "$prefix missing credential accepted"; fi; ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-malformed-credential"; base="$root/$prefix-malformed-credential"; jq 'del(.region)' "$base/input/credential.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/credential.json"
  if run_adapter "$kind" "$base"; then die "$prefix malformed credential accepted"; fi; ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-missing-selection"; base="$root/$prefix-missing-selection"; rm -f "$base/input/selection.json"
  if run_adapter "$kind" "$base"; then die "$prefix missing selection accepted"; fi; ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-nonprivate-workspace"; base="$root/$prefix-nonprivate-workspace"; chmod 755 "$base/workspace"
  if run_adapter "$kind" "$base"; then die "$prefix non-private workspace accepted"; fi; ledger_is "$base" ''; no_artifacts "$base"
  make_case "$kind" "$prefix-nonempty-workspace"; base="$root/$prefix-nonempty-workspace"; printf sentinel >"$base/workspace/sentinel"
  if run_adapter "$kind" "$base"; then die "$prefix nonempty workspace accepted"; fi; ledger_is "$base" ''; [ "$(cat "$base/workspace/sentinel")" = sentinel ] || die "$prefix workspace sentinel changed"; [ ! -e "$base/workspace/recovery.dump" ] && [ ! -e "$base/workspace/recovery.provenance.json" ] || die "$prefix nonempty workspace left final artifact"
  make_case "$kind" "$prefix-preexisting-dump"; base="$root/$prefix-preexisting-dump"; printf sentinel >"$base/workspace/recovery.dump"
  if run_adapter "$kind" "$base"; then die "$prefix pre-existing dump accepted"; fi; ledger_is "$base" ''; [ "$(cat "$base/workspace/recovery.dump")" = sentinel ] || die "$prefix sentinel changed"; [ ! -e "$base/workspace/recovery.provenance.json" ] || die "$prefix sentinel wrote provenance"
}

downstream_failures() {
  kind=$1 prefix=$2
  make_case "$kind" "$prefix-head-mismatch"; base="$root/$prefix-head-mismatch"; jq '.Metadata["source-kind"]="wrong-source"' "$base/store/metadata/recovery/2026/package.tar.gz.json" >"$base/changed"; /bin/mv "$base/changed" "$base/store/metadata/recovery/2026/package.tar.gz.json"
  if run_adapter "$kind" "$base"; then die "$prefix head mismatch accepted"; fi
  ledger_is "$base" head; no_artifacts "$base"
  make_case "$kind" "$prefix-get-failure"; base="$root/$prefix-get-failure"; rm -f "$base/store/objects/recovery/2026/package.tar.gz"
  if run_adapter "$kind" "$base"; then die "$prefix get failure accepted"; fi; ledger_is "$base" 'head get'; no_artifacts "$base"
  make_case "$kind" "$prefix-ciphertext-mismatch"; base="$root/$prefix-ciphertext-mismatch"; printf x >>"$base/store/objects/recovery/2026/package.tar.gz"
  if run_adapter "$kind" "$base"; then die "$prefix ciphertext mismatch accepted"; fi; ledger_is "$base" 'head get'; no_artifacts "$base"
  make_case "$kind" "$prefix-unreadable-archive"; base="$root/$prefix-unreadable-archive"; printf 'not an archive' >"$base/package.tar.gz"; refresh_selected_object "$base"
  if run_adapter "$kind" "$base"; then die "$prefix unreadable package accepted"; fi; ledger_is "$base" 'head get package-manifest archive'; no_artifacts "$base"
  make_case "$kind" "$prefix-extra-archive-member"; base="$root/$prefix-extra-archive-member"; printf x >"$base/extra"; refresh_package "$base" 'manifest.sha256 recovery.dump.enc extra'
  if run_adapter "$kind" "$base"; then die "$prefix extra archive member accepted"; fi; ledger_is "$base" 'head get package-manifest archive'; no_artifacts "$base"
  make_case "$kind" "$prefix-member-manifest-mismatch"; base="$root/$prefix-member-manifest-mismatch"; printf '%064d  recovery.dump.enc\n' 0 >"$base/manifest.sha256"; refresh_package "$base"
  if run_adapter "$kind" "$base"; then die "$prefix member checksum mismatch accepted"; fi; ledger_is "$base" 'head get package-manifest archive archive archive'; no_artifacts "$base"
  make_case "$kind" "$prefix-decrypt-failure"; base="$root/$prefix-decrypt-failure"; case_extra_env=KEEPLING_TEST_CIPHER_FAIL=1
  if run_adapter "$kind" "$base"; then die "$prefix decrypt failure accepted"; fi; unset case_extra_env; ledger_is "$base" 'head get package-manifest archive archive archive decrypt cipher'; no_artifacts "$base"
  make_case "$kind" "$prefix-plaintext-mismatch"; base="$root/$prefix-plaintext-mismatch"; jq '.plaintext_sha256="0000000000000000000000000000000000000000000000000000000000000000"' "$base/input/selection.json" >"$base/changed"; /bin/mv "$base/changed" "$base/input/selection.json"
  if run_adapter "$kind" "$base"; then die "$prefix plaintext mismatch accepted"; fi; ledger_is "$base" 'head get package-manifest archive archive archive decrypt cipher'; no_artifacts "$base"
  make_case "$kind" "$prefix-provenance-publish-failure"; base="$root/$prefix-provenance-publish-failure"; case_extra_env=KEEPLING_TEST_PROVENANCE_PUBLISH_FAIL=1
  if run_adapter "$kind" "$base"; then die "$prefix provenance publication failure accepted"; fi; unset case_extra_env; ledger_is "$base" 'head get package-manifest archive archive archive decrypt cipher publish publish'; no_artifacts "$base"
}

make_fakes
case "${1:-}" in
  --case) [ "${2:-}" = b2-success ] || die 'usage: test-recovery-source-adapters.sh [--case b2-success]'; success b2-primary b2-success;;
  '')
    success b2-primary b2-success; success r2-mirror r2-success
    # Every refusal is source-local and stops before the next fake boundary.
    basic_refusals b2-primary b2 r2-mirror; selection_refusals b2-primary b2; workspace_refusals b2-primary b2; downstream_failures b2-primary b2
    basic_refusals r2-mirror r2 b2-primary; selection_refusals r2-mirror r2; workspace_refusals r2-mirror r2; downstream_failures r2-mirror r2
    ;;
  *) die 'usage: test-recovery-source-adapters.sh [--case b2-success]';;
esac
echo "Recovery source adapter fixtures passed"
