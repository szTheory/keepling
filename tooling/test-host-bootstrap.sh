#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() { echo "Host bootstrap regression failed: $*" >&2; exit 1; }

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-bootstrap.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

cat >"$fixture_root/status-runner" <<'EOF'
#!/usr/bin/env sh
set -eu
scenario=$1
count=$(cat "$scenario/status-count")
count=$((count + 1))
printf '%s\n' "$count" >"$scenario/status-count"
last=$(cat "$scenario/status-total")
[ "$count" -le "$last" ] || count=$last
cat "$scenario/status-$count.json"
exit "$(cat "$scenario/status-$count.rc")"
EOF
cat >"$fixture_root/effect-runner" <<'EOF'
#!/usr/bin/env sh
set -eu
scenario=$1
cat "$scenario/effects.json"
exit "$(cat "$scenario/effects.rc")"
EOF
cat >"$fixture_root/teardown" <<'EOF'
#!/usr/bin/env sh
set -eu
count_file=$1
count=$(cat "$count_file")
printf '%s\n' "$((count + 1))" >"$count_file"
EOF
cat >"$fixture_root/dns-mutation" <<'EOF'
#!/usr/bin/env sh
set -eu
: >"$1"
EOF
chmod 700 "$fixture_root/status-runner" "$fixture_root/effect-runner" "$fixture_root/teardown" "$fixture_root/dns-mutation"

write_status() {
  destination=$1 extended=$2 errors=$3 recoverable=$4
  case "$extended" in
    error|error\ -\ running|error\ -\ done) base=error ;;
    degraded\ running) base=running ;;
    'degraded done') base='done' ;;
    *) base=$extended ;;
  esac
  jq -n --arg base "$base" --arg extended "$extended" --argjson errors "$errors" --argjson recoverable "$recoverable" '
    {status:$base,extended_status:$extended,cloud_init_version:"25.1.4",
     errors:(if $errors > 0 then ["SENSITIVE_FIXTURE_VALUE"] else [] end),
     recoverable_errors:(if $recoverable > 0 then {"scripts-user":["PRIVATE_IDENTIFIER_FIXTURE"]} else {} end),
     "init-local":{errors:[],recoverable_errors:{}},init:{errors:[],recoverable_errors:{}},
     "modules-config":{errors:[],recoverable_errors:{}},
     "modules-final":{
       errors:(if $errors > 0 then ["scripts-user package-update-upgrade-install SENSITIVE_FIXTURE_VALUE PRIVATE_IDENTIFIER_FIXTURE"] else [] end),
       recoverable_errors:(if $recoverable > 0 then {"scripts-user":["redacted fixture classification"]} else {} end)}}
  ' >"$destination"
}

new_scenario() {
  scenario=$1
  mkdir "$scenario"
  printf '0\n' >"$scenario/status-count"
  printf '0\n' >"$scenario/teardown-count"
  printf '0\n' >"$scenario/effects.rc"
  jq -n '{version:1,cloud_init_version:"25.1.4",sentinel:true,docker_active:true,required_paths:true,release_digest_matches:true,release_architecture_matches:true}' >"$scenario/effects.json"
}

