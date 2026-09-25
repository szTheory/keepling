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
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-synthetic-recovery-test.XXXXXX")
chmod 700 "$fixture"
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
die() { echo "Synthetic recovery fixture failed: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

make_capture() {
  directory=$1
  mkdir -m 700 "$directory"
  printf 'synthetic custom-format database archive\n' >"$directory/recovery.dump"
  printf '%064d' 7 >"$directory/rehearsal-login-credential"
  chmod 600 "$directory/recovery.dump" "$directory/rehearsal-login-credential"
  jq -n --arg dump "$(sha "$directory/recovery.dump")" \
    --arg credential "$(sha "$directory/rehearsal-login-credential")" \
    '{version:1,dump_sha256:$dump,rehearsal_login_credential_sha256:$credential,task_id:"00000000-0000-4000-8000-000000000001",source_epoch:"00000000-0000-4000-8000-000000000002",semantic:{login:true,read:true,write:true,undo:true,restored_login:true}}' \
    >"$directory/recovery-manifest.json"
  chmod 600 "$directory/recovery-manifest.json"
}

make_capture "$fixture/source"
mkdir -m 700 "$fixture/handoff"
"$root/tooling/prepare-synthetic-recovery.sh" "$fixture/source" "$fixture/handoff" >"$fixture/result" || die 'valid synthetic capture was refused'
[ "$(cat "$fixture/result")" = 'synthetic-recovery status=verified result=ready' ] || die 'result marker is not closed'
jq -e '(keys|sort)==["dump_file","provenance_file","rehearsal_login_credential_file","source_kind","version"] and .source_kind=="synthetic-rehearsal" and .version==1' "$fixture/handoff/recovery-selection.json" >/dev/null || die 'selection schema is invalid'
jq -e '(keys|sort)==["plaintext_bytes","plaintext_sha256","source_kind","verification","version"] and .source_kind=="synthetic-rehearsal" and .verification=={local_capture:true,local_restore:true,synthetic:true}' "$fixture/handoff/recovery.provenance.json" >/dev/null || die 'synthetic provenance claims are invalid'
[ "$(sha "$fixture/handoff/recovery.dump")" = "$(sha "$fixture/source/recovery.dump")" ] || die 'dump changed in handoff'
[ "$(portable_stat '%Lp' "$fixture/handoff/rehearsal-login-credential")" = 600 ] || die 'login credential is not private'

mkdir -m 700 "$fixture/bad-handoff"
printf x >>"$fixture/source/recovery.dump"
if "$root/tooling/prepare-synthetic-recovery.sh" "$fixture/source" "$fixture/bad-handoff" >/dev/null 2>&1; then die 'modified dump passed manifest validation'; fi
[ -z "$(find "$fixture/bad-handoff" -mindepth 1 -maxdepth 1 -print -quit)" ] || die 'failed validation left a partial handoff'

make_capture "$fixture/extra-source"
printf x >"$fixture/extra-source/unexpected"
chmod 600 "$fixture/extra-source/unexpected"
mkdir -m 700 "$fixture/extra-handoff"
if "$root/tooling/prepare-synthetic-recovery.sh" "$fixture/extra-source" "$fixture/extra-handoff" >/dev/null 2>&1; then die 'extra source member was accepted'; fi

make_capture "$fixture/semantic-source"
mkdir -m 700 "$fixture/bad-semantic-source"
jq '.semantic.undo=false' "$fixture/semantic-source/recovery-manifest.json" >"$fixture/bad-semantic-source/recovery-manifest.json"
cp "$fixture/semantic-source/recovery.dump" "$fixture/bad-semantic-source/"
cp "$fixture/semantic-source/rehearsal-login-credential" "$fixture/bad-semantic-source/"
chmod 600 "$fixture/bad-semantic-source"/*
mkdir -m 700 "$fixture/bad-semantic-handoff"
if "$root/tooling/prepare-synthetic-recovery.sh" "$fixture/bad-semantic-source" "$fixture/bad-semantic-handoff" >/dev/null 2>&1; then die 'unverified semantic restore was accepted'; fi

if "$root/tooling/prepare-synthetic-recovery.sh" "$fixture/source" "$root/tooling" >/dev/null 2>&1; then die 'repository handoff destination was accepted'; fi
printf '%s\n' 'Synthetic recovery fixtures passed: closed private capture, source binding, and semantic proof checks'
