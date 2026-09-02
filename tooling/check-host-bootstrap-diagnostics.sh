#!/bin/sh
set -eu

raw_file=
owned_raw=false
cleanup() { [ "$owned_raw" != true ] || rm -f -- "$raw_file"; }
trap cleanup EXIT HUP INT TERM

closed_state() {
  case "$1" in active|inactive|failed|activating|deactivating) printf '%s' "$1" ;; *) printf unknown ;; esac
}

if [ "${KEEPLING_DIAGNOSTIC_TEST_MODE:-}" = yes ]; then
  raw_file=${KEEPLING_DIAGNOSTIC_TEST_INPUT:-}
  [ -r "$raw_file" ] || exit 2
  datasource=${KEEPLING_DIAGNOSTIC_TEST_DATASOURCE:-unknown}
  metadata_reachable=${KEEPLING_DIAGNOSTIC_TEST_METADATA_REACHABLE:-false}
  network_online=${KEEPLING_DIAGNOSTIC_TEST_NETWORK_ONLINE:-false}
  dns=${KEEPLING_DIAGNOSTIC_TEST_DNS:-false}
  default_route=${KEEPLING_DIAGNOSTIC_TEST_DEFAULT_ROUTE:-false}
  unit_local=$(closed_state "${KEEPLING_DIAGNOSTIC_TEST_UNIT_LOCAL:-unknown}")
  unit_network=$(closed_state "${KEEPLING_DIAGNOSTIC_TEST_UNIT_NETWORK:-unknown}")
  unit_config=$(closed_state "${KEEPLING_DIAGNOSTIC_TEST_UNIT_CONFIG:-unknown}")
  unit_final=$(closed_state "${KEEPLING_DIAGNOSTIC_TEST_UNIT_FINAL:-unknown}")
else
  raw_file=$(mktemp "${TMPDIR:-/tmp}/keepling-cloud-init-diagnostic.XXXXXX")
  owned_raw=true
  chmod 600 "$raw_file"
  cloud-init status --format=json >"$raw_file" 2>/dev/null || true
  datasource=$(cloud-id 2>/dev/null || true)
  if cloud-init query ds.meta_data.instance_id >/dev/null 2>&1; then metadata_reachable=true; else metadata_reachable=false; fi
  if systemctl is-active --quiet network-online.target >/dev/null 2>&1; then network_online=true; else network_online=false; fi
  if [ -n "${KEEPLING_DIAGNOSTIC_DNS_PROBE:-}" ] && getent ahosts "$KEEPLING_DIAGNOSTIC_DNS_PROBE" >/dev/null 2>&1; then dns=true; else dns=false; fi
  if ip route show default 2>/dev/null | grep -q .; then default_route=true; else default_route=false; fi
  unit_local=$(closed_state "$(systemctl is-active cloud-init-local.service 2>/dev/null || true)")
  unit_network=$(closed_state "$(systemctl is-active cloud-init-network.service 2>/dev/null || true)")
  unit_config=$(closed_state "$(systemctl is-active cloud-config.service 2>/dev/null || true)")
  unit_final=$(closed_state "$(systemctl is-active cloud-final.service 2>/dev/null || true)")
fi

case "$datasource" in hetzner|nocloud|config-drive|ec2|azure|gce|none) ;; *) datasource=unknown ;; esac
for boolean in "$metadata_reachable" "$network_online" "$dns" "$default_route"; do
  [ "$boolean" = true ] || [ "$boolean" = false ] || exit 2
done

python3 - "$raw_file" "$datasource" "$metadata_reachable" "$network_online" "$dns" "$default_route" \
  "$unit_local" "$unit_network" "$unit_config" "$unit_final" <<'PY'
import json,re,sys
path, datasource, metadata, online, dns, route, unit_local, unit_network, unit_config, unit_final = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        status=json.load(stream)
except (OSError, ValueError):
    status={}

extended=status.get("extended_status")
if extended == "done": result="ready"
elif isinstance(extended,str) and extended.startswith("error"): result="error"
elif extended in ("not started","running","degraded running"): result="not-run"
else: result="unknown"

module_patterns=(
    ("metadata",r"metadata"),("datasource",r"datasource"),("network-connectivity",r"network|connectivity|route|dns"),
    ("systemd",r"systemd|systemctl"),("package-update",r"package.update|apt.update|update package"),
    ("package-install",r"package-update-upgrade-install|package install|apt|dpkg"),("scripts-user",r"scripts-user"),
    ("runcmd",r"runcmd"),("write-files",r"write-files"),
)
exception_patterns=(("timeout",r"timeout|timed out"),("connection",r"connection|unreachable|refused"),("permission",r"permission|denied"),
                    ("package-manager",r"apt|dpkg|package"),("service",r"systemd|systemctl|service"),("command",r"command|exit"),
                    ("validation",r"invalid|validation|schema"))
errno_patterns=(("network-unreachable",r"network.*unreachable|no route"),("connection-refused",r"connection refused"),
                ("timed-out",r"timed out|timeout"),("permission-denied",r"permission denied"),("not-found",r"not found|no such"),
                ("io",r"input.output|i/o error"))
events=[]
for stage in ("init-local","init","modules-config","modules-final"):
    value=status.get(stage)
    errors=value.get("errors",[]) if isinstance(value,dict) else []
    if not isinstance(errors,list): continue
    for raw in errors:
        text=raw if isinstance(raw,str) else ""
        module=next((name for name,pattern in module_patterns if re.search(pattern,text,re.I)),"unknown")
        exception=next((name for name,pattern in exception_patterns if re.search(pattern,text,re.I)),"unknown")
        errno=next((name for name,pattern in errno_patterns if re.search(pattern,text,re.I)),"unknown")
        events.append({"stage":stage,"module":module,"exception":exception,"errno":errno})

modules={event["module"] for event in events}
hard_error=isinstance(extended,str) and extended.startswith("error")
def outcome(module):
    if module in modules: return "failed"
    if extended == "done": return "ok"
    if hard_error: return "not-run"
    return "unknown"

payload={
  "version":1,
  "datasource":{"type":datasource,"result":result,"metadata_reachable":metadata=="true"},
  "network":{"online":online=="true","dns":dns=="true","default_route":route=="true"},
  "units":{"init_local":unit_local,"init_network":unit_network,"config":unit_config,"final":unit_final},
  "events":events[:16],"events_truncated":len(events)>16,
  "outcomes":{"package_update":outcome("package-update"),"package_install":outcome("package-install"),
              "scripts_user":outcome("scripts-user"),"runcmd":outcome("runcmd")},
}
print(json.dumps(payload,separators=(",",":"),sort_keys=True))
PY
