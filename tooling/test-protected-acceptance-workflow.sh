#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
workflow=$root/.github/workflows/phase-2-protected-acceptance.yml
[ -f "$workflow" ] || { printf '%s\n' 'not ok - protected acceptance workflow must exist'; exit 1; }
python3 - "$workflow" <<'PY'
import re, sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
checks = {
    "manual workflow_dispatch only": bool(re.search(r"(?m)^on:\s*\n(?:[ \t].*\n)*?[ \t]{2}workflow_dispatch:\s*$", source)) and not re.search(r"(?m)^  (?:push|pull_request|schedule|workflow_run):", source),
    "trusted main ref guard": "github.ref == 'refs/heads/main'" in source,
    "exact protected environment": "name: phase-2-protected-environment" in source,
    "one ephemeral native x64 runner": source.count("runs-on: ubuntu-24.04") == 1 and "strategy:" not in source,
    "least read-only workflow permissions": bool(re.search(r"(?ms)^permissions:\n  actions: read\n  contents: read\n", source)) and "actions: write" not in source and "contents: write" not in source,
    "immutable checkout action pin": bool(re.search(r"uses: actions/checkout@[0-9a-f]{40}", source)),
    "no cache or binary/private upload": "actions/cache@" not in source and not re.search(r"(?m)^\s+path:.*(?:\.tar|archive|runner\.temp/keepling-phase-2)", source),
    "authorization input is digest-bound": "authorization-json" in source and "authorization-sha256" in source,
    "single same-job runner invocation": source.count("tooling/run-phase-2-protected-acceptance.sh") == 1,
    "sanitized status upload after runner": source.find("tooling/run-phase-2-protected-acceptance.sh") < source.find("actions/upload-artifact@") and "phase-2-protected-status.json" in source,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("ok" if ok else "not ok") + " - " + name)
if failed:
    raise SystemExit(1)
print(f"# {len(checks)} protected-workflow contract checks passed")
PY
