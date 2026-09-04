#!/usr/bin/env node

/**
 * macOS-layer integration lane (rows A1-A15).
 *
 * These rows used to be a fifteen-item human checklist in
 * `docs/testing/desktop-dogfood.md`, on the stated grounds that they
 * "cannot be automated". That was true of the layer the existing suite
 * tests -- Chromium's DOM inside Electron genuinely cannot see VoiceOver,
 * real keystrokes, or system settings. It was NOT true of macOS, which
 * exposes every one of them:
 *
 *   A1-A4   the real AXUIElement tree (the same data VoiceOver speaks)
 *   A5-A7   Full Keyboard Access + real CGEvent keystrokes + input sources
 *   A8-A9   real OS global-shortcut arbitration and prior-app focus return
 *   A10-A15 real system accessibility/appearance settings, with legibility
 *           asserted as a COMPUTED WCAG contrast ratio over rendered pixels
 *
 * Anti-vacuous contract (inherited from `verify-desktop-phase.mjs`, which
 * registers this file as a required lane):
 *   * A missing capability is a LOUD FAILURE, never a skip. No Accessibility
 *     permission, no `swiftc`, no packaged artifact -> the lane fails and
 *     names exactly what to do about it.
 *   * A row that executes zero assertions fails. The lane's total case count
 *     must be positive or the lane fails.
 *   * The lane NEVER builds. It consumes the package manifest's executable
 *     path and verifies the artifact digest first, exactly as
 *     `smoke-desktop-packaged.mjs` does.
 *   * Any system setting it mutates is captured first and restored on every
 *     exit path -- success, failure, exception, SIGINT and SIGTERM -- and
 *     restoration is verified by re-reading.
 */

import { createHash } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const sourceDir = join(repositoryRoot, 'tooling', 'macos-integration')
const cacheDir = join(repositoryRoot, '.artifacts', 'macos-integration')

const ACCESSIBILITY_GRANT_INSTRUCTION = [
  'Accessibility (TCC) permission is REQUIRED and is not granted.',
  '',
  'Open:  System Settings -> Privacy & Security -> Accessibility',
  'Then:  enable the application that runs this lane (the terminal, IDE, or',
  '       CI agent process named in the probe\'s reported process chain).',
  '',
  'SIP protects the TCC database, so this one-time approval cannot be',
  'scripted. It persists once granted. This lane will NOT skip, soft-pass, or',
  'warn-and-continue without it -- a row that did not actually exercise macOS',
  'must never report green.',
].join('\n')

const fail = (message) => {
  console.error(`macOS integration lane failed: ${message}`)
  process.exitCode = 1
  throw new LaneFailure(message)
}

class LaneFailure extends Error {}

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2)
const flagValue = (name) => {
  const index = argv.indexOf(`--${name}`)
  return index === -1 ? null : argv[index + 1] ?? null
}
const hasFlag = (name) => argv.includes(`--${name}`)

const ALL_ROWS = ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10', 'A11', 'A12', 'A13', 'A14', 'A15']

const selfTestRestore = hasFlag('self-test-restore')
const gateMode = hasFlag('gate')
const runAllRows = hasFlag('all')
const restoreOnly = hasFlag('restore')
const withoutAccessibilityTrust = hasFlag('without-accessibility-trust')

/**
 * This lane drives real keyboard input and changes real system settings on
 * whatever machine it runs on, so it never starts by accident. Every mode
 * has to be asked for by name.
 */
if (!selfTestRestore && !gateMode && !runAllRows && !restoreOnly && !withoutAccessibilityTrust && flagValue('rows') === null && !hasFlag('internal-mutate-then-wait')) {
  console.error([
    'macOS integration lane: nothing selected, so nothing was run.',
    '',
    'This lane types on the real keyboard and changes real system settings',
    '(appearance, contrast, transparency, motion, keyboard access, input',
    'source). It is deliberately opt-in so it can never take over a machine',
    'by accident.',
    '',
    '  --all                    run every row A1-A15 and RECORD the evidence',
    '  --rows A1,A2             run selected rows only',
    '  --gate                   reuse recorded evidence for the current artifact',
    '  --without-accessibility-trust  run only rows needing no Accessibility grant',
    '  --self-test-restore      prove settings are restored after a failure and',
    '                           after a real interruption',
    '  --restore                manually restore settings from the last capture',
  ].join('\n'))
  process.exit(1)
}

let requestedRows = (() => {
  if (withoutAccessibilityTrust && flagValue('rows') === null) return null // resolved once the registry exists
  const raw = flagValue('rows')
  if (raw === null) return ALL_ROWS
  const rows = raw.split(',').map((entry) => entry.trim().toUpperCase()).filter(Boolean)
  const unknown = rows.filter((row) => !ALL_ROWS.includes(row))
  if (unknown.length > 0) {
    console.error(`macOS integration lane failed: unknown row(s) ${unknown.join(',')}`)
    process.exit(1)
  }
  if (rows.length === 0) {
    console.error('macOS integration lane failed: --rows selected nothing to run')
    process.exit(1)
  }
  return rows
})()

// ---------------------------------------------------------------------------
// Swift probe compilation (cached by source digest, never rebuilt blindly)
// ---------------------------------------------------------------------------

const requireSwiftc = () => {
  const probe = spawnSync('swiftc', ['--version'], { encoding: 'utf8' })
  if (probe.error || probe.status !== 0) {
    console.error(
      'macOS integration lane failed: `swiftc` is not available.\n\n' +
      'Install the Xcode command line tools (`xcode-select --install`) or select a\n' +
      'full Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.\n' +
      'The lane will not skip: the AX/CGEvent probe is the only thing that can\n' +
      'observe the macOS layer these rows are about.',
    )
    process.exit(1)
  }
  return (probe.stdout ?? '').trim().split('\n')[0] ?? 'swiftc'
}

const compileProbe = (name) => {
  const sourcePath = join(sourceDir, `${name}.swift`)
  if (!existsSync(sourcePath)) fail(`probe source is missing: ${relative(repositoryRoot, sourcePath)}`)
  const digest = createHash('sha256').update(readFileSync(sourcePath)).digest('hex').slice(0, 16)
  const binaryPath = join(cacheDir, `${name}-${digest}`)
  if (existsSync(binaryPath)) return { binaryPath, digest }
  mkdirSync(cacheDir, { recursive: true })
  const build = spawnSync('swiftc', ['-O', '-swift-version', '5', '-o', binaryPath, sourcePath], { encoding: 'utf8' })
  if (build.error || build.status !== 0) {
    fail(`could not compile ${name}.swift: ${(build.stderr ?? '').trim().slice(-2000)}`)
  }
  return { binaryPath, digest }
}

const probeSourceDigest = (name) => {
  const sourcePath = join(sourceDir, `${name}.swift`)
  if (!existsSync(sourcePath)) fail(`probe source is missing: ${relative(repositoryRoot, sourcePath)}`)
  return createHash('sha256').update(readFileSync(sourcePath)).digest('hex').slice(0, 16)
}

const PROBE_NAMES = ['AXProbe', 'HotkeyRival', 'SystemSettings']

/**
 * The Swift probes are not the only thing that decides what this lane
 * CLAIMS -- every assertion lives in this file. Binding evidence to the
 * probes alone left a hole: weaken or delete a check here, and the gate
 * would keep reusing evidence recorded before the change and keep
 * reporting PASS. That is precisely the vacuous green this lane exists to
 * prevent, so the runner's own source is part of what evidence is bound to.
 */
const laneSourceDigest = () =>
  createHash('sha256').update(readFileSync(join(repositoryRoot, 'tooling', 'verify-macos-integration.mjs'))).digest('hex').slice(0, 16)
const probeSourceDigests = () => Object.fromEntries(PROBE_NAMES.map((name) => [name, probeSourceDigest(name)]))

// ---------------------------------------------------------------------------
// Digest-bound evidence (D-47 idiom, same as package-once -> promotion)
// ---------------------------------------------------------------------------

/**
 * Running this lane costs the machine it runs on: it takes over the keyboard
 * and flips real system settings. Making that a precondition of EVERY gate
 * invocation would be unreasonable on a person's own workstation, so the
 * result is recorded against the exact artifact it was produced from and
 * reused for that artifact only.
 *
 * The reuse rules are deliberately strict, because a cache that can go stale
 * silently is worse than no cache:
 *   * A record is bound to one `applicationDigestSha256`. It is never reused
 *     for a different artifact.
 *   * It is also bound to the source digests of all three Swift probes. Edit
 *     a probe and the evidence stops counting.
 *   * A record only satisfies the gate if it covers EVERY row and every row
 *     passed. A recorded failure never satisfies anything.
 *   * Missing or stale evidence is a LOUD FAILURE naming the command that
 *     produces it -- never a skip, never a soft pass.
 * Reuse always prints the digest and the original run timestamp, so it can
 * never happen invisibly.
 */
const evidenceDir = join(cacheDir, 'evidence')
const evidencePathFor = (applicationDigest) => join(evidenceDir, `${applicationDigest}.json`)

