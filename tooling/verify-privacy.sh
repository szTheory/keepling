#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Privacy verification failed: $*" >&2
  exit 1
}

vector=packages/contracts/vectors/redaction.json
[ -f "$vector" ] || die "redaction vector is missing"
command -v jq >/dev/null 2>&1 || die "required command 'jq' is unavailable"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-privacy.XXXXXX")
cleanup() {
  case "$temporary_root" in
    "${TMPDIR:-/tmp}"/keepling-privacy.*) rm -rf -- "$temporary_root" ;;
    *) die "refusing unsafe cleanup" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

sentinels="$temporary_root/sentinels"
jq -er '.hostile_sentinels | type == "array" and length > 0' "$vector" >/dev/null ||
  die "hostile sentinel vector is empty"
jq -r '.hostile_sentinels[]' "$vector" >"$sentinels"

scan_paths() {
  [ "$#" -gt 0 ] || die "at least one diagnostic artifact path is required"
  files="$temporary_root/files"
  : >"$files"

  for candidate in "$@"; do
    [ -e "$candidate" ] || die "diagnostic artifact path is missing"
    if [ -d "$candidate" ]; then
      find "$candidate" -type f -print >>"$files"
    elif [ -f "$candidate" ]; then
      printf '%s\n' "$candidate" >>"$files"
    else
      die "diagnostic artifact path is not a regular file or directory"
    fi
  done

  artifact_count=$(awk 'NF {count += 1} END {print count + 0}' "$files")
  [ "$artifact_count" -gt 0 ] || die "diagnostic artifact set is empty"

  while IFS= read -r artifact; do
    if LC_ALL=C grep -aF -f "$sentinels" "$artifact" >/dev/null 2>&1; then
      die "hostile sentinel found in a diagnostic artifact"
    fi
  done <"$files"

  sentinel_count=$(wc -l <"$sentinels" | tr -d '[:space:]')
  printf '%s\n' "Privacy verification passed: artifacts=$artifact_count sentinels=$sentinel_count"
}

self_test() {
  clean="$temporary_root/clean"
  hostile="$temporary_root/hostile"
  mkdir "$clean" "$hostile"

  for name in logs metrics traces stdout stderr results.json manifest.json plan.tfplan backup.out doctor-bundle.txt; do
    printf '%s\n' 'bounded_status=verified count=1 elapsed_ms=1' >"$clean/$name"
  done
  scan_paths "$clean" >/dev/null

  sentinel_count=$(wc -l <"$sentinels" | tr -d '[:space:]')
  index=0
  for name in logs metrics traces stdout stderr results.json manifest.json plan.tfplan backup.out doctor-bundle.txt; do
    index=$((index + 1))
    sentinel_index=$(( (index - 1) % sentinel_count + 1 ))
    sentinel=$(sed -n "${sentinel_index}p" "$sentinels")
    printf '%s\n' "$sentinel" >"$hostile/$name"
    if (scan_paths "$hostile/$name" >/dev/null 2>&1); then
      die "self-test accepted a hostile diagnostic surface"
    fi
  done

  printf '%s\n' 'Privacy verifier self-test passed: surfaces=10 clean=accepted hostile=rejected'
}

case "${1:-}" in
  --self-test)
    [ "$#" -eq 1 ] || die "usage: $0 --self-test | PATH [PATH ...]"
    self_test
    ;;
  '') die "usage: $0 --self-test | PATH [PATH ...]" ;;
  *) scan_paths "$@" ;;
esac
