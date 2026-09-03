#!/usr/bin/env node
// D-43 desktop performance measurement orchestrator and evidence schema.
//
// Measures every named D-43 metric against the EXACT packaged executable
// selected by a package-once manifest (see tooling/package-desktop.mjs and
// tooling/smoke-desktop-packaged.mjs, which this script's manifest/digest
// verification deliberately mirrors) -- never a development/source build.
//
// Modes (combinable):
//   --manifest <path>     Required. Package manifest produced by package-desktop.mjs.
//   --record-baseline     After measuring, write/replace apps/desktop/performance-budgets.json
//                          baselines from the fresh measurement. A deliberate, human-reviewed action.
//   --check-budgets       After measuring, compare the fresh measurement against the existing
//                          apps/desktop/performance-budgets.json and fail closed on any gap.
//   --self-test-regression  Proves --check-budgets is not vacuous: injects a synthetic
//                          regression into a clone of the real samples and asserts the
//                          comparison logic rejects it, before reporting the real result.
//
// Evidence is written to .artifacts/desktop/performance-evidence.json plus a human summary
// on stdout. Every metric is bound to the exact packaged application digest, embedded
// runtime versions, host/OS metadata, fixture description, and sample count -- never a
// single unrepeated timing. See docs/testing/desktop-performance.md for the full contract.
//
// This module's pure statistics/privacy/budget-comparison logic (below the "Pure, exported
// helpers" marker) is imported and unit-tested directly by
// apps/desktop/test/performance/runtime.spec.ts. Only the code inside `runCli()` performs
// process.argv parsing, manifest/digest verification, and live Electron launches -- it never
// runs on import, only when this file is executed directly (see the entrypoint guard at the
// bottom), so importing the pure helpers for a fast vitest run never spawns Electron.

import { createHash } from 'node:crypto'
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { cpus, homedir, platform, release, tmpdir, totalmem } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'
import { _electron as electron, expect } from '@playwright/test'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const budgetsPath = join(desktopRoot, 'performance-budgets.json')
const evidenceDir = join(repositoryRoot, '.artifacts', 'desktop')
const evidencePath = join(evidenceDir, 'performance-evidence.json')

class MeasurementFailure extends Error {}

/** Reports failure. Throws so pure-logic callers (and tests) can catch it; the CLI entrypoint below converts an uncaught throw to a non-zero exit. */
const fail = (message) => {
  throw new MeasurementFailure(`Desktop performance measurement failed: ${message}`)
}

// ---------------------------------------------------------------------------
// Pure, exported helpers -- no process.argv, no filesystem/manifest reads, no
// Electron. Safe to import from a test file with zero side effects.
// ---------------------------------------------------------------------------

export const round = (value) => (Number.isFinite(value) ? Math.round(value * 100) / 100 : value)

export const percentile = (sortedValues, p) => {
  if (sortedValues.length === 0) return Number.NaN
  const index = Math.min(sortedValues.length - 1, Math.ceil((p / 100) * sortedValues.length) - 1)
  return sortedValues[Math.max(0, index)]
}

export const summarize = (samples) => {
  const sorted = [...samples].sort((a, b) => a - b)
  return {
    count: samples.length,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    max: sorted.length > 0 ? sorted[sorted.length - 1] : Number.NaN,
    min: sorted.length > 0 ? sorted[0] : Number.NaN,
  }
}

export const statisticValue = (summary, statistic) => summary[statistic]

// Privacy scan -- fails closed rather than merely documenting the rule.
// Rejects raw filesystem paths (temp/profile/home), URLs, and any embedded
// captured task content. Evidence values must be numbers/strings drawn from
// this closed metadata vocabulary only.
export const PRIVACY_PATTERNS = [
  /\/Users\//i,
  new RegExp(tmpdir().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
  /Application Support/i,
  /https?:\/\//i,
  /file:\/\//i,
  /namespace\.sqlite3/i,
]
export const PRIVACY_ALLOWED_RAW_STRING_KEYS = new Set(['sourceRevision', 'applicationDigestSha256', 'executableDigestSha256'])

export const privacyScan = (value, keyPath = []) => {
  if (typeof value === 'string') {
    const key = keyPath[keyPath.length - 1]
    if (PRIVACY_ALLOWED_RAW_STRING_KEYS.has(key)) return
    for (const pattern of PRIVACY_PATTERNS) {
      if (pattern.test(value)) {
        fail(`privacy scan rejected evidence field "${keyPath.join('.')}" -- contains a path/URL/content-like value`)
      }
    }
    return
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => privacyScan(entry, [...keyPath, String(index)]))
    return
  }
  if (value && typeof value === 'object') {
    for (const [key, entry] of Object.entries(value)) privacyScan(entry, [...keyPath, key])
  }
}

