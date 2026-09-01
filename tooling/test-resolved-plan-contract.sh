#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Resolved plan contract regression failed: $*" >&2; exit 1; }

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-resolved-plan.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
valid_plan=$fixture_root/valid-plan.json
tfvars=$fixture_root/omitted-default.tfvars.json
printf '{}\n' >"$tfvars"
jq -n '{format_version:"1.2",terraform_version:"1.12.6",variables:{target_architecture:{value:"x86_64"}}}' >"$valid_plan"
jq -e 'has("target_architecture") | not' "$tfvars" >/dev/null || die "default-omission fixture is invalid"

resolved=$fixture_root/resolved.json
./tooling/verify-host-replacement.sh --resolve-plan-architecture "$valid_plan" "$resolved" >/dev/null
[ "$(stat -f '%Lp' "$resolved" 2>/dev/null || stat -c '%a' "$resolved")" = 600 ] || die "resolved output is not owner-only"
[ "$(jq -r '.target_architecture' "$resolved")" = x86_64 ] || die "evaluated default was not preserved"
jq -e 'keys == ["target_architecture","version"] and .version == 1' "$resolved" >/dev/null || die "resolved output is not minimal"

effect_root=$fixture_root/effects
mkdir -p "$effect_root/etc/keepling/secrets" "$effect_root/etc/keepling/recovery" \
  "$effect_root/srv/keepling" "$effect_root/var/lib/keepling" "$effect_root/usr/local/sbin"
printf '%s\n' 'KEEPLING_TESTED_OCI_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'KEEPLING_TARGET_ARCHITECTURE=x86_64' >"$effect_root/etc/keepling/release.env"
printf '%s\n' '{"version":1,"status":"complete"}' >"$effect_root/var/lib/keepling/bootstrap-complete.json"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$effect_root/usr/local/sbin/keepling-bootstrap"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$fixture_root/systemctl"
printf '%s\n' '#!/usr/bin/env sh' 'echo "cloud-init 25.1.4"' >"$fixture_root/cloud-init"
chmod 700 "$effect_root/etc/keepling/secrets" "$effect_root/etc/keepling/recovery" "$effect_root/var/lib/keepling"
chmod 755 "$effect_root/srv/keepling" "$effect_root/usr/local/sbin/keepling-bootstrap" "$fixture_root/systemctl" "$fixture_root/cloud-init"
chmod 600 "$effect_root/var/lib/keepling/bootstrap-complete.json"
chmod 644 "$effect_root/etc/keepling/release.env"
effect_owner=$(stat -f '%Su:%Sg' "$effect_root" 2>/dev/null || stat -c '%U:%G' "$effect_root")
KEEPLING_EXPECTED_OCI_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
KEEPLING_EXPECTED_ARCHITECTURE=$(jq -er '.target_architecture' "$resolved") \
KEEPLING_EFFECT_TEST_MODE=yes KEEPLING_EFFECT_ROOT="$effect_root" \
KEEPLING_EFFECT_SYSTEMCTL_BIN="$fixture_root/systemctl" KEEPLING_EFFECT_CLOUD_INIT_BIN="$fixture_root/cloud-init" \
KEEPLING_EFFECT_EXPECTED_OWNER="$effect_owner" \
  ./tooling/check-host-bootstrap-effects.sh >"$fixture_root/effect-result.json"
jq -e '.release_architecture_matches == true' "$fixture_root/effect-result.json" >/dev/null || die "resolved architecture did not reach the effect gate"

expect_fail() {
  name=$1
  plan=$2
  output=$fixture_root/$name-output.json
  if ./tooling/verify-host-replacement.sh --resolve-plan-architecture "$plan" "$output" >/dev/null 2>&1; then
    die "$name was accepted"
  fi
  [ ! -e "$output" ] || die "$name wrote a resolved contract"
}

for mutation in missing-variable missing-value null boolean number wrong-alias empty array object wrong-version; do
  case "$mutation" in
    missing-variable) filter='del(.variables.target_architecture)' ;;
    missing-value) filter='del(.variables.target_architecture.value)' ;;
    null) filter='.variables.target_architecture.value=null' ;;
    boolean) filter='.variables.target_architecture.value=true' ;;
    number) filter='.variables.target_architecture.value=64' ;;
    wrong-alias) filter='.variables.target_architecture.value="amd64"' ;;
    empty) filter='.variables.target_architecture.value=""' ;;
    array) filter='.variables.target_architecture.value=["x86_64"]' ;;
    object) filter='.variables.target_architecture.value={name:"x86_64"}' ;;
    wrong-version) filter='.terraform_version="1.12.5"' ;;
  esac
  jq "$filter" "$valid_plan" >"$fixture_root/$mutation.json"
  expect_fail "$mutation" "$fixture_root/$mutation.json"
done
printf '{invalid\n' >"$fixture_root/malformed.json"
expect_fail malformed "$fixture_root/malformed.json"

existing=$fixture_root/existing.json
: >"$existing"
if ./tooling/verify-host-replacement.sh --resolve-plan-architecture "$valid_plan" "$existing" >/dev/null 2>&1; then
  die "existing output target was accepted"
fi
unsafe=$repository_root/.unsafe-resolved-plan.json
rm -f -- "$unsafe"
if ./tooling/verify-host-replacement.sh --resolve-plan-architecture "$valid_plan" "$unsafe" >/dev/null 2>&1; then
  die "repository output target was accepted"
fi
[ ! -e "$unsafe" ] || die "unsafe output was written"

echo "Resolved plan contract regression passed: evaluated defaults reach the effect gate and ambiguity fails closed"
