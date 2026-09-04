#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

/**
 * D-45/D-46: one fail-fast, anti-vacuous Phase 3 gate. Every lane below
 * reports a name, a positive case count, a duration, and an input digest
 * (and a seed where the lane has one) -- a lane that cannot report a
 * positive count is a FAILURE of the gate, never a silently-skipped green.
 *
 * D-48: every named adversarial category also has exactly one declared
 * owning fixture, checked to actually exist (by name, inside its file)
 * rather than merely asserted in prose -- a renamed/deleted fixture fails
 * this gate the same way a missing lane does.
 */

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')

const fail = (message) => {
  console.error(`Desktop phase gate failed: ${message}`)
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
      // A path in the tracked-input set that no longer exists on disk still
      // contributes its name to the digest -- it does not silently vanish
      // from provenance.
    }
    digest.update('\0')
  }
  return digest.digest('hex').slice(0, 16)
}

/**
 * Runs one lane's command, then hands raw stdout/stderr to `parse` to
 * extract a positive case count. `parse` MUST throw or return a
 * non-positive count for output it cannot make sense of -- there is no
 * "assume it passed" fallback anywhere in this file.
 */
const runLane = ({ command, args, cwd, env, name, parse, seed, trackedInputPaths }) => {
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
  results.push({ cases, durationMs, inputDigest, name, passed, seed: seed ?? 'n/a' })

  const statusWord = passed ? 'PASS' : 'FAIL'
  console.log(
    `LANE name=${name} status=${statusWord} cases=${cases} duration_ms=${durationMs} input_digest=${inputDigest} seed=${seed ?? 'n/a'}`,
  )
  if (!passed) {
    anyFailed = true
    if (parseError) fail(`${name}: ${parseError}`)
    else if (!exitedCleanly) fail(`${name}: exited ${result.status ?? 'without status'}${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
    else fail(`${name}: reported zero cases`)
    // Surface tail output for a failed lane so a CI log is actionable
    // without re-running locally.
    console.error(`--- ${name} stdout tail ---`)
    console.error(stdout.trim().slice(-4000))
    console.error(`--- ${name} stderr tail ---`)
    console.error(stderr.trim().slice(-2000))
  }
}

const vitestSummary = (stdout) => {
  const match = stdout.match(/Tests\s+(\d+)\s+passed/)
  if (!match) throw new Error('vitest summary line not found')
  const failedMatch = stdout.match(/(\d+)\s+failed/)
  if (failedMatch) throw new Error(`vitest reported ${failedMatch[1]} failing test(s)`)
  return Number(match[1])
}

const playwrightSummary = (stdout) => {
  const passedMatch = stdout.match(/(\d+) passed/)
  const failedMatch = stdout.match(/(\d+) failed/)
  if (failedMatch) throw new Error(`playwright reported ${failedMatch[1]} failing test(s)`)
  if (!passedMatch) throw new Error('playwright pass summary not found')
  return Number(passedMatch[1])
}

const tscClean = (stdout, stderr, status) => {
  if (status !== 0) throw new Error('tsc reported errors')
  return 1
}

// ---------------------------------------------------------------------------
// Lane registry (D-45/D-46). contracts:check and the Phase 2 reference-model
// test run OUTSIDE this file (see this plan's own <verify> command) -- they
// are proven, existing lanes this file deliberately does not reinvent.
// ---------------------------------------------------------------------------

runLane({
  args: ['typecheck:desktop'],
  command: 'pnpm',
  name: 'typecheck-desktop',
  parse: tscClean,
  trackedInputPaths: ['apps/desktop/main', 'apps/desktop/preload', 'apps/desktop/renderer', 'apps/desktop/store-worker', 'apps/desktop/tsconfig.json'],
})

runLane({
  args: ['typecheck:web'],
  command: 'pnpm',
  name: 'typecheck-web',
  parse: tscClean,
  trackedInputPaths: ['apps/web/src', 'packages/web-ui/src'],
})

runLane({
  args: ['test:desktop'],
  command: 'pnpm',
  name: 'unit-pure-vector-store-worker-performance',
  parse: vitestSummary,
  trackedInputPaths: [
    'apps/desktop/test/application',
    'apps/desktop/test/renderer',
    'apps/desktop/test/store',
    'apps/desktop/test/worker',
    'apps/desktop/test/performance',
    'apps/desktop/main',
    'apps/desktop/store-worker',
  ],
})

runLane({
  args: ['test:desktop:ipc'],
  command: 'pnpm',
  name: 'ipc-hostile-bridge',
  parse: vitestSummary,
  trackedInputPaths: ['apps/desktop/test/ipc', 'apps/desktop/preload', 'apps/desktop/main/protocol.ts'],
})

/**
 * Both Playwright lanes run WINDOWED here, forced -- never inheriting the
 * developer's value.
 *
 * `apps/desktop/playwright.config.ts` defaults to headless so a tight local
 * loop does not seize the screen, and excludes the `@windowed` specs (real
 * focus, window ordering, visibility) because headless cannot honestly assert
 * them. This gate is the one place that coverage still happens: there is no
 * git remote, so CI has never run and never will.
 *
 * Inheriting the variable here would mean the `@windowed` specs run NOWHERE,
 * and their absence would be silent -- the gate would report a green
 * `electron-e2e` lane having never opened a window. That is exactly the
 * vacuity class this phase has spent its time removing. Force the value.
 */
runLane({
  args: ['test:desktop:e2e'],
  command: 'pnpm',
  env: { KEEPLING_TEST_HEADLESS: '0' },
  name: 'electron-e2e',
  parse: playwrightSummary,
  trackedInputPaths: ['apps/desktop/test/e2e', 'apps/desktop/main', 'apps/desktop/preload', 'apps/desktop/renderer'],
})

runLane({
  args: ['package:desktop'],
  command: 'pnpm',
  name: 'package-once',
  parse: (stdout) => (stdout.includes('Desktop package manifest:') ? 1 : 0),
  trackedInputPaths: ['apps/desktop', 'tooling/package-desktop.mjs'],
})

runLane({
  args: ['smoke:desktop:packaged'],
  command: 'pnpm',
  env: { KEEPLING_TEST_HEADLESS: '0' },
  name: 'packaged',
  parse: playwrightSummary,
  trackedInputPaths: ['apps/desktop/test/packaged', 'tooling/smoke-desktop-packaged.mjs'],
})

/**
 * O-34/O-37/D-49: the PACKAGED artifact against a REAL Phoenix server on
 * REAL PostgreSQL, through the same harness the web lane proves against.
 *
 * Every other lane above fakes its transport, and for a long time so did a
 * spec literally named `real-stack-sync`. The first run of this lane found
 * three genuine client/server disagreements that no amount of fixture
 * testing had surfaced, which is the argument for it existing at all.
 *
 * Its runner enforces the anti-vacuity rules that a name cannot:
 * `KEEPLING_TEST_SYNC_MODE` unset in both the spec and the environment, no
 * stubbed `fetch`, no `.invalid` host, the shared backend harness actually
 * imported, and three evidence lines: `REAL_STACK_SYNC` (a positive
 * settled-mutation count and a proven exact-bytes retry), `REAL_STACK_MUTATIONS`
 * (every one of the eight command types a person can perform ARRIVING at the
 * real server, O-41), `REAL_STACK_CONFLICT` (capture-before-edit ordering
 * on the wire, plus a conflict raised by the REAL server refusing a REAL
 * second writer, O-38), and `REAL_STACK_UNDO` (a REAL server-issued undo
 * capability, an offline undo surviving a real quit and relaunch, the real
 * server's own state reversed, and a loud refusal when no handle was ever
 * issued, O-45). A green run that settled nothing, or that only ever
 * captured, or that never heard a conflict, or whose undo reconciled
 * nothing, fails here.
 *
 * Runs HEADLESS, unlike the two Playwright lanes above. Those are forced
 * windowed because their assertions are about real presentation --
 * visibility, focus, window ordering. This lane asserts none of that: its
 * claims are about bytes on a socket and rows in PostgreSQL, so a window on
 * screen would add cost and prove nothing.
 *
 * If PostgreSQL or Phoenix cannot start, this lane FAILS loudly with the
 * real error. It is never skipped, and it never degrades to a fake.
 */
runLane({
  args: ['tooling/verify-real-stack-desktop.mjs'],
  command: 'node',
  name: 'real-stack-sync',
  parse: (stdout) => {
    const summary = stdout.match(
      /Desktop real-stack lane passed: cases=(\d+) synced=(\d+) exact_bytes=(\d+) outcomes=(\S+) server_origin=(\S+) command_types=(\d+) conflicts=(\d+) undo=(\d+)/,
    )
    if (!summary) throw new Error('real-stack lane summary line not found')
    if (Number(summary[2]) <= 0) throw new Error('real-stack lane settled zero mutations against the real server')
    if (Number(summary[3]) <= 0) throw new Error('real-stack lane proved no exact-bytes retry')
    // O-41: `capture_task` was the only command type this client could ever
    // construct. A lane that observed one type has not proved it closed.
    if (Number(summary[6]) < 8) throw new Error('real-stack lane observed fewer than the eight command types a person can perform')
    // O-38: and it must have heard a conflict the REAL server raised.
    if (Number(summary[7]) <= 0) throw new Error('real-stack lane surfaced no server-raised conflict')
    if (!summary[4].split(',').includes('conflict')) throw new Error('real-stack lane observed no conflict outcome')
    // O-45: undo was the last mutation a person can perform that reached the
    // server never. A lane that did not follow a REAL server-issued handle
    // all the way to the server reversing the change has not proved it.
    if (Number(summary[8]) <= 0) throw new Error('real-stack lane never reconciled an undo against the real server')
    return Number(summary[1])
  },
  trackedInputPaths: [
    'apps/desktop/test/real-stack',
    'apps/web/e2e/support/backend.ts',
    'tooling/verify-real-stack-desktop.mjs',
  ],
})

/**
 * The macOS layer (rows A1-A15): the real AXUIElement tree VoiceOver speaks,
 * real CGEvent keystrokes, real input sources, and real system
 * accessibility/appearance settings, all against the SAME packaged artifact
 * `package-once` produced. This lane replaces what used to be a fifteen-row
 * human checklist.
 *
 * `--gate` deliberately does NOT run the rows. Running them takes over the
 * keyboard and changes real system settings on whatever machine the gate is
 * invoked on, which is not an acceptable cost for every ordinary gate run.
 * Instead the rows are executed ONCE per packaged artifact
 * (`node tooling/verify-macos-integration.mjs --all`) and the result is
 * recorded against that exact `applicationDigestSha256` -- the same
 * digest-binding idiom D-47 already uses for package-once -> promotion.
 *
 * The reuse is strict and visible: evidence is bound to the artifact digest
 * AND to the Swift probe source digests, must cover every row, must contain
 * no failing row, and prints the digest and original run timestamp whenever
 * it is reused. Missing, stale, partial or failing evidence is a LOUD
 * FAILURE naming the command that produces it -- never a skip, never a soft
 * pass.
 */
runLane({
  args: ['tooling/verify-macos-integration.mjs', '--gate'],
  command: 'node',
  name: 'macos-integration',
  parse: (stdout) => {
    const summary = stdout.match(/macOS integration lane summary: rows=(\d+) failed=(\d+) cases=(\d+)/)
    if (!summary) throw new Error('macOS integration lane summary line not found')
    if (Number(summary[2]) > 0) throw new Error(`macOS integration lane reported ${summary[2]} failing row(s)`)
    const passed = stdout.match(/macOS integration lane: PASSED cases=(\d+)/)
    if (!passed) throw new Error('macOS integration lane did not report a PASSED result')
    if (Number(passed[1]) !== Number(summary[3])) throw new Error('macOS integration lane case counts disagree')
    return Number(passed[1])
  },
  trackedInputPaths: ['tooling/macos-integration', 'tooling/verify-macos-integration.mjs'],
})

// Privacy: every generated packaged/E2E test-results artifact from this run
// is scanned for hostile content sentinels (packages/contracts vector,
// shared with Phase 2) AND for plaintext bearer/access-token-shaped
// strings. A zero-artifact scan is itself a failure -- it would silently
// pass because nothing was checked, exactly the vacuous-evidence failure
// this whole gate exists to prevent.
runLane({
  args: [],
  command: 'node',
  env: {},
  name: 'privacy',
  parse: () => {
    const testResultsDir = join(desktopRoot, 'test-results')
    const vectorPath = join(repositoryRoot, 'packages', 'contracts', 'vectors', 'redaction.json')
    let sentinels = []
    try {
      sentinels = JSON.parse(readFileSync(vectorPath, 'utf8')).hostile_sentinels ?? []
    } catch {
      throw new Error('redaction vector is missing or invalid')
    }
    if (sentinels.length === 0) throw new Error('redaction vector has no hostile sentinels')

    const walk = (directory) => {
      const files = []
      let entries
      try {
        entries = readdirSync(directory, { withFileTypes: true })
      } catch {
        return files
      }
      for (const entry of entries) {
        const path = join(directory, entry.name)
        if (entry.isDirectory()) files.push(...walk(path))
        else if (entry.isFile()) files.push(path)
      }
      return files
    }
    if (!existsSync(testResultsDir)) throw new Error(`no generated test-results directory at ${testResultsDir}`)
    const artifacts = walk(testResultsDir)
    if (artifacts.length === 0) throw new Error('no generated test-results artifacts were found to scan')

    const suspiciousPattern = /bearer\s+[a-z0-9._-]{16,}|"access_token"\s*:/i
    let scanned = 0
    for (const artifact of artifacts) {
      let content
      try {
        content = readFileSync(artifact, 'utf8')
      } catch {
        continue // binary artifact (screenshot/trace zip) -- not a text leak surface for this scan
      }
      scanned += 1
      for (const sentinel of sentinels) {
        if (content.includes(sentinel)) throw new Error(`hostile sentinel found in ${artifact}`)
      }
      if (suspiciousPattern.test(content)) throw new Error(`credential-shaped content found in ${artifact}`)
    }
    if (scanned === 0) throw new Error('every artifact found was unreadable as text -- nothing was actually scanned')
    return scanned
  },
})

// ---------------------------------------------------------------------------
// D-48 adversarial-fixture ownership registry. Each row names exactly one
// existing test (file + exact test-name substring) as the owner of that
// adversarial category. A renamed or deleted fixture fails this gate.
// ---------------------------------------------------------------------------

/**
 * Physical-accessibility row ownership (A1-A15). These rows were previously
 * a human checklist; each is now owned by exactly one named row
 * implementation in the macOS lane. A renamed or deleted row fails this
 * gate the same way a missing D-48 fixture does -- which is what stops the
 * checklist quietly coming back as an unowned claim.
 */
const accessibilityRowRegistry = [
  { file: 'tooling/verify-macos-integration.mjs', row: 'A1', testName: "runRow('A1'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A2', testName: "runRow('A2'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A3', testName: "runRow('A3'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A4', testName: "runRow('A4'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A5', testName: "runRow('A5'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A6', testName: "runRow('A6'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A7', testName: "runRow('A7'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A8', testName: "runRow('A8'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A9', testName: "runRow('A9'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A10', testName: "pixelAppearanceRow('A10'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A11', testName: "runRow('A11'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A12', testName: "pixelAppearanceRow('A12'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A13', testName: "pixelAppearanceRow('A13'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A14', testName: "pixelAppearanceRow('A14'" },
  { file: 'tooling/verify-macos-integration.mjs', row: 'A15', testName: "runRow('A15'" },
]

let accessibilityOwnershipFailed = false
for (const row of accessibilityRowRegistry) {
  const filePath = join(repositoryRoot, row.file)
  let source
  try {
    source = readFileSync(filePath, 'utf8')
  } catch {
    console.log(`AROW row=${row.row} status=MISSING file=${row.file}`)
    accessibilityOwnershipFailed = true
    continue
  }
  const found = source.includes(row.testName)
  console.log(`AROW row=${row.row} status=${found ? 'PASS' : 'FAIL'} file=${row.file}`)
  if (!found) accessibilityOwnershipFailed = true
}
if (accessibilityOwnershipFailed) {
  anyFailed = true
  fail('one or more physical-accessibility rows (A1-A15) has no owning implementation')
}

const ownershipRegistry = [
  { category: 'shortcut', file: 'apps/desktop/test/e2e/lifecycle.spec.ts', testName: 'the global Quick Entry shortcut is registered by the real shipped app' },
  { category: 'bounds', file: 'apps/desktop/test/e2e/lifecycle.spec.ts', testName: 'window bounds are restored (clamped to the current display) after close and Dock reactivation' },
  { category: 'crash', file: 'apps/desktop/test/ipc/hostile-bridge.test.ts', testName: 'a fresh (post-reload/crash) subscriber snapshot still contains the task committed before the renderer failure' },
  { category: 'transaction', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'rolls back completely on a mid-transaction failure' },
  { category: 'result-loss', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'fails a write against a read-only file without resetting or losing the prior committed task' },
  { category: 'concurrency', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'fails finitely under SQLITE_BUSY without hanging and without partial commit' },
  { category: 'lifecycle', file: 'apps/desktop/test/e2e/lifecycle.spec.ts', testName: 'quit is bounded and every post-COMMIT mutation survives it without waiting on the network' },
  { category: 'wake', file: 'tooling/measure-desktop-performance.mjs', testName: 'wake_reconnect_main_thread_work_ms' },
  { category: 'removal', file: 'apps/desktop/test/e2e/sync-recovery.spec.ts', testName: 'the second confirmation closes the store before deleting its whole file inventory and verifies absence' },
  { category: 'auth', file: 'apps/desktop/test/e2e/fixture-server-sync.spec.ts', testName: 'fences the active namespace before best-effort remote revocation' },
  { category: 'real-server', file: 'apps/desktop/test/real-stack/real-stack-sync.spec.ts', testName: 'the packaged app authorizes, captures offline, reconnects, and reaches Synced against real Phoenix and real PostgreSQL' },
  { category: 'sequence', file: 'apps/desktop/test/ipc/hostile-bridge.test.ts', testName: 'a sequence gap triggers an opaque presentation-snapshot refetch instead of applying the pushed value directly' },
  { category: 'theme', file: 'apps/desktop/test/e2e/accessibility.spec.ts', testName: 'a theme/contrast/motion change while a dialog is open never traps or discards focus' },
  { category: 'conflict', file: 'apps/desktop/test/e2e/daily-loop.spec.ts', testName: 'surfaces a sync conflict inline and requires an explicit mine/current choice' },
  { category: 'busy', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'fails finitely under SQLITE_BUSY without hanging and without partial commit' },
  { category: 'disk', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'classifies every closed failure code, including disk-full which this sandboxed environment cannot induce on real disk' },
  { category: 'migration', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'refuses migration checksum drift and preserves the retained store' },
  { category: 'corruption', file: 'apps/desktop/test/store/migrations-faults.test.ts', testName: 'surfaces real corruption without auto-reset and preserves the file for inspection' },
  { category: 'local-removal', file: 'apps/desktop/test/e2e/sync-recovery.spec.ts', testName: 'a partial external filesystem failure is reported as failed and remains inspectable and retryable, never silently claimed as removed' },
]

let ownershipFailed = false
for (const row of ownershipRegistry) {
  const filePath = join(repositoryRoot, row.file)
  let source
  try {
    source = readFileSync(filePath, 'utf8')
  } catch {
    console.log(`OWNER category=${row.category} status=MISSING file=${row.file}`)
    ownershipFailed = true
    continue
  }
  const found = source.includes(row.testName)
  console.log(`OWNER category=${row.category} status=${found ? 'PASS' : 'FAIL'} file=${row.file}`)
  if (!found) ownershipFailed = true
}
if (ownershipFailed) {
  anyFailed = true
  fail('one or more D-48 adversarial categories has no matching owning fixture')
}

// ---------------------------------------------------------------------------
// Deferred, explicitly non-passing evidence (D-45/D-46): named here so the
// gate's own summary makes clear what remains OUTSIDE this automated pass,
// rather than silently omitting it.
// ---------------------------------------------------------------------------

console.log(
  'DEFERRED item=signed-notarized-credential-continuity status=NON_PASSING reason=explicitly-deferred-not-part-of-this-automated-gate',
)
// Rows A1-A15 are no longer deferred human evidence: they are the
// `macos-integration` lane above. What remains for a person is informal
// feedback while dogfooding -- no checklist, no evidence record, no
// sign-off, and nothing that gates this file.
console.log(
  'NOT_A_GATE item=dogfood-feedback status=INFORMAL reason=physical-accessibility-rows-are-automated-see-tooling/verify-macos-integration.mjs',
)

console.log('')
console.log(`Desktop phase gate summary: lanes=${results.length} failed=${results.filter((r) => !r.passed).length}`)
for (const result of results) {
  console.log(`  ${result.passed ? 'PASS' : 'FAIL'} ${result.name} cases=${result.cases} duration_ms=${result.durationMs}`)
}

if (anyFailed) {
  console.error('Desktop phase gate: FAILED')
  process.exit(1)
}
console.log('Desktop phase gate: PASSED')
