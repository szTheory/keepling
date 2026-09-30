#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
workflow=$root/.github/workflows/phase-2-host-trust-approval.yml
approver=$root/tooling/approve-phase-2-host-trust.sh
waiter=$root/tooling/wait-for-phase-2-host-trust.sh
[ -f "$workflow" ] && [ -x "$approver" ] && [ -x "$waiter" ] || { printf '%s\n' 'not ok - host-trust workflow and helpers must exist and be executable'; exit 1; }
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-trust-test.XXXXXX")
chmod 700 "$fixture"
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
ledger=$fixture/external-calls
: >"$ledger"
chmod 600 "$ledger"
now=$(date +%s)
deadline=$((now + 600))
digest=$(printf '%064d' 0 | tr 0 a)
nonce=$(printf '%032d' 0 | tr 0 b)
fingerprint_digest=$(printf '%064d' 0 | tr 0 c)
fingerprint='SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'

python3 - "$fixture/signal.json" "$now" "$digest" "$nonce" "$fingerprint_digest" <<'PY'
import json, sys
path, now, digest, nonce, fingerprint = sys.argv[1:]
value={"version":1,"parent_run_id":777,"parent_run_attempt":1,"logical_run_digest":digest,"challenge_nonce":nonce,"owner_actor":"jon","marker_confirmed":True,"fingerprint_sha256":fingerprint,"issued_at":int(now),"expires_at":int(now)+900}
with open(path,"w",encoding="utf-8") as output:
 json.dump(value,output,sort_keys=True,separators=(",",":")); output.write("\n")
PY
chmod 600 "$fixture/signal.json"

run_wait() {
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    PHASE2_PARENT_RUN_ID=777 PHASE2_PARENT_RUN_ATTEMPT=1 PHASE2_LOGICAL_RUN_DIGEST="$digest" \
    PHASE2_CHALLENGE_NONCE="$nonce" PHASE2_OWNER_ACTOR=jon \
    PHASE2_CURRENT_FINGERPRINT_SHA256="$fingerprint_digest" PHASE2_TRUST_DEADLINE="$deadline" \
    KEEPLING_TEST_EXTERNAL_CALL_LEDGER="$ledger" sh "$waiter" "$@"
}

run_wait --verify-signal "$fixture/signal.json" >"$fixture/out" 2>"$fixture/err" || { cat "$fixture/out" "$fixture/err" >&2; exit 1; }
grep -Fqx 'host-trust status=verified signal=single-use' "$fixture/out" || { cat "$fixture/out" >&2; exit 1; }
printf '%s\n' 'ok - exact fresh owner signal validates without API calls'

mutate_and_refuse() {
  label=$1 expression=$2
  python3 - "$fixture/signal.json" "$fixture/mutated.json" "$expression" <<'PY'
import json,sys
source,target,expression=sys.argv[1:]
value=json.load(open(source))
field,raw=expression.split("=",1)
if field == "parent_run_id": value[field]=int(raw)
elif field in ("parent_run_attempt","issued_at","expires_at"): value[field]=int(raw)
elif field == "marker_confirmed": value[field]=(raw=="true")
else: value[field]=raw
json.dump(value,open(target,"w"),sort_keys=True,separators=(",",":"))
PY
  chmod 600 "$fixture/mutated.json"
  if run_wait --verify-signal "$fixture/mutated.json" >"$fixture/out" 2>"$fixture/err"; then
    printf 'not ok - %s must be refused\n' "$label"; exit 1
  fi
  grep -Eq '^host-trust status=NON_PASSING reason=[a-z0-9-]+$' "$fixture/err" || { cat "$fixture/err" >&2; exit 1; }
  printf 'ok - %s refused\n' "$label"
}