execute_case() (
  scenario=$1 expected=$2 expected_calls=$3 expected_teardown=$4 max_checks=${5:-3}
  result=0
  KEEPLING_BOOTSTRAP_STATUS_RUNNER="$fixture_root/status-runner" \
    KEEPLING_BOOTSTRAP_STATUS_RUNNER_ARGUMENT="$scenario" \
    KEEPLING_BOOTSTRAP_EFFECT_RUNNER="$fixture_root/effect-runner" \
    KEEPLING_BOOTSTRAP_EFFECT_RUNNER_ARGUMENT="$scenario" \
    KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER="$fixture_root/teardown" \
    KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT="$scenario/teardown-count" \
    KEEPLING_BOOTSTRAP_EVIDENCE_FILE="$scenario/evidence.json" \
    KEEPLING_BOOTSTRAP_MAX_CHECKS="$max_checks" KEEPLING_BOOTSTRAP_RETRY_SECONDS=0 \
    KEEPLING_DNS_MUTATION_RUNNER="$fixture_root/dns-mutation" \
    KEEPLING_DNS_MUTATION_RUNNER_ARGUMENT="$scenario/dns-called" \
    sh ${KEEPLING_TEST_TRACE:+-x} ./tooling/verify-host-replacement.sh --bootstrap-gate >"$scenario/output" 2>&1 || result=$?
  if [ "$expected" = pass ]; then
    if [ "$result" -ne 0 ]; then sed -n '1,100p' "$scenario/output" >&2; die "$(basename "$scenario") unexpectedly failed"; fi
  else [ "$result" -ne 0 ] || die "$(basename "$scenario") unexpectedly passed"; fi
  [ "$(cat "$scenario/status-count")" = "$expected_calls" ] || die "$(basename "$scenario") used the wrong poll count"
  [ "$(cat "$scenario/teardown-count")" = "$expected_teardown" ] || die "$(basename "$scenario") violated exactly-once teardown"
  [ ! -e "$scenario/dns-called" ] || die "$(basename "$scenario") reached DNS from the bootstrap gate"
  [ -r "$scenario/evidence.json" ] || die "$(basename "$scenario") omitted bounded evidence"
  [ "$(stat -f '%Lp' "$scenario/evidence.json")" = 600 ] || die "$(basename "$scenario") evidence is not owner-only"
  [ "$(wc -c <"$scenario/evidence.json" | tr -d ' ')" -le 4096 ] || die "$(basename "$scenario") evidence is unbounded"
  if grep -Eq 'SENSITIVE_FIXTURE_VALUE|PRIVATE_IDENTIFIER_FIXTURE|redacted fixture classification' "$scenario/evidence.json"; then
    die "$(basename "$scenario") retained raw diagnostic detail"
  fi
  jq -e '.version == 2 and (.cloud_init_version | test("^[0-9]+([.][0-9]+){1,3}")) and
    (.status_rc | type) == "number" and (.effect_check_rc | type) == "number" and
    (.effects | type) == "object" and .raw_detail_retained == false' "$scenario/evidence.json" >/dev/null ||
    die "$(basename "$scenario") evidence contract is incomplete"
)

single_case() {
  name=$1 extended=$2 rc=$3 errors=$4 recoverable=$5 expected=$6 teardown=$7
  scenario="$fixture_root/$name"
  new_scenario "$scenario"
  write_status "$scenario/status-1.json" "$extended" "$errors" "$recoverable"
  printf '%s\n' "$rc" >"$scenario/status-1.rc"
  printf '1\n' >"$scenario/status-total"
  execute_case "$scenario" "$expected" 1 "$teardown" 2
}

for extended in error 'error - running' 'error - done'; do
  for rc in 0 1 2; do
    slug=$(printf '%s-%s' "$extended" "$rc" | tr ' ' '-')
    single_case "$slug" "$extended" "$rc" 1 0 fail 1
  done
done
single_case degraded-done 'degraded done' 2 0 1 fail 1
single_case disabled disabled 0 0 0 fail 1
single_case done-nonzero 'done' 1 0 0 fail 1
single_case done-errors 'done' 0 1 0 fail 1
single_case done-recoverable 'done' 0 0 1 fail 1
single_case running-nonzero running 1 0 0 fail 1
single_case not-started-nonzero 'not started' 1 0 0 fail 1
single_case degraded-running-no-errors 'degraded running' 2 0 0 fail 1

