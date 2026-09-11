#!/usr/bin/env node
/**
 * tooling/verify-release.mjs (06-02-PLAN.md Task 1, D-09/D-13/D-15d)
 *
 * One command proves a named revision's artifacts and evidence lanes are
 * the ones actually tested -- a release claim a third party can check
 * instead of a claim only the maintainer can vouch for.
 * `node tooling/verify-release.mjs --manifest <path> [--offline]` takes a
 * single `release-manifest.json`, recomputes every present artifact's
 * digest from the bytes on disk (never trusting the manifest's own claim),
 * asserts every lane named in the committed `tooling/release-lanes.json`
 * inventory appears in the manifest exactly once, and asserts every PASSED
 * lane reports a positive case count and a `ranAgainstArtifactDigest` that
 * resolves to a real, present, re-hashed artifact entry.
 *
 * Verdict vocabulary:
 *   PASSED           -- the lane ran, reported a positive case count, and
 *                        its `ranAgainstArtifactDigest` matches a present,
 *                        re-hashed artifact.
 *   BLOCKED          -- the lane genuinely could not run (credentials,
 *                        hardware, a prior plan's evidence). Recorded
 *                        explicitly, never omitted, and keeps the overall
 *                        exit code non-zero.
 *   NOT_RUN_ON_FORK  -- the lane requires repository secrets unavailable to
 *                        a fork-originated run. Recorded explicitly so an
 *                        omitted job never reads as satisfied.
 *   INCOMPLETE       -- a lane's referenced artifact is missing from
 *                        `artifacts[]`, or an artifact present in the
 *                        manifest is missing on disk. Non-zero.
 *
 * A lane that vanished from a manifest is a hard failure, not a pass; a
 * missing artifact yields INCOMPLETE, never a pass. This command runs
 * fully offline against a committed bundle -- `--offline` (or an
 * unreachable network) degrades ONLY the attestation half of the claim to
 * `attestation=UNVERIFIED`, printed loudly, never a silent pass and never a
 * hard failure: a GitHub outage must cost the provenance half of the claim,
 * not the ability to state it at all (D-15d).
 */
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, readFileSync, readdirSync, readlinkSync } from 'node:fs'
import { basename, dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(laneDirectory, '..')

// Guard-refusal: this lane's own inventory and script must be present and
// their own tracked-input digest reported, so a shortcut injected into
// either file cannot hide from the report it produces about itself.
const GUARDED_FILES = [
  join(repositoryRoot, 'tooling', 'verify-release.mjs'),
  join(repositoryRoot, 'tooling', 'release-lanes.json'),
]

const TRACKED_INPUT_PATHS = ['tooling/verify-release.mjs', 'tooling/release-lanes.json']

const VERDICTS = Object.freeze({
  PASSED: 'PASSED',
  BLOCKED: 'BLOCKED',
  NOT_RUN_ON_FORK: 'NOT_RUN_ON_FORK',
  INCOMPLETE: 'INCOMPLETE',
})

const fail = (message) => {
  console.error(`verify-release failed: ${message}`)
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')

/**
 * Recomputes a digest over an artifact path, reusing the exact rule
 * `tooling/package-desktop.mjs`'s `hashDirectory` uses for a directory
 * (relative path, NUL, octal mode, NUL, contents) so a mode-losing
 * transport is detectable here the same way it is there. A single-file
 * artifact is treated as a one-entry directory listing under the same
 * rule.
 */
const hashArtifact = (root) => {
  const digest = createHash('sha256')
  const rootStat = lstatSync(root)
  if (rootStat.isDirectory()) {
    const visit = (directory) => {
      for (const entry of readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
        const path = join(directory, entry.name)
        const relativePath = relative(root, path)
        const metadata = lstatSync(path)
        digest.update(`${relativePath}\0${metadata.mode.toString(8)}\0`)
        if (entry.isDirectory()) visit(path)
        else if (entry.isSymbolicLink()) digest.update(`link\0${readlinkSync(path)}\0`)
        else digest.update(readFileSync(path))
      }
    }
    visit(root)
  } else {
    digest.update(`${basename(root)}\0${rootStat.mode.toString(8)}\0`)
    digest.update(readFileSync(root))
  }
  return digest.digest('hex')
}

/**
 * Attestation verification is a best-effort provenance check that is NEVER
 * allowed to hard-fail the run: a GitHub outage or explicit `--offline`
 * degrades to `attestation=UNVERIFIED`, printed loudly, so the release
 * claim can still be stated with the provenance half disclosed as missing.
 */
const verifyAttestation = (artifact, offline) => {
  if (offline) {
    console.log(`attestation=UNVERIFIED artifact=${artifact.artifactPath} reason=offline-flag`)
    return 'UNVERIFIED'
  }
  let result
  try {
    result = spawnSync('gh', ['attestation', 'verify', artifact.artifactPath, '--owner', 'szTheory'], {
      encoding: 'utf8',
      timeout: 10_000,
    })
  } catch (error) {
    console.log(`attestation=UNVERIFIED artifact=${artifact.artifactPath} reason=${error instanceof Error ? error.message : String(error)}`)
    return 'UNVERIFIED'
  }
  if (!result || result.error || result.status !== 0) {
    console.log(`attestation=UNVERIFIED artifact=${artifact.artifactPath} reason=network-or-tool-unavailable`)
    return 'UNVERIFIED'
  }
  console.log(`attestation=VERIFIED artifact=${artifact.artifactPath}`)
  return 'VERIFIED'
}

const args = process.argv.slice(2)
const manifestFlagIndex = args.indexOf('--manifest')
if (manifestFlagIndex === -1 || !args[manifestFlagIndex + 1]) {
  fail('--manifest <path> is required')
  process.exit(2)
}
const manifestPath = resolve(args[manifestFlagIndex + 1])
const offline = args.includes('--offline')

for (const guardedPath of GUARDED_FILES) {
  if (!existsSync(guardedPath)) {
    fail(`guarded file missing: ${guardedPath}`)
    process.exit(1)
  }
}
const trackedInputDigest = createHash('sha256')
for (const relativePath of TRACKED_INPUT_PATHS) {
  trackedInputDigest.update(`${relativePath}\0`)
  trackedInputDigest.update(readFileSync(join(repositoryRoot, relativePath)))
  trackedInputDigest.update('\0')
}
console.log(`verify-release tracked_input_sha256=${trackedInputDigest.digest('hex')}`)

let manifest
try {
  manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
} catch (error) {
  fail(`manifest at ${manifestPath} is missing or invalid JSON: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}

let lanesInventory
try {
  lanesInventory = JSON.parse(readFileSync(join(repositoryRoot, 'tooling', 'release-lanes.json'), 'utf8'))
} catch (error) {
  fail(`release-lanes.json is missing or invalid JSON: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}

let overallFailed = false
let overallVerdict = VERDICTS.PASSED

const artifacts = Array.isArray(manifest.artifacts) ? manifest.artifacts : []
if (artifacts.length === 0) {
  fail('manifest declares zero artifacts -- a vacuous manifest is refused, never a pass')
  process.exit(1)
}

// (1) Attestation -- degrades loudly, never hard-fails.
for (const artifact of artifacts) {
  verifyAttestation(artifact, offline)
}

// (2) Recompute every present artifact's digest from bytes on disk.
const presentArtifactDigests = new Map() // manifest-declared digestSha256 -> artifact entry
for (const artifact of artifacts) {
  const artifactAbsolutePath = resolve(repositoryRoot, artifact.artifactPath)
  if (!existsSync(artifactAbsolutePath)) {
    fail(`artifact missing on disk: ${artifact.artifactPath}`)
    overallFailed = true
    overallVerdict = VERDICTS.INCOMPLETE
    continue
  }
  const recomputed = hashArtifact(artifactAbsolutePath)
  if (recomputed !== artifact.digestSha256) {
    fail(`digest mismatch for ${artifact.artifactPath}: manifest=${artifact.digestSha256} recomputed=${recomputed}`)
    overallFailed = true
    continue
  }
  presentArtifactDigests.set(artifact.digestSha256, artifact)
}

// (3) Exact-set comparison: every lane in the committed inventory must
// appear in the manifest exactly once. A vanished lane is a hard failure,
// never a pass.
const manifestLanes = Array.isArray(manifest.lanes) ? manifest.lanes : []
const laneCountsByName = new Map()
for (const lane of manifestLanes) {
  laneCountsByName.set(lane.lane, (laneCountsByName.get(lane.lane) ?? 0) + 1)
}
for (const inventoryEntry of lanesInventory) {
  const count = laneCountsByName.get(inventoryEntry.lane) ?? 0
  if (count === 0) {
    fail(`lane vanished from manifest: ${inventoryEntry.lane}`)
    overallFailed = true
  } else if (count > 1) {
    fail(`lane ${inventoryEntry.lane} appears ${count} times in manifest -- must appear exactly once`)
    overallFailed = true
  }
}

// (4)/(5) Per-lane verdict handling.
for (const lane of manifestLanes) {
  if (lane.status === VERDICTS.PASSED) {
    const cases = lane.cases
    if (!Number.isInteger(cases) || cases <= 0) {
      fail(`lane ${lane.lane} claims PASSED with non-positive cases=${cases}`)
      overallFailed = true
      continue
    }
    const referencedArtifact = presentArtifactDigests.get(lane.ranAgainstArtifactDigest)
    if (!referencedArtifact) {
      fail(`lane ${lane.lane} claims PASSED against artifact digest ${lane.ranAgainstArtifactDigest}, which is not a present artifact`)
      overallFailed = true
      continue
    }
    console.log(`lane=${lane.lane} status=PASSED cases=${cases} ranAgainstArtifactDigest=${lane.ranAgainstArtifactDigest}`)
  } else if (lane.status === VERDICTS.BLOCKED) {
    fail(`lane ${lane.lane} reports BLOCKED`)
    overallFailed = true
  } else if (lane.status === VERDICTS.NOT_RUN_ON_FORK) {
    console.log(`lane=${lane.lane} status=NOT_RUN_ON_FORK`)
  } else if (lane.status === VERDICTS.INCOMPLETE) {
    fail(`lane ${lane.lane} reports INCOMPLETE`)
    overallFailed = true
  } else {
    fail(`lane ${lane.lane} reports unknown status ${lane.status}`)
    overallFailed = true
  }
}

if (overallFailed) {
  fail(`revision ${manifest.revision?.sha ?? 'unknown'} verification did not pass (${overallVerdict})`)
  process.exit(1)
}

console.log(`verify-release PASSED revision=${manifest.revision?.sha ?? 'unknown'} artifacts=${artifacts.length} lanes=${manifestLanes.length}`)
process.exit(0)
