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

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Provider ownership regression failed: $*" >&2; exit 1; }

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-provider-ownership.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
run_id=ownership-proof

write_counts() {
  jq -n '{servers:1,volumes:1,primary_ips:1,networks:1,firewalls:1,ssh_keys:1}' >"$1"
}
write_input() {
  jq -n --arg run_id "$run_id" '{
    id:"101",name:"replacement-host",ipv4_address:"192.0.2.40",primary_ip_id:102,
    network_id:"103",volume_id:"104",firewall_id:"105",ssh_key_id:"106",
    labels:{"managed-by":"opentofu","keepling-run":$run_id,purpose:"host-replacement"}
  }' >"$1"
}
expect_pass() {
  name=$1 input=$2 counts=$3
  output="$fixture_root/$name-output.json"
  ./tooling/verify-host-replacement.sh --normalize-provider-output "$input" "$counts" "$output" "$run_id" >/dev/null
  [ "$(portable_stat '%Lp' "$output" 2>/dev/null || stat -c '%a' "$output")" = 600 ] || die "$name output is not owner-only"
  jq -e '.version==1 and (.resources|length)==6 and ([.resources[]] | all(type=="string" and test("^[1-9][0-9]*$")))' "$output" >/dev/null || die "$name normalization is invalid"
  at_sign=$(printf '\100')
  forbidden_pattern="replacement-host|192[.]0[.]2[.]40|${at_sign}|to""ken|/pri""vate/|/Us""ers/"
  if grep -Eq "$forbidden_pattern" "$output"; then die "$name output retained disallowed context"; fi
}
expect_fail() {
  name=$1 input=$2 counts=$3
  output="$fixture_root/$name-output.json"
  if ./tooling/verify-host-replacement.sh --normalize-provider-output "$input" "$counts" "$output" "$run_id" >/dev/null 2>&1; then
    die "$name was accepted"
  fi
  [ ! -e "$output" ] || die "$name wrote an inventory"
}

write_input "$fixture_root/mixed.json"
write_counts "$fixture_root/counts.json"
expect_pass mixed "$fixture_root/mixed.json" "$fixture_root/counts.json"
jq '.primary_ip_id="102"' "$fixture_root/mixed.json" >"$fixture_root/all-string.json"
expect_pass all-string "$fixture_root/all-string.json" "$fixture_root/counts.json"
jq '.id="99999999999999999999999999999999999991" | .primary_ip_id="99999999999999999999999999999999999992" | .network_id="99999999999999999999999999999999999993" | .volume_id="99999999999999999999999999999999999994" | .firewall_id="99999999999999999999999999999999999995" | .ssh_key_id="99999999999999999999999999999999999996"' \
  "$fixture_root/mixed.json" >"$fixture_root/large.json"
expect_pass large-decimals "$fixture_root/large.json" "$fixture_root/counts.json"
jq '.primary_ip_id=.id | .network_id=.id | .volume_id=.id | .firewall_id=.id | .ssh_key_id=.id' \
  "$fixture_root/mixed.json" >"$fixture_root/class-scoped-equal.json"
expect_pass class-scoped-equal "$fixture_root/class-scoped-equal.json" "$fixture_root/counts.json"

for mutation in zero-number zero-string negative fraction leading-zero empty null boolean object array absent wrong-label extra-field; do
  case "$mutation" in
    zero-number) filter='.id=0' ;;
    zero-string) filter='.id="0"' ;;
    negative) filter='.id=-1' ;;
    fraction) filter='.id=1.5' ;;
    leading-zero) filter='.id="001"' ;;
    empty) filter='.id=""' ;;
    null) filter='.id=null' ;;
    boolean) filter='.id=true' ;;
    object) filter='.id={value:"101"}' ;;
    array) filter='.id=["101"]' ;;
    absent) filter='del(.id)' ;;
    wrong-label) filter='.labels.purpose="other"' ;;
    extra-field) filter='.unexpected_id="107"' ;;
  esac
  jq "$filter" "$fixture_root/mixed.json" >"$fixture_root/$mutation.json"
  expect_fail "$mutation" "$fixture_root/$mutation.json" "$fixture_root/counts.json"
done
sed 's/"id": "101"/"id": 1e2/' "$fixture_root/mixed.json" >"$fixture_root/exponent.json"
grep -q '"id": 1e2' "$fixture_root/exponent.json" || die "exponent fixture was not constructed"
expect_fail exponent "$fixture_root/exponent.json" "$fixture_root/counts.json"

for mutation in missing-class extra-class zero-class multiple-class string-class; do
  case "$mutation" in
    missing-class) filter='del(.servers)' ;;
    extra-class) filter='.snapshots=1' ;;
    zero-class) filter='.servers=0' ;;
    multiple-class) filter='.servers=2' ;;
    string-class) filter='.servers="1"' ;;
  esac
  jq "$filter" "$fixture_root/counts.json" >"$fixture_root/$mutation-counts.json"
  expect_fail "$mutation" "$fixture_root/mixed.json" "$fixture_root/$mutation-counts.json"
done

unsafe_output="$repository_root/.unsafe-provider-inventory.json"
rm -f -- "$unsafe_output"
if ./tooling/verify-host-replacement.sh --normalize-provider-output "$fixture_root/mixed.json" "$fixture_root/counts.json" "$unsafe_output" "$run_id" >/dev/null 2>&1; then
  die "in-repository output was accepted"
fi
[ ! -e "$unsafe_output" ] || die "unsafe output was written"

echo "Provider ownership regression passed: exact mixed identifiers normalize losslessly and unsafe identities fail closed"
