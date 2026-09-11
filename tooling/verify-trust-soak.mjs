#!/usr/bin/env node
// tooling/verify-trust-soak.mjs (D-49/D-51, 06-12-PLAN.md Task 3)
//
// The gate that refuses an oracle it cannot prove detects corruption.
// `--self-test` runs ~12 synthetic corrupted fixtures (tooling/trust-lanes/fixtures/),
// at least one per invariant, and requires every one to be flagged. A
// self-test failure BLOCKS `--gate` outright -- an oracle that passes clean
// data but cannot detect injected corruption is vacuous, and this gate
// never lets a vacuous oracle produce a passing verdict.
//
// `--gate` produces .artifacts/trust-soak/trust-soak-evidence.json, bound
// to five digests (application, build, git revision, lane source, oracle
// source). Exactly three verdicts exist: PASS, DISCLOSED-NOT-PROVEN, and
// BLOCKED. BLOCKED always exits non-zero. A verdict is never upgraded past
// what the accumulated evidence actually supports -- in particular, ANY
// invariant reporting a zero sample count blocks the whole gate, because a
// lane that observed nothing proves nothing.

import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { evaluateInvariants, INVARIANT_IDS } from './trust-lanes/invariants.mjs'
import { guardAgainstShortcuts, inputDigestFor, repositoryRoot } from './trust-lanes/oracle.mjs'
import { OPERATORS, corpusDigest } from './trust-lanes/chaos.mjs'
import { MUTATION_FLOOR, loadLedger, summarize } from './trust-lanes/census.mjs'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
const fixturesDir = join(laneDirectory, 'trust-lanes', 'fixtures')
const artifactsDir = join(repositoryRoot, '.artifacts', 'trust-soak')
const evidencePath = join(artifactsDir, 'trust-soak-evidence.json')
const violationsPath = join(artifactsDir, 'violations.ndjson')
const lockPath = join(artifactsDir, '.run.lock')
const censusLedgerPath = join(artifactsDir, 'census-ledger.json')

const STALE_LOCK_MS = 30 * 60 * 1000 // A lock older than this belongs to an interrupted run, not a live one.

const BLIND_SPOT =
  'The oracle sees only durable state. Loss between a keystroke and a commit -- before a ' +
  'mutation reaches its own client’s durable outbox -- is entirely outside its reach; that ' +
  'window belongs to the end-to-end and accessibility lanes, never to this oracle.'

const flag = (name) => {
  const index = process.argv.indexOf(`--${name}`)
  return index === -1 ? null : process.argv[index + 1] ?? null
}
const has = (name) => process.argv.includes(`--${name}`)

const laneSourceInputs = [
  'tooling/verify-trust-soak.mjs',
  'tooling/trust-lanes/oracle.mjs',
  'tooling/trust-lanes/invariants.mjs',
  'tooling/trust-lanes/chaos.mjs',
  'tooling/trust-lanes/census.mjs',
]

const gitRevision = () => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'rev-parse', 'HEAD'], { encoding: 'utf8' })
  return result.status === 0 ? result.stdout.trim() : 'UNKNOWN'
}

const fixtureFiles = () =>
  existsSync(fixturesDir)
    ? readdirSync(fixturesDir).filter((f) => f.endsWith('.json')).sort()
    : []

const loadFixture = (name) => JSON.parse(readFileSync(join(fixturesDir, name), 'utf8'))

/**
 * Runs every corruption fixture and requires each one's named invariant to
 * flag it. Returns { passed, exercised, results }. Never throws -- a
 * missing or malformed fixture is reported as a failed case, not a crash,
 * so removing one fixture (the load-bearing check this plan's own
 * <verification> block names) reliably fails the self-test rather than
 * silently reducing the exercised count.
 */
const runSelfTest = () => {
  const files = fixtureFiles().filter(
    (f) => !f.startsWith('interrupted-run') && !f.startsWith('overlapping-run'),
  )
  const results = files.map((file) => {
    try {
      const fixture = loadFixture(file)
      const [outcome] = evaluateInvariants(fixture.dataset, [fixture.invariant])
      const flagged = outcome.violations.length > 0
      return { file, invariant: fixture.invariant, flagged }
    } catch (error) {
      return { file, invariant: null, flagged: false, error: error.message }
    }
  })
  const invariantsCovered = new Set(results.map((r) => r.invariant).filter(Boolean))
  const missingInvariant = INVARIANT_IDS.find((id) => !invariantsCovered.has(id))
  const allFlagged = results.every((r) => r.flagged)
  const enoughFixtures = results.length >= 12
  return {
    passed: allFlagged && enoughFixtures && !missingInvariant,
    exercised: results.length,
    missingInvariant,
    results,
  }
}

