#!/usr/bin/env sh
set -eu

expected_digest=${KEEPLING_EXPECTED_OCI_DIGEST:-}
expected_architecture=${KEEPLING_EXPECTED_ARCHITECTURE:-}
[ -n "$expected_digest" ] && [ -n "$expected_architecture" ] || exit 2

effect_root=/
systemctl_bin=/usr/bin/systemctl
cloud_init_bin=/usr/bin/cloud-init
expected_owner=root:root
if [ "${KEEPLING_EFFECT_TEST_MODE:-}" = yes ]; then
  effect_root=${KEEPLING_EFFECT_ROOT:-}
  systemctl_bin=${KEEPLING_EFFECT_SYSTEMCTL_BIN:-}
  cloud_init_bin=${KEEPLING_EFFECT_CLOUD_INIT_BIN:-}
  expected_owner=${KEEPLING_EFFECT_EXPECTED_OWNER:-}
  [ -d "$effect_root" ] && [ -x "$systemctl_bin" ] && [ -x "$cloud_init_bin" ] || exit 2
  printf '%s' "$expected_owner" | grep -Eq '^[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$' || exit 2
fi

root_path() {
  if [ "$effect_root" = / ]; then printf '%s\n' "$1"; else printf '%s%s\n' "$effect_root" "$1"; fi
}

has_mode() {
  [ -e "$1" ] || return 1
  observed_mode=$(stat -c '%U:%G:%a' "$1" 2>/dev/null || stat -f '%Su:%Sg:%Lp' "$1" 2>/dev/null || true)
  [ "$observed_mode" = "$2" ]
}

sentinel=false docker_active=false required_paths=false release_digest_matches=false release_architecture_matches=false
sentinel_file=$(root_path /var/lib/keepling/bootstrap-complete.json)
release_file=$(root_path /etc/keepling/release.env)
bootstrap_file=$(root_path /usr/local/sbin/keepling-bootstrap)

if has_mode "$sentinel_file" "$expected_owner:600" &&
  [ "$(wc -l <"$sentinel_file" | tr -d ' ')" = 1 ] &&
  grep -Fx '{"version":1,"status":"complete"}' "$sentinel_file" >/dev/null; then sentinel=true; fi
if "$systemctl_bin" is-active --quiet docker.service >/dev/null 2>&1 &&
  "$systemctl_bin" is-enabled --quiet docker.service >/dev/null 2>&1; then docker_active=true; fi
if has_mode "$(root_path /srv/keepling)" "$expected_owner:755" &&
  has_mode "$(root_path /etc/keepling/secrets)" "$expected_owner:700" &&
  has_mode "$(root_path /etc/keepling/recovery)" "$expected_owner:700" &&
  has_mode "$(root_path /var/lib/keepling)" "$expected_owner:700" &&
  has_mode "$release_file" "$expected_owner:644" &&
  has_mode "$bootstrap_file" "$expected_owner:755"; then required_paths=true; fi
if grep -Fx "KEEPLING_TESTED_OCI_DIGEST=$expected_digest" "$release_file" >/dev/null 2>&1; then release_digest_matches=true; fi
if grep -Fx "KEEPLING_TARGET_ARCHITECTURE=$expected_architecture" "$release_file" >/dev/null 2>&1; then release_architecture_matches=true; fi

cloud_init_version=$($cloud_init_bin --version 2>/dev/null | awk 'NR == 1 {print $2}')
printf '%s' "$cloud_init_version" | grep -Eq '^[0-9]+([.][0-9]+){1,3}([+~._-][A-Za-z0-9]+)*$' || cloud_init_version=unknown
printf '{"version":1,"cloud_init_version":"%s","sentinel":%s,"docker_active":%s,"required_paths":%s,"release_digest_matches":%s,"release_architecture_matches":%s}\n' \
  "$cloud_init_version" "$sentinel" "$docker_active" "$required_paths" "$release_digest_matches" "$release_architecture_matches"

[ "$sentinel" = true ] && [ "$docker_active" = true ] && [ "$required_paths" = true ] &&
  [ "$release_digest_matches" = true ] && [ "$release_architecture_matches" = true ]
