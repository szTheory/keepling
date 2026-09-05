#!/usr/bin/env node
/**
 * D-45/D-46/D-24 (iOS): one fail-fast, anti-vacuous Phase 4 gate, structured
 * like tooling/verify-desktop-phase.mjs. Every lane reports a name, a
 * positive case count, a duration, and a tracked-input digest -- a lane
 * that cannot report a positive count is a FAILURE of the gate, never a
 * silently-skipped green.
 *
 * Lanes are discovered by globbing tooling/ios-lanes/*.mjs rather than
 * declared inline here, so a later plan in the same wave adds its lane by
 * adding a file, never by editing this runner (04-01-PLAN.md Task 2).
 *
 * `--requirements` checks the machine-readable requirement-to-lane map
 * (REQUIREMENT_LANES below) against the Phase 4 requirement ids read live
 * from .planning/REQUIREMENTS.md's Traceability table, and fails if any
 * requirement has no mapped lane or maps to a lane file that does not
 * exist (04-17-PLAN.md Task 1).
 *
 * A lane may report `BLOCKED` (never PASS, never silently absent) when it
 * genuinely cannot run for want of hardware, credentials, or a prior
 * plan's evidence -- e.g. the `device` lane before Plan 04-16's
 * device-install human-action checkpoint clears. BLOCKED still fails the
 * overall run (exit code stays non-zero) so this command can never report
 * green while required physical-device evidence is missing.
 */
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const lanesDir = join(repositoryRoot, 'tooling', 'ios-lanes')

const fail = (message) => {
  console.error(`iOS phase gate failed: ${message}`)
}

let anyFailed = false
const results = []

const gitLsFiles = (paths) => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'ls-files', '-z', ...paths], { encoding: 'utf8' })
  return result.stdout.split('\0').filter(Boolean).sort()
}

const inputDigestFor = (paths) => {
  const files = gitLsFiles(paths)
  const digest = createHash('sha256')
  for (const relativePath of files) {
    digest.update(`${relativePath}\0`)
    try {
      digest.update(readFileSync(join(repositoryRoot, relativePath)))
    } catch {
      // A tracked path that no longer exists on disk still contributes its
      // name to the digest -- it does not silently vanish from provenance.
    }
    digest.update('\0')
  }
  return digest.digest('hex').slice(0, 16)
}

/**
 * Runs one lane's command, then hands raw stdout/stderr to `parse` to
 * extract a positive case count. `parse` MUST throw or return a
 * non-positive count for output it cannot make sense of -- there is no
 * "assume it passed" fallback anywhere in this file. A lane file that fails
 * to LOAD is a runner failure, never a skipped lane (enforced by the loader
 * below, not here).
 */
