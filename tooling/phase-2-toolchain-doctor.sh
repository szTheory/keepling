#!/usr/bin/env sh
set -eu

die() { echo "Phase 2 toolchain doctor failed: $*" >&2; exit 1; }
tofu_bin=${TOFU_BIN:-tofu}
"$tofu_bin" version 2>/dev/null | head -n 1 | grep -Eq 'OpenTofu v1\.12\.6$' || die "OpenTofu 1.12.6 is required"

[ -n "${CLOUD_INIT_SCHEMA_BIN:-}" ] && [ -x "$CLOUD_INIT_SCHEMA_BIN" ] || die "CLOUD_INIT_SCHEMA_BIN is missing or not executable"
[ -n "${CLOUD_INIT_SCHEMA_VERSION:-}" ] || die "CLOUD_INIT_SCHEMA_VERSION is missing"
"$CLOUD_INIT_SCHEMA_BIN" --version 2>/dev/null | grep -F "$CLOUD_INIT_SCHEMA_VERSION" >/dev/null || die "cloud-init schema validator version does not match CLOUD_INIT_SCHEMA_VERSION"

[ -n "${HCLOUD_PROVIDER_PLUGIN_DIR:-}" ] && [ -d "$HCLOUD_PROVIDER_PLUGIN_DIR" ] || die "HCLOUD_PROVIDER_PLUGIN_DIR is missing or unreadable"
find "$HCLOUD_PROVIDER_PLUGIN_DIR" -type f -name 'terraform-provider-hcloud_v1.68.0*' -perm -u+x -print -quit | grep -q . ||
  die "pinned hcloud provider 1.68.0 is absent from HCLOUD_PROVIDER_PLUGIN_DIR"

echo "Phase 2 toolchain doctor passed: OpenTofu, cloud-init schema validator, and pinned hcloud provider are available"
