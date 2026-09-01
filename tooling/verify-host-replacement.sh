#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
TOFU_BIN=${TOFU_BIN:-tofu}

die() {
  echo "Host replacement verification failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable"
}

require_credentials() {
  [ -n "${HCLOUD_TOKEN:-}" ] || die "HCLOUD_TOKEN is missing"
  [ -n "${KEEPLING_DNS_ZONE_ID:-}" ] || die "KEEPLING_DNS_ZONE_ID is missing"
  [ -n "${KEEPLING_DNS_RECORD_NAME:-}" ] || die "KEEPLING_DNS_RECORD_NAME is missing"
  require_credential_file() {
    variable=$1
    path=$2
    [ -r "$path" ] || die "$variable is unreadable"
    case "$path" in "$repository_root"|"$repository_root"/*) die "$variable must remain outside the repository" ;; esac
  }
  require_credential_file KEEPLING_SSH_PUBLIC_KEY_FILE "${KEEPLING_SSH_PUBLIC_KEY_FILE:-}"
  require_credential_file KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE "${KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE:-}"
  require_credential_file KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE "${KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE:-}"
  require_credential_file KEEPLING_BACKUP_CIPHER_FILE "${KEEPLING_BACKUP_CIPHER_FILE:-}"
  require_credential_file CLOUDFLARE_API_TOKEN_FILE "${CLOUDFLARE_API_TOKEN_FILE:-}"
}

verify_selection() {
  selection=infra/tofu/hetzner/selection.json
  jq -e '
    .version == 1 and
    .location == "nbg1" and
    (.server_type | test("^(cx|cpx|ccx)[0-9]+$")) and
    .architecture == "x86_64" and
    .data_volume_gb >= 80 and
    .acceptance_limits.maximum_full_host_seconds == 14400 and
    .acceptance_limits.maximum_rpo_seconds == 300 and
    .catalog_cost.estimated_rehearsal_hourly_gross > 0
  ' "$selection" >/dev/null || die "catalog selection contract is invalid"
}

expected_state_addresses() {
  printf '%s\n' \
    hcloud_firewall.replacement \
    hcloud_firewall_attachment.replacement \
    hcloud_network.replacement \
    hcloud_network_subnet.replacement \
    hcloud_primary_ip.replacement \
    hcloud_server.replacement \
    hcloud_server_network.replacement \
    hcloud_ssh_key.replacement \
    hcloud_volume.replacement \
    hcloud_volume_attachment.replacement
}

state_contract_decision() {
  state_list=$1
  provider_counts=$2
  inventory=${3:-}
  expected=$(expected_state_addresses | sort)
  actual=$(sed '/^[[:space:]]*$/d' "$state_list" | sort)
  state_count=$(printf '%s' "$actual" | awk 'NF {count += 1} END {print count + 0}')
  owned_count=$(jq -e '[.servers,.volumes,.primary_ips,.networks,.firewalls,.ssh_keys] | all(type == "number" and . >= 0 and . <= 1)' "$provider_counts" >/dev/null &&
    jq '[.servers,.volumes,.primary_ips,.networks,.firewalls,.ssh_keys] | add' "$provider_counts") ||
    { echo "provider ownership counts are missing or ambiguous" >&2; return 1; }

  if [ "$owned_count" -eq 0 ] && [ "$state_count" -eq 0 ]; then
    echo clean
  elif [ "$expected" = "$actual" ] && [ "$owned_count" -gt 0 ]; then
    echo state-driven-destroy-required
  elif [ "$owned_count" -gt 0 ]; then
    [ -r "$inventory" ] || {
      echo "live owned resources with incomplete state require a private recovery inventory" >&2
      return 1
    }
    jq -e '
      .version == 1 and
      (.run_id | type == "string" and length >= 8) and
      ([.resources.servers,.resources.volumes,.resources.primary_ips,.resources.networks,.resources.firewalls,.resources.ssh_keys] |
        all(.id != null and .labels["keepling-run"] == $run_id))
    ' --arg run_id "$(jq -r '.run_id // empty' "$inventory")" "$inventory" >/dev/null ||
      { echo "private recovery inventory does not prove exact run ownership" >&2; return 1; }
    echo exact-import-recovery-required
  else
    echo state-refresh-required
  fi
}

verify_state_contract() (
  fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-state-contract.XXXXXX")
  trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM
  expected_state_addresses >"$fixture_root/complete"
  : >"$fixture_root/empty"
  jq -n '{servers:1,volumes:1,primary_ips:1,networks:1,firewalls:1,ssh_keys:1}' >"$fixture_root/live"
  jq -n '{servers:2,volumes:1,primary_ips:1,networks:1,firewalls:1,ssh_keys:1}' >"$fixture_root/ambiguous"
  jq -n '{servers:0,volumes:0,primary_ips:0,networks:0,firewalls:0,ssh_keys:0}' >"$fixture_root/absent"
  jq -n --arg run_id replacement-proof '{version:1,run_id:$run_id,resources:{servers:{id:1,labels:{"keepling-run":$run_id}},volumes:{id:2,labels:{"keepling-run":$run_id}},primary_ips:{id:3,labels:{"keepling-run":$run_id}},networks:{id:4,labels:{"keepling-run":$run_id}},firewalls:{id:5,labels:{"keepling-run":$run_id}},ssh_keys:{id:6,labels:{"keepling-run":$run_id}}}}' >"$fixture_root/inventory"

  [ "$(state_contract_decision "$fixture_root/complete" "$fixture_root/live")" = state-driven-destroy-required ] ||
    die "complete durable state did not require state-driven teardown"
  [ "$(state_contract_decision "$fixture_root/empty" "$fixture_root/absent")" = clean ] ||
    die "empty provider and state boundary was not clean"
  [ "$(state_contract_decision "$fixture_root/empty" "$fixture_root/live" "$fixture_root/inventory")" = exact-import-recovery-required ] ||
    die "empty state with live owned resources did not require exact import recovery"
  if state_contract_decision "$fixture_root/empty" "$fixture_root/live" "$fixture_root/missing" >/dev/null 2>&1; then
    die "live resources without a private recovery inventory were accepted"
  fi
  jq '.resources.ssh_keys.labels["keepling-run"] = "another-run"' "$fixture_root/inventory" >"$fixture_root/unowned"
  if state_contract_decision "$fixture_root/empty" "$fixture_root/live" "$fixture_root/unowned" >/dev/null 2>&1; then
    die "ownership-mismatched recovery inventory was accepted"
  fi
  if state_contract_decision "$fixture_root/empty" "$fixture_root/ambiguous" "$fixture_root/inventory" >/dev/null 2>&1; then
    die "ambiguous provider ownership counts were accepted"
  fi
)

run_with_optional_argument() {
  runner=$1
  argument=$2
  if [ -n "$argument" ]; then
    "$runner" "$argument"
  else
    "$runner"
  fi
}

capture_bootstrap_evidence() (
  status_file=$1
  evidence_file=$2
  evidence_directory=$(dirname "$evidence_file")
  [ -d "$evidence_directory" ] || {
    echo "Host replacement verification failed: bootstrap evidence directory is missing" >&2
    exit 1
  }
  case "$evidence_file" in
    "$repository_root"|"$repository_root"/*)
      echo "Host replacement verification failed: bootstrap evidence must remain outside the repository" >&2
      exit 1
      ;;
  esac

  evidence_tmp=$(mktemp "$evidence_directory/.bootstrap-evidence.XXXXXX")
  trap 'rm -f -- "$evidence_tmp"' EXIT HUP INT TERM
  if jq -e 'type == "object"' "$status_file" >/dev/null 2>&1; then
    jq '
      def stages: ["init-local", "init", "modules-config", "modules-final"];
      def error_count($stage):
        if (.[$stage].errors | type) == "array" then (.[$stage].errors | length) else 0 end;
      def recoverable_count($stage):
        if (.[$stage].recoverable_errors | type) == "object"
        then ([.[$stage].recoverable_errors[] | if type == "array" then length else 0 end] | add // 0)
        else 0
        end;
      def closed_status:
        (.extended_status // .status // "unknown") as $status |
        if ["not started", "running", "done", "error", "error - done", "error - running", "degraded done", "degraded running", "disabled"] | index($status)
        then $status
        else "unknown"
        end;
      {
        version: 1,
        bootstrap_status: closed_status,
        failed_stages: [stages[] as $stage | select(error_count($stage) > 0) | $stage],
        failed_modules: ([
          .. | strings |
          scan("package-update-upgrade-install|scripts-user|runcmd|write-files|bootcmd|ssh"; "i") |
          ascii_downcase
        ] | unique),
        error_count: ([stages[] as $stage | error_count($stage)] | add // 0),
        recoverable_error_count: ([stages[] as $stage | recoverable_count($stage)] | add // 0),
        raw_detail_retained: false
      }
    ' "$status_file" >"$evidence_tmp"
  else
    jq -n '{version:1,bootstrap_status:"unknown",failed_stages:[],failed_modules:[],error_count:0,recoverable_error_count:0,raw_detail_retained:false}' >"$evidence_tmp"
  fi
  chmod 600 "$evidence_tmp"
  mv "$evidence_tmp" "$evidence_file"
  evidence_tmp=
)

bootstrap_failure() {
  status_file=$1
  capture_result=0
  teardown_result=0
  capture_bootstrap_evidence "$status_file" "$KEEPLING_BOOTSTRAP_EVIDENCE_FILE" || capture_result=$?
  run_with_optional_argument "$KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER" "${KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT:-}" >/dev/null 2>&1 || teardown_result=$?
  rm -f -- "$status_file"

  [ "$teardown_result" -eq 0 ] || die "candidate teardown failed after bootstrap rejection"
  [ "$capture_result" -eq 0 ] || die "candidate was torn down but bounded bootstrap evidence could not be written"
  return 1
}

verify_bootstrap_gate() {
  status_runner=${KEEPLING_BOOTSTRAP_STATUS_RUNNER:-}
  teardown_runner=${KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER:-}
  evidence_file=${KEEPLING_BOOTSTRAP_EVIDENCE_FILE:-}
  [ -x "$status_runner" ] || die "bootstrap status runner is unavailable"
  [ -x "$teardown_runner" ] || die "bootstrap teardown runner is unavailable"
  [ -n "$evidence_file" ] || die "bootstrap evidence file is missing"

  max_checks=${KEEPLING_BOOTSTRAP_MAX_CHECKS:-60}
  retry_seconds=${KEEPLING_BOOTSTRAP_RETRY_SECONDS:-5}
  case "$max_checks:$retry_seconds" in
    *[!0-9:]*|:*|*:) die "bootstrap retry bounds must be non-negative integers" ;;
  esac
  [ "$max_checks" -gt 0 ] || die "bootstrap max checks must be positive"

  check=0
  while [ "$check" -lt "$max_checks" ]; do
    check=$((check + 1))
    status_file=$(mktemp "${TMPDIR:-/tmp}/keepling-bootstrap-status.XXXXXX")
    status_result=0
    run_with_optional_argument "$status_runner" "${KEEPLING_BOOTSTRAP_STATUS_RUNNER_ARGUMENT:-}" >"$status_file" 2>/dev/null || status_result=$?

    if jq -e 'type == "object"' "$status_file" >/dev/null 2>&1; then
      bootstrap_status=$(jq -r '.extended_status // .status // "unknown"' "$status_file")
    else
      bootstrap_status=unknown
    fi

    case "$bootstrap_status" in
      done)
        rm -f -- "$status_file"
        return 0
        ;;
      error|error\ -*|degraded\ *|disabled|unknown)
        bootstrap_failure "$status_file"
        return 1
        ;;
      running|not\ started)
        if [ "$status_result" -ne 0 ] || [ "$check" -eq "$max_checks" ]; then
          bootstrap_failure "$status_file"
          return 1
        fi
        rm -f -- "$status_file"
        [ "$retry_seconds" -eq 0 ] || sleep "$retry_seconds"
        ;;
      *)
        bootstrap_failure "$status_file"
        return 1
        ;;
    esac
  done
}

dry_run() {
  [ "$($TOFU_BIN version -json | jq -r '.terraform_version')" = "1.12.6" ] ||
    die "OpenTofu 1.12.6 is required"
  "$TOFU_BIN" -chdir=infra/tofu/hetzner fmt -check -recursive
  "$TOFU_BIN" -chdir=infra/tofu/hetzner init -backend=false >/dev/null
  "$TOFU_BIN" -chdir=infra/tofu/hetzner validate >/dev/null
  "$TOFU_BIN" -chdir=infra/tofu/hetzner test >/dev/null
  ./infra/dns/cloudflare.sh self-test >/dev/null
  ./infra/backup/mirror-snapshot.sh self-test >/dev/null
  ./tooling/verify-backup.sh --fixture local >/dev/null
  ./tooling/test-host-bootstrap.sh >/dev/null
  verify_selection
  verify_state_contract
  echo "Host replacement dry-run passed: provider graph, exact DNS identity, append-only mirror, and cost guard are deterministic"
}

credentialed_preflight() {
  require_credentials
  verify_selection
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/keepling-replacement-preflight.XXXXXX")
  trap 'rm -rf -- "$workspace"' EXIT HUP INT TERM
  chmod 700 "$workspace"

  catalog=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    'https://api.hetzner.cloud/v1/server_types?per_page=50')
  selected_type=$(jq -r '.server_type' infra/tofu/hetzner/selection.json)
  printf '%s' "$catalog" | jq -e --arg selected "$selected_type" \
    '[.server_types[] | select(.name == $selected and .architecture == "x86")] | length == 1' >/dev/null ||
    die "selected x86 catalog entry is unavailable"

  resources=$(curl --silent --show-error --fail \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    'https://api.hetzner.cloud/v1/servers?per_page=50')
  printf '%s' "$resources" | jq -e '.servers | length == 0' >/dev/null ||
    die "provider project is not empty; replacement ownership would be ambiguous"

  ./infra/dns/cloudflare.sh capture "$workspace/original-dns.json" >/dev/null
  jq -e '.content == "192.0.2.1" and .proxied == false and .ttl == 300' "$workspace/original-dns.json" >/dev/null ||
    die "safe pending-zone baseline changed"

  echo "Host replacement credentialed preflight passed: authority is readable, provider project is empty, catalog candidate exists, and exact DNS rollback state is capturable"
}

credentialed_apply() {
  require_credentials
  [ "${KEEPLING_ALLOW_BILLABLE_APPLY:-}" = yes ] ||
    die "billable provisioning requires KEEPLING_ALLOW_BILLABLE_APPLY=yes after an explicit checkpoint"
  [ "${KEEPLING_ALLOW_LIVE_DNS_MUTATION:-}" = yes ] ||
    die "DNS mutation requires KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes after an explicit checkpoint"
  jq -e '.status == "benchmark-verified" and .benchmark.projected_restore_seconds <= .acceptance_limits.maximum_full_host_seconds' \
    infra/tofu/hetzner/selection.json >/dev/null ||
    die "billable apply is refused until a disposable candidate records a passing storage/restore benchmark"
  [ -r "${KEEPLING_TOFU_STATE_CREDENTIAL_FILE:-}" ] ||
    die "separately scoped mutable OpenTofu state authority is required"
  die "credentialed apply is intentionally sealed until the billable benchmark checkpoint is approved"
}

for command in curl jq; do require_command "$command"; done
[ -x "$TOFU_BIN" ] || command -v "$TOFU_BIN" >/dev/null 2>&1 || die "OpenTofu command is unavailable"

case "${1:-}" in
  --dry-run) [ "$#" -eq 1 ] || die "usage: $0 --dry-run"; dry_run ;;
  --state-self-test) [ "$#" -eq 1 ] || die "usage: $0 --state-self-test"; verify_state_contract ;;
  --bootstrap-gate) [ "$#" -eq 1 ] || die "usage: $0 --bootstrap-gate"; verify_bootstrap_gate ;;
  --credentialed)
    case "${2:-}" in
      --preflight) [ "$#" -eq 2 ] || die "usage: $0 --credentialed --preflight"; credentialed_preflight ;;
      '') credentialed_apply ;;
      *) die "usage: $0 --credentialed [--preflight]" ;;
    esac
    ;;
  *) die "usage: $0 --dry-run | --state-self-test | --bootstrap-gate | --credentialed [--preflight]" ;;
esac