mutate_and_refuse 'wrong parent run' 'parent_run_id=778'
mutate_and_refuse 'wrong parent attempt' 'parent_run_attempt=2'
mutate_and_refuse 'wrong logical digest' "logical_run_digest=$(printf '%064d' 0 | tr 0 d)"
mutate_and_refuse 'wrong challenge nonce' "challenge_nonce=$(printf '%032d' 0 | tr 0 e)"
mutate_and_refuse 'wrong original owner' 'owner_actor=other'
mutate_and_refuse 'declined marker confirmation' 'marker_confirmed=false'
mutate_and_refuse 'wrong current fingerprint digest' "fingerprint_sha256=$(printf '%064d' 0 | tr 0 f)"
mutate_and_refuse 'expired signal' "issued_at=$((now - 1000))"

python3 - "$fixture/signal.json" "$fixture/signal-set.json" <<'PY'
import json,sys
signal=json.load(open(sys.argv[1]))
json.dump({"signals":[signal,signal]},open(sys.argv[2],"w"),sort_keys=True,separators=(",",":"))
PY
chmod 600 "$fixture/signal-set.json"
if run_wait --verify-signal-set "$fixture/signal-set.json" >"$fixture/out" 2>"$fixture/err"; then
  printf '%s\n' 'not ok - replayed signal set must be refused'; exit 1
fi
grep -Fq 'reason=signal-replay-or-ambiguous' "$fixture/err" || { cat "$fixture/err" >&2; exit 1; }
printf '%s\n' 'ok - replayed signal set refused'

env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  KEEPLING_TEST_MARKER_CONFIRMED=true KEEPLING_TEST_FINGERPRINT="$fingerprint" \
  sh "$approver" --validate-inputs \
  --parent-run-id 777 --parent-run-attempt 1 --logical-run-digest "$digest" \
  --challenge-nonce "$nonce" --owner-actor jon --deadline "$deadline" >"$fixture/out" 2>"$fixture/err" || { cat "$fixture/out" "$fixture/err" >&2; exit 1; }
grep -Fqx 'host-trust status=inputs-valid external-calls=0' "$fixture/out" || exit 1
if grep -Fq "$fingerprint" "$fixture/out" "$fixture/err"; then printf '%s\n' 'not ok - raw fingerprint appeared in helper output'; exit 1; fi
[ ! -s "$ledger" ] || { printf '%s\n' 'not ok - hermetic trust tests called an external adapter'; exit 1; }

python3 - "$workflow" "$approver" "$waiter" <<'PY'
import re,sys
from pathlib import Path
workflow,approver,waiter=map(Path,sys.argv[1:])
w=workflow.read_text(); a=approver.read_text(); v=waiter.read_text()
checks={
 "manual trusted-main signal workflow": "workflow_dispatch:" in w and "if: github.ref == 'refs/heads/main'" in w and not re.search(r"(?m)^  (?:push|pull_request|schedule|workflow_run):",w),
 "no provider credential references": not any(name in w for name in ("HCLOUD_TOKEN","CLOUDFLARE_API_TOKEN","BACKUP_PRIMARY","TOFU_STATE")),
 "only sanitized fingerprint digest is accepted": "fingerprint_sha256" in w and "raw_fingerprint" not in w and "INPUT_FINGERPRINT:" not in w,
 "single sanitized signal artifact": "phase-2-host-trust-signal.json" in w and "actions/upload-artifact@" in w and "image.tar" not in w,
 "local helper disables fingerprint echo and hashes locally": "stty -echo" in a and "shasum -a 256" in a and "gh workflow run phase-2-host-trust-approval.yml" in a,
 "waiter is bounded and checks one-time binding": "signal-timeout" in v and "signal-replay-or-ambiguous" in v and "expires_at" in v and "marker_confirmed" in v,
}
for name,ok in checks.items(): print(("ok" if ok else "not ok")+" - "+name)
if not all(checks.values()): raise SystemExit(1)
print(f"# {len(checks)} host-trust contract checks passed")
PY

printf '%s\n' 'host-trust hermetic fixtures passed: exact signal accepted; run/attempt/owner/nonce/marker/key/expiry/replay refused; 0 external calls'
