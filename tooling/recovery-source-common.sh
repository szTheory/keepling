#!/usr/bin/env sh
# Local-only recovery package validation.  Adapters decode provider documents and
# perform their read-only boundary calls; this file never selects a provider.
set -eu
umask 077

recovery_die() { echo "Recovery source failed: $1" >&2; exit 1; }
recovery_sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
recovery_mode() { stat -f '%Lp' "$1"; }

recovery_external_file() {
  name=$1 path=$2 repository_root=$3
  [ -n "$path" ] && [ -r "$path" ] && [ ! -L "$path" ] || recovery_die "$name must be a readable non-symlink file"
  directory=$(CDPATH='' cd -P "$(dirname "$path")" 2>/dev/null && pwd) || recovery_die "$name cannot be resolved"
  resolved="$directory/$(basename "$path")"
  case "$resolved" in "$repository_root"|"$repository_root"/*) recovery_die "$name must remain outside the repository";; esac
}

recovery_workspace() {
  workspace=$1 repository_root=$2
  [ -d "$workspace" ] && [ ! -L "$workspace" ] || recovery_die "workspace must be a non-symlink directory"
  directory=$(CDPATH='' cd -P "$workspace" 2>/dev/null && pwd) || recovery_die "workspace cannot be resolved"
  case "$directory" in "$repository_root"|"$repository_root"/*) recovery_die "workspace must remain outside the repository";; esac
  [ "$(recovery_mode "$directory")" = 700 ] || recovery_die "workspace must have mode 0700"
  [ -z "$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit)" ] || recovery_die "workspace must be empty"
  printf '%s\n' "$directory"
}

recovery_validate_selection() {
  selection=$1 source_kind=$2
  jq -e --arg source "$source_kind" '
    (keys | sort) == ["backup_id","ciphertext_sha256","encryption_format","object_key","plaintext_sha256","source_kind","version"] and
    .version == 1 and .source_kind == $source and
    # Object keys become fixture-relative paths after this local check.  Accept
    # only a normalized child path below the closed recovery prefix: no empty,
    # dot, parent, absolute, or alternate-separator components can reach a
    # provider or fixture boundary.
    (.object_key | type == "string" and length <= 249 and
      (split("/")) as $components |
      ($components | length >= 2 and .[0] == "recovery" and
        all(.[]; length > 0 and . != "." and . != ".." and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,240}$")))) and
    (.ciphertext_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.plaintext_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    .encryption_format == "tar-gzip-encrypted-v1" and
    (.backup_id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"))
  ' "$selection" >/dev/null 2>&1 || recovery_die "selection document is invalid"
}

recovery_validate_credential() {
  credential=$1
  jq -e '
    (keys | sort) == ["access_key_id","bucket","endpoint","region","secret_access_key","version"] and
    .version == 1 and (.endpoint, .region, .bucket, .access_key_id, .secret_access_key | type == "string" and length > 0)
  ' "$credential" >/dev/null 2>&1 || recovery_die "credential document is invalid"
}

recovery_validate_head() {
  metadata=$1 source_kind=$2 expected_sha=$3
  jq -e --arg source "$source_kind" --arg sha "$expected_sha" '
    (.Metadata // {}) as $metadata |
    ($metadata["source-kind"] == $source or $metadata.source_kind == $source) and
    ($metadata["ciphertext-sha256"] == $sha or $metadata.ciphertext_sha256 == $sha)
  ' "$metadata" >/dev/null 2>&1 || recovery_die "head metadata is not source-bound"
}

recovery_validate_archive() {
  archive=$1 encrypted=$2 workspace=$3
  members=$(tar -tzf "$archive") || recovery_die "package is not a readable archive"
  [ "$members" = "manifest.sha256
recovery.dump.enc" ] || recovery_die "package members are not closed"
  tar -xOzf "$archive" manifest.sha256 >"$workspace/.recovery-manifest" || recovery_die "package manifest is unreadable"
  tar -xOzf "$archive" recovery.dump.enc >"$encrypted" || recovery_die "encrypted member is unreadable"
  expected=$(awk '$2 == "recovery.dump.enc" {print $1}' "$workspace/.recovery-manifest")
  [ "$(printf '%s\n' "$expected" | wc -l | tr -d ' ')" = 1 ] && [ "${#expected}" -eq 64 ] || recovery_die "package manifest is invalid"
  case "$expected" in *[!0-9a-f]*) recovery_die "package manifest is invalid";; esac
  [ "$(recovery_sha256 "$encrypted")" = "$expected" ] || recovery_die "package member checksum mismatch"
  rm -f -- "$workspace/.recovery-manifest"
}

recovery_publish() {
  workspace=$1 source_kind=$2 ciphertext_sha=$3 plaintext_sha=$4 cipher_bytes=$5 plaintext=$6
  [ "$(recovery_sha256 "$plaintext")" = "$plaintext_sha" ] || recovery_die "plaintext checksum mismatch"
  printf '%s\n' plaintext-verified >&2
  chmod 600 "$plaintext"
  bytes=$(wc -c <"$plaintext" | tr -d '[:space:]')
  jq -n --arg source_kind "$source_kind" --arg ciphertext_sha256 "$ciphertext_sha" --arg plaintext_sha256 "$plaintext_sha" \
    --argjson ciphertext_bytes "$cipher_bytes" --argjson plaintext_bytes "$bytes" \
    '{version:1,source_kind:$source_kind,ciphertext_sha256:$ciphertext_sha256,plaintext_sha256:$plaintext_sha256,ciphertext_bytes:$ciphertext_bytes,plaintext_bytes:$plaintext_bytes,verification:{head:true,get:true,package_manifest:true,decrypt:true,plaintext:true}}' \
    >"$workspace/.recovery.provenance.tmp"
  chmod 600 "$workspace/.recovery.provenance.tmp"
  if ! mv "$plaintext" "$workspace/recovery.dump"; then
    rm -f -- "$workspace/.recovery.provenance.tmp"
    recovery_die "could not publish recovery dump"
  fi
  if ! mv "$workspace/.recovery.provenance.tmp" "$workspace/recovery.provenance.json"; then
    # The two names cannot be published as one filesystem operation.  Roll back
    # the first rename so a failed provenance publication never leaves a dump.
    rm -f -- "$workspace/recovery.dump" "$workspace/.recovery.provenance.tmp"
    recovery_die "could not publish recovery provenance"
  fi
}