/**
 * Compares one metric's fresh samples against its recorded regression
 * budget. Fails closed (returns `{ ok: false, reason }`, never throws) on:
 * a missing budget entry, an incomplete budget (missing baseline/budget
 * value/rationale/sampleFloor), or fewer samples than the budget's
 * `sampleFloor`. Otherwise compares the budget's chosen statistic (p50/p95/
 * min/max) against a relative-or-absolute threshold over the recorded
 * baseline.
 */
export const compareMetricAgainstBudget = (metricName, metricSamples, budgetsDoc) => {
  const budget = budgetsDoc?.metrics?.[metricName]
  if (!budget) return { ok: false, reason: `missing budget for ${metricName}` }
  if (
    typeof budget.baseline !== 'number' ||
    typeof budget.budget?.value !== 'number' ||
    !budget.rationale ||
    typeof budget.sampleFloor !== 'number'
  ) {
    return { ok: false, reason: `incomplete budget (baseline/budget/rationale/sampleFloor) for ${metricName}` }
  }
  if (metricSamples.length < budget.sampleFloor) {
    return { ok: false, reason: `insufficient samples for ${metricName}: got ${metricSamples.length}, need >= ${budget.sampleFloor}` }
  }
  const summary = summarize(metricSamples)
  const current = statisticValue(summary, budget.statistic)
  const threshold = budget.budget.kind === 'relative' ? budget.baseline * (1 + budget.budget.value) : budget.baseline + budget.budget.value
  const ok = current <= threshold
  return { ok, current, threshold, reason: ok ? null : `${metricName} exceeded budget: ${round(current)} > ${round(threshold)} (${budget.statistic})` }
}

export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')

// ---------------------------------------------------------------------------
// CLI entrypoint -- process.argv, manifest/digest verification, and live
// Electron launches. Only runs when this file is executed directly (see the
// entrypoint guard at the bottom of the file), never on import.
// ---------------------------------------------------------------------------

