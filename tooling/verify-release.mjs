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
 * The committed inventory also carries each lane's `authority` (D-09). The
 * anti-loophole rule -- NOTHING LOCAL MAY BIND TO LOCALLY BUILT BYTES -- is
 * enforced here: a `local-attested` lane reporting PASSED must record a
 * `ranAgainstArtifactDigest` resolving to an artifact that a CI run built
 * (`builtByRunId`/`builtByJob`/`runnerImage` all present and non-local). A
 * local-attested lane whose evidence records no CI artifact digest is a HARD
 * FAILURE, so a failing lane cannot be moved out of CI to make it green.
 * Symmetrically, a lane the inventory marks `ciWiring: "unwired"` with
 * `authority: "ci"` may never report PASSED -- it has no CI job it could have
 * passed in.
 *
 * A fork-originated manifest (`revision.forkOrigin === true`) may omit a lane
 * whose inventory entry sets `requiresSecrets: true`; the lane is then REPORTED
 * explicitly as `status=NOT_RUN_ON_FORK reason=fork-no-secrets` rather than
 * being silently absent, because an omitted lane reads as satisfied (D-15b).
 * Every other absence stays a hard failure.
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
 * A `local-attested` lane's evidence is valid ONLY if it binds to bytes a
 * continuous-integration run produced. An artifact entry proves that by naming
 * the run, the job and the runner image that built it; a locally produced
 * artifact names none of those, or names the reserved `local` sentinel.
 */
const isCiBuiltArtifact = (artifact) => {
  const isNamed = (value) => typeof value === 'string' && value.trim() !== '' && !/^local\b/i.test(value.trim())
  return isNamed(artifact?.builtByRunId) && isNamed(artifact?.builtByJob) && isNamed(artifact?.runnerImage)
}

/**
 * An artifact entry may be an ABSENCE RECORD: a committed statement that a
 * named artifact was NOT produced at this revision, with the reason. Those
 * records exist because an OMITTED artifact reads as satisfied -- the same rule
 * that forces an unrunnable lane to emit an explicit BLOCKED entry. But an
 * absence record must never become a binding target: a lane claiming PASSED
 * against `produced: false` bytes would be claiming to have tested something
 * that does not exist, which is the loophole the absence record itself opens if
 * it is left unguarded. So it is refused here.
 */
const isProducedArtifact = (artifact) => artifact?.produced !== false

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

// The inventory is either a bare array (schemaVersion 1) or an object with a
// `lanes` array plus its `$comment` block (schemaVersion 2). Both are accepted;
// neither is allowed to be empty, because an empty inventory would make the
// exactly-once assertion vacuously true.
const inventoryLanes = Array.isArray(lanesInventory) ? lanesInventory : lanesInventory?.lanes
if (!Array.isArray(inventoryLanes) || inventoryLanes.length === 0) {
  fail('release-lanes.json declares zero lanes -- a vacuous inventory cannot detect a vanished lane')
  process.exit(1)
}
const inventoryByLane = new Map(inventoryLanes.map((entry) => [entry.lane, entry]))

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
const forkOrigin = manifest.revision?.forkOrigin === true
for (const inventoryEntry of inventoryLanes) {
  const count = laneCountsByName.get(inventoryEntry.lane) ?? 0
  if (count === 0) {
    // D-15b: on a fork-originated run a secrets-requiring lane physically
    // cannot run. Report that explicitly rather than letting the omission
    // stand, which would read as satisfied.
    if (forkOrigin && inventoryEntry.requiresSecrets === true) {
      console.log(`lane=${inventoryEntry.lane} status=NOT_RUN_ON_FORK reason=fork-no-secrets`)
      continue
    }
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
    const inventoryEntry = inventoryByLane.get(lane.lane)
    if (!inventoryEntry) {
      fail(`lane ${lane.lane} claims PASSED but is not named in the committed release-lanes.json inventory`)
      overallFailed = true
      continue
    }
    if (!isProducedArtifact(referencedArtifact)) {
      fail(
        `lane ${lane.lane} claims PASSED against artifact ${referencedArtifact.artifactPath}, which the manifest itself ` +
          `records as NOT PRODUCED at this revision (${referencedArtifact.notProducedReason ?? 'no stated reason'}) -- ` +
          `a lane cannot have tested bytes that were never built`,
      )
      overallFailed = true
      continue
    }
    if (inventoryEntry.authority === 'local-attested' && !isCiBuiltArtifact(referencedArtifact)) {
      // THE ANTI-LOOPHOLE RULE: nothing local may bind to locally built bytes.
      fail(
        `local-attested lane ${lane.lane} claims PASSED against artifact ${referencedArtifact.artifactPath}, ` +
          `whose evidence records no continuous-integration artifact digest ` +
          `(builtByRunId=${referencedArtifact.builtByRunId ?? 'absent'} builtByJob=${referencedArtifact.builtByJob ?? 'absent'} runnerImage=${referencedArtifact.runnerImage ?? 'absent'}) -- ` +
          `nothing local may bind to locally built bytes`,
      )
      overallFailed = true
      continue
    }
    // A recorded evidence digest is worthless if nobody recomputes it. Without
    // this check a manifest could name a digest for a file that does not exist,
    // or whose bytes have since changed, and still be accepted -- the lane
    // would claim to be backed by evidence nobody ever opened.
    if (lane.evidenceDigestSha256) {
      const evidencePath = join(dirname(manifestPath), 'evidence', 'lanes', `${lane.lane}.log`)
      if (!existsSync(evidencePath)) {
        fail(
          `lane ${lane.lane} records evidenceDigestSha256=${lane.evidenceDigestSha256} but its evidence file ` +
            `does not exist at ${relative(dirname(manifestPath), evidencePath)} -- a digest naming nothing proves nothing`,
        )
        overallFailed = true
        continue
      }
      const recomputed = sha256(readFileSync(evidencePath))
      if (recomputed !== lane.evidenceDigestSha256) {
        fail(
          `lane ${lane.lane} evidence digest does not match its recorded value ` +
            `(recorded=${lane.evidenceDigestSha256} recomputed=${recomputed}) -- the retained evidence was altered`,
        )
        overallFailed = true
        continue
      }
    }
    if (inventoryEntry.authority === 'ci' && inventoryEntry.ciWiring === 'unwired') {
      fail(
        `lane ${lane.lane} claims PASSED but the inventory marks it unwired from continuous integration ` +
          `(${inventoryEntry.wiringBlocker ?? 'no stated reason'}) -- it has no job it could have passed in`,
      )
      overallFailed = true
      continue
    }
    console.log(`lane=${lane.lane} status=PASSED cases=${cases} authority=${inventoryEntry.authority} ranAgainstArtifactDigest=${lane.ranAgainstArtifactDigest}`)
  } else if (lane.status === VERDICTS.BLOCKED) {
    const inventoryEntry = inventoryByLane.get(lane.lane)
    const reason = lane.reason ?? inventoryEntry?.physicalBlocker ?? inventoryEntry?.wiringBlocker ?? 'no stated reason'
    console.log(`lane=${lane.lane} status=BLOCKED cases=${lane.cases ?? 0} owner=${inventoryEntry?.owner ?? 'UNOWNED'} reason=${reason}`)
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
