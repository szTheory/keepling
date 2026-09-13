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
  --check|--discover|--fields|--apply) mode=$1 ;;
  "") mode=--check ;;
  *) echo "usage: $0 [--check|--discover|--fields|--apply]" >&2; exit 2 ;;
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
  echo "Run --fields next to print the field labels of every 'Keepling' item,"
  echo "then edit $map_file and re-run with --apply."
  exit 0
fi

# ------------------------------------------------------------------- fields --
# Print every field label of every item whose title begins "Keepling". Writing
# the map needs a field label per credential, and getting them one item at a
# time is six invocations and six chances to mistype a title. Labels are not
# credential values, so this is safe to read and safe to paste.
if [ "$mode" = --fields ]; then
  non_excluded_vaults | while IFS= read -r vault; do
    op item list --vault "$vault" --format=json 2>/dev/null |
      node -e '
        let d = "";
        process.stdin.on("data", (c) => (d += c)).on("end", () => {
          for (const i of JSON.parse(d || "[]"))
            if (/^keepling/i.test(i.title)) console.log(i.id);
        });' |
      while IFS= read -r item_id; do
        # shellcheck disable=SC2016  # inlined JavaScript; nothing here is a shell expansion
        op item get "$item_id" --vault "$vault" --format=json 2>/dev/null |
          node -e '
            let d = "";
            process.stdin.on("data", (c) => (d += c)).on("end", () => {
              const item = JSON.parse(d || "{}");
              if (!item.title) return;
              // Address the item by UUID, never by title. `op read` rejects a
              // reference containing any character outside its own grammar,
              // and these titles use an en dash, so the title form can never
              // resolve. A UUID also survives the item being renamed.
              console.log("# " + item.title);
              for (const f of item.fields || [])
                // A label with no value is a section header or an unfilled
                // template row; naming it in the map would resolve to nothing.
                if (f.label && (f.value !== undefined || f.reference))
                  console.log("op://" + process.argv[1] + "/" + item.id + "/" + f.label);
              console.log("");
            });' "$vault"
      done
  done
  echo "Copy the references you need into $map_file, then run --check."
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

map_reference_for() {
  read_map | awk -F'\t' -v want="$1" '$2 == want { print $3; exit }'
}

# ------------------------------------------------------------- derivations --
# Two of the values the recovery drills need are not stored anywhere, because
# they are not independent facts: a Backblaze S3 endpoint and its region are
# determined by the account the application key belongs to, and Backblaze will
# state them itself. Asking the operator to look them up and paste them in is
# asking them to transcribe something a machine already knows, which is both
# manual work and a chance to get it silently wrong.
#
# b2_authorize_account is called at most once per run; the response is cached.
b2_authorization=""
b2_authorize() {
  [ -n "$b2_authorization" ] && { printf '%s' "$b2_authorization"; return 0; }

  key_id_reference=$(map_reference_for KEEPLING_BACKUP_PRIMARY_ACCESS_KEY)
  application_key_reference=$(map_reference_for KEEPLING_BACKUP_PRIMARY_SECRET_KEY)
  [ -n "$key_id_reference" ] && [ -n "$application_key_reference" ] ||
    die "a derived Backblaze value needs KEEPLING_BACKUP_PRIMARY_ACCESS_KEY and KEEPLING_BACKUP_PRIMARY_SECRET_KEY in $map_file"

  key_id=$(op read --no-newline "$key_id_reference") ||
    die "could not read $key_id_reference"
  application_key=$(op read --no-newline "$application_key_reference") ||
    die "could not read $application_key_reference"

  # Credentials go to curl through a stdin config file, never through argv.
  # `curl -u` would put the application key in `ps` output for every user.
  b2_authorization=$(
    printf 'user = "%s:%s"\nurl = "https://api.backblazeb2.com/b2api/v3/b2_authorize_account"\n' \
      "$key_id" "$application_key" |
      curl --silent --show-error --fail --config - 2>/dev/null
  ) || die "Backblaze rejected the application key in $key_id_reference"

  printf '%s' "$b2_authorization"
}

