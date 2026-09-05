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
  results.push({ cases, durationMs, inputDigest, name, passed })

  const statusWord = passed ? 'PASS' : 'FAIL'
  console.log(`LANE name=${name} status=${statusWord} cases=${cases} duration_ms=${durationMs} input_digest=${inputDigest}`)
  if (!passed) {
    anyFailed = true
    if (parseError) fail(`${name}: ${parseError}`)
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

const requestedLane = (() => {
  const flagIndex = process.argv.indexOf('--lane')
  return flagIndex === -1 ? null : process.argv[flagIndex + 1]
})()

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

console.log('')
console.log(`iOS phase gate summary: lanes=${results.length} failed=${results.filter((r) => !r.passed).length}`)
for (const result of results) {
  console.log(`  ${result.passed ? 'PASS' : 'FAIL'} ${result.name} cases=${result.cases} duration_ms=${result.durationMs}`)
}

if (anyFailed) {
  console.error('iOS phase gate: FAILED')
  process.exit(1)
}
console.log('iOS phase gate: PASSED')
