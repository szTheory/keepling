#!/usr/bin/env sh
set -eu
umask 077

usage() {
  printf '%s\n' 'usage: approve-phase-2-host-trust.sh --validate-inputs | --dispatch --parent-run-id ID --parent-run-attempt 1 --logical-run-digest SHA256 --challenge-nonce HEX32 --owner-actor ACTOR --deadline EPOCH' >&2
  exit 2
}
refuse() {
  reason=$1
  case "$reason" in *[!a-z0-9-]*|'') reason=invalid-input;; esac
  printf 'host-trust status=NON_PASSING reason=%s\n' "$reason" >&2
  exit 1
}

mode=${1:-}
[ "$mode" = --validate-inputs ] || [ "$mode" = --dispatch ] || usage
shift
parent= attempt= digest= nonce= actor= deadline=
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --parent-run-id) [ -z "$parent" ] || usage; parent=$2 ;;
    --parent-run-attempt) [ -z "$attempt" ] || usage; attempt=$2 ;;
    --logical-run-digest) [ -z "$digest" ] || usage; digest=$2 ;;
    --challenge-nonce) [ -z "$nonce" ] || usage; nonce=$2 ;;
    --owner-actor) [ -z "$actor" ] || usage; actor=$2 ;;
    --deadline) [ -z "$deadline" ] || usage; deadline=$2 ;;
    *) usage ;;
  esac
  shift 2
done

printf '%s' "$parent" | grep -Eq '^[1-9][0-9]{0,15}$' || refuse parent-run-invalid
[ "$attempt" = 1 ] || refuse parent-attempt-invalid
printf '%s' "$digest" | grep -Eq '^[0-9a-f]{64}$' || refuse logical-digest-invalid
printf '%s' "$nonce" | grep -Eq '^[0-9a-f]{32}$' || refuse challenge-nonce-invalid
printf '%s' "$actor" | grep -Eq '^[A-Za-z0-9-]{1,39}$' || refuse owner-actor-invalid
printf '%s' "$deadline" | grep -Eq '^[0-9]{10}$' || refuse deadline-invalid
now=$(date +%s)
[ "$deadline" -gt "$now" ] && [ "$deadline" -le $((now + 900)) ] || refuse deadline-expired

if [ "$mode" = --validate-inputs ]; then
  [ -n "${KEEPLING_TEST_MARKER_CONFIRMED:-}" ] || refuse marker-confirmation-missing
  [ "${KEEPLING_TEST_MARKER_CONFIRMED}" = true ] || refuse marker-confirmation-declined
  fingerprint=${KEEPLING_TEST_FINGERPRINT:-}
else
  [ "${GITHUB_ACTIONS:-false}" != true ] || refuse hosted-context-forbidden
  printf '%s' 'Confirm the authenticated console marker for this candidate (type CONFIRM): ' >/dev/tty
  IFS= read -r marker_confirmation </dev/tty || refuse marker-confirmation-missing
  [ "$marker_confirmation" = CONFIRM ] || refuse marker-confirmation-declined
  printf '%s' 'Current ED25519 fingerprint (input hidden): ' >/dev/tty
  old_tty=$(stty -g </dev/tty) || refuse terminal-unavailable
  restore_tty() { stty "$old_tty" </dev/tty 2>/dev/null || true; }
  trap restore_tty EXIT HUP INT TERM
  stty -echo </dev/tty || refuse terminal-unavailable
  IFS= read -r fingerprint </dev/tty || refuse fingerprint-unavailable
  restore_tty
  trap - EXIT HUP INT TERM
  printf '\n' >/dev/tty
fi

printf '%s' "$fingerprint" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' || refuse fingerprint-invalid
fingerprint_digest=$(printf '%s' "$fingerprint" | shasum -a 256 | awk '{print $1}') || refuse fingerprint-invalid
unset fingerprint
[ "${#fingerprint_digest}" -eq 64 ] || refuse fingerprint-invalid

if [ "$mode" = --validate-inputs ]; then
  printf '%s\n' 'host-trust status=inputs-valid external-calls=0'
  exit 0
fi

command -v gh >/dev/null 2>&1 || refuse github-cli-unavailable
current_actor=$(gh api user --jq .login 2>/dev/null) || refuse github-actor-unavailable
[ "$current_actor" = "$actor" ] || refuse github-actor-mismatch
if ! gh workflow run phase-2-host-trust-approval.yml --ref main \
  --field "parent_run_id=$parent" \
  --field "parent_run_attempt=$attempt" \
  --field "logical_run_digest=$digest" \
  --field "challenge_nonce=$nonce" \
  --field "owner_actor=$actor" \
  --field marker_confirmed=true \
  --field "fingerprint_sha256=$fingerprint_digest" >/dev/null 2>&1; then
  refuse signal-dispatch-failed
fi
printf '%s\n' 'host-trust status=signal-dispatched'
