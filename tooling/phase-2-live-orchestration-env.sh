#!/usr/bin/env sh
# Run this after setting KEEPLING_LIVE_ORCHESTRATION_FILE to a private,
# mode-0600 copy of the template. It installs no credentials and performs no
# network action; it prints only shell-safe exports for seven adapter paths.

_keepling_live_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
[ "${1:-}" = --exports ] && [ "$#" -eq 1 ] || { printf '%s\n' 'usage: phase-2-live-orchestration-env.sh --exports' >&2; exit 2; }
: "${KEEPLING_LIVE_ORCHESTRATION_FILE:?set a private orchestration file path}"
case "$KEEPLING_LIVE_ORCHESTRATION_FILE" in
  /*) ;;
  *) printf '%s\n' 'Phase 2 live orchestration file must be absolute' >&2; exit 2 ;;
esac
case "$KEEPLING_LIVE_ORCHESTRATION_FILE" in
  "$_keepling_live_root"|"$_keepling_live_root"/*) printf '%s\n' 'Phase 2 live orchestration file must remain outside the repository' >&2; exit 2 ;;
esac
[ -f "$KEEPLING_LIVE_ORCHESTRATION_FILE" ] && [ ! -L "$KEEPLING_LIVE_ORCHESTRATION_FILE" ] || { printf '%s\n' 'Phase 2 live orchestration file is unavailable' >&2; exit 2; }
_keepling_live_mode=$(stat -f '%Lp' "$KEEPLING_LIVE_ORCHESTRATION_FILE" 2>/dev/null || stat -c '%a' "$KEEPLING_LIVE_ORCHESTRATION_FILE")
[ "$_keepling_live_mode" = 600 ] || { printf '%s\n' 'Phase 2 live orchestration file must have mode 0600' >&2; exit 2; }
for _keepling_live_stage in bootstrap image restore runtime semantic dns teardown; do
  _keepling_live_name=$(printf '%s' "$_keepling_live_stage" | tr '[:lower:]' '[:upper:]')
  printf 'export KEEPLING_SEQUENCE_%s_RUNNER=%s\n' "$_keepling_live_name" "$_keepling_live_root/tooling/phase-2-live-runners/$_keepling_live_stage"
done