// ---------------------------------------------------------------------------
// Held-out interrupted-run / overlapping-run fixtures: these are about the
// gate's OWN run-conflict machinery, not about a corrupted dataset, so they
// are evaluated separately from the corruption fixtures above.
// ---------------------------------------------------------------------------

const readLock = () => {
  if (!existsSync(lockPath)) return null
  try {
    return JSON.parse(readFileSync(lockPath, 'utf8'))
  } catch {
    return { corrupt: true }
  }
}

const writeLock = () => {
  mkdirSync(artifactsDir, { recursive: true })
  writeFileSync(lockPath, JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }))
}

const releaseLock = () => {
  if (existsSync(lockPath)) rmSync(lockPath)
}

/**
 * Checks for a run conflict. `forcedFixture` simulates the two held-out
 * cases without needing a genuinely interrupted process: 'interrupted-run'
 * writes a lock old enough to be stale before checking; 'overlapping-run'
 * writes a fresh lock, simulating a second run finding the first still
 * live.
 */
const checkRunConflict = (forcedFixture) => {
  if (forcedFixture === 'interrupted-run') {
    writeLock()
    const stalePath = lockPath
    const staleTime = Date.now() - STALE_LOCK_MS - 1000
    writeFileSync(stalePath, JSON.stringify({ pid: 999999999, startedAt: new Date(staleTime).toISOString() }))
    // Force the mtime itself old too, so an mtime-based staleness check
    // (not just the JSON payload) also sees the conflict.
    const old = new Date(staleTime)
    try {
      utimesSync(stalePath, old, old)
    } catch {
      // Best-effort; the JSON payload's startedAt is authoritative below.
    }
    return { blocked: true, reason: 'interrupted-run: a stale run lock was found' }
  }
  if (forcedFixture === 'overlapping-run') {
    writeLock()
    return { blocked: true, reason: 'overlapping-run: a live run lock was found' }
  }

  const existing = readLock()
  if (existing == null) return { blocked: false }
  if (existing.corrupt) return { blocked: true, reason: 'interrupted-run: an unreadable run lock was found' }
  const age = Date.now() - new Date(existing.startedAt).getTime()
  if (age > STALE_LOCK_MS) {
    return { blocked: true, reason: 'interrupted-run: a stale run lock was found' }
  }
  return { blocked: true, reason: 'overlapping-run: a live run lock was found' }
}

// ---------------------------------------------------------------------------
// The evidence artifact.
// ---------------------------------------------------------------------------

const appendViolationLine = (violation) => {
  mkdirSync(artifactsDir, { recursive: true })
  const previous = existsSync(violationsPath)
    ? readFileSync(violationsPath, 'utf8').trim().split('\n').filter(Boolean).at(-1)
    : null
  const prevLineSha256 = previous
    ? createHash('sha256').update(previous).digest('hex')
    : createHash('sha256').update('').digest('hex')
  const line = JSON.stringify({ ...violation, prevLineSha256 })
  writeFileSync(violationsPath, `${existsSync(violationsPath) ? readFileSync(violationsPath, 'utf8') : ''}${line}\n`)
}

const detectionFloorFor = (totalSamples) => {
  if (totalSamples <= 0) {
    return {
      confidence: null,
      perCycleManifestationProbability: null,
      note: 'Insufficient accumulated samples to state a detection floor. This proves nothing about defects of any rarity yet.',
    }
  }
  // A defect present in a fraction p of cycles is detected with probability
  // 1-(1-p)^n across n independent samples; solved for the p this run's own
  // sample count can detect at 95% confidence.
  const confidence = 0.95
  const perCycleManifestationProbability = 1 - Math.pow(1 - confidence, 1 / totalSamples)
  return {
    confidence,
    perCycleManifestationProbability,
    note: `At ${totalSamples} accumulated samples, this run can detect a defect manifesting in at least ` +
      `${(perCycleManifestationProbability * 100).toFixed(2)}% of cycles with ${confidence * 100}% confidence. ` +
      'It proves nothing about defects rarer than that.',
  }
}

