#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-secret-provision-test.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

fixture_root="$temporary_root/repository"
stub_bin="$temporary_root/bin"
key_file="$temporary_root/keepling-ed25519"
mkdir -p "$fixture_root/tooling" "$stub_bin"
cp "$repository_root/tooling/provision-release-secrets.sh" "$fixture_root/tooling/"
cp "$repository_root/tooling/release-secrets.map" "$fixture_root/tooling/"
cp "$repository_root/tooling/check-phase-2-environment.mjs" "$fixture_root/tooling/"
printf '%s\n' '.env.local' >"$fixture_root/.gitignore"
git -C "$fixture_root" init -q
ssh-keygen -q -t ed25519 -N '' -C 'fixture-only' -f "$key_file"
chmod 600 "$key_file"

cat >"$stub_bin/gh" <<'GH_STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$GH_CALL_LOG"
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then exit 0; fi
if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then printf '%s' 'szTheory/keepling'; exit 0; fi
if [ "${1:-}" = secret ] && [ "${2:-}" = set ]; then
  [ "${3:-}" = KEEPLING_SSH_PRIVATE_KEY ] || exit 81
  case " $* " in *' --body '*) exit 82 ;; esac
  cat >"$GH_SECRET_CAPTURE"
  chmod 600 "$GH_SECRET_CAPTURE"
  exit 0
fi
if [ "${1:-}" = api ]; then
  endpoint=''
  for argument in "$@"; do endpoint=$argument; done
  case "$endpoint" in
    repos/szTheory/keepling)
      printf '%s\n' '{"full_name":"szTheory/keepling"}'
      ;;
    repos/szTheory/keepling/environments/phase-2-protected-environment)
      if [ "${GH_STUB_REVIEWER:-present}" = present ]; then
        reviewer='[{"type":"required_reviewers","reviewers":[{"type":"User","reviewer":{"login":"reviewer"}}]}]'
      else
        reviewer='[]'
      fi
      printf '{"protection_rules":%s,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n' "$reviewer"
      ;;
    repos/szTheory/keepling/environments/phase-2-protected-environment/deployment-branch-policies\?*)
      printf '%s\n' '[{"total_count":1,"branch_policies":[{"type":"branch","name":"main"}]}]'
      ;;
    repos/szTheory/keepling/environments/phase-2-protected-environment/secrets\?*)
      printf '%s\n' '[{"total_count":0,"secrets":[]}]'
      ;;
    repos/szTheory/keepling/branches/main/protection)
      printf '%s\n' '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"strict":true,"contexts":["All required checks passed","Desktop checks passed","iOS simulator checks passed"],"checks":[{"context":"All required checks passed","app_id":15368},{"context":"Desktop checks passed","app_id":15368},{"context":"iOS simulator checks passed","app_id":15368}]},"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
      ;;
    *) echo 'unexpected GitHub API endpoint' >&2; exit 83 ;;
  esac
  exit 0
fi
echo 'unexpected GitHub CLI command' >&2
exit 84
GH_STUB

cat >"$stub_bin/op" <<'OP_STUB'
#!/bin/sh
printf '%s\n' 'unexpected 1Password CLI invocation' >>"$OP_CALL_LOG"
exit 90
OP_STUB
chmod 700 "$stub_bin/gh" "$stub_bin/op"

export PATH="$stub_bin:$PATH"
export GH_CALL_LOG="$temporary_root/gh-calls"
export GH_SECRET_CAPTURE="$temporary_root/uploaded-secret"
export OP_CALL_LOG="$temporary_root/op-calls"

