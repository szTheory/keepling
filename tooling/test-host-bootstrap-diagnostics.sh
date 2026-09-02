#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Host bootstrap diagnostics regression failed: $*" >&2; exit 1; }
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-bootstrap-diagnostics.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

jq -n '{status:"error",extended_status:"error - running",errors:[],recoverable_errors:{},
  "init-local":{errors:["datasource timed out SENSITIVE_DETAIL","metadata unavailable PRIVATE_IDENTIFIER"],recoverable_errors:{}},
  init:{errors:["network DNS no route network unreachable PRIVATE_IDENTIFIER"],recoverable_errors:{}},
  "modules-config":{errors:["package update apt failure","package install dpkg connection refused"],recoverable_errors:{}},
  "modules-final":{errors:["scripts-user runcmd command exit permission denied"],recoverable_errors:{}}}' >"$fixture_root/status.json"
KEEPLING_DIAGNOSTIC_TEST_MODE=yes KEEPLING_DIAGNOSTIC_TEST_INPUT="$fixture_root/status.json" \
KEEPLING_DIAGNOSTIC_TEST_DATASOURCE=hetzner KEEPLING_DIAGNOSTIC_TEST_METADATA_REACHABLE=false \
KEEPLING_DIAGNOSTIC_TEST_NETWORK_ONLINE=false KEEPLING_DIAGNOSTIC_TEST_DNS=false KEEPLING_DIAGNOSTIC_TEST_DEFAULT_ROUTE=false \
KEEPLING_DIAGNOSTIC_TEST_UNIT_LOCAL=failed KEEPLING_DIAGNOSTIC_TEST_UNIT_NETWORK=failed \
KEEPLING_DIAGNOSTIC_TEST_UNIT_CONFIG=inactive KEEPLING_DIAGNOSTIC_TEST_UNIT_FINAL=inactive \
  ./tooling/check-host-bootstrap-diagnostics.sh >"$fixture_root/classified.json"
jq -e '
  .datasource == {type:"hetzner",result:"error",metadata_reachable:false} and
  .network == {online:false,dns:false,default_route:false} and
  .units.init_local == "failed" and .units.init_network == "failed" and
  ([.events[].module] | index("metadata") and index("datasource") and index("network-connectivity") and index("package-update") and index("package-install") and index("scripts-user")) and
  ([.events[].exception] | index("timeout") and index("connection") and index("package-manager") and index("permission")) and
  ([.events[].errno] | index("timed-out") and index("network-unreachable") and index("connection-refused") and index("permission-denied")) and
  .outcomes.package_install == "failed" and .outcomes.scripts_user == "failed" and .outcomes.runcmd == "not-run"
' "$fixture_root/classified.json" >/dev/null || die "closed classifications are incomplete"
if grep -Eq 'SENSITIVE_DETAIL|PRIVATE_IDENTIFIER|no route|apt connection' "$fixture_root/classified.json"; then die "raw diagnostics were retained"; fi

jq -n '{status:"error",extended_status:"error - done",errors:[],recoverable_errors:{},
  "modules-final":{errors:[range(0;24)|"UNTRUSTED_ARBITRARY_VALUE"],recoverable_errors:{}}}' >"$fixture_root/many.json"
KEEPLING_DIAGNOSTIC_TEST_MODE=yes KEEPLING_DIAGNOSTIC_TEST_INPUT="$fixture_root/many.json" \
  ./tooling/check-host-bootstrap-diagnostics.sh >"$fixture_root/bounded.json"
jq -e '(.events|length)==16 and .events_truncated==true and ([.events[]|.module,.exception,.errno]|all(.=="unknown"))' \
  "$fixture_root/bounded.json" >/dev/null || die "unknown event bounds are invalid"
[ "$(wc -c <"$fixture_root/bounded.json" | tr -d ' ')" -le 4096 ] || die "diagnostic output is unbounded"
grep -Fq UNTRUSTED_ARBITRARY_VALUE "$fixture_root/bounded.json" && die "untrusted error text was retained"

printf '{malformed\n' >"$fixture_root/malformed.json"
KEEPLING_DIAGNOSTIC_TEST_MODE=yes KEEPLING_DIAGNOSTIC_TEST_INPUT="$fixture_root/malformed.json" \
  ./tooling/check-host-bootstrap-diagnostics.sh >"$fixture_root/malformed-output.json"
jq -e '.datasource.result=="unknown" and .events==[] and .events_truncated==false' "$fixture_root/malformed-output.json" >/dev/null ||
  die "malformed status did not normalize safely"

echo "Host bootstrap diagnostics regression passed: closed classifications are bounded and raw-free"
