#!/usr/bin/env sh
# Validate a disposable local deploy-verification capture and make a private
# run handoff. This is deliberately distinct from B2/R2 recovery provenance.
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
die() { printf '%s\n' "synthetic recovery refused: $1" >&2; exit 2; }
mode_of() { portable_stat '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
outside_repo() { case "$1" in "$repository_root"|"$repository_root"/*) return 1;; *) return 0;; esac; }
private_directory() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  resolved=$(CDPATH='' cd -P "$1" 2>/dev/null && pwd) || return 1
  outside_repo "$resolved" || return 1
  [ "$(mode_of "$resolved")" = 700 ]
}
private_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(mode_of "$1")" = 600 ] || return 1
  parent=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  outside_repo "$parent/$(basename "$1")"
}
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

[ "$#" -eq 2 ] || die 'usage: tooling/prepare-synthetic-recovery.sh SOURCE_DIRECTORY EMPTY_HANDOFF_DIRECTORY'
source_dir=$1
handoff=$2
private_directory "$source_dir" || die 'source directory must be private and external'
private_directory "$handoff" || die 'handoff directory must be private and external'
[ -z "$(find "$handoff" -mindepth 1 -maxdepth 1 -print -quit)" ] || die 'handoff directory must be empty'

inventory=$(find "$source_dir" -mindepth 1 -maxdepth 1 -print | sed "s#^$source_dir/##" | sort)
expected_inventory=$(printf '%s\n' recovery-manifest.json recovery.dump rehearsal-login-credential | sort)
[ "$inventory" = "$expected_inventory" ] || die 'source inventory is not the closed synthetic capture'
dump=$source_dir/recovery.dump
credential=$source_dir/rehearsal-login-credential
manifest=$source_dir/recovery-manifest.json
private_file "$dump" && private_file "$credential" && private_file "$manifest" || die 'source files must be private regular files'

jq -e '
  (keys|sort)==["dump_sha256","rehearsal_login_credential_sha256","semantic","source_epoch","task_id","version"] and
  .version==1 and (.dump_sha256|test("^[0-9a-f]{64}$")) and
  (.rehearsal_login_credential_sha256|test("^[0-9a-f]{64}$")) and
  (.task_id|test("^[0-9a-fA-F-]{36}$")) and
  (.source_epoch|type=="string" and length>0 and length<=128) and
  (.semantic|type=="object" and .login==true and .read==true and .write==true and .undo==true and .restored_login==true)
' "$manifest" >/dev/null 2>&1 || die 'local verifier manifest is invalid'

expected_dump=$(jq -r .dump_sha256 "$manifest")
expected_credential=$(jq -r .rehearsal_login_credential_sha256 "$manifest")
[ "$(sha256 "$dump")" = "$expected_dump" ] || die 'synthetic dump checksum does not match local verifier evidence'
[ "$(sha256 "$credential")" = "$expected_credential" ] || die 'synthetic login credential does not match local verifier evidence'
[ "$(wc -c <"$dump" | tr -d '[:space:]')" -gt 0 ] || die 'synthetic dump is empty'
[ "$(wc -c <"$credential" | tr -d '[:space:]')" -eq 64 ] || die 'synthetic login credential shape is invalid'

install -m 600 "$dump" "$handoff/recovery.dump"
install -m 600 "$credential" "$handoff/rehearsal-login-credential"
dump_bytes=$(wc -c <"$handoff/recovery.dump" | tr -d '[:space:]')
jq -n --arg sha "$expected_dump" --argjson bytes "$dump_bytes" \
  '{version:1,source_kind:"synthetic-rehearsal",plaintext_sha256:$sha,plaintext_bytes:$bytes,verification:{local_capture:true,local_restore:true,synthetic:true}}' \
  >"$handoff/.recovery.provenance.tmp"
chmod 600 "$handoff/.recovery.provenance.tmp"
mv "$handoff/.recovery.provenance.tmp" "$handoff/recovery.provenance.json"
jq -n --arg dump "$handoff/recovery.dump" --arg provenance "$handoff/recovery.provenance.json" \
  --arg login "$handoff/rehearsal-login-credential" \
  '{version:1,source_kind:"synthetic-rehearsal",dump_file:$dump,provenance_file:$provenance,rehearsal_login_credential_file:$login}' \
  >"$handoff/.recovery-selection.tmp"
chmod 600 "$handoff/.recovery-selection.tmp"
mv "$handoff/.recovery-selection.tmp" "$handoff/recovery-selection.json"
[ "$(sha256 "$handoff/recovery.dump")" = "$expected_dump" ] || die 'handoff copy checksum mismatch'
printf '%s\n' 'synthetic-recovery status=verified result=ready'