for transition in 'not started:0:0' 'running:0:0' 'degraded running:0:1' 'degraded running:2:1'; do
  extended=${transition%%:*}; remainder=${transition#*:}; rc=${remainder%%:*}; recoverable=${remainder##*:}
  slug=$(printf '%s-%s' "$extended" "$rc" | tr ' ' '-')
  scenario="$fixture_root/poll-$slug"
  new_scenario "$scenario"
  write_status "$scenario/status-1.json" "$extended" 0 "$recoverable"
  write_status "$scenario/status-2.json" 'done' 0 0
  printf '%s\n' "$rc" >"$scenario/status-1.rc"; printf '0\n' >"$scenario/status-2.rc"; printf '2\n' >"$scenario/status-total"
  execute_case "$scenario" pass 2 0 3
done

for early in 'not started' running 'degraded running'; do
  scenario="$fixture_root/early-$(printf '%s' "$early" | tr ' ' '-')"; new_scenario "$scenario"
  if [ "$early" = 'degraded running' ]; then early_rc=2; early_recoverable=1; else early_rc=0; early_recoverable=0; fi
  write_status "$scenario/status-1.json" "$early" 0 "$early_recoverable"
  jq 'del(."modules-config", ."modules-final")' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json"
  write_status "$scenario/status-2.json" 'done' 0 0
  printf '%s\n' "$early_rc" >"$scenario/status-1.rc"; printf '0\n' >"$scenario/status-2.rc"; printf '2\n' >"$scenario/status-total"
  execute_case "$scenario" pass 2 0 3
done

scenario="$fixture_root/timeout"; new_scenario "$scenario"; write_status "$scenario/status-1.json" running 0 0
printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"; execute_case "$scenario" fail 2 1 2

for conflict in error-paired-running degraded-paired-done healthy-paired-error; do
  scenario="$fixture_root/$conflict"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'done' 0 0
  case "$conflict" in
    error-paired-running) jq '.status="running" | .extended_status="error - running"' "$scenario/status-1.json" >"$scenario/changed" ;;
    degraded-paired-done) jq '.status="done" | .extended_status="degraded running"' "$scenario/status-1.json" >"$scenario/changed" ;;
    healthy-paired-error) jq '.status="error" | .extended_status="done"' "$scenario/status-1.json" >"$scenario/changed" ;;
  esac
  mv "$scenario/changed" "$scenario/status-1.json"; printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"
  execute_case "$scenario" fail 1 1
done

for malformed in malformed-json missing-status missing-extended missing-stage malformed-errors malformed-error-element malformed-recoverable-element missing-top-errors malformed-top-recoverable unknown; do
  scenario="$fixture_root/$malformed"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'done' 0 0
  case "$malformed" in
    malformed-json) printf '{' >"$scenario/status-1.json" ;;
    missing-status) jq 'del(.status)' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    missing-extended) jq 'del(.extended_status)' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    missing-stage) jq 'del(."modules-final")' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    malformed-errors) jq '."modules-final".errors="invalid"' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    malformed-error-element) jq '."modules-final".errors=[{"invalid":true}]' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    malformed-recoverable-element) jq '."modules-final".recoverable_errors={fixture:[{"invalid":true}]}' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    missing-top-errors) jq 'del(.errors)' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    malformed-top-recoverable) jq '.recoverable_errors="invalid"' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
    unknown) jq '.status="future" | .extended_status="future"' "$scenario/status-1.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/status-1.json" ;;
  esac
  printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"; execute_case "$scenario" fail 1 1
done

for effect_case in malformed-effect nonzero-effect invalid-version; do
  scenario="$fixture_root/$effect_case"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'done' 0 0
  case "$effect_case" in
    malformed-effect) printf '{' >"$scenario/effects.json" ;;
    nonzero-effect) printf '7\n' >"$scenario/effects.rc" ;;
    invalid-version) jq '.cloud_init_version="PRIVATE_IDENTIFIER_FIXTURE"' "$scenario/effects.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/effects.json" ;;
  esac
  printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"; execute_case "$scenario" fail 1 1
done

for effect in sentinel docker_active required_paths release_digest_matches release_architecture_matches; do
  scenario="$fixture_root/effect-$effect"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'done' 0 0
  jq --arg field "$effect" '.[$field]=false' "$scenario/effects.json" >"$scenario/changed" && mv "$scenario/changed" "$scenario/effects.json"
  printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"; execute_case "$scenario" fail 1 1
done

scenario="$fixture_root/success"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'done' 0 0
printf '0\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"; execute_case "$scenario" pass 1 0
jq -e '.bootstrap_status == "done" and .status_rc == 0 and .effect_check_rc == 0 and ([.effects[]] | all)' "$scenario/evidence.json" >/dev/null ||
  die "clean completion did not preserve independent effect proof"

scenario="$fixture_root/unsafe-evidence"; new_scenario "$scenario"; write_status "$scenario/status-1.json" 'error - done' 1 0
printf '1\n' >"$scenario/status-1.rc"; printf '1\n' >"$scenario/status-total"
forbidden_evidence="$repository_root/.forbidden-bootstrap-evidence"; rm -f -- "$forbidden_evidence"; result=0
KEEPLING_BOOTSTRAP_STATUS_RUNNER="$fixture_root/status-runner" KEEPLING_BOOTSTRAP_STATUS_RUNNER_ARGUMENT="$scenario" \
  KEEPLING_BOOTSTRAP_EFFECT_RUNNER="$fixture_root/effect-runner" KEEPLING_BOOTSTRAP_EFFECT_RUNNER_ARGUMENT="$scenario" \
  KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER="$fixture_root/teardown" KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT="$scenario/teardown-count" \
  KEEPLING_BOOTSTRAP_EVIDENCE_FILE="$forbidden_evidence" ./tooling/verify-host-replacement.sh --bootstrap-gate >/dev/null 2>&1 || result=$?
