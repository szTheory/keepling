#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-live-toolchain.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
die() { printf '%s\n' "live invocation toolchain regression failed: $*" >&2; exit 1; }

mkdir -p -m 700 "$fixture_root/bin" "$fixture_root/home" "$fixture_root/tmp" \
  "$fixture_root/plugin" "$fixture_root/repo/tooling" "$fixture_root/repo/infra/tofu/hetzner"
cp tooling/verify-host-replacement.sh tooling/phase-2-credentials.sh "$fixture_root/repo/tooling/"
cp infra/tofu/hetzner/versions.tf infra/tofu/hetzner/.terraform.lock.hcl \
  "$fixture_root/repo/infra/tofu/hetzner/"

cat >"$fixture_root/bin/tofu" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'version -json') printf '{"terraform_version":"%s"}\n' "${KEEPLING_FAKE_TOFU_VERSION:-1.12.6}" ;;
  *) printf '%s\n' "unexpected-tofu-call=$*" >>"$KEEPLING_EXTERNAL_CALL_LEDGER"; exit 90 ;;
esac
EOF
chmod 700 "$fixture_root/bin/tofu"
for command_name in curl ssh ssh-keyscan scp; do
  cat >"$fixture_root/bin/$command_name" <<'EOF'
#!/bin/sh
printf '%s\n' "unexpected-external-call=$(basename "$0")" >>"$KEEPLING_EXTERNAL_CALL_LEDGER"
exit 91
EOF
  chmod 700 "$fixture_root/bin/$command_name"
done

plugin_version=$(awk '/source  = "hetznercloud\/hcloud"/{found=1; next} found && /version = "= [0-9.]+"/{gsub(/[^0-9.]/, "", $0); print; exit}' \
  "$fixture_root/repo/infra/tofu/hetzner/versions.tf")
[ -n "$plugin_version" ] || die 'fixture could not read the tracked hcloud constraint'
plugin_name="terraform-provider-hcloud_v${plugin_version}_fixture"
printf '#!/bin/sh\nexit 0\n' >"$fixture_root/plugin/$plugin_name"
chmod 700 "$fixture_root/plugin/$plugin_name"

clean_path="$fixture_root/bin:$PATH"
run_preflight() {
  name=$1 tofu_path=$2 plugin_path=$3 fake_version=$4 expected=$5
  ledger="$fixture_root/$name.external-calls"
  output="$fixture_root/$name.output"
  : >"$ledger"
  chmod 600 "$ledger"
  set +e
  case "$tofu_path:$plugin_path" in
    __UNSET__:__UNSET__)
      env -i PATH="$clean_path" HOME="$fixture_root/home" TMPDIR="$fixture_root/tmp" \
        KEEPLING_EXTERNAL_CALL_LEDGER="$ledger" KEEPLING_FAKE_TOFU_VERSION="$fake_version" \
        "$fixture_root/repo/tooling/verify-host-replacement.sh" --toolchain-preflight >"$output" 2>&1 ;;
    __UNSET__:*)
      env -i PATH="$clean_path" HOME="$fixture_root/home" TMPDIR="$fixture_root/tmp" \
        HCLOUD_PROVIDER_PLUGIN_DIR="$plugin_path" KEEPLING_EXTERNAL_CALL_LEDGER="$ledger" \
        KEEPLING_FAKE_TOFU_VERSION="$fake_version" \
        "$fixture_root/repo/tooling/verify-host-replacement.sh" --toolchain-preflight >"$output" 2>&1 ;;
    *:__UNSET__)
      env -i PATH="$clean_path" HOME="$fixture_root/home" TMPDIR="$fixture_root/tmp" \
        TOFU_BIN="$tofu_path" KEEPLING_EXTERNAL_CALL_LEDGER="$ledger" \
        KEEPLING_FAKE_TOFU_VERSION="$fake_version" \
        "$fixture_root/repo/tooling/verify-host-replacement.sh" --toolchain-preflight >"$output" 2>&1 ;;
    *)
      env -i PATH="$clean_path" HOME="$fixture_root/home" TMPDIR="$fixture_root/tmp" \
        TOFU_BIN="$tofu_path" HCLOUD_PROVIDER_PLUGIN_DIR="$plugin_path" \
        KEEPLING_EXTERNAL_CALL_LEDGER="$ledger" KEEPLING_FAKE_TOFU_VERSION="$fake_version" \
        "$fixture_root/repo/tooling/verify-host-replacement.sh" --toolchain-preflight >"$output" 2>&1 ;;
  esac
  result=$?
  set -e
  if [ "$expected" = pass ]; then
    [ "$result" -eq 0 ] || { cat "$output" >&2; die "$name should pass the local preflight"; }
    grep -F 'pinned OpenTofu' "$output" >/dev/null || die "$name did not report toolchain readiness"
  else
    [ "$result" -ne 0 ] || die "$name should refuse before provider access"
  fi
  [ ! -s "$ledger" ] || { cat "$ledger" >&2; die "$name reached a provider, network, or SSH command"; }
}

run_preflight valid "$fixture_root/bin/tofu" "$fixture_root/plugin" 1.12.6 pass
run_preflight tofu-unset __UNSET__ "$fixture_root/plugin" 1.12.6 refuse
run_preflight tofu-missing "$fixture_root/missing-tofu" "$fixture_root/plugin" 1.12.6 refuse
run_preflight tofu-relative relative/tofu "$fixture_root/plugin" 1.12.6 refuse
ln -s "$fixture_root/bin/tofu" "$fixture_root/bin/tofu-link"
run_preflight tofu-symlink "$fixture_root/bin/tofu-link" "$fixture_root/plugin" 1.12.6 refuse
cp "$fixture_root/bin/tofu" "$fixture_root/bin/tofu-noexec"
chmod 600 "$fixture_root/bin/tofu-noexec"
run_preflight tofu-nonexecutable "$fixture_root/bin/tofu-noexec" "$fixture_root/plugin" 1.12.6 refuse
run_preflight tofu-wrong-version "$fixture_root/bin/tofu" "$fixture_root/plugin" 1.12.5 refuse

