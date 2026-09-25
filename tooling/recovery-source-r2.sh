#!/usr/bin/env sh
set -eu
umask 077
repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
. "$repository_root/tooling/recovery-source-common.sh"
die() { recovery_die "$1"; }
[ "${1:-}" = fetch ] && [ "$#" -eq 2 ] || die "usage: $0 fetch PRIVATE_WORKSPACE"
workspace_input=$2
credential=${KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE:-}
selection=${KEEPLING_BACKUP_MIRROR_SELECTION_FILE:-}
recovery_external_file KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE "$credential" "$repository_root"
recovery_external_file KEEPLING_BACKUP_MIRROR_SELECTION_FILE "$selection" "$repository_root"
recovery_validate_credential "$credential"
recovery_validate_selection "$selection" r2-mirror
workspace=$(recovery_workspace "$workspace_input" "$repository_root")
object_key=$(jq -r '.object_key' "$selection")
ciphertext_sha=$(jq -r '.ciphertext_sha256' "$selection")
plaintext_sha=$(jq -r '.plaintext_sha256' "$selection")
bucket=$(jq -r '.bucket' "$credential"); endpoint=$(jq -r '.endpoint' "$credential"); region=$(jq -r '.region' "$credential")
metadata="$workspace/.head.json"; archive="$workspace/.ciphertext.tar.gz"; encrypted="$workspace/.recovery.dump.enc"; plain="$workspace/.recovery.dump.tmp"
cleanup() { status=$?; rm -f -- "$metadata" "$archive" "$encrypted" "$plain" "$workspace/.recovery-manifest" "$workspace/.recovery.provenance.tmp"; exit "$status"; }
trap cleanup EXIT HUP INT TERM
if [ -n "${KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT:-}" ]; then
  root=$KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT
  fixture_boundary() { [ -z "${KEEPLING_BACKUP_FIXTURE_LEDGER:-}" ] || printf '%s\n' "$1" >>"$KEEPLING_BACKUP_FIXTURE_LEDGER"; }
  [ -f "$root/metadata/$object_key.json" ] || die "fixture metadata is missing"
  fixture_boundary head
  cp "$root/metadata/$object_key.json" "$metadata"; printf '%s\n' head >&2
  recovery_validate_head "$metadata" r2-mirror "$ciphertext_sha"
  fixture_boundary get
  [ -f "$root/objects/$object_key" ] || die "fixture object is missing"
  cp "$root/objects/$object_key" "$archive"; printf '%s\n' get >&2
else
  AWS_ACCESS_KEY_ID=$(jq -r '.access_key_id' "$credential") AWS_SECRET_ACCESS_KEY=$(jq -r '.secret_access_key' "$credential") AWS_DEFAULT_REGION=$region \
    aws s3api head-object --bucket "$bucket" --key "$object_key" --endpoint-url "$endpoint" >"$metadata"
  printf '%s\n' head >&2; recovery_validate_head "$metadata" r2-mirror "$ciphertext_sha"
  AWS_ACCESS_KEY_ID=$(jq -r '.access_key_id' "$credential") AWS_SECRET_ACCESS_KEY=$(jq -r '.secret_access_key' "$credential") AWS_DEFAULT_REGION=$region \
    aws s3api get-object --bucket "$bucket" --key "$object_key" --endpoint-url "$endpoint" "$archive" >/dev/null
  printf '%s\n' get >&2
fi
chmod 600 "$archive"
[ "$(recovery_sha256 "$archive")" = "$ciphertext_sha" ] || die "ciphertext checksum mismatch"
printf '%s\n' package-manifest >&2
if [ -n "${KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT:-}" ]; then fixture_boundary package-manifest; fi
recovery_validate_archive "$archive" "$encrypted" "$workspace"
cipher=${KEEPLING_BACKUP_CIPHER_EXECUTABLE:-}
[ -n "$cipher" ] && [ -x "$cipher" ] && [ "${cipher#/}" != "$cipher" ] || die "cipher executable must be absolute and executable"
if [ -n "${KEEPLING_BACKUP_MIRROR_FIXTURE_ROOT:-}" ]; then fixture_boundary decrypt; fi
"$cipher" "${KEEPLING_BACKUP_CIPHER_FILE:-}" "$encrypted" "$plain"
printf '%s\n' decrypt >&2
[ -f "$plain" ] && [ ! -L "$plain" ] || die "decrypt did not create plaintext"
recovery_publish "$workspace" r2-mirror "$ciphertext_sha" "$plaintext_sha" "$(wc -c <"$archive" | tr -d '[:space:]')" "$plain"
trap - EXIT HUP INT TERM
rm -f -- "$metadata" "$archive" "$encrypted" "$workspace/.recovery-manifest"
echo "Recovery source verified: r2-mirror"