[ "$result" -ne 0 ] || die "unsafe evidence target was accepted"
[ "$(cat "$scenario/teardown-count")" = 1 ] || die "evidence refusal bypassed teardown-first cleanup"
[ ! -e "$forbidden_evidence" ] || die "unsafe in-repository evidence was written"

if CLOUD_INIT_SCHEMA_BIN='' CLOUD_INIT_SCHEMA_VERSION='' ./tooling/verify-host-replacement.sh --cloud-init-preflight >"$fixture_root/schema-output" 2>&1; then
  die "cloud-config preflight accepted an unpinned schema validator"
fi
grep -F 'cloud-init schema validator must be an explicit absolute executable path' "$fixture_root/schema-output" >/dev/null ||
  die "cloud-config preflight did not report its exact validator prerequisite"

effect_tree="$fixture_root/effect-tree"
mkdir -p "$effect_tree/srv/keepling" "$effect_tree/etc/keepling/secrets" "$effect_tree/etc/keepling/recovery" \
  "$effect_tree/var/lib/keepling" "$effect_tree/usr/local/sbin"
chmod 755 "$effect_tree/srv/keepling" "$effect_tree/usr/local/sbin"
chmod 700 "$effect_tree/etc/keepling/secrets" "$effect_tree/etc/keepling/recovery" "$effect_tree/var/lib/keepling"
printf '%s\n' 'KEEPLING_TESTED_OCI_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'KEEPLING_TARGET_ARCHITECTURE=x86_64' >"$effect_tree/etc/keepling/release.env"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$effect_tree/usr/local/sbin/keepling-bootstrap"
printf '%s\n' '{"version":1,"status":"complete"}' >"$effect_tree/var/lib/keepling/bootstrap-complete.json"
chmod 644 "$effect_tree/etc/keepling/release.env"
chmod 755 "$effect_tree/usr/local/sbin/keepling-bootstrap"
chmod 600 "$effect_tree/var/lib/keepling/bootstrap-complete.json"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$fixture_root/systemctl"
printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\n" "cloud-init 25.1.4"' >"$fixture_root/cloud-init"
chmod 700 "$fixture_root/systemctl" "$fixture_root/cloud-init"
effect_owner=$(stat -f '%Su:%Sg' "$effect_tree/var/lib/keepling/bootstrap-complete.json" 2>/dev/null ||
  stat -c '%U:%G' "$effect_tree/var/lib/keepling/bootstrap-complete.json" 2>/dev/null) ||
  die "fixture owner/group could not be derived portably"
KEEPLING_EFFECT_TEST_MODE=yes KEEPLING_EFFECT_ROOT="$effect_tree" KEEPLING_EFFECT_EXPECTED_OWNER="$effect_owner" \
  KEEPLING_EFFECT_SYSTEMCTL_BIN="$fixture_root/systemctl" KEEPLING_EFFECT_CLOUD_INIT_BIN="$fixture_root/cloud-init" \
  KEEPLING_EXPECTED_OCI_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  KEEPLING_EXPECTED_ARCHITECTURE=x86_64 ./tooling/check-host-bootstrap-effects.sh >"$fixture_root/effect-proof.json" ||
  die "independent effect checker rejected a complete exact fixture"
jq -e '.version == 1 and .cloud_init_version == "25.1.4" and ([.sentinel,.docker_active,.required_paths,.release_digest_matches,.release_architecture_matches] | all)' \
  "$fixture_root/effect-proof.json" >/dev/null || die "independent effect checker omitted required booleans"
rm -f -- "$effect_tree/var/lib/keepling/bootstrap-complete.json"
effect_result=0
KEEPLING_EFFECT_TEST_MODE=yes KEEPLING_EFFECT_ROOT="$effect_tree" KEEPLING_EFFECT_EXPECTED_OWNER="$effect_owner" \
  KEEPLING_EFFECT_SYSTEMCTL_BIN="$fixture_root/systemctl" KEEPLING_EFFECT_CLOUD_INIT_BIN="$fixture_root/cloud-init" \
  KEEPLING_EXPECTED_OCI_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  KEEPLING_EXPECTED_ARCHITECTURE=x86_64 ./tooling/check-host-bootstrap-effects.sh >"$fixture_root/effect-missing.json" || effect_result=$?