const readEvidence = (applicationDigest) => {
  const path = evidencePathFor(applicationDigest)
  if (!existsSync(path)) return null
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

const writeEvidence = (manifest, rows) => {
  mkdirSync(evidenceDir, { recursive: true })
  const record = {
    applicationDigestSha256: manifest.applicationDigestSha256,
    executableDigestSha256: manifest.executableDigestSha256,
    laneSourceDigest: laneSourceDigest(),
    probeSourceDigests: probeSourceDigests(),
    recordedAt: new Date().toISOString(),
    rowSelection: rows.length === ALL_ROWS.length ? 'complete' : 'partial',
    rows: rows.map((row) => ({
      cases: row.cases,
      durationMs: row.durationMs,
      id: row.id,
      passed: row.passed,
      requiresAccessibilityTrust: ROW_REGISTRY[row.id]?.requiresAccessibilityTrust ?? null,
      title: row.title,
    })),
    sourceRevision: manifest.sourceRevision,
    totalCases: rows.reduce((sum, row) => sum + row.cases, 0),
  }
  writeFileSync(evidencePathFor(manifest.applicationDigestSha256), JSON.stringify(record, null, 2))
  console.log(`LANE_EVIDENCE recorded=true file=${evidencePathFor(manifest.applicationDigestSha256)} rows=${record.rows.length} cases=${record.totalCases}`)
  return record
}

const EVIDENCE_PRODUCTION_INSTRUCTION = [
  '',
  'This lane types on the real keyboard and changes real system settings, so',
  'it is NOT run on every gate invocation. It runs ONCE per packaged artifact,',
  'and the gate reuses that result for exactly that artifact digest.',
  '',
  'Produce the evidence for the artifact currently under test:',
  '',
  '    pnpm package:desktop && node tooling/verify-macos-integration.mjs --all',
  '',
  'It restores every setting it changes on every exit path, including an',
  'interruption. If a run is ever cut short in a way that leaves something',
  'changed, `node tooling/verify-macos-integration.mjs --restore` puts it back',
  'from the capture taken before the first mutation.',
].join('\n')

/** Runs a probe subcommand. Missing TCC permission is always fatal, never soft. */
const runProbe = (binaryPath, args, { allowFailure = false } = {}) => {
  const result = spawnSync(binaryPath, args, { encoding: 'utf8', timeout: 60_000 })
  const stderr = (result.stderr ?? '').trim()
  if (stderr.includes('accessibility_permission_denied')) {
    console.error(`macOS integration lane failed: ${stderr}\n\n${ACCESSIBILITY_GRANT_INSTRUCTION}`)
    process.exit(1)
  }
  if (result.status !== 0) {
    if (allowFailure) return { error: stderr, ok: false }
    fail(`probe ${args[0]} failed: ${stderr || `exited ${result.status}`}`)
  }
  try {
    return { ok: true, value: JSON.parse(result.stdout) }
  } catch {
    return fail(`probe ${args[0]} produced unparseable output: ${(result.stdout ?? '').slice(0, 400)}`)
  }
}

// ---------------------------------------------------------------------------
// Package manifest (never build -- consume what package-once produced)
// ---------------------------------------------------------------------------

const locatorName = `keepling-desktop-latest-manifest-${createHash('sha256').update(repositoryRoot).digest('hex').slice(0, 16)}.txt`

const loadManifest = () => {
  const explicit = flagValue('manifest')
  let manifestPath
  if (explicit) manifestPath = resolve(explicit)
  else {
    const locatorPath = join(tmpdir(), locatorName)
    if (!existsSync(locatorPath)) {
      console.error(
        'macOS integration lane failed: no package manifest is selected.\n\n' +
        'Run `pnpm package:desktop` first, or pass `--manifest <path>`. This lane\n' +
        'deliberately never invokes a build -- it must run against the exact bytes\n' +
        'the package-once step produced and every other lane already tested.',
      )
      process.exit(1)
    }
    manifestPath = readFileSync(locatorPath, 'utf8').trim()
  }
  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch {
    console.error(`macOS integration lane failed: package manifest is missing or invalid JSON at ${manifestPath}`)
    process.exit(1)
  }

  const assertOutsideRepository = (path, label) => {
    const candidate = resolve(path)
    const fromRepository = relative(repositoryRoot, candidate)
    if (fromRepository === '' || (!fromRepository.startsWith(`..${sep}`) && !isAbsolute(fromRepository))) {
      console.error(`macOS integration lane failed: ${label} must be outside the source repository`)
      process.exit(1)
    }
    return candidate
  }
  const copiedApplicationPath = assertOutsideRepository(manifest.copiedApplicationPath, 'copied application')
  const executablePath = assertOutsideRepository(manifest.executablePath, 'packaged executable')
  if (!copiedApplicationPath.endsWith('.app') || !existsSync(copiedApplicationPath)) {
    console.error('macOS integration lane failed: manifest does not select an existing copied .app')
    process.exit(1)
  }
  if (!existsSync(executablePath)) {
    console.error('macOS integration lane failed: manifest-selected executable does not exist')
    process.exit(1)
  }

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
  if (hashDirectory(copiedApplicationPath) !== manifest.applicationDigestSha256) {
    console.error('macOS integration lane failed: copied application digest does not match the package manifest')
    process.exit(1)
  }
  if (createHash('sha256').update(readFileSync(executablePath)).digest('hex') !== manifest.executableDigestSha256) {
    console.error('macOS integration lane failed: executable digest does not match the package manifest')
    process.exit(1)
  }
  return { ...manifest, copiedApplicationPath, executablePath, manifestPath }
}

// ---------------------------------------------------------------------------
// Application lifecycle
// ---------------------------------------------------------------------------

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const disposableProfiles = []
const liveApplications = new Set()

const allocateProfile = (label) => {
  const path = mkdtempSync(join(tmpdir(), `keepling-macos-${label}-`))
  disposableProfiles.push(path)
  return path
}

const launchApplication = async (manifest, probeBinary, { profilePath, syncMode = 'offline', extraEnv = {} }) => {
  // `--force-renderer-accessibility` makes Chromium publish its COMPLETE
  // accessibility tree from startup instead of racing an assistive client's
  // AXManualAccessibility request. It changes no shipped byte -- it is a
  // runtime switch, and it is exactly the state the app is in when a real
  // screen reader is running. Without it the tree is structurally correct
  // but attribute-poor (no live regions, no control values, no
  // aria-current), which would let this lane silently assert less than it
  // claims.
  const child = spawn(manifest.executablePath, ['--force-renderer-accessibility', `--user-data-dir=${profilePath}`], {
    env: {
      ...process.env,
      ...extraEnv,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_SYNC_MODE: syncMode,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const handle = { child, pid: child.pid, probeBinary }
  liveApplications.add(handle)

  const deadline = Date.now() + 45_000 * WAIT_SCALE
  for (;;) {
    if (child.exitCode !== null) fail(`the packaged application exited (${child.exitCode}) before presenting a window`)
    const windows = runProbe(probeBinary, ['windows', '--pid', String(child.pid)], { allowFailure: true })
    if (windows.ok && Array.isArray(windows.value.windows) && windows.value.windows.length > 0) break
    if (Date.now() > deadline) fail('the packaged application never presented an accessible window')
    await sleep(500)
  }
  runProbe(probeBinary, ['raise', '--pid', String(child.pid)])
  // Raising is asynchronous at the WindowServer. Wait for the application to
  // actually BE frontmost rather than for 600ms to pass, so nothing below
  // acts on a window that has not been activated yet.
  await waitFor('the application under test to become frontmost after launch', async () => {
    const frontmost = runProbe(probeBinary, ['frontmost'], { allowFailure: true })
    if (frontmost.ok && frontmost.value.pid === child.pid) return true
    runProbe(probeBinary, ['raise', '--pid', String(child.pid)], { allowFailure: true })
    return false
  }, { intervalMs: 200, onTimeout: 'return', timeoutMs: 10_000 })

  // Chromium only publishes its COMPLETE accessibility tree (ARIA live
  // regions, control values, aria-current) once an assistive client asks
  // for it AND the web content actually exists. Asking before the renderer
  // is up yields a structurally correct but attribute-poor tree, which
  // would make this lane assert less than it claims to. Re-arm after the
  // web area appears and wait for the richer attributes to land.
  await waitFor('the application accessibility tree to reach complete mode', async () => {
    runProbe(probeBinary, ['activate', '--pid', String(child.pid)], { allowFailure: true })
    const nodes = []
    const tree = runProbe(probeBinary, ['dump', '--pid', String(child.pid), '--depth', '40', '--max-nodes', '3000'], { allowFailure: true })
    if (!tree.ok) return false
    flatten(tree.value.tree, nodes)
    const hasWebArea = nodes.some((node) => node.role === 'AXWebArea')
    const hasAriaDetail = nodes.some((node) => typeof node.ariaLive === 'string' && node.ariaLive.length > 0)
    return hasWebArea && hasAriaDetail
  }, { intervalMs: 500, timeoutMs: 30_000 })
  return handle
}

/**
 * Launches the packaged app WITHOUT touching the accessibility API at all.
 * Readiness is established by successfully capturing the window's pixels,
 * which goes through ScreenCaptureKit's window list rather than AX. This is
 * what lets the rows tagged `requiresAccessibilityTrust: false` run on a
 * machine with no Accessibility grant.
 */
const launchApplicationWithoutAccessibility = async (manifest, { profilePath, syncMode = 'offline' }) => {
  const child = spawn(manifest.executablePath, [`--user-data-dir=${profilePath}`], {
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_SYNC_MODE: syncMode,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const handle = { child, pid: child.pid, probeBinary: null }
  liveApplications.add(handle)
  await waitFor('the packaged application window to become capturable', async () => {
    if (child.exitCode !== null) fail(`the packaged application exited (${child.exitCode}) before presenting a window`)
    const probe = runProbe(settingsState.probeBinary, ['contrast', '--pid', String(child.pid)], { allowFailure: true })
    return probe.ok
  }, { intervalMs: 700, timeoutMs: 45_000 })
  return handle
}

const quitApplication = async (handle) => {
  liveApplications.delete(handle)
  if (handle.child.exitCode !== null) return
  handle.child.kill('SIGTERM')
  const deadline = Date.now() + 8_000 * WAIT_SCALE
  while (handle.child.exitCode === null && Date.now() < deadline) await sleep(150)
  if (handle.child.exitCode === null) {
    handle.child.kill('SIGKILL')
    // Wait for the process to be REAPED, not for a guess at how long that
    // takes. The next row launches against the same accessibility session,
    // and a still-live process would leave a stale window in it.
    const killDeadline = Date.now() + 5_000 * WAIT_SCALE
    while (handle.child.exitCode === null && Date.now() < killDeadline) await sleep(100)
  }
}

// ---------------------------------------------------------------------------
// AX helpers
// ---------------------------------------------------------------------------

const dumpTree = (handle) => runProbe(handle.probeBinary, ['dump', '--pid', String(handle.pid), '--depth', '40', '--max-nodes', '3000']).value.tree

const flatten = (node, out = [], ancestry = []) => {
  const entry = { ...node, ancestry, subtree: node }
  delete entry.children
  out.push(entry)
  for (const child of node.children ?? []) flatten(child, out, [...ancestry, node])
  return out
}

/**
 * The text a screen reader would actually read out for an element: its own
 * name plus every descendant static text, in document order. Chromium only
 * computes an AXGroup's own `AXTitle` once the group is focusable/focused,
 * so relying on the group name alone would make this lane assert nothing
 * for an unfocused row.
 */
const subtreeText = (node) => {
  const parts = []
  const visit = (entry) => {
    for (const key of ['title', 'value', 'description']) {
      const text = entry[key]
      if (typeof text === 'string' && text.length > 0 && !parts.includes(text)) parts.push(text)
    }
    for (const child of entry.children ?? []) visit(child)
  }
  visit(node)
  return parts.join(' ')
}

/** The application's own web content, excluding the system menu bar. */
const webNodes = (handle) => {
  const tree = dumpTree(handle)
  const windows = (tree.children ?? []).filter((child) => child.role === 'AXWindow')
  const nodes = []
  for (const window of windows) flatten(window, nodes)
  return nodes
}

/**
 * Everything the app's own windows say, as one string. Used where a row
 * asserts that a person was TOLD something -- the copy is authored in
 * `main/application/presentation.ts` and rendered verbatim, so finding it in
 * the real AX tree is finding what a screen reader would read out.
 */
const windowText = (handle) =>
  webNodes(handle)
    .flatMap((node) => ['title', 'value', 'description'].map((key) => node[key]))
    .filter((text) => typeof text === 'string' && text.length > 0)
    .join(' | ')

const findNode = (nodes, predicate) => nodes.find(predicate) ?? null
const findNodes = (nodes, predicate) => nodes.filter(predicate)

const focusedElement = (handle) => runProbe(handle.probeBinary, ['focused', '--pid', String(handle.pid)]).value.focused

/**
 * Focus a person could actually operate: a real node, not the application
 * element, with a non-zero frame. Shared so that A4, A5 and A6 poll for the
 * same notion of "not lost" that they assert on, rather than each restating
 * it slightly differently.
 */
const usableFocus = (node) =>
  node !== null &&
  node !== undefined &&
  node.role !== 'AXApplication' &&
  (node.frame?.width ?? 0) > 0 &&
  (node.frame?.height ?? 0) > 0

/** How a focus observation is reported when an assertion about it fails. */
const describeFocus = (node) => (node ? `${node.role} "${node.title ?? ''}"` : 'nothing')

const focusIdentity = (node) =>
  node === null || node === undefined
    ? null
    : JSON.stringify([node.role, node.title ?? '', node.description ?? '', node.frame ?? null])

/**
 * ONE lane-wide multiplier for EVERY bounded wait in this file (O-32).
 *
 * The rows were tuned standalone and then run inside `--all`, which is
 * measurably ~1.6x slower: the earlier VoiceOver-layer rows leave an AX
 * client attached to the machine, and every focus change and every tree dump
 * costs more under one. Measured 2026-09-03: A3 took 29.5s inside `--all`
 * against 14.6-16.5s standalone, and failed at a 10s `settledFocus` deadline
 * that is generous in isolation. Row-by-row deadline tuning is how that
 * asymmetry was created; doing it again per row would recreate it.
 *
 * So there is exactly one knob, and it is applied UNIFORMLY rather than only
 * under `--all`. A mode-dependent factor would reintroduce the very split
 * this exists to remove -- deadlines that hold in one invocation and not in
 * another. Scaling weakens no assertion and costs nothing on the happy path:
 * a wait whose condition is already true returns on its first poll, so the
 * larger deadline is only ever SPENT on a genuine failure, where spending it
 * buys certainty that the failure is real rather than early.
 */
const WAIT_SCALE = 2

/**
 * Reads the AX focused element only once it has SETTLED, i.e. once it is
 * non-null and unchanged across consecutive reads. Mounting a dialog moves
 * focus in more than one step and leaves the application with NO focused
 * element in between, so a single read after a fixed sleep intermittently
 * observes that hole and reports "focus was on nothing" (the same class of
 * defect fixed for A6 in fbdf2b4).
 *
 * Settling is deliberately WEAKER than anything a row asserts: it waits for
 * focus to stop moving, never for focus to be on a particular element. A row
 * whose focus settles on the wrong thing -- or on the application element,
 * or on a removed zero-sized node -- still fails loudly. At the deadline it
 * returns whatever it last saw, including null, so a genuine "focus is lost"
 * product defect is still reported rather than being waited away.
 */
/**
 * `until` polls for the condition the CALLER is about to assert, rather than
 * for focus merely holding still. That distinction matters: a run of `null`
 * reads never "settles" -- each one resets the repeat counter -- so a slow
 * machine returns `null` at the deadline and the row reports "focus was on
 * nothing" even though focus arrives correctly a moment later. Measured: A4
 * failed this way on a loaded machine where A3 took 16s against its usual
 * 5.5s. Passing `until` does not weaken any assertion. The caller still
 * checks the returned node exactly as before; if the condition never holds
 * within the deadline, the last observation is returned and the check fails.
 */
const settledFocus = async (handle, { intervalMs = 150, stableReads = 3, timeoutMs = 6_000, until = null } = {}) => {
  const deadline = Date.now() + timeoutMs * WAIT_SCALE
  let lastIdentity = null
  let repeats = 0
  let node = null
  for (;;) {
    node = focusedElement(handle) ?? null
    if (until !== null) {
      if (until(node)) return node
      if (Date.now() >= deadline) return node
      await sleep(intervalMs)
      continue
    }
    const identity = focusIdentity(node)
    if (identity !== null && identity === lastIdentity) repeats += 1
    else repeats = identity === null ? 0 : 1
    lastIdentity = identity
    if (repeats >= stableReads) return node
    if (Date.now() >= deadline) return node
    await sleep(intervalMs)
  }
}

/**
 * CGEvent keystrokes go to whatever the OS considers frontmost. Asserting
 * that the app under test really is frontmost before every keystroke is
 * what stops this lane from silently typing into some other window and then
 * reporting a misleading failure (or, worse, a misleading pass).
 */
const ensureFrontmost = (handle) => {
  const deadline = Date.now() + 6_000 * WAIT_SCALE
  for (;;) {
    const frontmost = runProbe(handle.probeBinary, ['frontmost'], { allowFailure: true })
    if (frontmost.ok && frontmost.value.pid === handle.pid) return
    runProbe(handle.probeBinary, ['raise', '--pid', String(handle.pid)], { allowFailure: true })
    if (Date.now() > deadline) {
      fail(`the application under test (pid ${handle.pid}) never became frontmost, so keystrokes could not be delivered to it`)
    }
  }
}

/**
 * `raise: false` is essential for A9: forcing the application frontmost
 * would make the harness itself the "prior application", and the row would
 * then be measuring its own interference instead of the app's focus
 * restoration.
 */
const postKeys = (handle, sequence, { raise = true } = {}) => {
  if (raise) ensureFrontmost(handle)
  return runProbe(handle.probeBinary, ['key', '--sequence', sequence])
}

/**
 * THE RULE THIS FILE KEEPS, stated once so it is not reintroduced:
 *
 *   Poll for the condition you are about to assert. Never sleep a fixed
 *   amount and read once, and never poll for "the value stopped changing".
 *
 * A fixed sleep encodes a guess about the machine's speed, so it turns a
 * loaded machine into a red row on unchanged bytes -- five rows (A3, A4, A6,
 * A7, A14) flaked exactly that way, and because this lane's evidence is
 * cached against the artifact digest, one lucky sample became DURABLE green.
 * Quiescence is no safer: an absent focus and a pending dead key are both
 * stable indefinitely, so "it stopped changing" settles happily on the
 * failure state and reports a pass.
 *
 * Two mechanisms implement the rule and there are deliberately no others:
 * `settledFocus(handle, { until })` for AX focus, and `waitFor` for
 * everything else. Neither weakens an assertion. Where the assertion should
 * still be able to report WHAT it saw, pass `onTimeout: 'return'` so the
 * deadline hands the last (falsy) observation back to the caller and the
 * caller's own `check` fails with its own detail; the default instead fails
 * the row loudly, which is right when a missing precondition would make the
 * assertion vacuous rather than false.
 */
const waitFor = async (description, predicate, { timeoutMs = 12_000, intervalMs = 300, onTimeout = 'fail' } = {}) => {
  const deadline = Date.now() + timeoutMs * WAIT_SCALE
  let last = null
  for (;;) {
    last = await predicate()
    if (last) return last
    if (Date.now() > deadline) return onTimeout === 'return' ? last : fail(`timed out waiting for ${description}`)
    await sleep(intervalMs)
  }
}

// ---------------------------------------------------------------------------
// System settings: capture before mutation, restore on EVERY exit path
// ---------------------------------------------------------------------------

/**
 * Everything in here exists because this lane runs on a person's own Mac and
 * changes real system settings. The rules it keeps:
 *
 *   1. Nothing is mutated until the current value has been captured AND
 *      written to disk, so even a `kill -9` leaves a record of what to put
 *      back.
 *   2. Restore is registered on normal exit, on an exception, and on SIGINT
 *      and SIGTERM -- before the first mutation, not after.
 *   3. Restore is VERIFIED by re-reading every setting. A restore that
 *      cannot prove it worked is a lane failure, not a shrug.
 */
const settingsState = {
  applied: false,
  baseline: null,
  capturePath: null,
  inputSource: null,
  probeBinary: null,
  restored: false,
}

const readSystemSettings = () => runProbe(settingsState.probeBinary, ['capture']).value

const captureSystemSettings = () => {
  if (settingsState.baseline !== null) return settingsState.baseline
  const baseline = readSystemSettings()
  mkdirSync(cacheDir, { recursive: true })
  settingsState.capturePath = join(cacheDir, 'settings-capture.json')
  writeFileSync(settingsState.capturePath, JSON.stringify(baseline, null, 2))
  settingsState.baseline = baseline
  console.log(`SETTINGS captured=${Object.keys(baseline).filter((key) => key !== 'inputSource').length} file=${settingsState.capturePath}`)
  return baseline
}

const MANAGED_KEYS = ['appearance', 'differentiateWithoutColor', 'fullKeyboardAccess', 'increaseContrast', 'reduceMotion', 'reduceTransparency']

const PROTECTED_DOMAIN_INSTRUCTION = [
  '',
  'The Accessibility settings domain (`com.apple.universalaccess`) is protected',
  'by macOS privacy controls: an unentitled process may write to it and receive',
  'NO error while nothing is actually stored. That silent no-op is exactly the',
  'vacuous pass this lane exists to prevent, so it is treated as a failure.',
  '',
  'Open:  System Settings -> Privacy & Security -> Full Disk Access',
  'Then:  enable the application that runs this lane (the terminal, IDE, or CI',
  '       agent process), and restart it so the new grant takes effect.',
  '',
  'This is a one-time approval. The lane will NOT skip these rows without it.',
].join('\n')

/**
 * Applies settings and then VERIFIES the write landed by re-reading in a
 * SEPARATE process. An in-process read-back would be satisfied by the
 * preferences cache even when nothing reached disk.
 */
const applySystemSettings = (changes) => {
  captureSystemSettings()
  settingsState.applied = true
  runProbe(settingsState.probeBinary, ['apply', '--settings', JSON.stringify(changes)])
  const observed = readSystemSettings()
  const rejected = Object.entries(changes).filter(([key, value]) => JSON.stringify(observed[key] ?? null) !== JSON.stringify(value))
  if (rejected.length > 0) {
    const detail = rejected.map(([key, value]) => `${key}: asked for ${JSON.stringify(value)}, the system still reports ${JSON.stringify(observed[key] ?? null)}`).join('; ')
    console.error(`macOS integration lane failed: the operating system did not accept a setting change -- ${detail}\n${PROTECTED_DOMAIN_INSTRUCTION}`)
    restoreSystemSettings()
    process.exit(1)
  }
}

const selectInputSource = (identifier) => {
  captureSystemSettings()
  const previous = settingsState.baseline.inputSource?.id ?? null
  const result = runProbe(settingsState.probeBinary, ['select-input-source', '--id', identifier]).value
  settingsState.inputSource = { enabledByUs: result.enabledByUs === true, identifier, previous }
  return result
}

/**
 * Synchronous on purpose: `process.on('exit')` cannot await, and a restore
 * that only runs on the happy path is not a restore.
 */
const restoreSystemSettings = ({ verify = true } = {}) => {
  if (settingsState.baseline === null || settingsState.restored) return true
  settingsState.restored = true

  if (settingsState.inputSource !== null) {
    const { enabledByUs, identifier, previous } = settingsState.inputSource
    if (previous !== null) spawnSync(settingsState.probeBinary, ['select-input-source', '--id', previous], { encoding: 'utf8' })
    if (enabledByUs) spawnSync(settingsState.probeBinary, ['disable-input-source', '--id', identifier], { encoding: 'utf8' })
  }

  const restoreTo = {}
  for (const key of MANAGED_KEYS) restoreTo[key] = settingsState.baseline[key] ?? null
  spawnSync(settingsState.probeBinary, ['apply', '--settings', JSON.stringify(restoreTo)], { encoding: 'utf8' })

  if (!verify) return true
  const after = spawnSync(settingsState.probeBinary, ['capture'], { encoding: 'utf8' })
  let current
  try {
    current = JSON.parse(after.stdout)
  } catch {
    console.error('macOS integration lane failed: could not re-read system settings to verify restoration')
    return false
  }
  const differences = []
  for (const key of MANAGED_KEYS) {
    const expected = settingsState.baseline[key] ?? null
    const actual = current[key] ?? null
    if (JSON.stringify(expected) !== JSON.stringify(actual)) differences.push(`${key}: expected ${JSON.stringify(expected)}, found ${JSON.stringify(actual)}`)
  }
  const expectedSource = settingsState.baseline.inputSource?.id ?? null
  const actualSource = current.inputSource?.id ?? null
  if (expectedSource !== actualSource) differences.push(`inputSource: expected ${expectedSource}, found ${actualSource}`)
  const expectedEnabled = JSON.stringify(settingsState.baseline.inputSource?.enabled ?? [])
  const actualEnabled = JSON.stringify(current.inputSource?.enabled ?? [])
  if (expectedEnabled !== actualEnabled) differences.push(`enabled input sources: expected ${expectedEnabled}, found ${actualEnabled}`)

  if (differences.length > 0) {
    console.error(`SETTINGS restore=FAILED differences=${differences.length}`)
    for (const difference of differences) console.error(`  ${difference}`)
    console.error(`The captured original values remain at ${settingsState.capturePath}.`)
    return false
  }
  console.log('SETTINGS restore=VERIFIED every mutated setting matches its captured value')
  return true
}

let restoreFailed = false
const restoreOnExit = () => {
  if (!restoreSystemSettings()) restoreFailed = true
}
process.on('exit', restoreOnExit)
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {
    console.error(`\nmacOS integration lane interrupted by ${signal} -- restoring system settings before exiting.`)
    const ok = restoreSystemSettings()
    for (const handle of [...liveApplications]) handle.child.kill('SIGKILL')
    for (const path of disposableProfiles.splice(0)) rmSync(path, { force: true, recursive: true })
    process.exit(ok ? 130 : 1)
  })
}
process.on('uncaughtException', (error) => {
  console.error(`macOS integration lane failed: ${error instanceof Error ? error.stack ?? error.message : String(error)}`)
  restoreSystemSettings()
  process.exit(1)
})

// ---------------------------------------------------------------------------
// Row registry
// ---------------------------------------------------------------------------

const rowResults = []

const runRow = async (id, title, body) => {
  const startedAt = Date.now()
  const assertions = []
  const check = (claim, condition, detail = '') => {
    assertions.push({ claim, ok: Boolean(condition) })
    if (!condition) fail(`${id}: ${claim}${detail ? ` -- ${detail}` : ''}`)
  }
  try {
    await body(check)
  } catch (error) {
    if (!(error instanceof LaneFailure)) {
      const detail = error instanceof Error ? error.stack ?? error.message : String(error)
      console.error(`macOS integration lane failed: ${id}: ${detail}`)
      rowResults.push({ cases: assertions.length, durationMs: Date.now() - startedAt, id, passed: false, title })
      console.log(`ROW id=${id} status=FAIL cases=${assertions.length} duration_ms=${Date.now() - startedAt}`)
      throw new LaneFailure(`${id}: ${detail}`)
    }
    rowResults.push({ cases: assertions.length, durationMs: Date.now() - startedAt, id, passed: false, title })
    console.log(`ROW id=${id} status=FAIL cases=${assertions.length} duration_ms=${Date.now() - startedAt}`)
    throw error
  }
  if (assertions.length === 0) {
    console.log(`ROW id=${id} status=FAIL cases=0 duration_ms=${Date.now() - startedAt}`)
    fail(`${id} executed zero assertions -- a row that asserts nothing is never green`)
  }
  rowResults.push({ cases: assertions.length, durationMs: Date.now() - startedAt, id, passed: true, title })
  console.log(`ROW id=${id} status=PASS cases=${assertions.length} duration_ms=${Date.now() - startedAt}`)
}


// ---------------------------------------------------------------------------
// Shared row helpers
// ---------------------------------------------------------------------------

const CAPTURE_FIELD_LABEL = 'What do you want to keep?'

/**
 * Tabs (or shift-tabs) until the AX FOCUSED element satisfies `predicate`.
 * Everything about this is real: a real CGEvent Tab, and the focus answer
 * read back out of the AX tree rather than out of the DOM.
 */
const tabUntil = async (handle, description, predicate, { key = 'tab', limit = 24, raise = true } = {}) => {
  for (let step = 0; step < limit; step += 1) {
    const focused = focusedElement(handle)
    if (focused && predicate(focused)) return focused
    const before = focusIdentity(focused)
    postKeys(handle, key, { raise })
    // Wait for the press to LAND before deciding whether to press again.
    // A fixed 120ms cadence outruns a loaded renderer: presses queue up
    // while focus is read behind them, the budget is consumed by moves that
    // were never observed, and the row reports "could not reach X within N
    // presses" against a window that is working correctly. That is the
    // measured A3 failure -- traversal cycled the whole Quick Entry window
    // and stopped back on the capture field.
    //
    // The budget is NOT raised and the predicate is NOT relaxed. Focus that
    // genuinely never moves -- a real keyboard trap -- still burns every one
    // of the `limit` presses and still fails with what it last saw, because
    // this wait returns at its own deadline rather than failing the row.
    await waitFor(
      `keyboard focus to move after a ${key} press`,
      async () => focusIdentity(focusedElement(handle)) !== before,
      { intervalMs: 60, onTimeout: 'return', timeoutMs: 1_000 },
    )
  }
  const focused = focusedElement(handle)
  if (focused && predicate(focused)) return focused
  return fail(`could not reach ${description} by keyboard within ${limit} ${key} presses (focus stopped on ${focused ? `${focused.role} "${focused.title ?? ''}"` : 'nothing'})`)
}

const ancestryText = (node) =>
  [...(node.ancestors ?? [])].map((entry) => `${entry.title ?? ''} ${entry.description ?? ''} ${entry.value ?? ''}`).join(' | ')

/** A labelled text field and its current value, read back out of the AX tree. */
const textFieldNode = (handle, title) =>
  findNode(webNodes(handle), (node) => node.role === 'AXTextField' && node.title === title) ?? null
const textFieldValue = (handle, title) => {
  const node = textFieldNode(handle, title)
  return node === null ? null : node.value ?? ''
}

/**
 * Types real CGEvent keystrokes and does not return until the field actually
 * CONTAINS them.
 *
 * Every controllable consequence of typing -- a Save button arming, a discard
 * confirmation becoming reachable, a form becoming dirty -- is downstream of
 * the renderer having processed the keystrokes and repainted. Sleeping a
 * fixed amount and then tabbing means acting on a window that may still be
 * showing the previous frame, which is how A3 exhausted its tab budget
 * looking for a Discard Draft button that did not exist yet.
 *
 * This asserts nothing: it establishes the precondition the caller's own
 * assertions depend on. If the text never arrives, the row fails HERE, loudly
 * and with the reason, instead of failing later as a misleading "could not
 * reach X by keyboard".
 */
const typeIntoField = async (handle, title, text, { exact = true, expect = null, raise = true } = {}) => {
  // `expect` is what the field should READ once the keystrokes land, which is
  // not the same as what was typed when the text is appended to an existing
  // value. Waiting on the wrong one would wait forever on a correct app.
  const wanted = expect ?? text
  postKeys(handle, `text:${text}`, { raise })
  // ANY field carrying this label counts. While Quick Entry is open the main
  // window's own capture field is still in the tree with the same label, and
  // insisting on the first match would wait for the wrong one forever.
  await waitFor(`the typed text "${text}" to reach a "${title}" field`, async () =>
    findNodes(webNodes(handle), (node) => node.role === 'AXTextField' && node.title === title)
      .some((node) => {
        const value = node.value ?? ''
        return exact ? value === wanted : value.includes(wanted)
      }),
  { intervalMs: 100, timeoutMs: 10_000 })
}

const captureTaskByKeyboard = async (handle, title) => {
  postKeys(handle, 'cmd+n')
  // Cmd-N is the app's own "new task" command. Wait for the field it is
  // supposed to produce, not for 400ms, before tabbing towards it.
  await waitFor('the capture field to be present after cmd+n', async () => textFieldNode(handle, CAPTURE_FIELD_LABEL) !== null)
  await tabUntil(handle, 'the capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
  await typeIntoField(handle, CAPTURE_FIELD_LABEL, title)
  await tabUntil(handle, 'the Add Task button', (node) => node.role === 'AXButton' && node.title === 'Add Task')
  postKeys(handle, 'space')
  await waitFor(`the captured task "${title}" to appear in the AX tree`, async () =>
    taskRows(handle).some((row) => row.text.includes(title)))
}

/** Direct children of the labelled task list -- one entry per visible task. */
const taskRows = (handle, nodes = webNodes(handle)) => {
  const rows = findNodes(nodes, (node) => {
    const parent = (node.ancestry ?? [])[(node.ancestry ?? []).length - 1]
    return parent !== undefined && parent.role === 'AXList' && parent.description === 'Tasks'
  })
  return rows.map((row) => ({ ...row, text: subtreeText(row.subtree) }))
}

// ---------------------------------------------------------------------------
// Rows A1-A4 -- the screen-reader layer, read from the real AXUIElement tree
// ---------------------------------------------------------------------------

const rowA1 = (context) => runRow('A1', 'VoiceOver layer: capture', async (check) => {
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a1') })
  try {
    const nodes = webNodes(handle)
    const field = findNode(nodes, (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    check('the capture field exposes its label to the accessibility tree', field !== null)

    const addTask = findNode(nodes, (node) => node.role === 'AXButton' && node.title === 'Add Task')
    check('the Add Task button exposes its name to the accessibility tree', addTask !== null)
    // A1 asks for the button's name AND state. With an empty field the
    // button is legitimately disabled -- what matters is that the state is
    // exposed at all, and that it tracks reality.
    check('the Add Task button exposes its enabled state', typeof addTask?.enabled === 'boolean')
    check('the Add Task button is announced as disabled while there is nothing to add', addTask?.enabled === false)

    // Cmd-N is the app's own "new task" command; the AX tree, not the DOM,
    // is what confirms focus actually landed on the labelled field.
    postKeys(handle, 'cmd+n')
    await waitFor('the capture field to be present after cmd+n', async () => textFieldNode(handle, CAPTURE_FIELD_LABEL) !== null)
    const focusedField = await tabUntil(handle, 'the capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    check('the capture field can hold accessibility focus', focusedField.role === 'AXTextField')

    postKeys(handle, 'text:Prove the screen reader layer')
    const typed = await waitFor('the typed title to reach the capture field', async () => {
      const node = findNode(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL)
      return node && node.value === 'Prove the screen reader layer' ? node : null
    })
    check('real CGEvent keystrokes reach the capture field and are readable as AXValue', typed.value === 'Prove the screen reader layer')
    // The enabled state is re-announced a beat after the value lands, so poll
    // for the enabled button rather than sampling once behind the value read.
    const addTaskButton = () => findNode(webNodes(handle), (node) => node.role === 'AXButton' && node.title === 'Add Task')
    const armed = await waitFor(
      'the Add Task button to be announced as enabled',
      async () => { const node = addTaskButton(); return node?.enabled === true ? node : null },
      { onTimeout: 'return' },
    ) ?? addTaskButton()
    check(
      'the Add Task button announces the state change to enabled once there is something to add',
      armed?.enabled === true,
      `Add Task announced enabled=${JSON.stringify(armed?.enabled ?? null)}`,
    )

    await tabUntil(handle, 'the Add Task button', (node) => node.role === 'AXButton' && node.title === 'Add Task')
    postKeys(handle, 'space')
    // The row's title and its sync status are announced in two separate
    // paints: the row appears, then persistence resolves and "Saved on this
    // Mac" joins the same announcement. Waiting only for the title and then
    // asserting on the status raced that second paint.
    const capturedRow = () => taskRows(handle).find((entry) => entry.text.includes('Prove the screen reader layer')) ?? null
    const row = await waitFor(
      'the captured task to appear with its sync status',
      async () => { const entry = capturedRow(); return entry !== null && entry.text.includes('Saved on this Mac') ? entry : null },
      { onTimeout: 'return' },
    ) ?? capturedRow()
    check('the captured task announces its title', (row?.text ?? '').includes('Prove the screen reader layer'), `row announcement was "${row?.text ?? ''}"`)
    check(
      'the post-submit "Saved on this Mac" status is discoverable in the same announcement, without a second interaction',
      (row?.text ?? '').includes('Saved on this Mac'),
      `row announcement was "${row?.text ?? ''}"`,
    )
    const liveRegions = findNodes(webNodes(handle), (node) => node.ariaLive === 'polite')
    check(
      'a polite live region is present at the macOS accessibility layer to carry acknowledgements',
      liveRegions.length >= 1,
      `saw ${liveRegions.length} polite live region(s)`,
    )
  } finally {
    await quitApplication(handle)
  }
})

const rowA2 = (context) => runRow('A2', 'VoiceOver layer: list navigation and selection', async (check) => {
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a2') })
  try {
    await captureTaskByKeyboard(handle, 'First task')
    await captureTaskByKeyboard(handle, 'Second task')

    // Both rows announce their sync status a beat after they appear, so poll
    // for the announcement this row asserts on instead of sampling once.
    const bothRows = () => taskRows(handle)
    const rows = await waitFor(
      'both captured tasks to announce their titles and their sync status',
      async () => {
        const entries = bothRows()
        return entries.length === 2 && entries.every((entry) => entry.text.includes('Saved on this Mac')) ? entries : null
      },
      { onTimeout: 'return' },
    ) ?? bothRows()
    check('both captured tasks are exposed as rows of the labelled task list', rows.length === 2, `saw ${rows.length}`)
    for (const title of ['First task', 'Second task']) {
      const row = rows.find((entry) => entry.text.includes(title))
      check(
        `row "${title}" announces its title and its sync status together`,
        row !== undefined && row.text.includes('Saved on this Mac'),
        row === undefined ? 'row not found' : `announcement was "${row.text}"`,
      )
    }
    check('no task is selected before anything is chosen', rows.every((row) => row.ariaCurrent === undefined))

    const firstRow = await tabUntil(handle, 'the task list', (node) =>
      node.role === 'AXGroup' && ancestryText(node).includes('Tasks'))
    check('a task row can hold roving accessibility focus', (firstRow.title ?? '').length > 0, `focused row name was "${firstRow.title ?? ''}"`)
    check('roving focus alone never marks a task as selected', firstRow.ariaCurrent === undefined)

    postKeys(handle, 'down')
    // Roving focus moves in two steps -- the old row gives focus up before the
    // new one takes it -- so a single read after a fixed sleep can land in the
    // hole between them and report that focus never moved.
    const movedRow = await settledFocus(handle, {
      timeoutMs: 8_000,
      until: (node) => node !== null && node.title !== firstRow.title,
    })
    check(
      'arrow-key navigation moves accessibility focus between rows',
      movedRow !== null && movedRow.title !== firstRow.title,
      `focus was on ${movedRow ? `${movedRow.role} "${movedRow.title ?? ''}"` : 'nothing'} after focusing "${firstRow.title ?? ''}"`,
    )
    check('arrow-key navigation still selects nothing', movedRow !== null && movedRow.ariaCurrent === undefined, `ariaCurrent=${movedRow?.ariaCurrent ?? 'unset'}`)

    postKeys(handle, 'return')
    const selection = () => taskRows(handle).filter((row) => row.ariaCurrent === 'true')
    const selectedRows = await waitFor(
      'exactly one task to be marked as selected',
      async () => { const marked = selection(); return marked.length === 1 ? marked : null },
      { onTimeout: 'return' },
    ) ?? selection()
    check('Return selects exactly one task -- the roving-focused one', selectedRows.length === 1, `saw ${selectedRows.length} selected`)
    const movedTitle = String(movedRow?.title ?? '').split(' Saved')[0]
    check(
      'the selected task is the row focus had reached, by stable identity',
      selectedRows[0] !== undefined && selectedRows[0].text.includes(movedTitle),
      `selected "${selectedRows[0]?.text ?? ''}" after focusing "${movedTitle}"`,
    )

    postKeys(handle, 'up')
    const focusedAfter = await settledFocus(handle, {
      timeoutMs: 8_000,
      until: (node) => node !== null && node.ariaCurrent === undefined,
    })
    check(
      'the SELECTED task stays distinguishable from the VoiceOver-focused row (D-05)',
      focusedAfter !== null && focusedAfter.ariaCurrent === undefined && taskRows(handle).some((row) => row.ariaCurrent === 'true'),
      `focus was on ${focusedAfter ? `${focusedAfter.role} "${focusedAfter.title ?? ''}"` : 'nothing'} reporting ariaCurrent=${focusedAfter?.ariaCurrent ?? 'unset'}`,
    )
  } finally {
    await quitApplication(handle)
  }
})

const rowA3 = (context) => runRow('A3', 'VoiceOver layer: dialogs announce themselves', async (check) => {
  const profilePath = allocateProfile('a3')
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath })
  try {
    // Quick Entry discard-draft confirmation, opened through the REAL global
    // accelerator rather than a menu click.
    postKeys(handle, 'ctrl+alt+space')
    const quickEntryField = await waitFor('the Quick Entry window', async () => {
      const node = findNode(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL && ancestryText(entry).includes('Quick Entry'))
      return node ?? (findNodes(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL).length > 1 ? true : null)
    })
    check('the real global accelerator opens Quick Entry', quickEntryField !== null)

    await tabUntil(handle, 'the Quick Entry capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    // The Discard Draft button only EXISTS once the draft is non-empty, so
    // tabbing for it before the keystrokes have been processed and repainted
    // searches a window that legitimately does not contain it yet. Measured
    // failure: "could not reach the Discard Draft button by keyboard within
    // 24 tab presses (focus stopped on AXTextField \"What do you want to
    // keep?\")" -- traversal had cycled the whole window. Wait for the
    // field's own value, then for the button the value produces.
    await typeIntoField(handle, CAPTURE_FIELD_LABEL, 'Draft to discard')
    await waitFor('the Discard Draft button to be produced by the non-empty draft', async () =>
      findNode(webNodes(handle), (node) => node.role === 'AXButton' && (node.title ?? '').startsWith('Discard Draft')) !== null)
    await tabUntil(handle, 'the Discard Draft button', (node) => node.role === 'AXButton' && (node.title ?? '').startsWith('Discard Draft'))
    postKeys(handle, 'space')

    const discardFocus = await settledFocus(handle, {
      timeoutMs: 10_000,
      until: (node) => (node?.title ?? '') === 'Keep Draft',
    })
    check(
      'the discard-draft confirmation moves focus into itself',
      discardFocus !== null && (discardFocus.title ?? '') === 'Keep Draft',
      `focus was on ${discardFocus ? `${discardFocus.role} "${discardFocus.title ?? ''}"` : 'nothing'}`,
    )
    check(
      'a screen reader hears the dialog heading immediately, without exploring the window',
      discardFocus !== null && ancestryText(discardFocus).includes('Discard Quick Entry Draft?'),
      `ancestry was "${discardFocus === null ? '' : ancestryText(discardFocus)}"`,
    )
    // Keep Draft: wait for the confirmation to actually go away before
    // pressing Escape, so Escape cannot land on the dialog it was never
    // meant for.
    postKeys(handle, 'space')
    await waitFor('the discard-draft confirmation to close', async () =>
      findNode(webNodes(handle), (node) => (node.title ?? '').includes('Discard Quick Entry Draft?') || (node.description ?? '').includes('Discard Quick Entry Draft?')) === null)
    await returnFocusIntoQuickEntry(handle)
    postKeys(handle, 'escape')
    await waitFor('Quick Entry to close', async () => !quickEntryIsOpen(handle))

    await captureTaskByKeyboard(handle, 'Buy milk')
  } finally {
    await quitApplication(handle)
  }

  // An inline sync conflict, produced by the same fixture the E2E suite
  // uses, against the SAME profile.
  const conflictHandle = await launchApplication(context.manifest, context.axProbe, { profilePath, syncMode: 'conflict' })
  try {
    const heading = await waitFor('the inline conflict presentation', async () =>
      findNode(webNodes(conflictHandle), (node) =>
        node.role === 'AXHeading' && subtreeText(node.subtree).includes('This task changed somewhere else.')) ?? null)
    check('an inline sync conflict is announced as a heading', heading.role === 'AXHeading')
    // The heading MOUNTS before the app moves focus onto it, so reading focus
    // the instant the heading appears samples the gap in between and reports
    // "focus was on nothing" against product code that is working. Poll for
    // the focus the check below asserts on; a conflict that genuinely never
    // takes focus still fails at the deadline, with what it saw instead.
    const focused = await settledFocus(conflictHandle, {
      timeoutMs: 10_000,
      until: (node) => (node?.title ?? '').includes('This task changed somewhere else.'),
    })
    check(
      'the conflict moves focus to its own heading so the interruption is announced',
      focused !== null && (focused.title ?? '').includes('This task changed somewhere else.'),
      `focus was on ${focused ? `${focused.role} "${focused.title ?? ''}"` : 'nothing'}`,
    )
  } finally {
    await quitApplication(conflictHandle)
  }
})

const rowA4 = (context) => runRow('A4', 'VoiceOver layer: the unsaved-changes dialog', async (check) => {
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a4') })
  try {
    await captureTaskByKeyboard(handle, 'Edit me')

    await tabUntil(handle, 'the task row', (node) =>
      node.role === 'AXGroup' && ancestryText(node).includes('Tasks') && (node.title ?? '').includes('Edit me'))
    postKeys(handle, 'return')
    // Opening a task mounts the detail editor. Tabbing for the Title field
    // before it mounts spends the budget on the list instead.
    await waitFor('the task detail editor to mount', async () => textFieldNode(handle, 'Title') !== null)

    const titleField = await tabUntil(handle, 'the task title editor', (node) => node.role === 'AXTextField' && node.title === 'Title')
    check('the task title editor is reachable by keyboard and exposes its label', titleField.title === 'Title')
    postKeys(handle, 'right')
    // The unsaved-changes guard only arms once the form is actually dirty, so
    // wait for the edit to be readable in the field rather than for 300ms.
    await typeIntoField(handle, 'Title', ' unsaved', { exact: false })

    // Navigate away using the destination control itself, reached by
    // keyboard. (The Cmd-2 accelerator routes straight through
    // `facade.setRoute` in the desktop shell and therefore bypasses the
    // unsaved-changes guard entirely -- recorded as a finding rather than
    // silently worked around; see this plan's SUMMARY.)
    await tabUntil(handle, 'the Today destination button', (node) => node.role === 'AXButton' && node.title === 'Today', { key: 'shift+tab', limit: 24 })
    postKeys(handle, 'space')
    await waitFor('the unsaved-changes dialog to mount', async () =>
      findNode(webNodes(handle), (node) => (node.description ?? '') === 'Discard unsaved changes?' || (node.title ?? '') === 'Discard unsaved changes?'),
    { intervalMs: 150, timeoutMs: 10_000 })

    const nodes = webNodes(handle)
    const dialog = findNode(nodes, (node) => (node.description ?? '') === 'Discard unsaved changes?' || (node.title ?? '') === 'Discard unsaved changes?')
    check('navigating away with unsaved edits raises the unsaved-changes dialog', dialog !== null)

    const focused = await settledFocus(handle, {
      timeoutMs: 15_000,
      until: (node) => (node?.title ?? '') === 'Keep Editing',
    })
    check(
      'the unsaved-changes dialog moves focus INTO itself (previously a disclosed gap, fixed in 03-15)',
      focused !== null && (focused.title ?? '') === 'Keep Editing',
      `focus was on ${describeFocus(focused)}`,
    )
    check(
      'the safe, non-destructive action is the one focus lands on',
      (focused?.title ?? '') === 'Keep Editing',
    )
    check(
      'a screen reader hears the dialog heading immediately',
      focused !== null && ancestryText(focused).includes('Discard unsaved changes?'),
      `ancestry was "${focused === null ? '' : ancestryText(focused)}"`,
    )

    postKeys(handle, 'space')
    const afterClose = await settledFocus(handle, { timeoutMs: 15_000, until: usableFocus })
    check(
      'closing the dialog leaves focus on a visible, operable element -- never the application element, never a removed node',
      usableFocus(afterClose),
      `focus was on ${describeFocus(afterClose)}`,
    )
  } finally {
    await quitApplication(handle)
  }
})


// ---------------------------------------------------------------------------
// Rows A5-A7 -- real keyboard access, real keystrokes, real input sources
// ---------------------------------------------------------------------------

/**
 * No trailing sleep. Every call site in this file follows the activation with
 * a `waitFor` on the consequence it actually cares about (a row leaving a
 * list, a button being replaced by its counterpart), which is a stronger and
 * cheaper wait than any fixed pause. A sleep here would only delay that wait.
 */
const activateButton = async (handle, name) => {
  await tabUntil(handle, `the "${name}" button`, (node) => node.role === 'AXButton' && node.title === name)
  postKeys(handle, 'space')
}

/** Moves roving focus to a task row by name and opens it -- keyboard only. */
const openTaskByKeyboard = async (handle, titleFragment) => {
  await tabUntil(handle, `the "${titleFragment}" task row`, (node) =>
    node.role === 'AXGroup' && ancestryText(node).includes('Tasks') && (node.title ?? '').includes(titleFragment))
  postKeys(handle, 'return')
  // Opening is only complete once the detail editor exists; the next action
  // is always aimed at a control inside it.
  await waitFor('the task detail editor to mount', async () => textFieldNode(handle, 'Title') !== null)
}

const hasButton = (handle, name) => findNode(webNodes(handle), (node) => node.role === 'AXButton' && node.title === name) !== null

/**
 * Puts keyboard focus back INSIDE the Quick Entry form before a key that the
 * form itself has to interpret (Escape) is posted.
 *
 * MEASURED 2026-09-03 on application_digest=937b279c..., recorded as an open
 * item rather than worked around silently: dismissing the discard
 * confirmation with "Keep Draft" leaves AX focus on the window's AXWebArea --
 * the document, not the "Discard Draft..." button that opened the dialog.
 * Quick Entry's Escape handler is bound to a div INSIDE the React root, so a
 * keydown targeted at the document never reaches it and Escape silently does
 * nothing. Observed directly: focus "AXWebArea \"Keepling\"", Escape posted,
 * both windows still present 2s later; tab back into the field first and the
 * same Escape hides the window immediately.
 *
 * This is TEARDOWN, not an assertion: A3 and A6 use Escape here only to get
 * back to the main window, and neither claims anything about Escape. Nothing
 * is weakened -- focus restoration after a dialog is still asserted by A6,
 * and the underlying defect is filed, not hidden.
 */
const returnFocusIntoQuickEntry = async (handle) => {
  await tabUntil(handle, 'the Quick Entry capture field', (node) =>
    node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
}

const rowA5 = (context) => runRow('A5', 'Full Keyboard Access: the complete scoped sequence, keyboard only', async (check) => {
  applySystemSettings({ fullKeyboardAccess: 3 })
  const settings = readSystemSettings()
  check('Full Keyboard Access is genuinely enabled at the OS level before the sequence runs', settings.fullKeyboardAccess === 3, `AppleKeyboardUIMode=${settings.fullKeyboardAccess}`)

  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a5') })
  try {
    // Every step below is driven by CGEvent keys alone. No mouse event is
    // ever posted by this lane, so "reachable by keyboard" is a property of
    // the run rather than a claim about it.
    await captureTaskByKeyboard(handle, 'Keyboard loop')
    check('capture is reachable by keyboard alone', taskRows(handle).some((row) => row.text.includes('Keyboard loop')))

    await openTaskByKeyboard(handle, 'Keyboard loop')
    const titleEditor = () => findNode(webNodes(handle), (node) => node.role === 'AXTextField' && node.title === 'Title')
    await waitFor('the task detail editor to mount', async () => titleEditor(), { onTimeout: 'return' })
    check('opening a task is reachable by keyboard alone', titleEditor() !== null)

    await tabUntil(handle, 'the task title editor', (node) => node.role === 'AXTextField' && node.title === 'Title')
    // Tabbing into a text field selects its contents; move the caret to the
    // end first so this appends rather than replacing the title.
    postKeys(handle, 'right')
    await typeIntoField(handle, 'Title', ' edited', { exact: false, expect: 'Keyboard loop edited' })
    await activateButton(handle, 'Save Changes')
    await waitFor('the edited title to reach the list', async () => taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    check('editing and saving are reachable by keyboard alone', taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    await activateButton(handle, 'Complete')
    await waitFor('the Reopen button to replace Complete', async () => hasButton(handle, 'Reopen'), { onTimeout: 'return' })
    check('completing is reachable by keyboard alone', hasButton(handle, 'Reopen'))
    await activateButton(handle, 'Reopen')
    await waitFor('the Complete button to come back', async () => hasButton(handle, 'Complete'), { onTimeout: 'return' })
    check('reopening is reachable by keyboard alone', hasButton(handle, 'Complete'))

    // Adding to Today moves the task OUT of Inbox, so the round trip has to
    // cross routes -- by keyboard, like everything else here.
    await activateButton(handle, 'Add to Today')
    await waitFor('the planned task to leave Inbox', async () => !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    await activateButton(handle, 'Today')
    await waitFor('the planned task to appear in Today', async () => taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    check('adding to Today is reachable by keyboard alone', taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    await openTaskByKeyboard(handle, 'Keyboard loop')
    await activateButton(handle, 'Remove from Today')
    await waitFor('the task to leave Today', async () => !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    check('removing from Today is reachable by keyboard alone', !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    await activateButton(handle, 'Inbox')
    await waitFor('the task to return to Inbox', async () => taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    await openTaskByKeyboard(handle, 'Keyboard loop')
    await activateButton(handle, 'Move to Trash')
    await waitFor('the trashed task to leave Inbox', async () => !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    check('trashing is reachable by keyboard alone', !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    await activateButton(handle, 'Trash')
    await waitFor('the trashed task to appear in Trash', async () => taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    await openTaskByKeyboard(handle, 'Keyboard loop')
    await activateButton(handle, 'Restore')
    await waitFor('the restored task to leave Trash', async () => !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))
    check('restoring is reachable by keyboard alone', !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    // O-45. This step USED to assert that Command-Z put the task back in
    // Trash. It no longer can, and the change is deliberate.
    //
    // `POST /commands/undo-task` takes a SERVER-ISSUED handle carried in the
    // acknowledgement. This row runs the packaged app with NO server
    // configured, so nothing is ever acknowledged and no handle exists. The
    // old behaviour reversed the projection and enqueued nothing -- an undo
    // durable on this Mac and invisible to the server forever, which is the
    // defect O-45 filed. Refusing, and SAYING so, is the honest answer.
    //
    // The row's claim is unchanged and is NOT weakened: it is about whether
    // the keystroke reaches the app and produces a real, authored response a
    // person can perceive -- and that is now asserted against copy found in
    // the real AXUIElement tree, which is stronger than the previous
    // list-membership check, plus the fact that nothing was changed.
    postKeys(handle, 'cmd+z')
    await waitFor('Keepling to answer the undo keystroke', async () => windowText(handle).includes('can’t be undone'))
    check('undo is reachable by keyboard alone, and Keepling answers it', windowText(handle).includes('can’t be undone'))
    check('a refused undo changes nothing -- the task stays restored', !taskRows(handle).some((row) => row.text.includes('Keyboard loop edited')))

    // The refusal row appears above the workspace, and for a beat the AX
    // tree reports no focused element at all. Poll for the same condition
    // this asserts.
    const stillFocused = (node) => node !== null && node.role !== 'AXApplication' && (node.frame?.width ?? 0) > 0
    const focused = await settledFocus(handle, { timeoutMs: 8_000, until: stillFocused })
    check(
      'after the whole sequence, focus is still on a visible, operable element -- never lost',
      stillFocused(focused),
      `focus was on ${describeFocus(focused)}`,
    )
  } finally {
    await quitApplication(handle)
  }
})

const rowA6 = (context) => runRow('A6', 'Full Keyboard Access: focus is never trapped or lost', async (check) => {
  applySystemSettings({ fullKeyboardAccess: 3 })
  check('Full Keyboard Access is enabled at the OS level', readSystemSettings().fullKeyboardAccess === 3)

  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a6') })
  try {
    // Focus must SETTLE on a usable element, which is not the same as being
    // usable at one arbitrary instant. Dismissing a dialog unmounts the node
    // focus was on, and for a beat the AX tree legitimately reports no focused
    // element at all while the app moves it somewhere safe. Sampling once
    // after a fixed sleep raced that beat: this row passed, passed, then
    // failed on the same application digest b7bd61a7, at a different case
    // each time.
    //
    // Polling to a deadline removes the race WITHOUT weakening the claim --
    // focus that never settles on a visible operable element still fails,
    // which is the actual defect this row exists to catch. A transient null
    // during a dismissal is not that defect; a permanent one is.
    //
    // The deadline is 10s, matching the two dialog-OPEN settles in this same
    // row rather than being half of them. That asymmetry was the race:
    // restoring focus after a dialog closes is the SLOWER operation of the
    // two -- the destructive branch commits a route change, re-renders the
    // list, and runs two focus effects -- yet it was given half the budget
    // of merely opening a dialog.
    //
    // Measured 2026-09-03 on application_digest=e1c9d695...: this row's
    // final case ("after discarding changes and navigating away") failed
    // inside a full `--all` run with `last read was nothing`, while the same
    // row passed 4/4 standalone. The `--all` context is measurably slower
    // (39.5s for the row against 24.9-25.5s standalone, ~1.6x) because the
    // preceding VoiceOver-layer rows leave an AX client attached, and every
    // focus change costs more under one.
    //
    // Raising the deadline weakens NOTHING. `usableFocus(last)` is still
    // asserted exactly as before, and `settledFocus` still returns whatever
    // it last saw at the deadline -- including null -- so focus that is
    // genuinely trapped or lost still fails this row loudly. What changes is
    // only that a slow machine is no longer reported as a lost-focus defect.
    const FOCUS_RESTORE_TIMEOUT_MS = 10_000
    const assertUsableFocus = async (label) => {
      const last = await settledFocus(handle, { intervalMs: 200, timeoutMs: FOCUS_RESTORE_TIMEOUT_MS, until: usableFocus })
      check(
        `${label}: focus is on a visible, operable element -- never the application element, never a removed node, never a silent reset`,
        usableFocus(last),
        `focus never settled within ${FOCUS_RESTORE_TIMEOUT_MS}ms; last read was ${last ? `${last.role} "${last.title ?? ''}" ${JSON.stringify(last.frame ?? null)}` : 'nothing'}`,
      )
      return last
    }

    // Dialog 1: Quick Entry discard-draft confirmation.
    postKeys(handle, 'ctrl+alt+space')
    await waitFor('Quick Entry to open from the real global accelerator', async () => quickEntryIsOpen(handle))
    await tabUntil(handle, 'the Quick Entry capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    // Same precondition as A3: Discard Draft does not exist until the draft
    // is non-empty, so wait for the draft, then for the button it produces.
    await typeIntoField(handle, CAPTURE_FIELD_LABEL, 'Draft')
    await waitFor('the Discard Draft button to be produced by the non-empty draft', async () =>
      findNode(webNodes(handle), (node) => node.role === 'AXButton' && (node.title ?? '').startsWith('Discard Draft')) !== null)
    await tabUntil(handle, 'the Discard Draft button', (node) => node.role === 'AXButton' && (node.title ?? '').startsWith('Discard Draft'))
    postKeys(handle, 'space')
    const keepDraft = await settledFocus(handle, { timeoutMs: 10_000, until: (node) => (node?.title ?? '') === 'Keep Draft' })
    check(
      'the Quick Entry discard dialog opens by keyboard alone',
      (keepDraft?.title ?? '') === 'Keep Draft',
      `focus was on ${describeFocus(keepDraft)}`,
    )
    postKeys(handle, 'space')
    // Wait for the dialog to be GONE before asserting where focus went; the
    // assertion is about focus after the dismissal, not during it.
    await waitFor('the Quick Entry discard dialog to close', async () => !hasButton(handle, 'Keep Draft'))
    await assertUsableFocus('after closing the Quick Entry discard dialog by keyboard')
    await returnFocusIntoQuickEntry(handle)
    postKeys(handle, 'escape')
    await waitFor('Quick Entry to close', async () => !quickEntryIsOpen(handle))

    // Dialog 2: the workspace unsaved-changes alertdialog.
    await captureTaskByKeyboard(handle, 'Focus safety')
    await tabUntil(handle, 'the task row', (node) => node.role === 'AXGroup' && ancestryText(node).includes('Tasks') && (node.title ?? '').includes('Focus safety'))
    postKeys(handle, 'return')
    await waitFor('the task detail editor to mount', async () => textFieldNode(handle, 'Title') !== null)
    await tabUntil(handle, 'the task title editor', (node) => node.role === 'AXTextField' && node.title === 'Title')
    postKeys(handle, 'right')
    await typeIntoField(handle, 'Title', ' dirty', { exact: false })
    await tabUntil(handle, 'the Today destination button', (node) => node.role === 'AXButton' && node.title === 'Today', { key: 'shift+tab', limit: 24 })
    postKeys(handle, 'space')
    const keepEditing = await settledFocus(handle, { timeoutMs: 10_000, until: (node) => (node?.title ?? '') === 'Keep Editing' })
    check(
      'the unsaved-changes dialog opens by keyboard alone',
      (keepEditing?.title ?? '') === 'Keep Editing',
      `focus was on ${describeFocus(keepEditing)}`,
    )
    postKeys(handle, 'space')
    await waitFor('the unsaved-changes dialog to close', async () => !hasButton(handle, 'Keep Editing'))
    await assertUsableFocus('after closing the unsaved-changes dialog by keyboard')

    // And once more through the destructive branch, which removes the
    // element focus was on -- the case a naive implementation strands.
    await tabUntil(handle, 'the Today destination button', (node) => node.role === 'AXButton' && node.title === 'Today', { key: 'shift+tab', limit: 24 })
    postKeys(handle, 'space')
    await waitFor('the unsaved-changes dialog to re-open', async () => hasButton(handle, 'Discard Changes'))
    await tabUntil(handle, 'the Discard Changes button', (node) => node.role === 'AXButton' && node.title === 'Discard Changes')
    postKeys(handle, 'space')
    await waitFor('the unsaved-changes dialog to close after discarding', async () => !hasButton(handle, 'Discard Changes'))
    await assertUsableFocus('after discarding changes and navigating away')
  } finally {
    await quitApplication(handle)
  }
})

const DEAD_KEY_LAYOUT = 'com.apple.keylayout.USInternational-PC'

const rowA7 = (context) => runRow('A7', 'Non-US layout with dead keys', async (check) => {
  const selection = selectInputSource(DEAD_KEY_LAYOUT)
  check('a non-US layout with dead keys is genuinely selected at the OS level', selection.selected === DEAD_KEY_LAYOUT, `selected ${selection.selected}`)

  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a7') })
  try {
    postKeys(handle, 'cmd+n')
    await waitFor('the capture field to be present after cmd+n', async () => textFieldNode(handle, CAPTURE_FIELD_LABEL) !== null)
    await tabUntil(handle, 'the capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    // Raw virtual key codes, so the OS composes through the ACTIVE input
    // source rather than this lane faking the result: `'` (dead acute) then
    // `e` must produce `é`.
    //
    // The two keystrokes are posted SEPARATELY, with the letter gated on the
    // dead key having actually landed, because a single burst with a fixed
    // `wait:120` between them intermittently lost the `e` and left the field
    // on the pending dead key ("Caf'"). Measured timeline: the dead key
    // appears as marked text within 100ms and then sits there INDEFINITELY
    // until the composing letter arrives -- so "the field stopped changing"
    // is not a safe settle condition here, but "the dead key is pending" is.
    const captureFieldNode = () =>
      findNode(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL) ?? null
    const captureFieldValue = () => {
      const node = captureFieldNode()
      return node === null ? null : node.value ?? ''
    }

    postKeys(handle, 'text:Caf')
    await waitFor('the literal prefix to reach the capture field', async () => captureFieldValue() === 'Caf', { intervalMs: 100, timeoutMs: 10_000 })
    postKeys(handle, 'code:39')
    await waitFor('the dead acute to land as a pending composition', async () => {
      const value = captureFieldValue()
      return value !== null && value !== 'Caf' && value.length > 0
    }, { intervalMs: 100, timeoutMs: 10_000 })
    postKeys(handle, 'e')

    const composed = await waitFor('the dead-key composition to resolve in the field', async () => {
      const node = captureFieldNode()
      const value = node === null ? '' : node.value ?? ''
      // Resolved means the pending dead key is gone: the composing letter
      // has been consumed one way or another. What it resolved TO is the
      // assertion below, which still fails loudly on "Caf'e" or "Cafe".
      return value.length > 0 && !value.endsWith("'") ? node : null
    }, { intervalMs: 100, timeoutMs: 10_000 })
    check(
      'a dead-key sequence composes the accented character in the field, read back as AXValue',
      composed.value === 'Café',
      `field value was "${composed.value}"`,
    )

    await tabUntil(handle, 'the Add Task button', (node) => node.role === 'AXButton' && node.title === 'Add Task')
    postKeys(handle, 'space')
    const row = await waitFor('the composed title to commit', async () =>
      taskRows(handle).find((entry) => entry.text.includes('Café')) ?? null)
    check('the composed character survives commit and is announced correctly', row.text.includes('Café'), `row announcement was "${row.text}"`)
  } finally {
    await quitApplication(handle)
  }
})

// ---------------------------------------------------------------------------
// Rows A10-A15 -- real system appearance settings, legibility measured in pixels
// ---------------------------------------------------------------------------

const WCAG_AA_BODY_TEXT = 4.5

const measureContrast = (handle) => runProbe(settingsState.probeBinary, ['contrast', '--pid', String(handle.pid)]).value

/**
 * The legibility rows for settings whose effect is purely visual. These
 * deliberately use NO accessibility API and post NO keystrokes: they launch
 * the packaged app, apply the real OS setting, and measure a WCAG contrast
 * ratio over the window's real rendered pixels. That is what makes them
 * runnable without an Accessibility (TCC) grant.
 *
 * They still need Screen Recording (there are no pixels to measure without
 * it) and, for the `com.apple.universalaccess` settings, the ability to
 * write that protected domain -- both surfaced as loud failures, never
 * skips.
 */
const pixelAppearanceRow = (id, title, { changes, live = false }) => (context) =>
  runRow(id, title, async (check) => {
    if (!live) applySystemSettings(changes)
    const handle = await launchApplicationWithoutAccessibility(context.manifest, { profilePath: allocateProfile(id.toLowerCase()) })
    try {
      const before = live ? measureContrast(handle) : null
      if (live) {
        // A14 is explicitly about a change made WHILE the app is open.
        applySystemSettings(changes)
        // The re-theme is delivered to a RUNNING application asynchronously:
        // the appearance daemon notifies AppKit, Chromium re-evaluates
        // `prefers-color-scheme`, and the window repaints. Measured on this
        // machine that takes ~4-5s, so the fixed 2s sleep this replaced
        // sampled the window mid-flight and A14 flaked on unchanged bytes --
        // PASS at 20:54:21 and FAIL ~30 minutes later on the identical
        // application_digest 5f8ad9fa. Poll until the repaint has SETTLED
        // instead. This does not weaken the row: if the background never
        // changes within the deadline, the loop exits and the
        // `re-themes live` check below fails exactly as it did before.
        //
        // The settle condition is every condition this row asserts, not just
        // "the background changed": a window caught mid-repaint can already
        // report a different background while its text has not been repainted
        // yet, which would measure a transient contrast ratio.
        await waitFor(
          'the live re-theme to settle into a legible window',
          async () => {
            const sample = measureContrast(handle)
            return JSON.stringify(sample.backgroundColour) !== JSON.stringify(before.backgroundColour) &&
              sample.distinctSignificantColours > 1 &&
              sample.bestRatio >= WCAG_AA_BODY_TEXT
              ? sample
              : null
          },
          { intervalMs: 300, onTimeout: 'return', timeoutMs: 15_000 },
        )
      }
      const applied = readSystemSettings()
      for (const [key, value] of Object.entries(changes)) {
        check(`${key} is genuinely applied as the real OS setting`, JSON.stringify(applied[key] ?? null) === JSON.stringify(value), `read back ${JSON.stringify(applied[key] ?? null)}`)
      }

      const measurement = measureContrast(handle)
      check(
        'the window still renders distinguishable content (more than one significant colour)',
        measurement.distinctSignificantColours > 1,
        `saw ${measurement.distinctSignificantColours}`,
      )
      check(
        `legibility is a MEASURED WCAG contrast ratio over rendered pixels, not an impression (>= ${WCAG_AA_BODY_TEXT}:1)`,
        measurement.bestRatio >= WCAG_AA_BODY_TEXT,
        `measured ${measurement.bestRatio.toFixed(2)}:1 between ${JSON.stringify(measurement.backgroundColour)} and ${JSON.stringify(measurement.foregroundColour)}`,
      )
      if (live && before !== null) {
        check(
          'the window re-themes live, without a relaunch',
          JSON.stringify(before.backgroundColour) !== JSON.stringify(measurement.backgroundColour),
          `background stayed ${JSON.stringify(measurement.backgroundColour)}`,
        )
      }
    } finally {
      await quitApplication(handle)
    }
  })

const rowA10 = pixelAppearanceRow('A10', 'Increase Contrast', { changes: { increaseContrast: true } })

const rowA11 = (context) => runRow('A11', 'Differentiate Without Color', async (check) => {
  applySystemSettings({ differentiateWithoutColor: true })
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a11') })
  try {
    await captureTaskByKeyboard(handle, 'A11 legibility')
    check('differentiateWithoutColor is genuinely applied as the real OS setting', readSystemSettings().differentiateWithoutColor === true)

    const measurement = measureContrast(handle)
    check(
      `legibility is a MEASURED WCAG contrast ratio over rendered pixels, not an impression (>= ${WCAG_AA_BODY_TEXT}:1)`,
      measurement.bestRatio >= WCAG_AA_BODY_TEXT,
      `measured ${measurement.bestRatio.toFixed(2)}:1`,
    )

    const rows = taskRows(handle)
    check(
      'sync status is conveyed by TEXT, not colour alone',
      rows.length > 0 && rows.every((row) => /Saved on this Mac|Synced|Draft/.test(row.text)),
      `row announcements were ${JSON.stringify(rows.map((row) => row.text))}`,
    )
    await tabUntil(handle, 'a task row', (node) => node.role === 'AXGroup' && ancestryText(node).includes('Tasks'))
    postKeys(handle, 'return')
    const isSelected = () => taskRows(handle).some((row) => row.ariaCurrent === 'true')
    await waitFor('the selected task to be marked with aria-current', async () => isSelected(), { onTimeout: 'return' })
    check(
      'selection is conveyed by a non-colour cue the accessibility layer can read (aria-current)',
      isSelected(),
      `row announcements were ${JSON.stringify(taskRows(handle).map((row) => `${row.text} ariaCurrent=${row.ariaCurrent ?? 'unset'}`))}`,
    )
    postKeys(handle, 'cmd+n')
    // The empty capture field and the disabled Add Task button are painted
    // together but announced independently, so poll for the announced state.
    const addTaskButton = () => findNode(webNodes(handle), (node) => node.role === 'AXButton' && node.title === 'Add Task')
    const addTask = await waitFor(
      'the Add Task button to be announced as disabled for the empty capture field',
      async () => { const node = addTaskButton(); return node?.enabled === false ? node : null },
      { onTimeout: 'return' },
    ) ?? addTaskButton()
    check(
      'an invalid capture is conveyed as an announced control state, not a colour',
      addTask?.enabled === false,
      `Add Task announced enabled=${JSON.stringify(addTask?.enabled ?? null)}`,
    )
  } finally {
    await quitApplication(handle)
  }
})

const rowA12 = pixelAppearanceRow('A12', 'Reduce Transparency', { changes: { reduceTransparency: true } })
const rowA13 = pixelAppearanceRow('A13', 'Reduce Motion', { changes: { reduceMotion: true } })
const rowA14 = pixelAppearanceRow('A14', 'Light/Dark change while the app is open', { changes: { appearance: 'Dark' }, live: true })

const rowA15 = (context) => runRow('A15', '200% zoom equivalent: no primary control is clipped', async (check) => {
  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a15') })
  try {
    await captureTaskByKeyboard(handle, 'Zoom legibility')

    // A display scaled to ~200% halves the logical viewport the window gets.
    // Resizing the real window through the accessibility API reproduces that
    // logical size against the real packaged app.
    const before = runProbe(handle.probeBinary, ['windows', '--pid', String(handle.pid)]).value.windows[0].frame
    const resized = runProbe(handle.probeBinary, ['resize', '--pid', String(handle.pid), '--width', '520', '--height', '420']).value
    const windowFrame = resized.window.frame
    // A ~200% scaled display halves the logical space the window gets. The
    // window shrinks to the smallest size the app itself permits; the claim
    // under test is that NOTHING is clipped at that floor, not that the app
    // will shrink without limit.
    check(
      'the window really does shrink toward the reduced logical size a ~200% scaled display produces',
      windowFrame.width < before.width && windowFrame.height < before.height,
      `before ${JSON.stringify(before)} after ${JSON.stringify(windowFrame)}`,
    )
    const primaryControls = [
      { predicate: (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL, name: 'the capture field' },
      { predicate: (node) => node.role === 'AXButton' && node.title === 'Add Task', name: 'the Add Task button' },
      { predicate: (node) => node.role === 'AXButton' && node.title === 'Inbox', name: 'the Inbox destination' },
      { predicate: (node) => node.role === 'AXButton' && node.title === 'Today', name: 'the Today destination' },
      { predicate: (node) => node.role === 'AXButton' && node.title === 'Trash', name: 'the Trash destination' },
      { predicate: (node) => node.role === 'AXList' && node.description === 'Tasks', name: 'the task list' },
    ]
    const unclipped = (frame) =>
      frame !== null &&
      frame.width > 0 &&
      frame.height > 0 &&
      frame.x >= windowFrame.x - 1 &&
      frame.y >= windowFrame.y - 1 &&
      frame.x + frame.width <= windowFrame.x + windowFrame.width + 1 &&
      frame.y + frame.height <= windowFrame.y + windowFrame.height + 1

    // Reflow after a resize is asynchronous: controls are re-laid-out over
    // several frames, and reading the tree once after a fixed 800ms could
    // measure a control mid-flight, still reported at its pre-resize frame
    // and therefore "clipped". Poll for the settled layout this asserts on --
    // a control that is genuinely clipped never satisfies it and still fails
    // below, with the frame it actually had.
    const settledNodes = await waitFor(
      'the layout to settle at the reduced window size',
      async () => {
        const sample = webNodes(handle)
        return primaryControls.every((control) => unclipped(findNode(sample, control.predicate)?.frame ?? null)) ? sample : null
      },
      { intervalMs: 250, onTimeout: 'return', timeoutMs: 10_000 },
    )
    const nodes = settledNodes ?? webNodes(handle)
    for (const control of primaryControls) {
      const frame = findNode(nodes, control.predicate)?.frame ?? null
      check(`${control.name} stays visible and unclipped at the reduced size`, unclipped(frame), `frame ${JSON.stringify(frame)} against window ${JSON.stringify(windowFrame)}`)
    }
  } finally {
    await quitApplication(handle)
  }
})

// ---------------------------------------------------------------------------
// Rows A8-A9 -- real OS arbitration and real prior-application focus
// ---------------------------------------------------------------------------

const QUICK_ENTRY_ACCELERATOR = 'ctrl+alt+space'

const windowTitles = (handle) =>
  runProbe(handle.probeBinary, ['windows', '--pid', String(handle.pid)]).value.windows.map((window) => window.title ?? '')

/**
 * Two independent signals, because a panel-style window is not always
 * reported the same way depending on which window is frontmost: a window
 * titled for Quick Entry, or a second capture field somewhere in the tree.
 */
const quickEntryIsOpen = (handle) => {
  if (windowTitles(handle).some((title) => title.includes('Quick Entry'))) return true
  return findNodes(webNodes(handle), (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL).length > 1
}

const rowA8 = (context) => runRow('A8', 'Real global-shortcut collision and OS arbitration', async (check) => {
  // Phase 1: a separate, real process takes the accelerator FIRST.
  const rival = spawn(context.rivalProbe, [], { stdio: ['ignore', 'pipe', 'pipe'] })
  let rivalOutput = ''
  rival.stdout.on('data', (chunk) => { rivalOutput += String(chunk) })
  rival.stderr.on('data', (chunk) => { rivalOutput += String(chunk) })
  const rivalExited = new Promise((resolve) => rival.once('exit', resolve))

  try {
    await waitFor('the rival process to report its registration', async () => rivalOutput.includes('RIVAL registered='), { intervalMs: 150, timeoutMs: 20_000 })
    check(
      'a separate real process genuinely holds Keepling\'s Quick Entry accelerator',
      rivalOutput.includes('RIVAL registered=true'),
      rivalOutput.trim().slice(-300),
    )

    const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a8-collision') })
    try {
      // Keepling must SAY it lost. A silent fallback to a different
      // shortcut, or claiming a shortcut it does not hold, is the failure.
      postKeys(handle, 'cmd+comma')
      // Wait for the Settings pane to have STATED a position, not for a fixed
      // 1.8s. This is a precondition rather than the assertion: an empty
      // settings text would make "Keepling does not claim the shortcut" read
      // as TRUE and could manufacture a pass, so a pane that never renders
      // must fail the row loudly instead.
      const shortcutSettingsText = () => {
        const text = webNodes(handle).map((node) => subtreeText(node.subtree ?? node)).join(' ')
        return text.includes('Current shortcut') || /Quick Entry shortcut isn.t available/.test(text) ? text : null
      }
      const settingsText = await waitFor('the Settings pane to state a position on the Quick Entry accelerator', shortcutSettingsText, { intervalMs: 250, timeoutMs: 20_000 })
      const keeplingClaimsTheShortcut = !/Quick Entry shortcut isn.t available/.test(settingsText)
      check(
        'Keepling states a definite position on the accelerator rather than saying nothing',
        settingsText.includes('Current shortcut') || !keeplingClaimsTheShortcut,
        settingsText.slice(0, 300),
      )
      check(
        'when Keepling reports the accelerator unavailable it offers a direct rebind, never a silent fallback to a different shortcut',
        keeplingClaimsTheShortcut || settingsText.includes('Change Shortcut'),
      )

      const before = rivalOutput
      postKeys(handle, QUICK_ENTRY_ACCELERATOR)
      // Both registrants are asserted to have received the keystroke, and each
      // arrives on its own schedule. Poll until BOTH have, then read them; a
      // registrant that never receives it still fails at the deadline with the
      // observed values, which is the whole point of the row.
      const rivalGotIt = () => rivalOutput.slice(before.length).includes('RIVAL received=1')
      await waitFor(
        'the accelerator to reach both registrants',
        async () => rivalGotIt() && quickEntryIsOpen(handle),
        { intervalMs: 250, onTimeout: 'return', timeoutMs: 10_000 },
      )
      const rivalReceived = rivalGotIt()
      const keeplingReceived = quickEntryIsOpen(handle)
      console.log(`ARBITRATION rival_registered=true keepling_claims_shortcut=${keeplingClaimsTheShortcut} rival_received=${rivalReceived} keepling_received=${keeplingReceived}`)

      // MEASURED, not assumed. macOS global hot keys are NOT exclusive:
      // the second registration succeeds (verified in both orders) and the
      // key is delivered to every registrant. So a collision does not
      // silently steal Keepling's accelerator, and Keepling reporting the
      // accelerator as available is a TRUE statement even while another
      // application also receives it.
      check(
        'the collision is real: a separate application received the same accelerator in the same keystroke',
        rivalReceived === true,
        `rival received=${rivalReceived}`,
      )
      check(
        'Keepling never silently believes it holds a shortcut it does not: it reported the accelerator as available AND actually received it',
        keeplingClaimsTheShortcut === keeplingReceived,
        `Keepling reported ${keeplingClaimsTheShortcut ? 'available' : 'unavailable'} but ${keeplingReceived ? 'received' : 'did not receive'} the accelerator`,
      )
      check(
        'a colliding application does not suppress Keepling\'s own Quick Entry',
        keeplingReceived === true,
        `Keepling opened Quick Entry=${keeplingReceived}`,
      )
    } finally {
      await quitApplication(handle)
    }
  } finally {
    rival.kill('SIGTERM')
    await Promise.race([rivalExited, sleep(5_000)])
    if (rival.exitCode === null) rival.kill('SIGKILL')
    // Phase 2 only means anything with the rival GONE, so wait for it to
    // actually be gone rather than for 800ms.
    const rivalDeadline = Date.now() + 5_000 * WAIT_SCALE
    while (rival.exitCode === null && Date.now() < rivalDeadline) await sleep(100)
  }

  // Phase 2: with the rival gone, Keepling holds and receives its own
  // accelerator. Without this the row would pass just as happily against an
  // application whose shortcut never works at all.
  const solo = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a8-solo') })
  try {
    postKeys(solo, 'cmd+comma')
    // Same precondition as phase 1, and for the same reason: asserting
    // "Keepling does not report the accelerator unavailable" against a pane
    // that has not rendered yet would pass on an empty string.
    const settingsText = await waitFor(
      'the Settings pane to state a position on the Quick Entry accelerator',
      async () => {
        const text = webNodes(solo).map((node) => subtreeText(node.subtree ?? node)).join(' ')
        return text.includes('Current shortcut') || /Quick Entry shortcut isn.t available/.test(text) ? text : null
      },
      { intervalMs: 250, timeoutMs: 20_000 },
    )
    check(
      'with no rival, Keepling reports the accelerator as available',
      !/Quick Entry shortcut isn.t available/.test(settingsText),
      settingsText.slice(0, 300),
    )
    postKeys(solo, 'escape')
    // The accelerator below must reach the main window, not a Settings pane
    // still on screen, so wait for the pane to actually be gone.
    await waitFor('the Settings pane to close', async () => {
      const text = webNodes(solo).map((node) => subtreeText(node.subtree ?? node)).join(' ')
      return !text.includes('Current shortcut') && !/Quick Entry shortcut isn.t available/.test(text)
    }, { intervalMs: 200, onTimeout: 'return', timeoutMs: 10_000 })
    postKeys(solo, QUICK_ENTRY_ACCELERATOR)
    await waitFor('Quick Entry to open from the real global accelerator', async () => quickEntryIsOpen(solo), { timeoutMs: 20_000 })
    check('with no rival, the real global accelerator reaches Keepling', quickEntryIsOpen(solo))
  } finally {
    await quitApplication(solo)
  }
})

const PRIOR_APPLICATION = { bundleIdentifier: 'com.apple.TextEdit', name: 'TextEdit' }

const rowA9 = (context) => runRow('A9', 'Prior-application focus and caret return', async (check) => {
  const documentPath = join(mkdtempSync(join(tmpdir(), 'keepling-macos-a9-')), 'prior-application.txt')
  writeFileSync(documentPath, 'The caret in this real prior application must come back exactly where it was.\n')
  disposableProfiles.push(dirname(documentPath))

  spawnSync('open', ['-a', PRIOR_APPLICATION.name, documentPath], { encoding: 'utf8' })
  const priorPid = await waitFor(`${PRIOR_APPLICATION.name} to become frontmost`, async () => {
    const frontmost = runProbe(context.axProbe, ['frontmost'], { allowFailure: true })
    return frontmost.ok && frontmost.value.bundleIdentifier === PRIOR_APPLICATION.bundleIdentifier ? frontmost.value.pid : null
  }, { intervalMs: 500, timeoutMs: 30_000 })
  const priorHandle = { child: { exitCode: null, kill: () => {} }, pid: priorPid, probeBinary: context.axProbe }

  const handle = await launchApplication(context.manifest, context.axProbe, { profilePath: allocateProfile('a9') })
  try {
    for (const ending of ['submitted', 'discarded']) {
      // Put the caret at a known, non-trivial offset in the REAL prior app.
      // Keystrokes go to whatever is frontmost, so wait for the prior
      // application to BE frontmost before typing into it. Raising is
      // asynchronous; 1200ms was a guess at how asynchronous.
      runProbe(context.axProbe, ['raise', '--pid', String(priorPid)])
      await waitFor(`${PRIOR_APPLICATION.name} to be frontmost before the caret is placed`, async () => {
        const frontmost = runProbe(context.axProbe, ['frontmost'], { allowFailure: true })
        if (frontmost.ok && frontmost.value.pid === priorPid) return true
        runProbe(context.axProbe, ['raise', '--pid', String(priorPid)], { allowFailure: true })
        return false
      }, { intervalMs: 200, timeoutMs: 15_000 })
      postKeys(priorHandle, 'cmd+down')
      // The six lefts are relative to wherever cmd+down left the caret, so
      // they must not be posted until that move has actually landed.
      await waitFor(`${PRIOR_APPLICATION.name} to move its caret to the end of the document`, async () => {
        const value = runProbe(context.axProbe, ['selection', '--pid', String(priorPid)], { allowFailure: true })
        return value.ok && value.value.selection !== null && typeof value.value.selection.location === 'number' && value.value.selection.location > 0
      }, { intervalMs: 100, onTimeout: 'return', timeoutMs: 10_000 })
      for (let step = 0; step < 6; step += 1) postKeys(priorHandle, 'left')
      // TextEdit reports the caret through the AX API a beat after the keys
      // land; poll for the caret this asserts on rather than sampling once.
      const priorSelection = () => runProbe(context.axProbe, ['selection', '--pid', String(priorPid)]).value.selection
      const selectionBefore = await waitFor(
        `${PRIOR_APPLICATION.name} to report a caret at a known offset`,
        async () => { const value = priorSelection(); return value !== null && typeof value.location === 'number' && value.location > 0 ? value : null },
        { onTimeout: 'return' },
      ) ?? priorSelection()
      check(
        `${ending}: the prior application really has a caret at a known offset before Quick Entry is invoked`,
        selectionBefore !== null && typeof selectionBefore.location === 'number' && selectionBefore.location > 0,
        JSON.stringify(selectionBefore),
      )

      postKeys(priorHandle, QUICK_ENTRY_ACCELERATOR)
      await waitFor('Quick Entry to open over the prior application', async () => quickEntryIsOpen(handle))
      // From here on the harness must NOT raise anything: Quick Entry takes
      // focus by itself, and forcing the application frontmost would make
      // the harness the prior application and invalidate the whole row.
      await tabUntil(handle, 'the Quick Entry capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL, { raise: false })
      // Return would submit an empty draft, and Escape would discard a draft
      // that never arrived; either way the row would measure the wrong thing.
      // Wait for the text to be readable in the field before deciding it.
      await typeIntoField(handle, CAPTURE_FIELD_LABEL, `Captured while ${ending}`, { raise: false })
      if (ending === 'submitted') postKeys(handle, 'return', { raise: false })
      else postKeys(handle, 'escape', { raise: false })
      await waitFor('Quick Entry to close', async () => !quickEntryIsOpen(handle), { timeoutMs: 15_000 })

      // Activation is handed back by the OS asynchronously, and TextEdit
      // restores its caret after it is reactivated. Poll for each condition
      // the checks below assert on; focus that lands somewhere else and stays
      // there still fails at the deadline, reporting where it actually went.
      const readFrontmost = () => runProbe(context.axProbe, ['frontmost']).value
      const frontmost = await waitFor(
        `focus to return to ${PRIOR_APPLICATION.name}`,
        async () => { const value = readFrontmost(); return value.bundleIdentifier === PRIOR_APPLICATION.bundleIdentifier ? value : null },
        { intervalMs: 200, onTimeout: 'return', timeoutMs: 10_000 },
      ) ?? readFrontmost()
      check(
        `${ending}: focus returns to the SAME prior application -- never Keepling's main window, never the Dock`,
        frontmost.bundleIdentifier === PRIOR_APPLICATION.bundleIdentifier,
        `frontmost was ${frontmost.name} (${frontmost.bundleIdentifier})`,
      )
      const sameSelection = (value) =>
        value !== null && value.location === selectionBefore?.location && value.length === selectionBefore?.length
      const selectionAfter = await waitFor(
        `${PRIOR_APPLICATION.name} to restore its caret to the same place`,
        async () => { const value = priorSelection(); return sameSelection(value) ? value : null },
        { intervalMs: 200, onTimeout: 'return', timeoutMs: 10_000 },
      ) ?? priorSelection()
      check(
        `${ending}: the caret comes back to exactly the same place in the same field`,
        selectionAfter !== null && selectionAfter.location === selectionBefore.location && selectionAfter.length === selectionBefore.length,
        `before ${JSON.stringify(selectionBefore)} after ${JSON.stringify(selectionAfter)}`,
      )
    }
  } finally {
    await quitApplication(handle)
    // Close the prior application without saving, and take its document with
    // it -- this lane leaves nothing behind on the machine.
    spawnSync('osascript', ['-e', `tell application "${PRIOR_APPLICATION.name}" to close every document saving no`], { encoding: 'utf8', timeout: 10_000 })
    spawnSync('osascript', ['-e', `tell application "${PRIOR_APPLICATION.name}" to quit`], { encoding: 'utf8', timeout: 10_000 })
  }
})

// ---------------------------------------------------------------------------
// Restore self-test: an interrupted run must leave the machine as it was
// ---------------------------------------------------------------------------

/**
 * The restore path is the one piece of this lane that touches a person's
 * own machine, so "it restores on the happy path" is not good enough. This
 * proves the two paths that actually matter:
 *
 *   1. A mid-row EXCEPTION still restores every setting.
 *   2. A SIGTERM (the shape of a Ctrl-C, a CI cancellation, or a killed
 *      job) still restores every setting -- proven by forking a real child
 *      process that mutates settings and is then killed for real, with the
 *      PARENT checking the machine afterwards.
 */
/**
 * Deliberately uses settings the lane can always write (the global domain)
 * plus the input source, so the self-test proves the RESTORE MACHINERY
 * rather than incidentally re-testing whether a protected domain is
 * writable. Restoring these is exactly as hard as restoring the others.
 */
const SELF_TEST_MUTATIONS = { appearance: 'Dark', fullKeyboardAccess: 0 }

const settingsSubset = (snapshot) => {
  const subset = {}
  for (const key of MANAGED_KEYS) subset[key] = snapshot[key] ?? null
  subset.inputSource = snapshot.inputSource ?? null
  return subset
}

const runSelfTestRestore = async () => {
  const baseline = settingsSubset(readSystemSettings())
  console.log(`SELF_TEST baseline=${JSON.stringify(baseline)}`)

  // Case 1: a mid-row exception.
  await runRow('SELF-TEST-EXCEPTION', 'a mid-row failure restores every mutated setting', async (check) => {
    let threw = false
    try {
      applySystemSettings(SELF_TEST_MUTATIONS)
      selectInputSource(DEAD_KEY_LAYOUT)
      const mutated = readSystemSettings()
      check(
        'the self-test really did mutate the machine before failing',
        mutated.appearance === 'Dark' && mutated.fullKeyboardAccess === 0 && mutated.inputSource.id === DEAD_KEY_LAYOUT,
        JSON.stringify(mutated),
      )
      throw new Error('deliberate mid-row failure')
    } catch (error) {
      threw = error instanceof Error && error.message === 'deliberate mid-row failure'
      if (!threw) throw error
    }
    check('the deliberate failure actually happened', threw)
    check('restore reports success after the failure', restoreSystemSettings() === true)
    const after = settingsSubset(readSystemSettings())
    check(
      'every setting matches the value captured before the run',
      JSON.stringify(after) === JSON.stringify(baseline),
      `after=${JSON.stringify(after)} baseline=${JSON.stringify(baseline)}`,
    )
    // Allow a subsequent case to capture and restore again.
    settingsState.baseline = null
    settingsState.restored = false
    settingsState.inputSource = null
  })

  // Case 2: a genuine external interruption of a real child process. The
  // child mutates the machine, announces it, and then does nothing but wait
  // -- so the ONLY thing that can put the machine back is the signal
  // handler, not any tidy return path.
  await runRow('SELF-TEST-SIGNAL', 'an interrupted run restores every mutated setting', async (check) => {
    const child = spawn(process.execPath, [import.meta.filename, '--internal-mutate-then-wait'], { stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += String(chunk) })
    child.stderr.on('data', (chunk) => { stderr += String(chunk) })

    const exited = new Promise((resolve) => child.once('exit', (code, signal) => resolve({ code, signal })))
    const mutated = await waitFor('the child process to mutate the machine', async () => stdout.includes('SELF_TEST_CHILD mutated=true'), { intervalMs: 200, timeoutMs: 60_000 })
    check('the child process actually mutated the machine before being interrupted', mutated === true, stdout.trim().slice(-400))

    const duringInterruption = settingsSubset(readSystemSettings())
    check(
      'the machine really was in a mutated state at the moment of the interruption',
      JSON.stringify(duringInterruption) !== JSON.stringify(baseline),
      `state matched the baseline, so the interruption proved nothing: ${JSON.stringify(duringInterruption)}`,
    )

    child.kill('SIGTERM')
    const outcome = await Promise.race([exited, sleep(30_000).then(() => null)])
    if (outcome === null) {
      child.kill('SIGKILL')
      fail('the interrupted child never exited')
    }
    check('the interrupted child exited through its signal handler', outcome.code === 130, `code=${outcome.code} signal=${outcome.signal} stderr=${stderr.trim().slice(-400)}`)

    const after = settingsSubset(readSystemSettings())
    check(
      'the machine is exactly as it was found after the interruption',
      JSON.stringify(after) === JSON.stringify(baseline),
      `after=${JSON.stringify(after)} baseline=${JSON.stringify(baseline)}`,
    )
  })
}

/**
 * Proves the digest-bound evidence RULES without a Mac, without permissions
 * and without running a row. The positive case matters as much as the
 * negative ones: a reuse mechanism that quietly never reuses, or quietly
 * always reuses, is worse than none.
 */
const runEvidenceSelfTest = async () => {
  const manifest = { applicationDigestSha256: 'digest-under-test', executableDigestSha256: 'executable-under-test' }
  const probeDigests = { AXProbe: 'ax-1', HotkeyRival: 'rival-1', SystemSettings: 'settings-1' }
  const completeRecord = {
    applicationDigestSha256: 'digest-under-test',
    executableDigestSha256: 'executable-under-test',
    laneSourceDigest: 'lane-1',
    probeSourceDigests: { ...probeDigests },
    recordedAt: '2026-09-03T00:00:00.000Z',
    rows: ALL_ROWS.map((id) => ({ cases: 3, durationMs: 10, id, passed: true })),
  }
  const clone = (mutate) => {
    const copy = JSON.parse(JSON.stringify(completeRecord))
    mutate(copy)
    return copy
  }

  await runRow('SELF-TEST-EVIDENCE', 'digest-bound evidence is reused only when it is complete, passing and current', async (check) => {
    const accepted = evaluateEvidence(completeRecord, { laneDigest: 'lane-1', manifest, probeDigests })
    check('complete, wholly passing evidence for this exact artifact is reused', accepted.ok === true, accepted.reason ?? '')
    check('the reused evidence carries every row', accepted.recordedRows?.length === ALL_ROWS.length)

    const cases = [
      ['absent evidence is never a pass', null],
      ['evidence for a different artifact digest is never reused', clone((record) => { record.applicationDigestSha256 = 'a-different-digest' })],
      ['evidence for a different packaged executable is never reused', clone((record) => { record.executableDigestSha256 = 'a-different-executable' })],
      ['evidence recorded before a probe source changed is never reused', clone((record) => { record.probeSourceDigests.AXProbe = 'ax-2' })],
      ['evidence recorded before the lane\'s own assertions changed is never reused', clone((record) => { record.laneSourceDigest = 'lane-2' })],
      ['evidence predating lane-source binding entirely is never reused', clone((record) => { delete record.laneSourceDigest })],
      ['a recorded FAILING row never satisfies the gate', clone((record) => { record.rows[0].passed = false })],
      ['evidence covering only the untrusted subset never satisfies the gate', clone((record) => { record.rows = record.rows.filter((row) => UNTRUSTED_ROWS.includes(row.id)) })],
      ['evidence with zero cases never satisfies the gate', clone((record) => { record.rows = record.rows.map((row) => ({ ...row, cases: 0 })) })],
    ]
    for (const [claim, record] of cases) {
      const outcome = evaluateEvidence(record, { laneDigest: 'lane-1', manifest, probeDigests })
      check(claim, outcome.ok === false, `it was accepted with ${outcome.recordedRows?.length ?? 0} row(s)`)
    }
  })
}

const runInternalMutateThenWait = async () => {
  applySystemSettings(SELF_TEST_MUTATIONS)
  selectInputSource(DEAD_KEY_LAYOUT)
  const mutated = readSystemSettings()
  const reallyMutated = mutated.appearance === 'Dark' && mutated.fullKeyboardAccess === 0 && mutated.inputSource.id === DEAD_KEY_LAYOUT
  console.log(`SELF_TEST_CHILD mutated=${reallyMutated}`)
  // Then do nothing at all, forever. There is no tidy return path from here:
  // whatever puts the machine back has to be the signal handler. The timer
  // keeps the event loop alive so Node does not exit on its own and
  // accidentally take the ordinary exit path instead.
  await new Promise(() => {
    setInterval(() => {}, 1_000)
  })
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

/**
 * Row capability registry.
 *
 * `requiresAccessibilityTrust` is the OBSERVED boundary, not a predicted
 * one. Everything that reads another process's AXUIElement tree, posts a
 * CGEvent to another application, or sets `AXManualAccessibility` on
 * another process needs `AXIsProcessTrusted()`. That is A1-A9 as expected --
 * and, contrary to the initial prediction, ALSO A11 and A15, because A11's
 * "conveyed by text, not colour" claim is a claim about the accessibility
 * tree, and A15 asserts control geometry read from AX frames. Rewriting
 * either to avoid AX would have meant asserting something weaker than the
 * row actually says, so they are tagged honestly instead.
 *
 * The untrusted subset (A10, A12, A13, A14) genuinely uses no accessibility
 * API and posts no keystrokes: it launches the packaged app, applies the
 * real OS setting, and measures WCAG contrast from real rendered pixels.
 *
 * Two further capabilities came out of implementation and are tracked
 * separately because they are separate grants, not the Accessibility one:
 *   * `requiresScreenRecording` -- there are no pixels to measure without it.
 *   * `requiresProtectedSettingsWrite` -- `com.apple.universalaccess` is a
 *     privacy-protected domain. An unentitled process may write to it and
 *     get NO error while nothing is stored, so every write is verified.
 * So no row is literally free of all TCC grants; only A14 in the untrusted
 * subset avoids the protected settings domain, and it still needs Screen
 * Recording.
 */
const ROW_REGISTRY = {
  A1: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA1 },
  A2: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA2 },
  A3: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA3 },
  A4: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA4 },
  A5: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA5 },
  A6: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA6 },
  A7: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA7 },
  A8: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA8 },
  A9: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA9 },
  A10: { requiresAccessibilityTrust: false, requiresProtectedSettingsWrite: true, requiresScreenRecording: true, run: rowA10 },
  A11: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: true, requiresScreenRecording: true, run: rowA11 },
  A12: { requiresAccessibilityTrust: false, requiresProtectedSettingsWrite: true, requiresScreenRecording: true, run: rowA12 },
  A13: { requiresAccessibilityTrust: false, requiresProtectedSettingsWrite: true, requiresScreenRecording: true, run: rowA13 },
  A14: { requiresAccessibilityTrust: false, requiresProtectedSettingsWrite: false, requiresScreenRecording: true, run: rowA14 },
  A15: { requiresAccessibilityTrust: true, requiresProtectedSettingsWrite: false, requiresScreenRecording: false, run: rowA15 },
}

const PIXEL_MEASURED_ROWS = ALL_ROWS.filter((row) => ROW_REGISTRY[row]?.requiresScreenRecording)
const UNTRUSTED_ROWS = ALL_ROWS.filter((row) => ROW_REGISTRY[row]?.requiresAccessibilityTrust === false)
if (requestedRows === null) requestedRows = UNTRUSTED_ROWS

const cleanUp = async () => {
  for (const handle of [...liveApplications]) await quitApplication(handle)
  for (const path of disposableProfiles.splice(0)) rmSync(path, { force: true, recursive: true })
  // Restore here, not only in the exit handler, so a failed restoration can
  // still change this process's exit code. The exit/signal handlers remain
  // as the last-resort net for paths that never reach here.
  if (!restoreSystemSettings()) restoreFailed = true
}

/**
 * Gate mode: consult recorded evidence for the artifact currently under test.
 * It never runs a row, never touches the keyboard, and never changes a
 * setting -- an ordinary gate run leaves the machine completely alone.
 */
/**
 * PURE decision function, so the reuse rules can be tested without a Mac,
 * without permissions, and without running a row. Returns `{ ok: true }`
 * only for evidence that is complete, wholly passing, and bound to this
 * exact artifact and these exact probe sources.
 */
const evaluateEvidence = (record, { manifest, probeDigests, laneDigest }) => {
  const digest = manifest.applicationDigestSha256
  if (record === null || record === undefined) return { ok: false, reason: `no macOS integration evidence exists for application digest ${digest}` }
  if (record.applicationDigestSha256 !== digest) return { ok: false, reason: `the recorded evidence is for a different application digest (${record.applicationDigestSha256})` }
  if (record.executableDigestSha256 !== manifest.executableDigestSha256) return { ok: false, reason: 'the recorded evidence is for a different packaged executable' }

  const changedProbes = PROBE_NAMES.filter((name) => (record.probeSourceDigests ?? {})[name] !== probeDigests[name])
  if (changedProbes.length > 0) return { ok: false, reason: `the macOS probe source(s) ${changedProbes.join(', ')} changed since that evidence was recorded, so it no longer describes this lane` }

  if (record.laneSourceDigest !== laneDigest) {
    return { ok: false, reason: `the lane's own source changed since that evidence was recorded (recorded ${record.laneSourceDigest ?? 'nothing'}, now ${laneDigest}), so it no longer describes these assertions` }
  }

  const recordedRows = record.rows ?? []
  const failedRows = recordedRows.filter((row) => !row.passed)
  if (failedRows.length > 0) return { ok: false, reason: `the recorded evidence for this digest contains ${failedRows.length} FAILING row(s): ${failedRows.map((row) => row.id).join(', ')}` }
  // A record covering only the untrusted subset can never satisfy the gate
  // as if it covered all fifteen. Partial evidence is a loud failure for the
  // rows it does not cover.
  const missingRows = ALL_ROWS.filter((row) => !recordedRows.some((recorded) => recorded.id === row))
  if (missingRows.length > 0) {
    return { ok: false, reason: `the recorded evidence for this digest covers ${recordedRows.length}/${ALL_ROWS.length} rows and does not cover row(s) ${missingRows.join(', ')}` }
  }

  const totalCases = recordedRows.reduce((sum, row) => sum + row.cases, 0)
  if (totalCases <= 0) return { ok: false, reason: 'the recorded evidence contains zero cases' }
  return { ok: true, recordedRows, totalCases }
}

const runGateMode = (manifest) => {
  const digest = manifest.applicationDigestSha256
  const record = readEvidence(digest)
  const outcome = evaluateEvidence(record, { laneDigest: laneSourceDigest(), manifest, probeDigests: probeSourceDigests() })
  if (!outcome.ok) {
    console.error(`macOS integration lane failed: ${outcome.reason}\n${EVIDENCE_PRODUCTION_INSTRUCTION}`)
    console.log('macOS integration lane summary: rows=0 failed=1 cases=0 duration_ms=0')
    process.exit(1)
  }
  const { recordedRows, totalCases } = outcome

  console.log(`LANE_EVIDENCE reuse=true application_digest=${digest} recorded_at=${record.recordedAt} source_revision=${record.sourceRevision} file=${evidencePathFor(digest)}`)
  console.log('LANE_EVIDENCE note=this-gate-run-executed-no-rows-and-changed-no-system-setting')
  for (const row of recordedRows) console.log(`ROW id=${row.id} status=PASS cases=${row.cases} duration_ms=${row.durationMs} source=recorded-evidence`)
  console.log('')
  console.log(`macOS integration lane summary: rows=${recordedRows.length} failed=0 cases=${totalCases} duration_ms=0`)
  for (const row of recordedRows) console.log(`  PASS ${row.id} ${row.title} cases=${row.cases}`)
  console.log(`macOS integration lane: PASSED cases=${totalCases} (reusing evidence recorded ${record.recordedAt} for artifact digest ${digest})`)
  process.exit(0)
}

const main = async () => {
  if (restoreOnly) {
    const capturePath = join(cacheDir, 'settings-capture.json')
    if (!existsSync(capturePath)) {
      console.error(`macOS integration lane: nothing to restore -- no settings capture exists at ${capturePath}`)
      process.exit(1)
    }
    settingsState.probeBinary = compileProbe('SystemSettings').binaryPath
    settingsState.baseline = JSON.parse(readFileSync(capturePath, 'utf8'))
    settingsState.capturePath = capturePath
    settingsState.inputSource = null
    if (!restoreSystemSettings()) process.exit(1)
    console.log('macOS integration lane: system settings restored from the last capture')
    process.exit(0)
  }

  const swiftVersion = requireSwiftc()
  if (hasFlag('internal-mutate-then-wait')) {
    settingsState.probeBinary = compileProbe('SystemSettings').binaryPath
    await runInternalMutateThenWait()
    return
  }
  const manifest = loadManifest()
  const axProbe = compileProbe('AXProbe')
  const settingsProbe = compileProbe('SystemSettings')
  settingsState.probeBinary = settingsProbe.binaryPath

  if (gateMode) runGateMode(manifest)

  // Only demanded by the rows that genuinely need it. The untrusted subset
  // (see ROW_REGISTRY) runs on a machine with no Accessibility grant at all.
  const trustedRows = requestedRows.filter((row) => ROW_REGISTRY[row]?.requiresAccessibilityTrust)
  if (trustedRows.length > 0 || selfTestRestore) {
    const permission = runProbe(axProbe.binaryPath, ['permission'])
    if (permission.value.trusted !== true) {
      const chain = (permission.value.ancestry ?? []).map((entry) => entry.name).join(' <- ')
      console.error(`macOS integration lane failed: row(s) ${trustedRows.join(',')} read the accessibility tree and post real keystrokes, and accessibility_permission_denied (process chain: ${chain})\n\n${ACCESSIBILITY_GRANT_INSTRUCTION}`)
      process.exit(1)
    }
  }

  console.log(`LANE_INPUT swiftc="${swiftVersion}" ax_probe_digest=${axProbe.digest} settings_probe_digest=${settingsProbe.digest}`)
  console.log(`LANE_ARTIFACT application_digest=${manifest.applicationDigestSha256} executable=${manifest.executablePath} source_revision=${manifest.sourceRevision}`)

  const rivalProbe = compileProbe('HotkeyRival')
  const context = { axProbe: axProbe.binaryPath, manifest, rivalProbe: rivalProbe.binaryPath }

  if (selfTestRestore) {
    await runEvidenceSelfTest()
    await runSelfTestRestore(context)
    return
  }

  // Legibility rows measure a WCAG contrast ratio over REAL rendered pixels.
  // Without Screen Recording there are no pixels to measure, so those rows
  // fail loudly and up front rather than after launching an application.
  const pixelRows = requestedRows.filter((row) => PIXEL_MEASURED_ROWS.includes(row))
  if (pixelRows.length > 0 && runProbe(settingsProbe.binaryPath, ['screen-permission']).value.granted !== true) {
    console.error(
      `macOS integration lane failed: row(s) ${pixelRows.join(',')} measure legibility from real rendered pixels, and Screen Recording is not granted.\n\n` +
      'Open:  System Settings -> Privacy & Security -> Screen Recording\n' +
      'Then:  enable the application that runs this lane (the terminal, IDE, or CI\n' +
      '       agent process), and restart it so the new grant takes effect.\n\n' +
      'This is a one-time approval. These rows will NOT be skipped or downgraded\n' +
      'to an unmeasured assertion without it -- a legibility claim with no pixels\n' +
      'behind it is exactly the vacuous evidence this lane replaced.',
    )
    process.exit(1)
  }


  const rows = requestedRows.filter((row) => ROW_REGISTRY[row] !== undefined)
  const unimplemented = requestedRows.filter((row) => ROW_REGISTRY[row] === undefined)
  if (unimplemented.length > 0) fail(`row(s) ${unimplemented.join(',')} have no implementation -- an unimplemented row is a failure, never a skip`)

  for (const row of rows) await ROW_REGISTRY[row].run(context)

  // Only a COMPLETE, wholly passing run becomes reusable evidence. A partial
  // `--rows` run is for developing the lane, not for satisfying the gate.
  const coversEveryRow = ALL_ROWS.every((row) => rowResults.some((result) => result.id === row && result.passed))
  if (coversEveryRow) writeEvidence(manifest, rowResults)
  else if (runAllRows) console.log('LANE_EVIDENCE recorded=false reason=not-every-row-passed')
  else console.log('LANE_EVIDENCE recorded=false reason=partial-row-selection-is-never-recorded-as-gate-evidence')
}

const startedAt = Date.now()
let exitCode = 0
try {
  await main()
} catch (error) {
  exitCode = 1
  if (!(error instanceof LaneFailure)) console.error(`macOS integration lane failed: ${error instanceof Error ? error.stack ?? error.message : String(error)}`)
} finally {
  await cleanUp()
}

const totalCases = rowResults.reduce((sum, row) => sum + row.cases, 0)
const failedRows = rowResults.filter((row) => !row.passed)
console.log('')
console.log(`macOS integration lane summary: rows=${rowResults.length} failed=${failedRows.length} cases=${totalCases} duration_ms=${Date.now() - startedAt}`)
for (const row of rowResults) console.log(`  ${row.passed ? 'PASS' : 'FAIL'} ${row.id} ${row.title} cases=${row.cases}`)

if (!selfTestRestore && rowResults.length !== requestedRows.length) {
  console.error(`macOS integration lane failed: ${requestedRows.length} row(s) were requested but ${rowResults.length} reported -- a row that did not run is never a skip`)
  exitCode = 1
}
if (totalCases <= 0) {
  console.error('macOS integration lane failed: zero cases were executed')
  exitCode = 1
}
if (restoreFailed) {
  console.error('macOS integration lane failed: system settings could not be restored to their captured values')
  exitCode = 1
}
if (exitCode !== 0 || failedRows.length > 0) {
  console.error('macOS integration lane: FAILED')
  process.exit(1)
}
console.log(`macOS integration lane: PASSED cases=${totalCases}`)
process.exit(0)