const runLane = ({ command, args, cwd, env, name, parse, trackedInputPaths }) => {
  const startedAt = Date.now()
  const result = spawnSync(command, args, { cwd: cwd ?? repositoryRoot, encoding: 'utf8', env: { ...process.env, ...env } })
  const durationMs = Date.now() - startedAt
  const stdout = result.stdout ?? ''
  const stderr = result.stderr ?? ''
  const inputDigest = trackedInputPaths ? inputDigestFor(trackedInputPaths) : 'n/a'

  let cases = 0
  let parseError = null
  try {
    cases = parse(stdout, stderr, result.status)
  } catch (error) {
    parseError = error instanceof Error ? error.message : String(error)
  }

  const exitedCleanly = result.status === 0 && !result.error
  const passed = exitedCleanly && parseError === null && Number.isFinite(cases) && cases > 0

  // A parse error prefixed "BLOCKED:" is a genuine, disclosed inability to
  // run (missing hardware/credentials/prior-plan evidence -- e.g. the
  // `device` lane before Plan 04-16's device-install checkpoint clears) --
  // NEVER a silent skip and NEVER counted as a pass. It still fails the
  // gate (anyFailed stays true, exit code stays non-zero) so the aggregate
  // command cannot report green while required evidence is missing, but it
  // is labeled distinctly from an ordinary bug so a human reading the
  // output does not mistake "blocked on hardware" for "broken code"
  // (orchestrator note, 04-17-PLAN.md).
  const blocked = !passed && parseError !== null && parseError.startsWith('BLOCKED:')
  results.push({ blocked, cases, durationMs, inputDigest, name, passed })

  const statusWord = passed ? 'PASS' : blocked ? 'BLOCKED' : 'FAIL'
  console.log(`LANE name=${name} status=${statusWord} cases=${cases} duration_ms=${durationMs} input_digest=${inputDigest}`)
  if (!passed) {
    anyFailed = true
    if (blocked) fail(`${name}: ${parseError}`)
    else if (parseError) fail(`${name}: ${parseError}`)
    else if (!exitedCleanly) fail(`${name}: exited ${result.status ?? 'without status'}${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
    else fail(`${name}: reported zero cases`)
    console.error(`--- ${name} stdout tail ---`)
    console.error(stdout.trim().slice(-4000))
    console.error(`--- ${name} stderr tail ---`)
    console.error(stderr.trim().slice(-2000))
  }
}

/**
 * Parses xcodebuild's own test summary output. Throws on output it cannot
 * parse -- there is no assume-it-passed fallback (D-45's own rule, carried
 * to iOS).
 */
const xcodebuildSummary = (stdout) => {
  if (/\*\* TEST FAILED \*\*/.test(stdout)) throw new Error('xcodebuild reported TEST FAILED')
  if (!/\*\* TEST SUCCEEDED \*\*/.test(stdout)) throw new Error('xcodebuild summary line "** TEST SUCCEEDED **" not found')
  // A disclosed skip (04-06/04-08) changes xcodebuild's own summary wording
  // to "Executed N tests, with K test(s) skipped and M failures" -- the
  // optional non-capturing group below tolerates that wording without
  // treating a skip as a reason to disregard the real executed-test total
  // (04-08-PLAN.md Task 3's `KEEPLING_TEST_SERVER_URL`-gated real-stack
  // test is the first lane whose ONLY test class carries a skip, so no
  // earlier non-skipped class summary line was available to accidentally
  // satisfy the old, stricter pattern).
  const executed = stdout.match(/Executed (\d+) tests?,\s*with(?:\s+\d+\s+tests?\s+skipped\s+and)?\s*(\d+) failures?/)
  if (!executed) throw new Error('xcodebuild "Executed N tests" summary not found')
  const total = Number(executed[1])
  const failures = Number(executed[2])
  if (failures > 0) throw new Error(`xcodebuild reported ${failures} failing test(s)`)
  if (total === 0) throw new Error('xcodebuild executed zero tests')
  return total
}

/**
 * The requirement-to-lane map (04-17-PLAN.md Task 1). Every phase
 * requirement this plan owns -- IOS-01..04 and the SRV-02 iPhone adapter
 * proof -- must map to at least one existing lane file, checked below by
 * `--requirements` rather than merely described in prose. `device` is
 * listed everywhere the underlying truth genuinely depends on physical
 * hardware (D-22's full daily loop, offline/relaunch reconciliation, the
 * physical-device state disambiguation, and the SRV-02 iPhone adapter
 * proof itself) -- it stays in the map, and in the gate's normal run, even
 * while it is BLOCKED, so the requirement is never quietly reported as
 * proven by simulator lanes alone (orchestrator note, 04-17-PLAN.md).
 */
const REQUIREMENT_LANES = {
  'IOS-01': ['core-loop', 'undo', 'tracer-e2e', 'device'],
  'IOS-02': ['storage', 'storage-gates', 'sync-pass', 'durability-posture', 'device'],
  'IOS-03': ['accessibility', 'state-matrix', 'design-tokens'],
  'IOS-04': ['sync-presentation', 'auth', 'state-matrix', 'device'],
  'SRV-02': ['transport', 'vector-conformance', 'sync-pass', 'device'],
}

/**
 * Reads this phase's requirement ids straight from the Phase 4 row of
 * `.planning/REQUIREMENTS.md`'s Traceability table, rather than
 * hard-coding them, so a requirement later added to that row without a
 * lane fails `--requirements` instead of silently passing.
 */
const phase4RequirementIds = () => {
  const requirementsPath = join(repositoryRoot, '.planning', 'REQUIREMENTS.md')
  const text = readFileSync(requirementsPath, 'utf8')
  const row = text.split('\n').find((line) => line.includes('| Phase 4 |') && line.includes('IOS'))
  if (!row) throw new Error('no Phase 4 row found in .planning/REQUIREMENTS.md Traceability table')
  const ids = new Set()
  for (const match of row.matchAll(/([A-Z]+)-(\d+)\.\.(\d+)/g)) {
    const [, prefix, start, end] = match
    for (let n = Number(start); n <= Number(end); n += 1) ids.add(`${prefix}-${String(n).padStart(2, '0')}`)
  }
  for (const match of row.matchAll(/\b([A-Z]+-\d+)\b/g)) {
    if (!/\.\.$/.test(row.slice(0, match.index))) ids.add(match[1])
  }
  if (ids.size === 0) throw new Error('Phase 4 row named no requirement ids')
  return [...ids].sort()
}

const requestedLane = (() => {
  const flagIndex = process.argv.indexOf('--lane')
  return flagIndex === -1 ? null : process.argv[flagIndex + 1]
})()

const requirementsMode = process.argv.includes('--requirements')

let laneFiles
try {
  laneFiles = readdirSync(lanesDir)
    .filter((entry) => entry.endsWith('.mjs'))
    .sort()
} catch (error) {
  console.error(`iOS phase gate failed: could not read lane directory ${lanesDir}: ${String(error)}`)
  process.exit(1)
}

if (laneFiles.length === 0) {
  console.error('iOS phase gate failed: tooling/ios-lanes/ contains no lane files')
  process.exit(1)
}

if (requirementsMode) {
  let ids
  try {
    ids = phase4RequirementIds()
  } catch (error) {
    console.error(`iOS phase gate failed: ${String(error.message ?? error)}`)
    process.exit(1)
  }
  let unmapped = false
  for (const id of ids) {
    const lanes = REQUIREMENT_LANES[id]
    if (!lanes || lanes.length === 0) {
      console.error(`iOS phase gate failed: requirement ${id} has no mapped lane in REQUIREMENT_LANES`)
      unmapped = true
      continue
    }
    const missingLanes = lanes.filter((lane) => !laneFiles.includes(`${lane}.mjs`))
    if (missingLanes.length > 0) {
      console.error(`iOS phase gate failed: requirement ${id} maps to lane(s) with no definition file: ${missingLanes.join(', ')}`)
      unmapped = true
      continue
    }
    console.log(`REQUIREMENT id=${id} lanes=${lanes.join(',')}`)
  }
  const unmappedDefinedLanes = Object.keys(REQUIREMENT_LANES).filter((id) => !ids.includes(id))
  if (unmappedDefinedLanes.length > 0) {
    console.error(`iOS phase gate failed: REQUIREMENT_LANES declares id(s) absent from the Phase 4 row: ${unmappedDefinedLanes.join(', ')}`)
    unmapped = true
  }
  if (unmapped) {
    console.error('iOS requirement map: FAILED')
    process.exit(1)
  }
  console.log(`iOS requirement map: ${ids.length} requirement(s) all mapped to existing lanes`)
  process.exit(0)
}

for (const file of laneFiles) {
  const laneName = file.replace(/\.mjs$/, '')
  if (requestedLane !== null && requestedLane !== laneName) continue
  let laneModule
  try {
    // eslint-disable-next-line no-await-in-loop
    laneModule = await import(join(lanesDir, file))
  } catch (error) {
    // A lane file that fails to load is a RUNNER failure, never a skipped
    // lane (04-01-PLAN.md Task 2 acceptance criterion).
    console.error(`iOS phase gate failed: lane file ${file} failed to load: ${String(error)}`)
    process.exit(1)
  }
  if (typeof laneModule.default !== 'function') {
    console.error(`iOS phase gate failed: lane file ${file} has no default export function`)
    process.exit(1)
  }
  const definition = laneModule.default({ repositoryRoot, xcodebuildSummary })
  runLane(definition)
}

if (requestedLane !== null && results.length === 0) {
  console.error(`iOS phase gate failed: requested lane "${requestedLane}" was not found in ${lanesDir}`)
  process.exit(1)
}

const blockedCount = results.filter((r) => r.blocked).length
console.log('')
console.log(`iOS phase gate summary: lanes=${results.length} failed=${results.filter((r) => !r.passed).length} blocked=${blockedCount}`)
for (const result of results) {
  const word = result.passed ? 'PASS' : result.blocked ? 'BLOCKED' : 'FAIL'
  console.log(`  ${word} ${result.name} cases=${result.cases} duration_ms=${result.durationMs}`)
}

if (blockedCount > 0) {
  console.error('')
  console.error(
    `iOS phase gate: BLOCKED (${blockedCount} lane(s) cannot run yet -- see BLOCKED lines above). This is not a code defect; ` +
      'it is disclosed, genuine missing evidence (hardware/credentials/prior-plan checkpoint). The gate refuses to report ' +
      'success while it is missing, per D-24 and the anti-vacuity contract.',
  )
}

if (anyFailed) {
  console.error('iOS phase gate: FAILED')
  process.exit(1)
}
console.log('iOS phase gate: PASSED')