if [ "$effect_result" -eq 0 ] || ! jq -e '.sentinel == false' "$fixture_root/effect-missing.json" >/dev/null; then
  die "independent effect checker accepted a missing sentinel"
fi

docker_line=$(grep -n 'systemctl enable --now docker.service' infra/tofu/hetzner/cloud-init.yml | cut -d: -f1)
active_line=$(grep -n 'systemctl is-active --quiet docker.service' infra/tofu/hetzner/cloud-init.yml | cut -d: -f1)
sentinel_line=$(grep -n 'mv -f.*bootstrap-complete.json' infra/tofu/hetzner/cloud-init.yml | cut -d: -f1)
[ "$docker_line" -lt "$active_line" ] && [ "$active_line" -lt "$sentinel_line" ] || die "sentinel is not ordered after Docker verification"
if ! grep -F 'root:root:755' infra/tofu/hetzner/cloud-init.yml >/dev/null ||
  ! grep -F 'root:root:700' infra/tofu/hetzner/cloud-init.yml >/dev/null ||
  ! grep -F 'chmod 0600' infra/tofu/hetzner/cloud-init.yml >/dev/null; then
  die "cloud-config does not enforce exact effect modes"
fi

mkdir "$fixture_root/bundle-sources" "$fixture_root/bundle"
printf image >"$fixture_root/bundle-sources/image"; printf dump >"$fixture_root/bundle-sources/dump"
printf credential >"$fixture_root/bundle-sources/credential"; printf compose >"$fixture_root/bundle-sources/compose"
printf caddy >"$fixture_root/bundle-sources/caddy"; printf override >"$fixture_root/bundle-sources/override"
printf '#!/bin/sh' >"$fixture_root/bundle-sources/runner"
KEEPLING_BUNDLE_IMAGE_SOURCE="$fixture_root/bundle-sources/image" KEEPLING_BUNDLE_RECOVERY_SOURCE="$fixture_root/bundle-sources/dump" \
  KEEPLING_BUNDLE_LOGIN_CREDENTIAL_SOURCE="$fixture_root/bundle-sources/credential" KEEPLING_BUNDLE_COMPOSE_SOURCE="$fixture_root/bundle-sources/compose" \
  KEEPLING_BUNDLE_CADDY_SOURCE="$fixture_root/bundle-sources/caddy" KEEPLING_BUNDLE_OVERRIDE_SOURCE="$fixture_root/bundle-sources/override" \
  KEEPLING_BUNDLE_RUNNER_SOURCE="$fixture_root/bundle-sources/runner" KEEPLING_BUNDLE_DESTINATION="$fixture_root/bundle" \
  KEEPLING_BUNDLE_MANIFEST_FILE="$fixture_root/bundle-manifest.json" ./tooling/verify-host-replacement.sh --stage-bundle >/dev/null
find "$fixture_root/bundle" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort >"$fixture_root/bundle-actual"
printf '%s\n' Caddyfile compose-override.yml compose.yml image.tar.gz new-login-credential recovery.dump remote-prepare.sh >"$fixture_root/bundle-expected"
cmp -s "$fixture_root/bundle-expected" "$fixture_root/bundle-actual" || die "bundle basenames are not canonical"
[ "$(stat -f '%Lp' "$fixture_root/bundle/new-login-credential")" = 600 ] || die "bundle exposed credential"
[ "$(stat -f '%Lp' "$fixture_root/bundle/remote-prepare.sh")" = 700 ] || die "bundle runner mode is wrong"
jq -e '.version == 1 and .complete == true and (.files | length) == 7 and ([.files[].sha256] | all(test("^[0-9a-f]{64}$")))' "$fixture_root/bundle-manifest.json" >/dev/null || die "bundle manifest is incomplete"
if grep -Fq "$fixture_root" "$fixture_root/bundle-manifest.json"; then die "bundle manifest retained private paths"; fi

echo "Host bootstrap regression passed: cloud-init and Keepling effects are independently fail-closed, redacted, DNS-safe, and teardown-first"
