#!/usr/bin/env sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

# Nested Git metadata is banned in repository CONTENT. Git-ignored paths are
# not content: SwiftPM checks its dependencies out under `apps/ios/.build/`
# (gitignored), and each checkout legitimately carries its own `.git`. A raw
# `find` does not honour .gitignore, so it failed this whole gate whenever the
# iOS app had simply been built. Check each hit against `git check-ignore` and
# skip the ignored ones; anything not ignored is still a hard failure, so an
# untracked-but-not-ignored nested clone is caught exactly as before.
find . -mindepth 2 \( -type d -o -type f \) -name .git -print | while IFS= read -r nested_git; do
  if git check-ignore -q "$nested_git"; then
    continue
  fi
  echo "Nested Git metadata is not allowed: $nested_git" >&2
  exit 1
done || exit 1

if [ -f .gitmodules ]; then
  echo "Git submodules are not allowed in the Keepling monorepo." >&2
  exit 1
fi

gitlinks=$(git ls-files --stage | awk '$1 == 160000 { print $4 }')
if [ -n "$gitlinks" ]; then
  echo "Tracked gitlinks are not allowed:" >&2
  echo "$gitlinks" >&2
  exit 1
fi

echo "Repository integrity checks passed."

# --- Governance: the public trust posture must fail loudly when it rots (D-32) ---
# Every root policy file exists and is non-empty; the licence hashes to the canonical
# upstream text; every manifest declares the expected licence; SECURITY.md's
# supported-version table mirrors the compatibility source; every PRIVACY.md claim
# names an evidence path that exists; and the generated limitations list matches what
# the ledger regenerates. A governance lane that performs zero assertions is a failure
# of the lane, never a silent green -- so this block counts what it actually checked.

governance_assertions=0

for governance_file in LICENSE NOTICE SECURITY.md SUPPORT.md CONTRIBUTING.md \
  CODE_OF_CONDUCT.md PRIVACY.md KNOWN-LIMITATIONS.md; do
  if [ ! -s "$governance_file" ]; then
    echo "Governance: required policy file is missing or empty: $governance_file" >&2
    exit 1
  fi
  governance_assertions=$((governance_assertions + 1))
done

canonical_license_sha256="cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"
license_sha256=$(shasum -a 256 LICENSE | awk '{print $1}')
if [ "$license_sha256" != "$canonical_license_sha256" ]; then
  echo "Governance: LICENSE does not hash to the canonical upstream Apache-2.0 text (got $license_sha256, expected $canonical_license_sha256)" >&2
  exit 1
fi
governance_assertions=$((governance_assertions + 1))

if ! node -e '
const fs = require("fs");
const expected = "Apache-2.0";
const manifests = [
  "package.json",
  "apps/web/package.json",
  "apps/desktop/package.json",
  "packages/web-ui/package.json",
];
for (const manifestPath of manifests) {
  if (!fs.existsSync(manifestPath)) {
    console.error("Governance: missing package manifest " + manifestPath);
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.license !== expected) {
    console.error(
      "Governance: " + manifestPath + " declares licence " + JSON.stringify(manifest.license) +
        ", expected " + JSON.stringify(expected),
    );
    process.exit(1);
  }
}
const mixSource = fs.readFileSync("apps/server/mix.exs", "utf8");
const mixMatch = mixSource.match(/licenses:\s*\[\s*"([^"]+)"\s*\]/);
if (!mixMatch || mixMatch[1] !== expected) {
  console.error("Governance: apps/server/mix.exs does not declare licenses: [\"" + expected + "\"]");
  process.exit(1);
}
'; then
  exit 1
fi
governance_assertions=$((governance_assertions + 1))

if ! node -e '
const fs = require("fs");
let configSource;
try {
  configSource = fs.readFileSync("apps/server/config/config.exs", "utf8");
} catch {
  console.error("Governance: BLOCKED -- could not read the compatibility source (apps/server/config/config.exs); reporting blocked, not a pass");
  process.exit(1);
}

function extract(key) {
  const match = configSource.match(new RegExp("\"" + key + "\"\\s*=>\\s*(nil|\\d+|\"[^\"]*\")"));
  if (!match) {
    console.error("Governance: BLOCKED -- compatibility source is missing key \"" + key + "\"");
    process.exit(1);
  }
  const raw = match[1];
  if (raw === "nil") return null;
  if (raw.startsWith("\"")) return raw.slice(1, -1);
  return Number(raw);
}

const currentTrain = extract("current_protocol_train");
const previousTrain = extract("previous_protocol_train");
const deprecationDeadline = extract("deprecation_deadline");

const rows =
  previousTrain === null
    ? "| — | no released version yet | — |"
    : "| " + currentTrain + " | Supported | — |\n| " + previousTrain + " | Supported | " + deprecationDeadline + " |";

const rendered = ["| Protocol train | Status | Support ends |", "|---|---|---|", rows].join("\n");

const startMarker = "<!-- keepling:generated:supported-versions:start -->";
const endMarker = "<!-- keepling:generated:supported-versions:end -->";
const security = fs.readFileSync("SECURITY.md", "utf8");
const startIndex = security.indexOf(startMarker);
const endIndex = security.indexOf(endMarker);
if (startIndex === -1 || endIndex === -1) {
  console.error("Governance: SECURITY.md is missing the generated supported-versions markers");
  process.exit(1);
}
const actual = security.slice(startIndex + startMarker.length, endIndex).trim();
if (actual !== rendered.trim()) {
  console.error("Governance: SECURITY.md supported-versions table has drifted from the compatibility source");
  console.error("expected:\n" + rendered);
  console.error("actual:\n" + actual);
  process.exit(1);
}
'; then
  exit 1
fi
governance_assertions=$((governance_assertions + 1))

if ! node -e '
const fs = require("fs");
const privacy = fs.readFileSync("PRIVACY.md", "utf8");
const paths = [...privacy.matchAll(/`([^`]+\/[^`]+)`/g)]
  .map((match) => match[1])
  .filter((candidate) => !candidate.startsWith("http"));
if (paths.length === 0) {
  console.error("Governance: PRIVACY.md names zero evidence paths -- a privacy policy asserting nothing checkable");
  process.exit(1);
}
const missing = paths.filter((candidate) => !fs.existsSync(candidate));
if (missing.length > 0) {
  console.error("Governance: PRIVACY.md names an evidence path that does not exist: " + missing.join(", "));
  process.exit(1);
}
'; then
  exit 1
fi
governance_assertions=$((governance_assertions + 1))

known_limitations_check=$(mktemp "${TMPDIR:-/tmp}/keepling-known-limitations.XXXXXX")
if ! node tooling/generate-known-limitations.mjs --out "$known_limitations_check" >/dev/null; then
  rm -f "$known_limitations_check"
  echo "Governance: could not regenerate KNOWN-LIMITATIONS.md from .planning/WINDOWS.md" >&2
  exit 1
fi
if ! diff -q KNOWN-LIMITATIONS.md "$known_limitations_check" >/dev/null 2>&1; then
  rm -f "$known_limitations_check"
  echo "Governance: KNOWN-LIMITATIONS.md has diverged from what .planning/WINDOWS.md regenerates -- regenerate it" >&2
  exit 1
fi
rm -f "$known_limitations_check"
governance_assertions=$((governance_assertions + 1))

echo "Governance checks passed: $governance_assertions assertions performed."

