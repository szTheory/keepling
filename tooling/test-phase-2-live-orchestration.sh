#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-live-orchestration.XXXXXX")
fixture=$(CDPATH='' cd -P "$fixture" && pwd)
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
die() { printf '%s\n' "Phase 2 live orchestration regression failed: $*" >&2; exit 1; }
mkdir -m 700 "$fixture/private" "$fixture/external-bin"
export KEEPLING_EXTERNAL_CALL_LEDGER="$fixture/external-calls"
: >"$KEEPLING_EXTERNAL_CALL_LEDGER"
: >"$fixture/stages"
for command_name in curl ssh tofu pgbackrest dig hcloud scp aws; do
  printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\\n" "${0##*/}" >>"$KEEPLING_EXTERNAL_CALL_LEDGER"' 'exit 97' >"$fixture/external-bin/$command_name"
  chmod 700 "$fixture/external-bin/$command_name"
done
PATH="$fixture/external-bin:$PATH"; export PATH
private="$fixture/private"
for f in archive image candidate recovery server-image cidrs login cipher hetzner cloudflare primary mirror state identity known dump provenance; do
  printf 'private-fixture-%s\n' "$f" >"$private/$f"; chmod 600 "$private/$f"
done
digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
write_bundle() {
  target=$1 run_id=$2 workspace=$3
  {
    printf 'RUN_ID=%s\nWORKSPACE=%s\nIMAGE_DIGEST=%s\n' "$run_id" "$workspace" "$digest"
    printf 'DNS_TEST_RECORD_NAME=phase2-%s.example.invalid\n' "$run_id"
    for key in IMAGE_ARCHIVE_FILE IMAGE_CONTRACT_FILE CANDIDATE_SELECTION_FILE RECOVERY_SELECTION_FILE SERVER_IMAGE_SELECTION_FILE ADMIN_SOURCE_CIDRS_FILE LOGIN_CREDENTIAL_FILE BACKUP_CIPHER_FILE HETZNER_CREDENTIAL_FILE CLOUDFLARE_CREDENTIAL_FILE PRIMARY_BACKUP_CREDENTIAL_FILE MIRROR_BACKUP_CREDENTIAL_FILE TOFU_STATE_CREDENTIAL_FILE SSH_PUBLIC_KEY_FILE SSH_KNOWN_HOSTS_FILE RECOVERY_DUMP_FILE RECOVERY_PROVENANCE_FILE; do
      case "$key" in IMAGE_ARCHIVE_FILE) f=archive;; IMAGE_CONTRACT_FILE) f=image;; CANDIDATE_SELECTION_FILE) f=candidate;; RECOVERY_SELECTION_FILE) f=recovery;; SERVER_IMAGE_SELECTION_FILE) f=server-image;; ADMIN_SOURCE_CIDRS_FILE) f=cidrs;; LOGIN_CREDENTIAL_FILE) f=login;; BACKUP_CIPHER_FILE) f=cipher;; HETZNER_CREDENTIAL_FILE) f=hetzner;; CLOUDFLARE_CREDENTIAL_FILE) f=cloudflare;; PRIMARY_BACKUP_CREDENTIAL_FILE) f=primary;; MIRROR_BACKUP_CREDENTIAL_FILE) f=mirror;; TOFU_STATE_CREDENTIAL_FILE) f=state;; SSH_PUBLIC_KEY_FILE) f=identity;; SSH_KNOWN_HOSTS_FILE) f=known;; RECOVERY_DUMP_FILE) f=dump;; *) f=provenance;; esac
      printf '%s=%s/%s\n' "$key" "$private" "$f"
    done
    for stage_name in bootstrap image restore runtime semantic dns teardown; do
      printf '%s_RUNNER=%s/tooling/phase-2-live-runners/%s\n' "$(printf '%s' "$stage_name" | tr '[:lower:]' '[:upper:]')" "$root" "$stage_name"
    done
  } >"$target"
  chmod 600 "$target"
}
armed() {
  KEEPLING_LIVE_ORCHESTRATION_FILE=$1 KEEPLING_ALLOW_BILLABLE_APPLY=yes \
  KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
  KEEPLING_LIVE_CHANGE_TRIGGER=fixture-run KEEPLING_LIVE_STAGE_FIXTURE=yes \
  KEEPLING_STAGE_FIXTURE_LEDGER="$fixture/stages" "$root/tooling/phase-2-live-runners/$2"
}

bundle="$private/orchestration.env" workspace="$private/workspace" run_id=replace-20260922-deadbeef
write_bundle "$bundle" "$run_id" "$workspace"
"$root/tooling/phase-2-live-orchestration.sh" --validate "$bundle" >/dev/null || die 'closed valid bundle rejected'
for stage_name in bootstrap image restore runtime semantic dns teardown; do
  if ! armed "$bundle" "$stage_name" >"$fixture/output" 2>&1; then cat "$fixture/output" >&2; die "$stage_name stage failed in the sealed fixture"; fi
  grep -Fx "stage=$stage_name result=passed" "$fixture/output" >/dev/null || die "$stage_name output was not bounded"
