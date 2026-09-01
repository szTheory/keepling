#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Host bootstrap regression failed: $*" >&2
  exit 1
}

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-host-bootstrap.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

cat >"$fixture_root/status" <<'EOF'
#!/usr/bin/env sh
set -eu
count_file=$1
count=$(cat "$count_file")
printf '%s\n' "$((count + 1))" >"$count_file"
cat <<'JSON'
{
  "status": "error - done",
  "extended_status": "error - done",
  "init-local": {"errors": [], "recoverable_errors": {}},
  "init": {"errors": [], "recoverable_errors": {}},
  "modules-config": {"errors": [], "recoverable_errors": {}},
  "modules-final": {
    "errors": [
      "Running module scripts-user failed while package-update-upgrade-install referenced SENSITIVE_FIXTURE_VALUE and PRIVATE_IDENTIFIER_FIXTURE"
    ],
    "recoverable_errors": {}
  }
}
JSON
exit 1
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

chmod 700 "$fixture_root/status" "$fixture_root/teardown" "$fixture_root/dns-mutation"
printf '0\n' >"$fixture_root/status-count"
printf '0\n' >"$fixture_root/teardown-count"

if KEEPLING_BOOTSTRAP_STATUS_RUNNER="$fixture_root/status" \
  KEEPLING_BOOTSTRAP_STATUS_RUNNER_ARGUMENT="$fixture_root/status-count" \
  KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER="$fixture_root/teardown" \
  KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT="$fixture_root/teardown-count" \
  KEEPLING_BOOTSTRAP_EVIDENCE_FILE="$fixture_root/evidence.json" \
  KEEPLING_DNS_MUTATION_RUNNER="$fixture_root/dns-mutation" \
  KEEPLING_DNS_MUTATION_RUNNER_ARGUMENT="$fixture_root/dns-called" \
  ./tooling/verify-host-replacement.sh --bootstrap-gate >/dev/null 2>&1; then
  die "terminal cloud-init failure was accepted"
fi

[ "$(cat "$fixture_root/status-count")" = 1 ] ||
  die "terminal cloud-init failure was retried"
[ "$(cat "$fixture_root/teardown-count")" = 1 ] ||
  die "terminal cloud-init failure did not drive teardown exactly once"
[ ! -e "$fixture_root/dns-called" ] ||
  die "DNS mutation ran after terminal cloud-init failure"
[ -r "$fixture_root/evidence.json" ] ||
  die "bounded bootstrap evidence was not captured"

jq -e '
  .version == 1 and
  .bootstrap_status == "error - done" and
  .failed_stages == ["modules-final"] and
  .failed_modules == ["package-update-upgrade-install", "scripts-user"] and
  .error_count == 1 and
  .recoverable_error_count == 0 and
  .raw_detail_retained == false
' "$fixture_root/evidence.json" >/dev/null ||
  die "bootstrap evidence did not identify the bounded failing stage and modules"

if grep -Eq 'SENSITIVE_FIXTURE_VALUE|PRIVATE_IDENTIFIER_FIXTURE' "$fixture_root/evidence.json"; then
  die "bootstrap evidence retained sensitive or identifying raw detail"
fi
[ "$(wc -c <"$fixture_root/evidence.json" | tr -d ' ')" -le 2048 ] ||
  die "bootstrap evidence exceeded its bounded size"
[ "$(stat -f '%Lp' "$fixture_root/evidence.json")" = 600 ] ||
  die "bootstrap evidence permissions were not owner-only"

printf '0\n' >"$fixture_root/status-count"
printf '0\n' >"$fixture_root/teardown-count"
forbidden_evidence="$repository_root/.forbidden-bootstrap-evidence"
rm -f -- "$forbidden_evidence"
if KEEPLING_BOOTSTRAP_STATUS_RUNNER="$fixture_root/status" \
  KEEPLING_BOOTSTRAP_STATUS_RUNNER_ARGUMENT="$fixture_root/status-count" \
  KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER="$fixture_root/teardown" \
  KEEPLING_BOOTSTRAP_TEARDOWN_RUNNER_ARGUMENT="$fixture_root/teardown-count" \
  KEEPLING_BOOTSTRAP_EVIDENCE_FILE="$forbidden_evidence" \
  ./tooling/verify-host-replacement.sh --bootstrap-gate >/dev/null 2>&1; then
  die "unsafe in-repository bootstrap evidence was accepted"
fi
[ "$(cat "$fixture_root/status-count")" = 1 ] ||
  die "evidence refusal retried terminal cloud-init failure"
[ "$(cat "$fixture_root/teardown-count")" = 1 ] ||
  die "evidence refusal bypassed teardown-first cleanup"
[ ! -e "$forbidden_evidence" ] ||
  die "unsafe in-repository bootstrap evidence was written"

mkdir "$fixture_root/bundle-sources" "$fixture_root/bundle"
printf '%s' image >"$fixture_root/bundle-sources/noncanonical-image"
printf '%s' dump >"$fixture_root/bundle-sources/noncanonical-dump"
printf '%s' credential >"$fixture_root/bundle-sources/noncanonical-credential"
printf '%s' compose >"$fixture_root/bundle-sources/noncanonical-compose"
printf '%s' caddy >"$fixture_root/bundle-sources/noncanonical-caddy"
printf '%s' override >"$fixture_root/bundle-sources/source-override-name"
printf '%s' '#!/bin/sh' >"$fixture_root/bundle-sources/noncanonical-runner"

KEEPLING_BUNDLE_IMAGE_SOURCE="$fixture_root/bundle-sources/noncanonical-image" \
  KEEPLING_BUNDLE_RECOVERY_SOURCE="$fixture_root/bundle-sources/noncanonical-dump" \
  KEEPLING_BUNDLE_LOGIN_CREDENTIAL_SOURCE="$fixture_root/bundle-sources/noncanonical-credential" \
  KEEPLING_BUNDLE_COMPOSE_SOURCE="$fixture_root/bundle-sources/noncanonical-compose" \
  KEEPLING_BUNDLE_CADDY_SOURCE="$fixture_root/bundle-sources/noncanonical-caddy" \
  KEEPLING_BUNDLE_OVERRIDE_SOURCE="$fixture_root/bundle-sources/source-override-name" \
  KEEPLING_BUNDLE_RUNNER_SOURCE="$fixture_root/bundle-sources/noncanonical-runner" \
  KEEPLING_BUNDLE_DESTINATION="$fixture_root/bundle" \
  ./tooling/verify-host-replacement.sh --stage-bundle >/dev/null

find "$fixture_root/bundle" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort >"$fixture_root/bundle-actual"
cat >"$fixture_root/bundle-expected" <<'EOF'
Caddyfile
compose-override.yml
compose.yml
image.tar.gz
new-login-credential
recovery.dump
remote-prepare.sh
EOF
cmp -s "$fixture_root/bundle-expected" "$fixture_root/bundle-actual" ||
  die "candidate bundle did not normalize every exact remote basename"
cmp -s "$fixture_root/bundle-sources/source-override-name" "$fixture_root/bundle/compose-override.yml" ||
  die "candidate bundle did not preserve the normalized override payload"
[ "$(stat -f '%Lp' "$fixture_root/bundle/new-login-credential")" = 600 ] ||
  die "candidate bundle exposed the transient login credential"
[ "$(stat -f '%Lp' "$fixture_root/bundle/remote-prepare.sh")" = 700 ] ||
  die "candidate bundle runner is not owner-executable"

echo "Host bootstrap regression passed: terminal failure is fail-fast, redacted, DNS-safe, and teardown-first"