run_preflight plugin-unset "$fixture_root/bin/tofu" __UNSET__ 1.12.6 refuse
run_preflight plugin-relative "$fixture_root/bin/tofu" relative/plugins 1.12.6 refuse
run_preflight plugin-missing "$fixture_root/bin/tofu" "$fixture_root/missing-plugin" 1.12.6 refuse
ln -s "$fixture_root/plugin" "$fixture_root/plugin-link"
run_preflight plugin-symlink-directory "$fixture_root/bin/tofu" "$fixture_root/plugin-link" 1.12.6 refuse
mkdir -m 700 "$fixture_root/plugin-wrong-version"
printf '#!/bin/sh\nexit 0\n' >"$fixture_root/plugin-wrong-version/terraform-provider-hcloud_v1.67.0_fixture"
chmod 700 "$fixture_root/plugin-wrong-version/terraform-provider-hcloud_v1.67.0_fixture"
run_preflight plugin-wrong-version "$fixture_root/bin/tofu" "$fixture_root/plugin-wrong-version" 1.12.6 refuse
mkdir -m 700 "$fixture_root/plugin-nonexecutable"
printf '#!/bin/sh\nexit 0\n' >"$fixture_root/plugin-nonexecutable/$plugin_name"
chmod 600 "$fixture_root/plugin-nonexecutable/$plugin_name"
run_preflight plugin-nonexecutable "$fixture_root/bin/tofu" "$fixture_root/plugin-nonexecutable" 1.12.6 refuse
mkdir -m 700 "$fixture_root/plugin-symlink"
ln -s "$fixture_root/plugin/$plugin_name" "$fixture_root/plugin-symlink/$plugin_name"
run_preflight plugin-symlink-binary "$fixture_root/bin/tofu" "$fixture_root/plugin-symlink" 1.12.6 refuse

mkdir -p -m 700 "$fixture_root/repo-mismatch/tooling" "$fixture_root/repo-mismatch/infra/tofu/hetzner"
cp "$fixture_root/repo/tooling/verify-host-replacement.sh" "$fixture_root/repo/tooling/phase-2-credentials.sh" \
  "$fixture_root/repo-mismatch/tooling/"
cp "$fixture_root/repo/infra/tofu/hetzner/versions.tf" "$fixture_root/repo/infra/tofu/hetzner/.terraform.lock.hcl" \
  "$fixture_root/repo-mismatch/infra/tofu/hetzner/"
sed 's/version = "= 1\.68\.0"/version = "= 1.69.0"/' \
  "$fixture_root/repo-mismatch/infra/tofu/hetzner/versions.tf" >"$fixture_root/repo-mismatch/infra/tofu/hetzner/versions.next"
mv "$fixture_root/repo-mismatch/infra/tofu/hetzner/versions.next" "$fixture_root/repo-mismatch/infra/tofu/hetzner/versions.tf"
ledger="$fixture_root/lock-mismatch.external-calls"
: >"$ledger"
chmod 600 "$ledger"
set +e
env -i PATH="$clean_path" HOME="$fixture_root/home" TMPDIR="$fixture_root/tmp" \
  TOFU_BIN="$fixture_root/bin/tofu" HCLOUD_PROVIDER_PLUGIN_DIR="$fixture_root/plugin" \
  KEEPLING_EXTERNAL_CALL_LEDGER="$ledger" KEEPLING_FAKE_TOFU_VERSION=1.12.6 \
  "$fixture_root/repo-mismatch/tooling/verify-host-replacement.sh" --toolchain-preflight \
  >"$fixture_root/lock-mismatch.output" 2>&1
result=$?
set -e
[ "$result" -ne 0 ] || die 'provider lock/constraint disagreement should refuse'
[ ! -s "$ledger" ] || die 'lock mismatch reached an external call'

live_lane=$(sed -n '/^lane_live_host_dns_acceptance() {/,/^}/p' tooling/test-phase-2.sh)
preflight_line=$(printf '%s\n' "$live_lane" | grep -n -- '--toolchain-preflight' | head -n 1 | cut -d: -f1)
attempt_line=$(printf '%s\n' "$live_lane" | grep -n 'LIVE_ACCEPTANCE_STATUS=ATTEMPTED' | head -n 1 | cut -d: -f1)
[ -n "$preflight_line" ] && [ -n "$attempt_line" ] && [ "$preflight_line" -lt "$attempt_line" ] ||
  die 'live lane must run local preflight before reporting ATTEMPTED'
grep -F 'TOFU_BIN' tooling/test-phase-2.sh >/dev/null &&
  grep -F 'HCLOUD_PROVIDER_PLUGIN_DIR' tooling/test-phase-2.sh >/dev/null ||
  die 'live lane inputs must include both pinned toolchain paths'
grep -F './tooling/test-live-invocation-toolchain.sh' tooling/test-phase-2.sh >/dev/null ||
  die 'host-fixture lane must run the sanitized invocation regression'

printf '%s\n' 'Live invocation toolchain regression passed: sanitized path/version refusals and zero external calls'
