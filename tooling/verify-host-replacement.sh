#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
TOFU_BIN=${TOFU_BIN:-}

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

verify_network_graph_contract() {
  graph=infra/tofu/hetzner/main.tf
  server_block=$(awk '
    /^resource "hcloud_server" "replacement" \{/ { capture = 1 }
    capture {
      print
      opened = gsub(/\{/, "{")
      closed = gsub(/\}/, "}")
      depth += opened - closed
      if (depth == 0) exit
    }
  ' "$graph")
  [ -n "$server_block" ] || die "replacement server graph is missing"
  [ "$(grep -Ec '^[[:space:]]*resource "hcloud_server_network"' "$graph")" -eq 0 ] ||
    die "private network attachment must not be a post-boot resource"
  [ "$(printf '%s\n' "$server_block" | grep -Fc 'depends_on = [hcloud_network_subnet.replacement]')" -eq 1 ] ||
    die "server creation must explicitly wait for the declared private subnet"
  [ "$(printf '%s\n' "$server_block" | grep -Ec '^[[:space:]]+network \{')" -eq 1 ] ||
    die "server creation must declare exactly one private network attachment"
  printf '%s\n' "$server_block" | grep -F 'subnet_id = hcloud_network_subnet.replacement.id' >/dev/null ||
    die "server creation must bind the exact declared private subnet"
  printf '%s\n' "$server_block" | grep -F 'alias_ips = []' >/dev/null ||
    die "server private-network aliases must be explicit and empty"
  if grep -Eq 'port[[:space:]]*=[[:space:]]*"5432"' "$graph"; then
    die "PostgreSQL must not be exposed by the provider firewall graph"
  fi
}

expected_state_addresses() {
  printf '%s\n' \
    hcloud_firewall.replacement \
    hcloud_firewall_attachment.replacement \
    hcloud_network.replacement \
    hcloud_network_subnet.replacement \
    hcloud_primary_ip.replacement \
    hcloud_server.replacement \
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
  status_rc=$2
  effect_file=$3
  effect_rc=$4
  diagnostic_file=$5
  diagnostic_rc=$6
  evidence_file=$7
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
  normalized_effect=$(mktemp "$evidence_directory/.bootstrap-effects.XXXXXX")
  normalized_diagnostic=$(mktemp "$evidence_directory/.bootstrap-diagnostics.XXXXXX")
  trap 'rm -f -- "$evidence_tmp" "$normalized_effect" "$normalized_diagnostic"' EXIT HUP INT TERM
  if jq -e 'type == "object"' "$effect_file" >/dev/null 2>&1; then
    jq '{cloud_init_version:(.cloud_init_version // "unknown"),sentinel:(.sentinel // false),docker_active:(.docker_active // false),required_paths:(.required_paths // false),release_digest_matches:(.release_digest_matches // false),release_architecture_matches:(.release_architecture_matches // false)}' "$effect_file" >"$normalized_effect"
  else
    jq -n '{cloud_init_version:"unknown",sentinel:false,docker_active:false,required_paths:false,release_digest_matches:false,release_architecture_matches:false}' >"$normalized_effect"
  fi
  jq -n '{valid:false,datasource:{type:"unknown",result:"unknown",metadata_reachable:false},network:{online:false,dns:false,default_route:false},units:{init_local:"unknown",init_network:"unknown",config:"unknown",final:"unknown"},events:[],events_truncated:false,outcomes:{package_update:"unknown",package_install:"unknown",scripts_user:"unknown",runcmd:"unknown"}}' >"$normalized_diagnostic"
  diagnostic_size=$(wc -c <"$diagnostic_file" | tr -d ' ')
  if [ "$diagnostic_rc" -eq 0 ] && [ "$diagnostic_size" -le 16384 ] && jq -e 'type == "object" and .version == 1' "$diagnostic_file" >/dev/null 2>&1; then
    jq '
      def closed($value;$allowed): if ($value|type)=="string" and ($allowed|index($value)) then $value else "unknown" end;
      def boolean($value): if ($value|type)=="boolean" then $value else false end;
      def member($value;$allowed): ($value|type)=="string" and ($allowed|index($value)) != null;
      . as $root | (if ($root.events|type)=="array" then $root.events else [] end) as $events |
      ((($root.datasource|type)=="object") and member($root.datasource.type;["hetzner","nocloud","config-drive","ec2","azure","gce","none","unknown"]) and member($root.datasource.result;["ready","error","not-run","unknown"]) and (($root.datasource.metadata_reachable|type)=="boolean") and
        (($root.network|type)=="object") and (($root.network.online|type)=="boolean") and (($root.network.dns|type)=="boolean") and (($root.network.default_route|type)=="boolean") and
        (($root.units|type)=="object") and (["init_local","init_network","config","final"] | all(member($root.units[.];["active","inactive","failed","activating","deactivating","unknown"]))) and
        (($root.events|type)=="array") and ($events | all((type=="object") and member(.stage;["init-local","init","modules-config","modules-final","unknown"]) and member(.module;["metadata","datasource","network-connectivity","systemd","package-update","package-install","scripts-user","runcmd","write-files","unknown"]) and member(.exception;["timeout","connection","permission","package-manager","service","command","validation","unknown"]) and member(.errno;["network-unreachable","connection-refused","timed-out","permission-denied","not-found","io","unknown"]))) and
        (($root.events_truncated|type)=="boolean") and (($root.outcomes|type)=="object") and (["package_update","package_install","scripts_user","runcmd"] | all(member($root.outcomes[.];["ok","failed","not-run","unknown"])))) as $schema_valid |
      {valid:$schema_valid,
       datasource:{type:closed($root.datasource.type;["hetzner","nocloud","config-drive","ec2","azure","gce","none","unknown"]),result:closed($root.datasource.result;["ready","error","not-run","unknown"]),metadata_reachable:boolean($root.datasource.metadata_reachable)},
       network:{online:boolean($root.network.online),dns:boolean($root.network.dns),default_route:boolean($root.network.default_route)},
       units:{init_local:closed($root.units.init_local;["active","inactive","failed","activating","deactivating","unknown"]),init_network:closed($root.units.init_network;["active","inactive","failed","activating","deactivating","unknown"]),config:closed($root.units.config;["active","inactive","failed","activating","deactivating","unknown"]),final:closed($root.units.final;["active","inactive","failed","activating","deactivating","unknown"])},
       events:[$events[:16][]? | {stage:closed(.stage;["init-local","init","modules-config","modules-final","unknown"]),module:closed(.module;["metadata","datasource","network-connectivity","systemd","package-update","package-install","scripts-user","runcmd","write-files","unknown"]),exception:closed(.exception;["timeout","connection","permission","package-manager","service","command","validation","unknown"]),errno:closed(.errno;["network-unreachable","connection-refused","timed-out","permission-denied","not-found","io","unknown"])}],
       events_truncated:(($events|length)>16 or $root.events_truncated==true),
       outcomes:{package_update:closed($root.outcomes.package_update;["ok","failed","not-run","unknown"]),package_install:closed($root.outcomes.package_install;["ok","failed","not-run","unknown"]),scripts_user:closed($root.outcomes.scripts_user;["ok","failed","not-run","unknown"]),runcmd:closed($root.outcomes.runcmd;["ok","failed","not-run","unknown"])}}
    ' "$diagnostic_file" >"$normalized_diagnostic"
  fi
  if jq -e 'type == "object"' "$status_file" >/dev/null 2>&1; then
    jq --argjson status_rc "$status_rc" --argjson effect_rc "$effect_rc" --slurpfile effects "$normalized_effect" --slurpfile diagnostics "$normalized_diagnostic" '
      def stages: ["init-local", "init", "modules-config", "modules-final"];
      def error_count($stage):
        if (.[$stage].errors | type) == "array" then (.[$stage].errors | length) else 0 end;
      def recoverable_count($stage):
        if (.[$stage].recoverable_errors | type) == "object"
        then ([.[$stage].recoverable_errors[] | if type == "array" then length else 0 end] | add // 0)
        else 0
        end;
      def closed_status:
        (if (.status | type) == "string" and (.extended_status | type) == "string" and
          ((.status == "not started" and .extended_status == "not started") or
           (.status == "running" and (.extended_status == "running" or .extended_status == "degraded running")) or
           (.status == "done" and (.extended_status == "done" or .extended_status == "degraded done")) or
           (.status == "error" and (.extended_status == "error" or .extended_status == "error - running" or .extended_status == "error - done")) or
           (.status == "disabled" and .extended_status == "disabled"))
         then .extended_status else "unknown" end) as $status |
        if ["not started", "running", "done", "error", "error - done", "error - running", "degraded done", "degraded running", "disabled"] | index($status)
        then $status
        else "unknown"
        end;
      def safe_version:
        ((.cloud_init_version // $effects[0].cloud_init_version // "unknown") | tostring) as $version |
        if ($version | test("^[0-9]+([.][0-9]+){1,3}([+~._-][A-Za-z0-9]+)*$")) then $version else "unknown" end;
      def effect_boolean($name):
        if (($effects[0][$name] // false) | type) == "boolean" then ($effects[0][$name] // false) else false end;
      {
        version: 2,
        cloud_init_version: safe_version,
        bootstrap_status: closed_status,
        status_rc: $status_rc,
        failed_stages: [stages[] as $stage | select(error_count($stage) > 0) | $stage],
        failed_modules: ([
          .. | strings as $text |
          [
            {name:"metadata",pattern:"metadata"},
            {name:"datasource",pattern:"datasource"},
            {name:"network-connectivity",pattern:"network|connectivity"},
            {name:"systemd",pattern:"systemd|systemctl"},
            {name:"package-install",pattern:"package-update-upgrade-install|package install|apt"},
            {name:"scripts-user",pattern:"scripts-user"},
            {name:"runcmd",pattern:"runcmd"},
            {name:"write-files",pattern:"write-files"}
          ][] as $classification |
          select($text | test($classification.pattern; "i")) |
          $classification.name
        ] | unique),
        error_count: ([((.errors | if type == "array" then length else 0 end)), ([stages[] as $stage | error_count($stage)] | add // 0)] | max),
        unknown_error_count: ([stages[] as $stage | .[$stage].errors[]? |
          select((type != "string") or (test("metadata|datasource|network|connectivity|systemd|systemctl|package-update-upgrade-install|package install|apt|scripts-user|runcmd|write-files"; "i") | not))] | length),
        recoverable_error_count: ([((.recoverable_errors | if type == "object" then ([.[] | if type == "array" then length else 0 end] | add // 0) else 0 end)), ([stages[] as $stage | recoverable_count($stage)] | add // 0)] | max),
        effect_check_rc: $effect_rc,
        effects: {
          sentinel: effect_boolean("sentinel"),
          docker_active: effect_boolean("docker_active"),
          required_paths: effect_boolean("required_paths"),
          release_digest_matches: effect_boolean("release_digest_matches"),
          release_architecture_matches: effect_boolean("release_architecture_matches")
        },
        diagnostics: $diagnostics[0],
        raw_detail_retained: false
      }
    ' "$status_file" >"$evidence_tmp"
  else
    jq -n --argjson status_rc "$status_rc" --argjson effect_rc "$effect_rc" --slurpfile effects "$normalized_effect" --slurpfile diagnostics "$normalized_diagnostic" \
      '{version:2,cloud_init_version:(if ($effects[0].cloud_init_version | type) == "string" and ($effects[0].cloud_init_version | test("^[0-9]+([.][0-9]+){1,3}([+~._-][A-Za-z0-9]+)*$")) then $effects[0].cloud_init_version else "unknown" end),bootstrap_status:"unknown",status_rc:$status_rc,failed_stages:[],failed_modules:[],error_count:0,unknown_error_count:0,recoverable_error_count:0,effect_check_rc:$effect_rc,effects:{sentinel:($effects[0].sentinel == true),docker_active:($effects[0].docker_active == true),required_paths:($effects[0].required_paths == true),release_digest_matches:($effects[0].release_digest_matches == true),release_architecture_matches:($effects[0].release_architecture_matches == true)},diagnostics:$diagnostics[0],raw_detail_retained:false}' >"$evidence_tmp"
  fi
  chmod 600 "$evidence_tmp"
  mv "$evidence_tmp" "$evidence_file"
  evidence_tmp=
)

bootstrap_failure() {
  status_file=$1
  status_rc=$2
  capture_result=0
  teardown_result=0
  effect_file=$(mktemp "${TMPDIR:-/tmp}/keepling-bootstrap-effects.XXXXXX")
  effect_result=0
  run_with_optional_argument "$KEEPLING_BOOTSTRAP_EFFECT_RUNNER" "${KEEPLING_BOOTSTRAP_EFFECT_RUNNER_ARGUMENT:-}" >"$effect_file" 2>/dev/null || effect_result=$?
  diagnostic_file=$(mktemp "${TMPDIR:-/tmp}/keepling-bootstrap-diagnostics.XXXXXX")
  diagnostic_result=0
  run_with_optional_argument "$KEEPLING_BOOTSTRAP_DIAGNOSTIC_RUNNER" "${KEEPLING_BOOTSTRAP_DIAGNOSTIC_RUNNER_ARGUMENT:-}" >"$diagnostic_file" 2>/dev/null || diagnostic_result=$?
  capture_bootstrap_evidence "$status_file" "$status_rc" "$effect_file" "$effect_result" "$diagnostic_file" "$diagnostic_result" "$KEEPLING_BOOTSTRAP_EVIDENCE_FILE" || capture_result=$?
  run_with_optional_argument "$KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER" "${KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT:-}" >/dev/null 2>&1 || teardown_result=$?
  rm -f -- "$status_file" "$effect_file" "$diagnostic_file"

  [ "$teardown_result" -eq 0 ] || die "candidate teardown failed after bootstrap rejection"
  [ "$capture_result" -eq 0 ] || die "candidate was torn down but bounded bootstrap evidence could not be written"
  return 1
}

verify_bootstrap_gate() {
  status_runner=${KEEPLING_BOOTSTRAP_STATUS_RUNNER:-}
  effect_runner=${KEEPLING_BOOTSTRAP_EFFECT_RUNNER:-}
  teardown_runner=${KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER:-}
  diagnostic_runner=${KEEPLING_BOOTSTRAP_DIAGNOSTIC_RUNNER:-}
  evidence_file=${KEEPLING_BOOTSTRAP_EVIDENCE_FILE:-}
  [ -x "$status_runner" ] || die "bootstrap status runner is unavailable"
  [ -x "$effect_runner" ] || die "bootstrap effect-check runner is unavailable"
  [ -x "$teardown_runner" ] || die "bootstrap teardown runner is unavailable"
  [ -x "$diagnostic_runner" ] || die "bootstrap diagnostic runner is unavailable"
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

    decision=$(jq -er --argjson rc "$status_result" '
      . as $root |
      def stages: ["init-local", "init", "modules-config", "modules-final"];
      def pair_valid:
        (($root.status == "not started" and $root.extended_status == "not started") or
         ($root.status == "running" and ($root.extended_status == "running" or $root.extended_status == "degraded running")) or
         ($root.status == "done" and ($root.extended_status == "done" or $root.extended_status == "degraded done")) or
         ($root.status == "error" and ($root.extended_status == "error" or $root.extended_status == "error - running" or $root.extended_status == "error - done")) or
         ($root.status == "disabled" and $root.extended_status == "disabled"));
      def stage_valid($stage):
        ($root[$stage] | type) == "object" and
        ($root[$stage].errors | type) == "array" and
        all($root[$stage].errors[]; type == "string") and
        ($root[$stage].recoverable_errors | type) == "object" and
        all($root[$stage].recoverable_errors[]; type == "array" and all(.[]; type == "string"));
      def present_stages_valid:
        [stages[] as $stage | (($root | has($stage) | not) or stage_valid($stage))] | all;
      def all_stages_present:
        [stages[] as $stage | ($root | has($stage))] | all;
      def aggregate_valid:
        ($root.errors | type) == "array" and
        all($root.errors[]; type == "string") and
        ($root.recoverable_errors | type) == "object" and
        all($root.recoverable_errors[]; type == "array" and all(.[]; type == "string"));
      def structurally_valid:
        ($root | type) == "object" and ($root.status | type) == "string" and
        ($root.extended_status | type) == "string" and pair_valid and aggregate_valid and present_stages_valid;
      def errors: ($root.errors | length) + ([stages[] as $stage | $root[$stage].errors[]?] | length);
      def recoverable: ([$root.recoverable_errors[]?[]] | length) + ([stages[] as $stage | $root[$stage].recoverable_errors[]?[]] | length);
      if structurally_valid | not then "reject"
      elif (.extended_status == "error" or .extended_status == "error - running" or .extended_status == "error - done") then "reject"
      elif .extended_status == "done" and all_stages_present and $rc == 0 and errors == 0 and recoverable == 0 then "effects"
      elif .extended_status == "done" then "reject"
      elif (.extended_status == "not started" or .extended_status == "running") and $rc == 0 and errors == 0 and recoverable == 0 then "poll"
      elif .extended_status == "degraded running" and ($rc == 0 or $rc == 2) and errors == 0 and recoverable > 0 then "poll"
      else "reject"
      end
    ' "$status_file" 2>/dev/null || printf '%s' reject)

    case "$decision" in
      effects)
        effect_file=$(mktemp "${TMPDIR:-/tmp}/keepling-bootstrap-effects.XXXXXX")
        effect_result=0
        run_with_optional_argument "$effect_runner" "${KEEPLING_BOOTSTRAP_EFFECT_RUNNER_ARGUMENT:-}" >"$effect_file" 2>/dev/null || effect_result=$?
        if [ "$effect_result" -eq 0 ] && jq -e '
          type == "object" and .version == 1 and
          (.cloud_init_version | type) == "string" and
          (.cloud_init_version | test("^[0-9]+([.][0-9]+){1,3}([+~._-][A-Za-z0-9]+)*$")) and
          .sentinel == true and .docker_active == true and .required_paths == true and
          .release_digest_matches == true and .release_architecture_matches == true
        ' "$effect_file" >/dev/null 2>&1; then
          diagnostic_file=$(mktemp "${TMPDIR:-/tmp}/keepling-bootstrap-diagnostics.XXXXXX")
          diagnostic_result=0
          run_with_optional_argument "$diagnostic_runner" "${KEEPLING_BOOTSTRAP_DIAGNOSTIC_RUNNER_ARGUMENT:-}" >"$diagnostic_file" 2>/dev/null || diagnostic_result=$?
          capture_bootstrap_evidence "$status_file" "$status_result" "$effect_file" "$effect_result" "$diagnostic_file" "$diagnostic_result" "$evidence_file"
          rm -f -- "$status_file" "$effect_file" "$diagnostic_file"
          return 0
        fi
        rm -f -- "$effect_file"
        bootstrap_failure "$status_file" "$status_result"
        return 1
        ;;
      poll)
        if [ "$check" -eq "$max_checks" ]; then
          bootstrap_failure "$status_file" "$status_result"
          return 1
        fi
        rm -f -- "$status_file"
        [ "$retry_seconds" -eq 0 ] || sleep "$retry_seconds"
        ;;
      *)
        bootstrap_failure "$status_file" "$status_result"
        return 1
        ;;
    esac
  done
}

stage_candidate_bundle() {
  destination=${KEEPLING_BUNDLE_DESTINATION:-}
  manifest_file=${KEEPLING_BUNDLE_MANIFEST_FILE:-}
  [ -d "$destination" ] || die "candidate bundle destination is missing"
  [ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
    die "candidate bundle destination must be empty"
  [ -n "$manifest_file" ] && [ ! -e "$manifest_file" ] ||
    die "candidate bundle manifest target must be new"
  case "$destination" in
    "$repository_root"|"$repository_root"/*) die "candidate bundle must remain outside the repository" ;;
  esac
  case "$manifest_file" in
    "$repository_root"|"$repository_root"/*) die "candidate bundle manifest must remain outside the repository" ;;
  esac

  image_source=${KEEPLING_BUNDLE_IMAGE_SOURCE:-}
  recovery_source=${KEEPLING_BUNDLE_RECOVERY_SOURCE:-}
  credential_source=${KEEPLING_BUNDLE_LOGIN_CREDENTIAL_SOURCE:-}
  compose_source=${KEEPLING_BUNDLE_COMPOSE_SOURCE:-}
  caddy_source=${KEEPLING_BUNDLE_CADDY_SOURCE:-}
  override_source=${KEEPLING_BUNDLE_OVERRIDE_SOURCE:-}
  runner_source=${KEEPLING_BUNDLE_RUNNER_SOURCE:-}
  for source_file in \
    "$image_source" "$recovery_source" "$credential_source" \
    "$compose_source" "$caddy_source" "$override_source" "$runner_source"; do
    [ -f "$source_file" ] && [ -r "$source_file" ] || die "candidate bundle source is unreadable"
  done

  umask 077
  install -m 0600 "$image_source" "$destination/image.tar.gz"
  install -m 0600 "$recovery_source" "$destination/recovery.dump"
  install -m 0600 "$credential_source" "$destination/new-login-credential"
  install -m 0600 "$compose_source" "$destination/compose.yml"
  install -m 0600 "$caddy_source" "$destination/Caddyfile"
  install -m 0600 "$override_source" "$destination/compose-override.yml"
  install -m 0700 "$runner_source" "$destination/remote-prepare.sh"

  [ "$(find "$destination" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 7 ] ||
    die "candidate bundle is incomplete"

  manifest_tmp=$(mktemp "$(dirname "$manifest_file")/.candidate-bundle-manifest.XXXXXX")
  trap 'rm -f -- "$manifest_tmp"' EXIT HUP INT TERM
  files_json='[]'
  for name in Caddyfile compose-override.yml compose.yml image.tar.gz new-login-credential recovery.dump remote-prepare.sh; do
    file="$destination/$name"
    sha256=$(shasum -a 256 "$file" | awk '{print $1}')
    mode=$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file")
    size=$(wc -c <"$file" | tr -d ' ')
    files_json=$(printf '%s' "$files_json" | jq \
      --arg name "$name" --arg sha256 "$sha256" --arg mode "$mode" --argjson size "$size" \
      '. + [{name:$name,sha256:$sha256,mode:$mode,size:$size}]')
  done
  printf '%s' "$files_json" | jq '{version:1,complete:(length == 7),files:.}' >"$manifest_tmp"
  chmod 600 "$manifest_tmp"
  mv "$manifest_tmp" "$manifest_file"
  manifest_tmp=
  trap - EXIT HUP INT TERM
  echo "Host replacement bundle passed: exact canonical remote inputs staged privately"
}

normalize_provider_ownership() {
  input_file=$1
  counts_file=$2
  output_file=$3
  expected_run_id=$4
  require_command python3
  [ -r "$input_file" ] && [ -r "$counts_file" ] || die "provider ownership inputs are unreadable"
  [ ! -e "$output_file" ] || die "normalized provider inventory target must be new"
  case "$output_file" in
    "$repository_root"|"$repository_root"/*) die "normalized provider inventory must remain outside the repository" ;;
  esac

  python3 - "$input_file" "$counts_file" "$output_file" "$expected_run_id" <<'PY' ||
import ipaddress
import json
import os
import re
import sys
import tempfile

try:
    input_path, counts_path, output_path, expected_run_id = sys.argv[1:]
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{7,39}", expected_run_id):
        raise ValueError
    if os.path.getsize(input_path) > 65_536 or os.path.getsize(counts_path) > 16_384:
        raise ValueError
    with open(input_path, "r", encoding="utf-8") as stream:
        provider = json.load(stream)
    with open(counts_path, "r", encoding="utf-8") as stream:
        counts = json.load(stream)
    expected_provider_keys = {
        "firewall_id", "id", "ipv4_address", "labels", "name",
        "network_id", "primary_ip_id", "ssh_key_id", "volume_id",
    }
    expected_count_keys = {
        "firewalls", "networks", "primary_ips", "servers", "ssh_keys", "volumes",
    }
    if not isinstance(provider, dict) or set(provider) != expected_provider_keys:
        raise ValueError
    if not isinstance(counts, dict) or set(counts) != expected_count_keys:
        raise ValueError
    if any(type(count) is not int or count != 1 for count in counts.values()):
        raise ValueError
    labels = provider["labels"]
    expected_labels = {
        "managed-by": "opentofu",
        "keepling-run": expected_run_id,
        "purpose": "host-replacement",
    }
    if labels != expected_labels:
        raise ValueError
    if not isinstance(provider["name"], str) or not provider["name"]:
        raise ValueError
    if not isinstance(provider["ipv4_address"], str):
        raise ValueError
    ipaddress.IPv4Address(provider["ipv4_address"])

    def normalize(value):
        if type(value) is int and value > 0:
            return str(value)
        if isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*", value):
            return value
        raise ValueError

    resources = {
        "server_id": normalize(provider["id"]),
        "primary_ip_id": normalize(provider["primary_ip_id"]),
        "network_id": normalize(provider["network_id"]),
        "volume_id": normalize(provider["volume_id"]),
        "firewall_id": normalize(provider["firewall_id"]),
        "ssh_key_id": normalize(provider["ssh_key_id"]),
    }
    inventory = {"version": 1, "resources": resources, "labels": labels}
    directory = os.path.dirname(os.path.abspath(output_path))
    if not os.path.isdir(directory) or os.path.exists(output_path):
        raise ValueError
    descriptor, temporary_path = tempfile.mkstemp(prefix=".provider-inventory.", dir=directory)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            json.dump(inventory, stream, separators=(",", ":"), sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        if os.path.exists(output_path):
            raise ValueError
        os.rename(temporary_path, output_path)
        temporary_path = None
        os.chmod(output_path, 0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_path is not None:
            os.unlink(temporary_path)
except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError):
    print("provider ownership normalization rejected input", file=sys.stderr)
    sys.exit(1)
PY
    die "provider ownership output is incomplete, ambiguous, or unsafe"
}

resolve_plan_architecture() (
  plan_file=$1
  output_file=$2
  [ -r "$plan_file" ] || die "evaluated plan is unreadable"
  [ ! -e "$output_file" ] || die "resolved plan contract target must be new"
  case "$output_file" in
    /*) ;;
    *) die "resolved plan contract target must be an absolute path" ;;
  esac
  case "$output_file" in
    "$repository_root"|"$repository_root"/*) die "resolved plan contract must remain outside the repository" ;;
  esac
  [ "$(wc -c <"$plan_file" | tr -d ' ')" -le 33554432 ] || die "evaluated plan exceeds the bounded contract size"
  output_directory=${output_file%/*}
  [ -d "$output_directory" ] || die "resolved plan contract directory is unavailable"
  temporary=$(mktemp "$output_directory/.resolved-plan-contract.XXXXXX")
  trap 'rm -f -- "$temporary"' EXIT HUP INT TERM
  chmod 600 "$temporary"
  jq -e '
    (.format_version | type == "string") and
    .terraform_version == "1.12.6" and
    (.variables | type == "object") and
    (.variables.target_architecture | type == "object") and
    (.variables.target_architecture.value | type == "string") and
    .variables.target_architecture.value == "x86_64"
  ' "$plan_file" >/dev/null || die "evaluated architecture contract is missing or unsupported"
  jq -c '{version:1,target_architecture:.variables.target_architecture.value}' "$plan_file" >"$temporary"
  mv "$temporary" "$output_file"
  temporary=
  trap - EXIT HUP INT TERM
)

resolve_image_archive_contract() {
  archive_file=$1
  output_file=$2
  require_command python3
  [ -r "$archive_file" ] || die "image archive is unreadable"
  [ ! -e "$output_file" ] || die "image archive contract target must be new"
  case "$output_file" in
    /*) ;;
    *) die "image archive contract target must be an absolute path" ;;
  esac
  case "$output_file" in
    "$repository_root"|"$repository_root"/*) die "image archive contract must remain outside the repository" ;;
  esac

  python3 - "$archive_file" "$output_file" <<'PY' ||
import hashlib
import json
import os
import re
import sys
import tarfile
import tempfile

try:
    archive_path, output_path = sys.argv[1:]
    archive_size = os.path.getsize(archive_path)
    if archive_size <= 0 or archive_size > 8 * 1024 * 1024 * 1024:
        raise ValueError
    archive_hash = hashlib.sha256()
    with open(archive_path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            archive_hash.update(block)
    with tarfile.open(archive_path, "r:*") as archive:
        manifest_member = archive.getmember("manifest.json")
        if not manifest_member.isfile() or manifest_member.size > 65_536:
            raise ValueError
        manifest = json.load(archive.extractfile(manifest_member))
        if not isinstance(manifest, list) or len(manifest) != 1 or not isinstance(manifest[0], dict):
            raise ValueError
        entry = manifest[0]
        required_manifest_keys = {"Config", "RepoTags", "Layers"}
        allowed_manifest_keys = required_manifest_keys | {"LayerSources"}
        if not required_manifest_keys.issubset(entry) or not set(entry).issubset(allowed_manifest_keys):
            raise ValueError
        if "LayerSources" in entry and not isinstance(entry["LayerSources"], dict):
            raise ValueError
        if entry["RepoTags"] != ["keepling-server:plan-02-09-amd64"]:
            raise ValueError
        if not isinstance(entry["Layers"], list) or not entry["Layers"]:
            raise ValueError
        config_name = entry["Config"]
        if not isinstance(config_name, str) or config_name.startswith("/") or ".." in config_name.split("/"):
            raise ValueError
        config_member = archive.getmember(config_name)
        if not config_member.isfile() or config_member.size > 1024 * 1024:
            raise ValueError
        config_bytes = archive.extractfile(config_member).read()
        config = json.loads(config_bytes)
        config_hash = hashlib.sha256(config_bytes).hexdigest()
        config_basename = config_name.rsplit("/", 1)[-1]
        if config_basename.endswith(".json"):
            config_basename = config_basename[:-5]
        if config_basename != config_hash:
            raise ValueError
        labels = config.get("config", {}).get("Labels")
        revision = labels.get("org.opencontainers.image.revision") if isinstance(labels, dict) else None
        if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{7,64}", revision):
            raise ValueError
        if config.get("architecture") != "amd64" or config.get("os") != "linux":
            raise ValueError
        contract = {
            "version": 1,
            "archive_sha256": archive_hash.hexdigest(),
            "image_id": "sha256:" + config_hash,
            "revision": revision,
            "architecture": "amd64",
        }
    directory = os.path.dirname(os.path.abspath(output_path))
    if not os.path.isdir(directory) or os.path.exists(output_path):
        raise ValueError
    descriptor, temporary_path = tempfile.mkstemp(prefix=".image-archive-contract.", dir=directory)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            json.dump(contract, stream, separators=(",", ":"), sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        if os.path.exists(output_path):
            raise ValueError
        os.rename(temporary_path, output_path)
        temporary_path = None
        os.chmod(output_path, 0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_path is not None:
            os.unlink(temporary_path)
except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError, tarfile.TarError):
    print("image archive contract rejected input", file=sys.stderr)
    sys.exit(1)
PY
    die "image archive contract is incomplete or unsafe"
}

verify_candidate_sequence() (
  bootstrap_runner=${KEEPLING_SEQUENCE_BOOTSTRAP_RUNNER:-}
  image_runner=${KEEPLING_SEQUENCE_IMAGE_RUNNER:-}
  restore_runner=${KEEPLING_SEQUENCE_RESTORE_RUNNER:-}
  runtime_runner=${KEEPLING_SEQUENCE_RUNTIME_RUNNER:-}
  semantic_runner=${KEEPLING_SEQUENCE_SEMANTIC_RUNNER:-}
  dns_runner=${KEEPLING_SEQUENCE_DNS_RUNNER:-}
  teardown_runner=${KEEPLING_SEQUENCE_TEARDOWN_RUNNER:-}
  for runner in \
    "$bootstrap_runner" "$image_runner" "$restore_runner" "$runtime_runner" \
    "$semantic_runner" "$dns_runner" "$teardown_runner"; do
    [ -x "$runner" ] || die "candidate sequence runner is unavailable"
  done

  teardown_attempted=false
  teardown_once() {
    if [ "$teardown_attempted" = false ]; then
      teardown_attempted=true
      "$teardown_runner"
    fi
  }
  # Invoked indirectly by the signal/exit trap below.
  # shellcheck disable=SC2329
  cleanup_sequence() {
    result=$?
    trap - EXIT HUP INT TERM
    teardown_once || result=1
    exit "$result"
  }
  trap cleanup_sequence EXIT HUP INT TERM

  "$bootstrap_runner"
  "$image_runner"
  "$restore_runner"
  "$runtime_runner"
  "$semantic_runner"
  # DNS is intentionally unreachable until every candidate proof above passes.
  "$dns_runner"
  teardown_once
  trap - EXIT HUP INT TERM
  echo "Host replacement sequence passed: candidate gates, DNS rehearsal, and teardown completed in order"
)

require_pinned_executable() {
  label=$1
  executable=$2
  case "$executable" in
    /*) [ -x "$executable" ] || die "$label pinned executable is unavailable" ;;
    *) die "$label must be an explicit absolute executable path" ;;
  esac
}

verify_cloud_init_preflight() (
  schema_bin=${CLOUD_INIT_SCHEMA_BIN:-}
  schema_version=${CLOUD_INIT_SCHEMA_VERSION:-}
  require_pinned_executable "cloud-init schema validator" "$schema_bin"
  case "$schema_version" in
    ''|*[!0-9A-Za-z.+~_-]*) die "CLOUD_INIT_SCHEMA_VERSION must pin the schema validator version" ;;
  esac
  reported_version=$($schema_bin --version 2>&1) || die "cloud-init schema validator version check failed"
  printf '%s\n' "$reported_version" | grep -F "$schema_version" >/dev/null ||
    die "cloud-init schema validator version does not match CLOUD_INIT_SCHEMA_VERSION"

  rendered=$(mktemp "${TMPDIR:-/tmp}/keepling-cloud-config.XXXXXX")
  trap 'rm -f -- "$rendered"' EXIT HUP INT TERM
  chmod 600 "$rendered"
  # shellcheck disable=SC2016 # Match OpenTofu template tokens literally.
  sed \
    -e 's/${tested_oci_digest}/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g' \
    -e 's/${architecture}/x86_64/g' \
    infra/tofu/hetzner/cloud-init.yml >"$rendered"

  if ! grep -F 'systemctl enable --now docker.service' "$rendered" >/dev/null ||
    ! grep -F 'systemctl is-active --quiet docker.service' "$rendered" >/dev/null ||
    ! grep -F '/var/lib/keepling/bootstrap-complete.json' "$rendered" >/dev/null ||
    ! grep -F '{"version":1,"status":"complete"}' "$rendered" >/dev/null; then
    die "rendered cloud-config is missing the Keepling completion contract"
  fi
  "$schema_bin" schema --config-file "$rendered" >/dev/null ||
    die "rendered cloud-config failed the pinned cloud-init schema validator"
)

verify_pinned_tofu() {
  require_pinned_executable "OpenTofu" "$TOFU_BIN"
  [ "$($TOFU_BIN version -json | jq -r '.terraform_version')" = "1.12.6" ] ||
    die "OpenTofu 1.12.6 is required"
  provider_dir=${HCLOUD_PROVIDER_PLUGIN_DIR:-}
  case "$provider_dir" in
    /*) [ -d "$provider_dir" ] || die "pinned provider plugin directory is unavailable" ;;
    *) die "HCLOUD_PROVIDER_PLUGIN_DIR must be an explicit absolute directory" ;;
  esac
  configured_provider_version=$(awk '/source  = "hetznercloud\/hcloud"/{found=1; next} found && /version = "= [0-9.]+"/{gsub(/[^0-9.]/, "", $0); print; exit}' infra/tofu/hetzner/versions.tf)
  locked_provider_version=$(awk '/provider "registry.opentofu.org\/hetznercloud\/hcloud"/{found=1; next} found && /version/{gsub(/[^0-9.]/, "", $0); print; exit}' infra/tofu/hetzner/.terraform.lock.hcl)
  [ -n "$configured_provider_version" ] && [ "$configured_provider_version" = "$locked_provider_version" ] ||
    die "tracked hcloud provider constraint and lock resolution disagree"
  find "$provider_dir" -type f -name "terraform-provider-hcloud_v${configured_provider_version}*" -perm -111 -print -quit |
    grep -q . || die "the tracked pinned hcloud provider is unavailable"
}

dry_run() {
  verify_cloud_init_preflight
  verify_pinned_tofu
  verify_network_graph_contract
  tofu_data=$(mktemp -d "${TMPDIR:-/tmp}/keepling-tofu-data.XXXXXX")
  trap 'rm -rf -- "$tofu_data"' EXIT HUP INT TERM
  "$TOFU_BIN" -chdir=infra/tofu/hetzner fmt -check -recursive
  TF_DATA_DIR="$tofu_data" "$TOFU_BIN" -chdir=infra/tofu/hetzner init -backend=false -lockfile=readonly -plugin-dir="$HCLOUD_PROVIDER_PLUGIN_DIR" >/dev/null
  TF_DATA_DIR="$tofu_data" "$TOFU_BIN" -chdir=infra/tofu/hetzner validate >/dev/null
  TF_DATA_DIR="$tofu_data" "$TOFU_BIN" -chdir=infra/tofu/hetzner test >/dev/null
  ./infra/dns/cloudflare.sh self-test >/dev/null
  ./infra/backup/mirror-snapshot.sh self-test >/dev/null
  ./tooling/verify-backup.sh --fixture local >/dev/null
  ./tooling/test-host-bootstrap.sh >/dev/null
  ./tooling/test-host-bootstrap-diagnostics.sh >/dev/null
  ./tooling/test-provider-ownership.sh >/dev/null
  ./tooling/test-resolved-plan-contract.sh >/dev/null
  ./tooling/test-image-archive-contract.sh >/dev/null
  ./tooling/test-remote-prepare-observability.sh >/dev/null
  ./tooling/test-host-replacement-sequence.sh >/dev/null
  verify_selection
  verify_state_contract
  echo "Host replacement dry-run passed: provider graph, exact DNS identity, append-only mirror, and cost guard are deterministic"
}

credentialed_preflight() {
  require_credentials
  verify_selection
  verify_network_graph_contract
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

case "${1:-}" in
  --dry-run) [ "$#" -eq 1 ] || die "usage: $0 --dry-run"; dry_run ;;
  --cloud-init-preflight) [ "$#" -eq 1 ] || die "usage: $0 --cloud-init-preflight"; verify_cloud_init_preflight ;;
  --state-self-test) [ "$#" -eq 1 ] || die "usage: $0 --state-self-test"; verify_state_contract ;;
  --bootstrap-gate) [ "$#" -eq 1 ] || die "usage: $0 --bootstrap-gate"; verify_bootstrap_gate ;;
  --stage-bundle) [ "$#" -eq 1 ] || die "usage: $0 --stage-bundle"; stage_candidate_bundle ;;
  --normalize-provider-output)
    [ "$#" -eq 5 ] || die "usage: $0 --normalize-provider-output INPUT COUNTS OUTPUT EXPECTED_RUN_ID"
    normalize_provider_ownership "$2" "$3" "$4" "$5"
    ;;
  --resolve-plan-architecture)
    [ "$#" -eq 3 ] || die "usage: $0 --resolve-plan-architecture PLAN OUTPUT"
    resolve_plan_architecture "$2" "$3"
    ;;
  --resolve-image-archive)
    [ "$#" -eq 3 ] || die "usage: $0 --resolve-image-archive ARCHIVE OUTPUT"
    resolve_image_archive_contract "$2" "$3"
    ;;
  --candidate-sequence) [ "$#" -eq 1 ] || die "usage: $0 --candidate-sequence"; verify_candidate_sequence ;;
  --credentialed)
    case "${2:-}" in
      --preflight) [ "$#" -eq 2 ] || die "usage: $0 --credentialed --preflight"; credentialed_preflight ;;
      '') credentialed_apply ;;
      *) die "usage: $0 --credentialed [--preflight]" ;;
    esac
    ;;
  *) die "usage: $0 --dry-run | --cloud-init-preflight | --state-self-test | --bootstrap-gate | --stage-bundle | --normalize-provider-output INPUT COUNTS OUTPUT EXPECTED_RUN_ID | --resolve-plan-architecture PLAN OUTPUT | --resolve-image-archive ARCHIVE OUTPUT | --candidate-sequence | --credentialed [--preflight]" ;;
esac