cases=0
fail() { echo "test-provision-release-secrets: $*" >&2; exit 1; }
write_path() { printf 'KEEPLING_SSH_PRIVATE_KEY_FILE=%s\n' "$1" >"$fixture_root/.env.local"; }
check_refused_without_disclosure() {
  local expected=$1 output
  if output=$(cd "$fixture_root" && ./tooling/provision-release-secrets.sh --check-ssh-key 2>&1); then
    fail "invalid key source was accepted ($expected)"
  fi
  printf '%s\n' "$output" | grep -Fq "$expected" || fail "missing fixed refusal reason ($expected)"
  case "$output" in
    *"$temporary_root"*|*'PRIVATE KEY'*) fail 'refusal output disclosed a path or key marker' ;;
  esac
  cases=$((cases + 1))
}

write_path "$key_file"
valid_output=$(cd "$fixture_root" && ./tooling/provision-release-secrets.sh --check-ssh-key 2>&1)
printf '%s\n' "$valid_output" | grep -Fq 'The local SSH key source resolves' || fail 'valid ED25519 key did not resolve'
case "$valid_output" in *"$temporary_root"*|*'PRIVATE KEY'*) fail 'key check disclosed its path or contents' ;; esac
[ ! -e "$GH_CALL_LOG" ] && [ ! -e "$OP_CALL_LOG" ] || fail 'local key check invoked GitHub or 1Password'
cases=$((cases + 1))

printf 'KEEPLING_SSH_PRIVATE_KEY_FILE=%s\n' "$key_file" >>"$fixture_root/.env.local"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'

cp "$key_file" "$fixture_root/private-key"
chmod 600 "$fixture_root/private-key"
write_path "$fixture_root/private-key"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'

write_path "$key_file"
chmod 644 "$key_file"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'
chmod 600 "$key_file"

ln -s "$key_file" "$temporary_root/key-link"
write_path "$temporary_root/key-link"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'

ssh-keygen -q -t ed25519 -N 'fixture-passphrase' -C 'fixture-only-encrypted' -f "$temporary_root/encrypted-key"
chmod 600 "$temporary_root/encrypted-key"
write_path "$temporary_root/encrypted-key"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'

ssh-keygen -q -t rsa -b 2048 -N '' -C 'fixture-only-rsa' -f "$temporary_root/rsa-key"
chmod 600 "$temporary_root/rsa-key"
write_path "$temporary_root/rsa-key"
check_refused_without_disclosure 'local-ssh-key-file-invalid-or-unavailable'

write_path "$key_file"
apply_output=$(cd "$fixture_root" && ./tooling/provision-release-secrets.sh --apply-ssh-key 2>&1)
cmp -s "$key_file" "$GH_SECRET_CAPTURE" || fail 'GitHub did not receive the exact private-key bytes on stdin'
printf '%s\n' "$apply_output" | grep -Fq 'Uploaded the SSH key only; no 1Password value was read.' || fail 'SSH-only upload did not report its scope'
case "$apply_output" in *"$temporary_root"*|*'PRIVATE KEY'*) fail 'SSH-only upload disclosed its path or contents' ;; esac
[ ! -e "$OP_CALL_LOG" ] || fail 'SSH-only upload invoked 1Password'
grep -Fq 'secret set KEEPLING_SSH_PRIVATE_KEY --env phase-2-protected-environment --repo szTheory/keepling' "$GH_CALL_LOG" ||
  fail 'SSH key was not written to the exact protected Environment'
cases=$((cases + 1))

rm -f "$GH_SECRET_CAPTURE"
export GH_STUB_REVIEWER=missing
if output=$(cd "$fixture_root" && ./tooling/provision-release-secrets.sh --apply-ssh-key 2>&1); then
  fail 'SSH key upload continued without a configured reviewer'
fi
case "$output" in *'GitHub protected-Environment policy is not ready'*|*'protected-Environment preflight failed'*) ;;
  *) fail 'missing reviewer did not cause a fixed preflight refusal' ;;
esac
[ ! -e "$GH_SECRET_CAPTURE" ] || fail 'secret was uploaded after a failed policy preflight'
[ ! -e "$OP_CALL_LOG" ] || fail 'failed protected upload invoked 1Password'
cases=$((cases + 1))

printf 'provision-release-secrets regression checks passed: cases=%s\n' "$cases"
