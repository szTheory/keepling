#!/usr/bin/env sh
# Move every credential the protected release lanes need from 1Password into the
# right GitHub environment, in one command.
#
#   ./tooling/provision-release-secrets.sh --check      report only
#   ./tooling/provision-release-secrets.sh --discover   suggest op:// references
#   ./tooling/provision-release-secrets.sh --apply      read and upload
#
# DESIGN NOTES, because this handles credentials:
#   * Secret VALUES never touch the filesystem, never reach a shell argument
#     (which is world-readable in `ps`), and are never echoed. They move through
#     a pipe from `op read` into `gh secret set --body-file -` and nowhere else.
#   * The map file names locations, never values, so it is safe to commit.
#   * The Squad vault is excluded from discovery unconditionally. It is an
#     employer vault and nothing in this repository may read it.
#   * --check exits non-zero when anything required is absent, so it composes.
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
map_file=tooling/release-secrets.map

# Vaults discovery must never read. Employer-owned; see the note above.
excluded_vaults="Squad"

mode=--check
case "${1:-}" in
  --check|--discover|--apply) mode=$1 ;;
  "") mode=--check ;;
  *) echo "usage: $0 [--check|--discover|--apply]" >&2; exit 2 ;;
esac

die() { echo "provision-release-secrets: $*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is unavailable$2"
}

require_command gh " -- install with 'brew install gh', then 'gh auth login'"
require_command op " -- install with 'brew install 1password-cli', then enable the CLI in 1Password > Settings > Developer"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"
[ -r "$map_file" ] || die "$map_file is missing"

# Probe with real work rather than with `op whoami`. Under desktop-app
# integration the session is established lazily by the first command that
# actually needs it, so `op whoami` reports "not signed in" on a perfectly
# usable install -- and would turn a working setup into a false failure here.
op vault list --format=json >/dev/null 2>&1 ||
  die "1Password is unavailable; unlock the desktop app (Settings > Developer > Integrate with 1Password CLI), or run 'op signin'"

repository=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

# ---------------------------------------------------------------- discovery --
non_excluded_vaults() {
  op vault list --format=json |
    node -e '
      let d = "";
      process.stdin.on("data", (c) => (d += c)).on("end", () => {
        const skip = new Set(process.argv[1].split(","));
        for (const v of JSON.parse(d)) if (!skip.has(v.name)) console.log(v.name);
      });' "$excluded_vaults"
}

if [ "$mode" = --discover ]; then
  echo "Vaults searched (Squad deliberately excluded):"
  non_excluded_vaults | sed 's/^/  /'
  echo
  echo "Items whose title suggests one of the credentials this repository needs:"
  non_excluded_vaults | while IFS= read -r vault; do
    op item list --vault "$vault" --format=json 2>/dev/null |
      node -e '
        let d = "";
        process.stdin.on("data", (c) => (d += c)).on("end", () => {
          const vault = process.argv[1];
          const want = /hetzner|hcloud|cloudflare|keepling|backblaze|wasabi|storj|scaleway|minio|\bs3\b|\br2\b/i;
          for (const i of JSON.parse(d || "[]"))
            if (want.test(i.title)) console.log("  op://" + vault + "/" + i.title + "/<field>");
        });' "$vault"
  done
  echo
  echo "Field names for an item:  op item get '<title>' --vault '<vault>' --format=json | jq -r '.fields[].label'"
  echo "Then edit $map_file and re-run with --apply."
  exit 0
fi

# ------------------------------------------------------------------ the map --
# Emits: environment<TAB>secret<TAB>reference<TAB>requirement, comments stripped.
# The reference is rejoined from the middle columns because an item title may
# legitimately contain spaces.
read_map() {
  sed -e 's/#.*//' "$map_file" |
    awk 'NF >= 4 {
      environment = $1; name = $2; requirement = $NF;
      reference = "";
      for (i = 3; i < NF; i++) reference = reference (reference == "" ? "" : " ") $i;
      printf "%s\t%s\t%s\t%s\n", environment, name, reference, requirement;
    }'
}

[ -n "$(read_map)" ] || die "$map_file declares no entries"

# --------------------------------------------------------------- the report --
missing_required=0
resolvable=0

printf '%-20s %-36s %s\n' ENVIRONMENT SECRET 1PASSWORD
printf '%-20s %-36s %s\n' ----------- ------ ---------
while IFS="$(printf '\t')" read -r environment secret reference requirement; do
  case "$reference" in
    op://*/*/*) ;;
    *) die "$secret has a malformed reference: $reference" ;;
  esac
  if op read "$reference" >/dev/null 2>&1; then
    state=found
    resolvable=$((resolvable + 1))
  else
    state="NOT FOUND"
    [ "$requirement" = required ] && missing_required=$((missing_required + 1))
  fi
  printf '%-20s %-36s %s\n' "$environment" "$secret" "$state"
done <<MAP_ENTRIES
$(read_map)
MAP_ENTRIES
echo

if [ "$missing_required" -gt 0 ]; then
  echo "$missing_required required credential(s) could not be read from 1Password." >&2
  echo "Run '$0 --discover' to find the right op:// references, then edit $map_file." >&2
  [ "$mode" = --apply ] && die "refusing to upload a partial credential set"
  exit 1
fi

if [ "$mode" != --apply ]; then
  echo "All $resolvable credential(s) resolve. Re-run with --apply to upload them to $repository."
  exit 0
fi

# ------------------------------------------------------------------- upload --
# Create any environment the map names but the repository does not yet have.
# `gh secret set --env` fails opaquely against a missing environment, so this is
# done first and explicitly rather than left to surface as a confusing error.
read_map | cut -f1 | sort -u | while IFS= read -r environment; do
  if gh api "repos/$repository/environments/$environment" >/dev/null 2>&1; then
    echo "environment $environment already exists"
  else
    gh api --method PUT "repos/$repository/environments/$environment" --silent
    echo "environment $environment created"
  fi
done
echo

uploaded=0
while IFS="$(printf '\t')" read -r environment secret reference requirement; do
  # The value exists only inside this pipe. It is never a file, never an
  # argument, and never printed.
  if op read --no-newline "$reference" |
    gh secret set "$secret" --env "$environment" --repo "$repository" --body-file - >/dev/null 2>&1; then
    echo "set $environment/$secret"
    uploaded=$((uploaded + 1))
  else
    die "failed to set $environment/$secret"
  fi
done <<MAP_ENTRIES
$(read_map)
MAP_ENTRIES

echo
echo "Uploaded $uploaded secret(s) to $repository."
echo "Verify with: gh secret list --env recovery-protected && gh secret list --env recovery-live"