const runCli = async () => {
  const args = process.argv.slice(2)
  const flag = (name) => args.includes(name)
  const option = (name) => {
    const index = args.indexOf(name)
    return index === -1 ? null : (args[index + 1] ?? null)
  }

  const manifestArg = option('--manifest')
  if (!manifestArg) fail('--manifest <path> is required')
  const recordBaseline = flag('--record-baseline')
  const checkBudgets = flag('--check-budgets')
  const selfTestRegression = flag('--self-test-regression')
  if (!recordBaseline && !checkBudgets) {
    fail('at least one of --record-baseline or --check-budgets must be given')
  }

  // --- Manifest + exact-digest verification (mirrors tooling/smoke-desktop-packaged.mjs) ---

  const manifestPath = resolve(manifestArg)
  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch {
    fail('the package manifest is missing or invalid JSON')
  }

  const hashFile = (path) => sha256(readFileSync(path))
  const hashDirectory = (root) => {
    const digest = createHash('sha256')
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
    return digest.digest('hex')
  }

  if (!existsSync(manifest.copiedApplicationPath) || !manifest.copiedApplicationPath.endsWith('.app')) {
    fail('manifest does not select an existing copied .app')
  }
  if (!existsSync(manifest.executablePath)) fail('manifest-selected executable does not exist')
  if (hashDirectory(manifest.copiedApplicationPath) !== manifest.applicationDigestSha256) {
    fail('copied application digest does not match the package manifest -- stale or corrupted artifact')
  }
  if (hashFile(manifest.executablePath) !== manifest.executableDigestSha256) {
    fail('copied executable digest does not match the package manifest -- stale or corrupted artifact')
  }
  const migrationPath = join(dirname(manifest.executablePath), '..', 'Resources', 'migrations', '0001_initial.sql')
  if (!existsSync(migrationPath)) fail('manifest-selected application is missing its bundled migration')

  console.log(`Measuring exact packaged digest=${manifest.applicationDigestSha256} revision=${manifest.sourceRevision}`)

  // --- Environment metadata (closed, privacy-safe: no usernames, no paths) ---

  const environment = {
    arch: process.arch,
    cpuModel: cpus()[0]?.model ?? 'unknown',
    cpuCount: cpus().length,
    electron: manifest.embeddedVersions.electron,
    chrome: manifest.embeddedVersions.chrome,
    embeddedNode: manifest.embeddedVersions.node,
    v8: manifest.embeddedVersions.v8,
    hostNode: process.version,
    osRelease: release(),
    platform: platform(),
    totalMemoryGb: Math.round((totalmem() / 1024 / 1024 / 1024) * 10) / 10,
  }

  // --- Disposable profile management (same containment discipline as
  // tooling/smoke-desktop-packaged.mjs / playwright.config.ts: never the
  // real Keepling Application Support directory, always a fresh
  // system-temp root). ---

  const profileRoot = mkdtempSync(join(tmpdir(), 'keepling-perf-'))
  const forbiddenUserDataDir = resolve(homedir(), 'Library', 'Application Support', 'Keepling')
  let profileCounter = 0
  const allocateProfile = (lane) => {
    profileCounter += 1
    const profilePath = resolve(join(profileRoot, `${lane.replaceAll(/[^a-z0-9-]/gi, '-')}-${profileCounter}`))
    if (profilePath === forbiddenUserDataDir) fail('refused to allocate the normal Keepling profile for measurement')
    mkdirSync(profilePath, { recursive: true })
    return profilePath
  }

  const dbPathFor = (profilePath) => join(profilePath, 'namespace.sqlite3')

  // --- Fixture database construction (D-43 "deterministic many-task
  // fixture"). Applies the SAME migration SQL the app applies, then
  // inserts N synthetic, non-private task rows directly -- avoiding
  // hundreds of slow UI captures just to build a scroll fixture. Titles
  // are synthetic placeholders, never real content. ---

  const FIXTURE_TASK_COUNT = 500

  const buildFixtureDatabase = (profilePath) => {
    const databasePath = dbPathFor(profilePath)
    const database = new DatabaseSync(databasePath)
    database.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;')
    // Mirror NodeSqliteLocalStore#applyMigration exactly (including the
    // schema_migrations ledger row) so the real app's startup invariant and
    // checksum checks accept this externally-built fixture without changes
    // to application source.
    const migrationSql = readFileSync(migrationPath, 'utf8')
    const migrationChecksum = sha256(Buffer.from(migrationSql, 'utf8'))
    database.exec('BEGIN IMMEDIATE')
    database.exec(migrationSql)
    database.prepare('INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (1, ?, ?)').run(
      migrationChecksum,
      new Date().toISOString(),
    )
    database.exec('COMMIT')
    const insert = database.prepare(
      'INSERT INTO visible_projection (task_id, title, sync_status, notes, completed_at, trashed_at, planned) VALUES (?, ?, ?, ?, NULL, NULL, 0)',
    )
    database.exec('BEGIN')
    for (let index = 0; index < FIXTURE_TASK_COUNT; index += 1) {
      insert.run(`fixture-task-${String(index).padStart(4, '0')}`, `Fixture task ${index}`, 'synced', '')
    }
    database.exec('COMMIT')
    database.exec('PRAGMA wal_checkpoint(TRUNCATE)')
    database.close()
  }

  // --- Electron launch helpers ---

  const launch = async (profilePath, envOverrides = {}) => {
    const application = await electron.launch({
      executablePath: manifest.executablePath,
      env: {
        ...process.env,
        KEEPLING_EXPECT_PACKAGED: '1',
        KEEPLING_FORBIDDEN_USER_DATA_DIR: forbiddenUserDataDir,
        KEEPLING_TEST_SYNC_MODE: 'offline',
        KEEPLING_TEST_USER_DATA_DIR: profilePath,
        ...envOverrides,
      },
      timeout: 30_000,
    })
    const window = await application.firstWindow()
    return { application, window }
  }

  const closeApp = async (application) => {
    await application.close().catch(() => {})
  }

  /**
   * Polls a cheap main-process round trip while `work` is in flight, to
   * prove the awaited operation does not block the Electron main thread
   * for a meaningful stretch. A generous 300ms ceiling absorbs CDP/IPC
   * round-trip noise while still catching multi-second synchronous
   * blocking, which is the actual risk D-43 guards against (database/
   * network work on the main thread).
   */
  const withMainThreadLivenessProbe = async (application, work) => {
    let maxRoundTripMs = 0
    let probing = true
    const probe = (async () => {
      while (probing) {
        const start = Date.now()
        await application.evaluate(() => Date.now()).catch(() => {})
        maxRoundTripMs = Math.max(maxRoundTripMs, Date.now() - start)
        await new Promise((r) => setTimeout(r, 15))
      }
    })()
    const result = await work()
    probing = false
    await probe
    return { maxRoundTripMs, result }
  }

  const withRendererThreadLivenessProbe = async (window, work) => {
    let maxRoundTripMs = 0
    let probing = true
    const probe = (async () => {
      while (probing) {
        const start = Date.now()
        await window.evaluate(() => performance.now()).catch(() => {})
        maxRoundTripMs = Math.max(maxRoundTripMs, Date.now() - start)
        await new Promise((r) => setTimeout(r, 15))
      }
    })()
    const result = await work()
    probing = false
    await probe
    return { maxRoundTripMs, result }
  }

  const THREAD_LIVENESS_BUDGET_MS = 300

  // --- Metric collectors ---

  const SAMPLE_COUNTS = {
    launch: 3,
    idle: 10,
    wake: 3,
    walCheckpoint: 3,
  }

  const samples = {
    cold_launch_to_local_interactive_ms: [],
    warm_launch_to_local_interactive_ms: [],
    quick_entry_open_to_focus_ms: [],
    local_commit_ms: [],
    list_scroll_frame_p95_ms: [],
    idle_cpu_percent: [],
    idle_memory_mb: [],
    wake_reconnect_main_thread_work_ms: [],
    wake_reconnect_renderer_thread_work_ms: [],
    wal_bytes: [],
    checkpoint_ms: [],
    packaged_app_bytes: [],
  }

  const threadOwnership = { commit: [], reconnect: [] }

  // Phase A: cold + warm launch, Quick Entry, local commit, idle.

  const measureColdWarmSession = async (index) => {
    const profilePath = allocateProfile(`session-${index}`)

    const coldStart = Date.now()
    const { application, window } = await launch(profilePath)
    await window.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    samples.cold_launch_to_local_interactive_ms.push(Date.now() - coldStart)

    // Quick Entry open-to-focus: first invocation in this session (the
    // resident-window pattern makes repeat opens a fast reshow, not a
    // fresh "open" -- see docs/testing/desktop-performance.md for why
    // first-open per session is the honest scenario for this metric).
    const quickEntryStart = Date.now()
    const [quickEntryWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      application.evaluate(({ Menu }) => {
        const find = (items) => {
          for (const item of items) {
            if (item.label.startsWith('Quick Entry')) return item
            if (item.submenu) {
              const found = find(item.submenu.items)
              if (found) return found
            }
          }
          return null
        }
        const menu = Menu.getApplicationMenu()
        const item = menu ? find(menu.items) : null
        if (!item) throw new Error('Quick Entry menu item not found')
        item.click()
      }),
    ])
    await quickEntryWindow.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    await expect(quickEntryWindow.getByLabel('What do you want to keep?')).toBeFocused()
    samples.quick_entry_open_to_focus_ms.push(Date.now() - quickEntryStart)
    await application.evaluate(({ BrowserWindow }) => {
      const quickEntry = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes('view=quick-entry'))
      quickEntry?.hide()
    })

    // Local commit: fill + submit the main window's capture form, timing
    // to the post-COMMIT "Saved on this Mac" indicator (D-03 -- never a
    // paint or optimistic-update proxy). Wrapped with a main-thread
    // liveness probe to assert the commit does not block the main
    // process event loop.
    const title = `Perf fixture capture ${index}`
    const { maxRoundTripMs, result: commitMs } = await withMainThreadLivenessProbe(application, async () => {
      const start = Date.now()
      await window.getByLabel('What do you want to keep?').fill(title)
      await window.getByRole('button', { name: 'Add Task' }).click()
      await window.getByText(title).waitFor({ state: 'visible' })
      await window.getByText('Saved on this Mac').first().waitFor({ state: 'visible' })
      return Date.now() - start
    })
    samples.local_commit_ms.push(commitMs)
    threadOwnership.commit.push(maxRoundTripMs)

    // Idle CPU/memory: sample Electron's own process metrics repeatedly
    // after settling, with no further interaction.
    await window.waitForTimeout(400)
    const cpuSamples = []
    const memSamples = []
    for (let sampleIndex = 0; sampleIndex < SAMPLE_COUNTS.idle; sampleIndex += 1) {
      const metrics = await application.evaluate(({ app }) => app.getAppMetrics())
      const cpuTotal = metrics.reduce((sum, entry) => sum + (entry.cpu?.percentCPUUsage ?? 0), 0)
      const memTotalKb = metrics.reduce((sum, entry) => sum + (entry.memory?.workingSetSize ?? 0), 0)
      cpuSamples.push(cpuTotal)
      memSamples.push(memTotalKb / 1024)
      await window.waitForTimeout(150)
    }
    samples.idle_cpu_percent.push(...cpuSamples)
    samples.idle_memory_mb.push(...memSamples)

    await closeApp(application)

    // Warm launch: relaunch against the SAME (now-initialized) profile.
    const warmStart = Date.now()
    const { application: warmApplication, window: warmWindow } = await launch(profilePath)
    await warmWindow.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    samples.warm_launch_to_local_interactive_ms.push(Date.now() - warmStart)
    await closeApp(warmApplication)

    return profilePath
  }

  // Phase B: wake/reconnect.
  //
  // This application has no OS-level sleep/wake ("resume") listener wired
  // in main/index.ts today (verified by source inspection -- see
  // docs/testing/desktop-performance.md "Known scope gap"). The only
  // implemented reconciliation code path is `DesktopApplication#reconcile()`,
  // run once at bootstrap. The closest honest, real (non-fabricated)
  // approximation of "reconnect work" this codebase can produce is exactly
  // the scenario the offline-capture/lifecycle E2E suites already exercise:
  // capture while offline, quit, relaunch with the network now reachable,
  // and let the bootstrap reconcile pass settle the queued mutation.
  // Main-thread work is isolated as the marginal cost over an equivalent
  // warm relaunch with nothing pending (measured in Phase A); renderer-
  // thread work is the time from interactive to the acknowledgement's
  // "Synced" repaint.

  const runWakeReconnectSession = async (index) => {
    const profilePath = allocateProfile(`wake-${index}`)
    const title = `Reconnect fixture ${index}`

    const { application: offlineApp, window: offlineWindow } = await launch(profilePath, { KEEPLING_TEST_SYNC_MODE: 'offline' })
    await offlineWindow.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    await offlineWindow.getByLabel('What do you want to keep?').fill(title)
    await offlineWindow.getByRole('button', { name: 'Add Task' }).click()
    await offlineWindow.getByText('Saved on this Mac').first().waitFor({ state: 'visible' })
    await closeApp(offlineApp)

    const totalStart = Date.now()
    const { application, window } = await launch(profilePath, { KEEPLING_TEST_SYNC_MODE: 'acknowledge' })
    const { maxRoundTripMs } = await withMainThreadLivenessProbe(application, async () => {
      await window.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    })
    const interactiveAt = Date.now()
    const { maxRoundTripMs: rendererMaxRoundTripMs } = await withRendererThreadLivenessProbe(window, async () => {
      await window.getByText('Synced').first().waitFor({ state: 'visible' })
    })
    const syncedAt = Date.now()
    await closeApp(application)

    return {
      totalRelaunchMs: interactiveAt - totalStart,
      rendererWorkMs: syncedAt - interactiveAt,
      mainRoundTripMs: maxRoundTripMs,
      rendererRoundTripMs: rendererMaxRoundTripMs,
    }
  }

  // Phase C: list scroll frame pacing.

  const runScrollSession = async () => {
    const profilePath = allocateProfile('scroll')
    buildFixtureDatabase(profilePath)
    const { application, window } = await launch(profilePath)
    await window.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    await window.locator("ul[aria-label='Tasks'] li").first().waitFor({ state: 'visible' })

    const frameDeltas = await window.evaluate(async () => {
      const list = document.querySelector("ul[aria-label='Tasks']")
      if (!list) throw new Error('scroll fixture list not found')
      const stamps = []
      const durationMs = 1500
      await new Promise((resolveFrames) => {
        let start = null
        const step = (timestamp) => {
          if (start === null) start = timestamp
          stamps.push(timestamp)
          list.scrollTop += 32
          if (timestamp - start < durationMs) requestAnimationFrame(step)
          else resolveFrames(undefined)
        }
        requestAnimationFrame(step)
      })
      const deltas = []
      for (let i = 1; i < stamps.length; i += 1) deltas.push(stamps[i] - stamps[i - 1])
      return deltas
    })
    await closeApp(application)

    // Discard the first 5 frames as warmup (initial layout/scroll settling).
    return frameDeltas.slice(5)
  }

  // Phase D: WAL bytes + checkpoint duration.

  const CAPTURES_PER_WAL_SESSION = 10

  const runWalCheckpointSession = async (index) => {
    const profilePath = allocateProfile(`wal-${index}`)
    const { application, window } = await launch(profilePath)
    await window.getByLabel('What do you want to keep?').waitFor({ state: 'visible' })
    for (let captureIndex = 0; captureIndex < CAPTURES_PER_WAL_SESSION; captureIndex += 1) {
      const title = `WAL fixture ${index}-${captureIndex}`
      await window.getByLabel('What do you want to keep?').fill(title)
      await window.getByRole('button', { name: 'Add Task' }).click()
      await window.getByText(title).waitFor({ state: 'visible' })
    }

    // WAL bytes and checkpoint duration MUST be measured while the app's
    // own worker connection is still open: SQLite auto-checkpoints (and
    // truncates the WAL) when the last connection to a WAL-mode database
    // closes, which would make a post-quit measurement read back a
    // checkpoint that already happened for free. SQLite WAL mode
    // explicitly supports a second concurrent reader/writer connection
    // from another process against the same file, so a short-lived
    // external node:sqlite connection can stat the live WAL file and run
    // a real `PRAGMA wal_checkpoint(TRUNCATE)` without disturbing the
    // app's own connection (verified empirically: a second connection
    // successfully truncates the WAL to 0 bytes while the first stays
    // open).
    const walFilePath = `${dbPathFor(profilePath)}-wal`
    const walBytes = existsSync(walFilePath) ? statSync(walFilePath).size : 0

    const database = new DatabaseSync(dbPathFor(profilePath))
    const checkpointStart = Date.now()
    database.prepare('PRAGMA wal_checkpoint(TRUNCATE)').get()
    const checkpointMs = Date.now() - checkpointStart
    database.close()

    await closeApp(application)

    return { walBytes, checkpointMs }
  }

  // Packaged footprint.

  const directoryByteSize = (root) => {
    let total = 0
    const visit = (directory) => {
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const path = join(directory, entry.name)
        if (entry.isSymbolicLink()) continue
        if (entry.isDirectory()) visit(path)
        else total += statSync(path).size
      }
    }
    visit(root)
    return total
  }

  // --- Run everything ---

  mkdirSync(evidenceDir, { recursive: true })

  console.log(`Phase A: cold/warm launch, Quick Entry, local commit, idle (${SAMPLE_COUNTS.launch} sessions)`)
  for (let i = 0; i < SAMPLE_COUNTS.launch; i += 1) {
    await measureColdWarmSession(i)
  }

  console.log(`Phase B: wake/reconnect (${SAMPLE_COUNTS.wake} sessions)`)
  for (let i = 0; i < SAMPLE_COUNTS.wake; i += 1) {
    const result = await runWakeReconnectSession(i)
    samples.wake_reconnect_main_thread_work_ms.push(result.totalRelaunchMs)
    samples.wake_reconnect_renderer_thread_work_ms.push(result.rendererWorkMs)
    threadOwnership.reconnect.push(Math.max(result.mainRoundTripMs, result.rendererRoundTripMs))
  }
  // Main-thread work is the marginal reconnect cost over the warm-launch
  // control measured in Phase A -- both are launches against an
  // already-initialized profile, differing only in whether mutations are
  // pending reconciliation.
  const warmControlP50 = summarize(samples.warm_launch_to_local_interactive_ms).p50
  samples.wake_reconnect_main_thread_work_ms = samples.wake_reconnect_main_thread_work_ms.map((value) =>
    Math.max(0, value - warmControlP50),
  )

  console.log('Phase C: list scroll frame pacing')
  samples.list_scroll_frame_p95_ms = await runScrollSession()

  console.log(`Phase D: WAL bytes + checkpoint duration (${SAMPLE_COUNTS.walCheckpoint} sessions)`)
  for (let i = 0; i < SAMPLE_COUNTS.walCheckpoint; i += 1) {
    const result = await runWalCheckpointSession(i)
    samples.wal_bytes.push(result.walBytes)
    samples.checkpoint_ms.push(result.checkpointMs)
  }

  console.log('Packaged footprint')
  samples.packaged_app_bytes.push(directoryByteSize(manifest.copiedApplicationPath))
  const zipBytes = existsSync(manifest.zipPath) ? statSync(manifest.zipPath).size : null

  // Thread-ownership assertion (acceptance criterion: "thread-work
  // assertions show store/network ownership outside UI threads").
  const maxCommitRoundTripMs = Math.max(0, ...threadOwnership.commit)
  const maxReconnectRoundTripMs = Math.max(0, ...threadOwnership.reconnect)
  const threadOwnershipEvidence = {
    commit: { maxMainThreadRoundTripMs: maxCommitRoundTripMs, budgetMs: THREAD_LIVENESS_BUDGET_MS, withinBudget: maxCommitRoundTripMs <= THREAD_LIVENESS_BUDGET_MS },
    reconnect: { maxRoundTripMs: maxReconnectRoundTripMs, budgetMs: THREAD_LIVENESS_BUDGET_MS, withinBudget: maxReconnectRoundTripMs <= THREAD_LIVENESS_BUDGET_MS },
  }
  if (!threadOwnershipEvidence.commit.withinBudget || !threadOwnershipEvidence.reconnect.withinBudget) {
    fail(
      `main/renderer thread liveness probe exceeded ${THREAD_LIVENESS_BUDGET_MS}ms during commit or reconnect -- ` +
        'database/network work appears to be blocking a UI-owning thread',
    )
  }

  // --- Evidence assembly ---

  const metricUnits = {
    cold_launch_to_local_interactive_ms: 'ms',
    warm_launch_to_local_interactive_ms: 'ms',
    quick_entry_open_to_focus_ms: 'ms',
    local_commit_ms: 'ms',
    list_scroll_frame_p95_ms: 'ms',
    idle_cpu_percent: 'percent',
    idle_memory_mb: 'mb',
    wake_reconnect_main_thread_work_ms: 'ms',
    wake_reconnect_renderer_thread_work_ms: 'ms',
    wal_bytes: 'bytes',
    checkpoint_ms: 'ms',
    packaged_app_bytes: 'bytes',
  }

  const metricFixtures = {
    cold_launch_to_local_interactive_ms: 'fresh disposable profile, empty local store',
    warm_launch_to_local_interactive_ms: 'same profile as a prior session, initialized local store',
    quick_entry_open_to_focus_ms: 'first Quick Entry invocation per session via real native menu click',
    local_commit_ms: 'single synthetic task captured through the main window form',
    list_scroll_frame_p95_ms: `deterministic ${FIXTURE_TASK_COUNT}-task fixture, synthetic titles, driven scroll for 1.5s (rAF deltas, first 5 frames discarded)`,
    idle_cpu_percent: `${SAMPLE_COUNTS.idle} Electron app-metric samples at 150ms intervals with no interaction`,
    idle_memory_mb: `${SAMPLE_COUNTS.idle} Electron app-metric samples at 150ms intervals with no interaction`,
    wake_reconnect_main_thread_work_ms: 'proxy: bootstrap reconcile pass on relaunch with 1 pending offline mutation, minus warm-launch control (see docs/testing/desktop-performance.md)',
    wake_reconnect_renderer_thread_work_ms: 'time from interactive to the acknowledged task\'s "Synced" repaint',
    wal_bytes: `${CAPTURES_PER_WAL_SESSION} sequential captures through the real write path, WAL file size before checkpoint`,
    checkpoint_ms: `PRAGMA wal_checkpoint(TRUNCATE) after ${CAPTURES_PER_WAL_SESSION} captures, app fully closed`,
    packaged_app_bytes: 'exact copied .app bundle, recursive byte sum (symlinks excluded)',
  }

  const evidenceMetrics = {}
  for (const [name, values] of Object.entries(samples)) {
    const summary = summarize(values)
    evidenceMetrics[name] = {
      unit: metricUnits[name],
      fixture: metricFixtures[name],
      sampleCount: summary.count,
      p50: summary.p50,
      p95: summary.p95,
      min: summary.min,
      max: summary.max,
      privacyPass: true,
    }
  }

  const evidence = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    source: {
      applicationDigestSha256: manifest.applicationDigestSha256,
      executableDigestSha256: manifest.executableDigestSha256,
      inputDigestSha256: manifest.inputDigestSha256,
      sourceRevision: manifest.sourceRevision,
      zipBytes,
    },
    environment,
    threadOwnership: threadOwnershipEvidence,
    metrics: evidenceMetrics,
  }

  privacyScan(evidence)

  writeFileSync(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8')
  console.log(`Evidence written: ${evidencePath}`)

  console.log('')
  console.log('D-43 measurement summary:')
  for (const [name, metric] of Object.entries(evidenceMetrics)) {
    console.log(
      `  ${name}: p50=${round(metric.p50)} p95=${round(metric.p95)} max=${round(metric.max)} ${metric.unit} (n=${metric.sampleCount})`,
    )
  }

  // --- --record-baseline ---

  const REGRESSION_BUDGETS = {
    // Latency-ish metrics: launches/interaction cross multiple process
    // boundaries (worker thread, IPC, renderer paint) with real scheduler
    // noise -- 35% relative headroom absorbs that without being vacuous.
    cold_launch_to_local_interactive_ms: { kind: 'relative', value: 0.35, statistic: 'p95', rationale: 'Cross-process launch path (main -> worker -> IPC -> renderer paint) has real scheduler noise; 35% relative headroom over p95 avoids flagging normal variance while catching a genuine regression.' },
    warm_launch_to_local_interactive_ms: { kind: 'relative', value: 0.35, statistic: 'p95', rationale: 'Same cross-process path as cold launch, lower absolute magnitude but comparable relative variance.' },
    quick_entry_open_to_focus_ms: { kind: 'relative', value: 0.4, statistic: 'p95', rationale: 'Window creation plus focus involves OS window-server round trips with higher relative variance on a shared CI/dev machine.' },
    local_commit_ms: { kind: 'relative', value: 0.5, statistic: 'p95', rationale: 'SQLite worker round trip is normally fast (single-digit-to-low-double-digit ms) so relative variance is naturally larger; absolute regressions of a few ms would otherwise false-positive.' },
    list_scroll_frame_p95_ms: { kind: 'absolute', value: 8, statistic: 'p95', rationale: 'Frame pacing target is 16.6ms/frame (60fps); an absolute +8ms budget over the recorded p95 flags real jank without chasing sub-millisecond rAF scheduler jitter.' },
    idle_cpu_percent: { kind: 'absolute', value: 5, statistic: 'p95', rationale: 'Idle CPU should be near-zero; a flat +5 percentage-point budget catches a real idle-loop regression while tolerating brief OS scheduling spikes.' },
    idle_memory_mb: { kind: 'relative', value: 0.25, statistic: 'p95', rationale: 'Electron/V8 heap and renderer memory vary with OS memory pressure; 25% relative headroom avoids false positives from GC timing.' },
    wake_reconnect_main_thread_work_ms: { kind: 'absolute', value: 200, statistic: 'p95', rationale: 'This is a derived (marginal) measurement -- see fixture note; absolute budget avoids amplifying noise from two subtracted measurements into a relative percentage.' },
    wake_reconnect_renderer_thread_work_ms: { kind: 'relative', value: 0.5, statistic: 'p95', rationale: 'Single IPC round trip plus one React re-render; naturally small and noisy in absolute terms.' },
    wal_bytes: { kind: 'relative', value: 0.3, statistic: 'p50', rationale: 'WAL growth per fixed capture count is deterministic-ish but SQLite page allocation has some run-to-run variance.' },
    checkpoint_ms: { kind: 'absolute', value: 10, statistic: 'p95', rationale: 'Checkpoint duration on a small WAL is normally 0-1ms at Date.now() millisecond resolution, so a baseline near zero makes a relative budget nearly untestable (50% of 1ms is 1.5ms); an absolute +10ms budget still catches a real regression (e.g. disk contention or a much larger WAL) without quantization noise flipping pass/fail.' },
    packaged_app_bytes: { kind: 'relative', value: 0.1, statistic: 'p50', rationale: 'Packaged bytes should only grow with genuine dependency/asset changes; 10% headroom tolerates minor Electron/asset churn between releases without masking a real bloat regression.' },
  }

  // Most metrics have a FIXED sample count (SAMPLE_COUNTS above is a
  // constant), so recording the observed count as sampleFloor is exact and
  // safe. `list_scroll_frame_p95_ms` is the one exception: its sample count
  // is the number of requestAnimationFrame callbacks that actually fired
  // during a fixed 1.5s wall-clock window, which is itself subject to
  // ordinary scheduler variance (observed 175-176 frames across otherwise
  // identical runs on this machine). Recording the exact observed count as
  // sampleFloor would make --check-budgets fail on totally normal frame-
  // count jitter, not a real regression -- so this metric gets an explicit,
  // conservatively-below-typical floor instead of its raw observed count.
  const SAMPLE_FLOOR_OVERRIDES = {
    list_scroll_frame_p95_ms: 100,
  }

  if (recordBaseline) {
    const budgets = {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      recordedSourceRevision: manifest.sourceRevision,
      environment,
      metrics: {},
    }
    for (const [name, metric] of Object.entries(evidenceMetrics)) {
      const budgetSpec = REGRESSION_BUDGETS[name]
      budgets.metrics[name] = {
        unit: metric.unit,
        statistic: budgetSpec.statistic,
        baseline: metric[budgetSpec.statistic],
        budget: { kind: budgetSpec.kind, value: budgetSpec.value },
        sampleFloor: SAMPLE_FLOOR_OVERRIDES[name] ?? metric.sampleCount,
        rationale: budgetSpec.rationale,
      }
    }
    writeFileSync(budgetsPath, `${JSON.stringify(budgets, null, 2)}\n`, 'utf8')
    console.log(`Baseline recorded: ${budgetsPath}`)
  }

  // --- --check-budgets (+ optional --self-test-regression) ---

  if (checkBudgets) {
    if (!existsSync(budgetsPath)) fail('--check-budgets requires apps/desktop/performance-budgets.json to exist (run --record-baseline first)')
    let budgets
    try {
      budgets = JSON.parse(readFileSync(budgetsPath, 'utf8'))
    } catch {
      fail('apps/desktop/performance-budgets.json is invalid JSON')
    }

    if (selfTestRegression) {
      const canaryMetric = 'cold_launch_to_local_interactive_ms'
      const injected = samples[canaryMetric].map((v) => v * 10 + 5_000)
      const injectedResult = compareMetricAgainstBudget(canaryMetric, injected, budgets)
      if (injectedResult.ok) {
        fail(`self-test-regression FAILED: an injected 10x+5000ms regression on ${canaryMetric} was NOT detected -- budget check is vacuous`)
      }
      console.log(`self-test-regression: PASSED (injected regression on ${canaryMetric} correctly rejected: ${injectedResult.reason})`)
    }

    const failures = []
    for (const [name, values] of Object.entries(samples)) {
      const result = compareMetricAgainstBudget(name, values, budgets)
      if (!result.ok) failures.push(result.reason)
    }

    if (failures.length > 0) {
      for (const reason of failures) console.error(`  FAIL: ${reason}`)
      fail(`${failures.length} metric(s) failed budget check`)
    }
    console.log('check-budgets: all metrics within recorded regression budgets')
  }

  rmSync(profileRoot, { force: true, recursive: true })
}

// ---------------------------------------------------------------------------
// Entrypoint guard -- only run the CLI when this file is executed directly
// (`node tooling/measure-desktop-performance.mjs ...`), never on import
// (e.g. from apps/desktop/test/performance/runtime.spec.ts, which imports
// only the pure helpers above).
// ---------------------------------------------------------------------------

const isMainModule = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href
if (isMainModule) {
  try {
    await runCli()
  } catch (error) {
    if (error instanceof MeasurementFailure) {
      console.error(error.message)
      process.exit(1)
    }
    throw error
  }
}