done
printf 'bootstrap %s %s %s\nimage %s %s %s\nrestore %s %s %s\nruntime %s %s %s\nsemantic %s %s %s\ndns %s %s %s\nteardown %s %s %s\n' \
  "$run_id" "$workspace" "$digest" "$run_id" "$workspace" "$digest" "$run_id" "$workspace" "$digest" \
  "$run_id" "$workspace" "$digest" "$run_id" "$workspace" "$digest" "$run_id" "$workspace" "$digest" \
  "$run_id" "$workspace" "$digest" >"$fixture/expected"
cmp -s "$fixture/expected" "$fixture/stages" || die 'stage order, run, workspace, or digest changed'

if armed "$bundle" image >"$fixture/output" 2>&1; then die 'duplicate stage call was accepted'; fi
if armed "$bundle" teardown >"$fixture/output" 2>&1; then die 'duplicate teardown attempt was accepted'; fi

tamper_workspace="$private/tamper-workspace" tamper_bundle="$private/tamper.env"
write_bundle "$tamper_bundle" replace-20260922-tamper "$tamper_workspace"
armed "$tamper_bundle" bootstrap >/dev/null 2>&1 || die 'tamper fixture bootstrap failed'
sed "s#^HETZNER_CREDENTIAL_FILE=.*#HETZNER_CREDENTIAL_FILE=$private/primary#" "$tamper_bundle" >"$private/tamper-replacement.env"
chmod 600 "$private/tamper-replacement.env"
mv "$private/tamper-replacement.env" "$tamper_bundle"
if armed "$tamper_bundle" image >"$fixture/output" 2>&1; then die 'altered sealed bundle was accepted'; fi

for failing in bootstrap image restore runtime semantic dns teardown; do
  case "$failing" in bootstrap) target_index=1;; image) target_index=2;; restore) target_index=3;; runtime) target_index=4;; semantic) target_index=5;; dns) target_index=6;; teardown) target_index=7;; esac
  fail_workspace="$private/failure-$failing" fail_bundle="$private/failure-$failing.env"
  fail_run="replace-20260922-$failing"
  write_bundle "$fail_bundle" "$fail_run" "$fail_workspace"
  : >"$fixture/stages"
  index=1
  for stage_name in bootstrap image restore runtime semantic dns teardown; do
    if [ "$index" -lt "$target_index" ]; then
      armed "$fail_bundle" "$stage_name" >/dev/null 2>&1 || die "setup before $failing failed"
    elif [ "$index" -eq "$target_index" ]; then
      if KEEPLING_LIVE_ORCHESTRATION_FILE="$fail_bundle" KEEPLING_ALLOW_BILLABLE_APPLY=yes \
        KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
        KEEPLING_LIVE_CHANGE_TRIGGER=fixture-run KEEPLING_LIVE_STAGE_FIXTURE=yes \
        KEEPLING_STAGE_FIXTURE_LEDGER="$fixture/stages" KEEPLING_STAGE_FIXTURE_FAIL_AT="$failing" \
        "$root/tooling/phase-2-live-runners/$stage_name" >"$fixture/output" 2>&1; then
        die "$failing injected failure was accepted"
      fi
      [ ! -e "$fail_workspace/.stage-$failing.complete" ] || die "$failing left a success marker"
    else
      if [ "$stage_name" = teardown ]; then
        [ "$failing" != teardown ] || break
        armed "$fail_bundle" teardown >/dev/null 2>&1 || die 'one cleanup attempt did not remain available after a failed stage'
        break
      fi
      if armed "$fail_bundle" "$stage_name" >"$fixture/output" 2>&1; then die "$stage_name passed after $failing failed"; fi
      break
    fi
    index=$((index + 1))
  done
done

sed 's/^IMAGE_DIGEST=.*/IMAGE_DIGEST=mutable/' "$bundle" >"$private/malformed.env"; chmod 600 "$private/malformed.env"
if "$root/tooling/phase-2-live-orchestration.sh" --validate "$private/malformed.env" >/dev/null 2>&1; then die 'mutable digest accepted'; fi
if [ -s "$KEEPLING_EXTERNAL_CALL_LEDGER" ]; then die 'a fixture reached an external command boundary'; fi
if grep -E 'credential|task|\.invalid|/Users/|/tmp/' "$fixture/output" >/dev/null 2>&1; then cat "$fixture/output" >&2; die 'private fixture data escaped into stage output'; fi
printf '%s\n' 'Phase 2 live orchestration fixtures passed: seven run-bound stage actions, failure fences, and external-call ledger remained hermetic'