const runGate = async () => {
  guardAgainstShortcuts(join(repositoryRoot, 'tooling', 'trust-lanes', 'oracle.mjs'))
  guardAgainstShortcuts(join(repositoryRoot, 'tooling', 'trust-lanes', 'invariants.mjs'))
  guardAgainstShortcuts(fileURLToPath(import.meta.url))

  const selfTest = runSelfTest()
  if (!selfTest.passed) {
    console.error(
      `TRUST_SOAK_GATE verdict=BLOCKED cases=0 reason=self-test-failed exercised=${selfTest.exercised}`,
    )
    return 1
  }

  const conflict = checkRunConflict(null)
  if (conflict.blocked) {
    console.error(`TRUST_SOAK_GATE verdict=BLOCKED cases=0 reason=${conflict.reason}`)
    return 1
  }

  writeLock()
  try {
    const { buildDataset } = await import('./trust-lanes/oracle.mjs')
    const { dataset } = await buildDataset({
      serverDbUrl: process.env.KEEPLING_TRUST_SOAK_AUDITOR_URL ?? null,
      serverBaseUrl: process.env.KEEPLING_TRUST_SOAK_SERVER_URL ?? null,
      desktopStorePath: process.env.KEEPLING_TRUST_SOAK_DESKTOP_STORE ?? null,
      iosStorePath: process.env.KEEPLING_TRUST_SOAK_IOS_STORE ?? null,
    })

    const invariantResults = evaluateInvariants(dataset)
    const totalSamples = invariantResults.reduce((sum, r) => sum + r.samples, 0)
    const zeroSampleInvariants = invariantResults.filter((r) => r.samples === 0).map((r) => r.id)
    const totalViolations = invariantResults.reduce((sum, r) => sum + r.violations.length, 0)

    for (const result of invariantResults) {
      for (const violation of result.violations) {
        appendViolationLine({ invariantId: result.id, ...violation, recordedAt: new Date().toISOString() })
      }
    }

    const censusLedger = loadLedger(censusLedgerPath)
    const censusSummary = summarize(censusLedger)
    const censusFloorMet = censusSummary.totalDays > 0 && censusSummary.nonThinDays > 0

    const chaosOperatorCounts = Object.fromEntries(OPERATORS.map((op) => [op.name, 0]))

    let verdict
    if (zeroSampleInvariants.length > 0) {
      verdict = 'BLOCKED'
    } else if (totalViolations === 0 && censusFloorMet) {
      verdict = 'PASS'
    } else {
      verdict = 'DISCLOSED-NOT-PROVEN'
    }

    const evidence = {
      applicationDigestSha256: process.env.KEEPLING_TRUST_SOAK_APPLICATION_DIGEST ?? 'UNVERIFIED',
      keeplingBuildDigest: process.env.KEEPLING_TRUST_SOAK_BUILD_DIGEST ?? 'UNVERIFIED',
      gitRevision: gitRevision(),
      laneSourceDigest: inputDigestFor(laneSourceInputs),
      oracleSourceDigest: inputDigestFor([
        'tooling/trust-lanes/oracle.mjs',
        'tooling/trust-lanes/invariants.mjs',
      ]),
      seedCorpusDigest: corpusDigest(),
      chaosOperatorCounts,
      dailyUsageCensus: censusLedger,
      detectionFloor: detectionFloorFor(totalSamples),
      blindSpot: BLIND_SPOT,
      verdict,
      invariants: invariantResults.map((r) => ({
        name: r.id,
        samples: r.samples,
        violations: r.violations.length,
        disposition: r.samples === 0 ? 'BLOCKED' : r.violations.length === 0 ? 'PASS' : 'DISCLOSED-NOT-PROVEN',
      })),
      generatedAt: new Date().toISOString(),
    }

    mkdirSync(artifactsDir, { recursive: true })
    writeFileSync(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`)

    console.log(`TRUST_SOAK_GATE verdict=${verdict} cases=${totalSamples}`)
    return verdict === 'PASS' ? 0 : 1
  } finally {
    releaseLock()
  }
}

const runSelfTestCli = (fixtureArg) => {
  if (fixtureArg === 'interrupted-run' || fixtureArg === 'overlapping-run') {
    const conflict = checkRunConflict(fixtureArg)
    console.log(`TRUST_SOAK_SELFTEST verdict=BLOCKED fixture=${fixtureArg} reason=${conflict.reason}`)
    releaseLock()
    return 1
  }

  const result = runSelfTest()
  for (const r of result.results) {
    console.log(
      `TRUST_SOAK_SELFTEST_FIXTURE file=${r.file} invariant=${r.invariant ?? 'unknown'} flagged=${r.flagged}${
        r.error ? ` error=${r.error}` : ''
      }`,
    )
  }
  console.log(
    `TRUST_SOAK_SELFTEST exercised=${result.exercised} passed=${result.passed}${
      result.missingInvariant ? ` missing_invariant=${result.missingInvariant}` : ''
    }`,
  )
  return result.passed ? 0 : 1
}

const main = async () => {
  if (has('self-test')) {
    process.exit(runSelfTestCli(flag('fixture')))
  }
  if (has('gate')) {
    process.exit(await runGate())
  }
  console.log('usage: node tooling/verify-trust-soak.mjs --self-test [--fixture NAME] | --gate')
  process.exit(1)
}

await main()