# v3 nests the S3 endpoint under apiInfo.storageApi; v2 had it at the top
# level. Accept either, so a future account on either API shape still resolves.
b2_s3_endpoint() {
  b2_authorize | node -e '
    let d = "";
    process.stdin.on("data", (c) => (d += c)).on("end", () => {
      const body = JSON.parse(d || "{}");
      const url = body?.apiInfo?.storageApi?.s3ApiUrl || body.s3ApiUrl;
      if (!url) process.exit(1);
      process.stdout.write(url);
    });'
}

b2_s3_region() {
  # shellcheck disable=SC2016  # inlined JavaScript; nothing here is a shell expansion
  b2_s3_endpoint | node -e '
    let d = "";
    process.stdin.on("data", (c) => (d += c)).on("end", () => {
      // An upstream failure arrives here as empty input. Guard before parsing:
      // `new URL("")` throws, and a stack trace is a worse diagnostic than the
      // real error the caller already printed.
      if (!d.trim()) process.exit(1);
      // https://s3.us-west-004.backblazeb2.com -> us-west-004
      const region = new URL(d.trim()).hostname.split(".")[1];
      if (!region) process.exit(1);
      process.stdout.write(region);
    });'
}

# Resolve one map reference to its value on stdout. Callers pipe this straight
# into `gh secret set`; it is never assigned to a variable that outlives the
# pipe and never printed.
resolve_reference() {
  case "$1" in
    op://*/*/*) op read --no-newline "$1" ;;
    derive:b2-s3-endpoint) b2_s3_endpoint ;;
    derive:b2-s3-region) b2_s3_region ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------- the report --
missing_required=0
resolvable=0

echo "Resolving $(read_map | wc -l | tr -d '[:space:]') credential(s) declared in $map_file:"
echo
while IFS="$(printf '\t')" read -r environment secret reference requirement; do
  case "$reference" in
    op://*/*/*|derive:b2-s3-endpoint|derive:b2-s3-region) ;;
    *) die "$secret has an unrecognised source: $reference" ;;
  esac
  # `op read` accepts only its own reference grammar and rejects anything else
  # outright -- an en dash in an item title is enough. Catch that here, where
  # the message can say what to do about it, rather than letting the same
  # opaque complaint repeat once per row.
  if printf '%s' "$reference" | LC_ALL=C grep -q '[^[:print:]]\|[^ -~]'; then
    die "$secret has a non-ASCII character in its source, which 'op read' will
    reject: $reference
    Address the item by UUID instead of by title. Run '$0 --fields', which
    emits UUID references ready to paste into $map_file."
  fi
  # Keep the resolver's own error message. Discarding it leaves every distinct
  # failure looking identical -- a wrong field label, a wrong item title, a
  # locked vault and a rejected key all read as "NOT FOUND" -- and there is
  # nothing left to debug from. Stdout goes to /dev/null because it is the
  # credential; stderr is the diagnosis and is kept.
  if failure=$(resolve_reference "$reference" 2>&1 >/dev/null); then
    printf '  found      %s\n' "$secret"
    resolvable=$((resolvable + 1))
  else
    printf '  NOT FOUND  %s\n' "$secret"
    printf '             source: %s\n' "$reference"
    printf '%s\n' "$failure" | sed -e '/^[[:space:]]*$/d' -e 's/^/             /' | head -4
    [ "$requirement" = required ] && missing_required=$((missing_required + 1))
  fi
done <<MAP_ENTRIES
$(read_map)
MAP_ENTRIES
echo

if [ "$missing_required" -gt 0 ]; then
  echo "$missing_required required credential(s) could not be resolved." >&2
  echo "Run '$0 --discover' and '$0 --fields' to find the right references, then edit $map_file." >&2
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
  if resolve_reference "$reference" |
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
