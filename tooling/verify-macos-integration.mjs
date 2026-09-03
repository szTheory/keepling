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
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { isAbsolute, join, relative, resolve, sep } from 'node:path'
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
const requestedRows = (() => {
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

  const deadline = Date.now() + 45_000
  for (;;) {
    if (child.exitCode !== null) fail(`the packaged application exited (${child.exitCode}) before presenting a window`)
    const windows = runProbe(probeBinary, ['windows', '--pid', String(child.pid)], { allowFailure: true })
    if (windows.ok && Array.isArray(windows.value.windows) && windows.value.windows.length > 0) break
    if (Date.now() > deadline) fail('the packaged application never presented an accessible window')
    await sleep(500)
  }
  runProbe(probeBinary, ['raise', '--pid', String(child.pid)])
  await sleep(600)

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

const quitApplication = async (handle) => {
  liveApplications.delete(handle)
  if (handle.child.exitCode !== null) return
  handle.child.kill('SIGTERM')
  const deadline = Date.now() + 8_000
  while (handle.child.exitCode === null && Date.now() < deadline) await sleep(150)
  if (handle.child.exitCode === null) handle.child.kill('SIGKILL')
  await sleep(400)
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

const findNode = (nodes, predicate) => nodes.find(predicate) ?? null
const findNodes = (nodes, predicate) => nodes.filter(predicate)

const focusedElement = (handle) => runProbe(handle.probeBinary, ['focused', '--pid', String(handle.pid)]).value.focused

/**
 * CGEvent keystrokes go to whatever the OS considers frontmost. Asserting
 * that the app under test really is frontmost before every keystroke is
 * what stops this lane from silently typing into some other window and then
 * reporting a misleading failure (or, worse, a misleading pass).
 */
const ensureFrontmost = (handle) => {
  const deadline = Date.now() + 6_000
  for (;;) {
    const frontmost = runProbe(handle.probeBinary, ['frontmost'], { allowFailure: true })
    if (frontmost.ok && frontmost.value.pid === handle.pid) return
    runProbe(handle.probeBinary, ['raise', '--pid', String(handle.pid)], { allowFailure: true })
    if (Date.now() > deadline) {
      fail(`the application under test (pid ${handle.pid}) never became frontmost, so keystrokes could not be delivered to it`)
    }
  }
}

const postKeys = (handle, sequence) => {
  ensureFrontmost(handle)
  return runProbe(handle.probeBinary, ['key', '--sequence', sequence])
}

const waitFor = async (description, predicate, { timeoutMs = 12_000, intervalMs = 300 } = {}) => {
  const deadline = Date.now() + timeoutMs
  let last = null
  for (;;) {
    last = await predicate()
    if (last) return last
    if (Date.now() > deadline) fail(`timed out waiting for ${description}`)
    await sleep(intervalMs)
  }
}

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
      rowResults.push({ cases: assertions.length, durationMs: Date.now() - startedAt, id, passed: false, title })
      console.log(`ROW id=${id} status=FAIL cases=${assertions.length} duration_ms=${Date.now() - startedAt}`)
      throw new LaneFailure(`${id}: ${error instanceof Error ? error.message : String(error)}`)
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
const tabUntil = async (handle, description, predicate, { key = 'tab', limit = 24 } = {}) => {
  for (let step = 0; step < limit; step += 1) {
    const focused = focusedElement(handle)
    if (focused && predicate(focused)) return focused
    postKeys(handle, key)
    await sleep(120)
  }
  const focused = focusedElement(handle)
  if (focused && predicate(focused)) return focused
  return fail(`could not reach ${description} by keyboard within ${limit} ${key} presses (focus stopped on ${focused ? `${focused.role} "${focused.title ?? ''}"` : 'nothing'})`)
}

const ancestryText = (node) =>
  [...(node.ancestors ?? [])].map((entry) => `${entry.title ?? ''} ${entry.description ?? ''} ${entry.value ?? ''}`).join(' | ')

const captureTaskByKeyboard = async (handle, title) => {
  postKeys(handle, 'cmd+n')
  await sleep(400)
  await tabUntil(handle, 'the capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
  postKeys(handle, `text:${title}`)
  await sleep(250)
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
    await sleep(500)
    const focusedField = await tabUntil(handle, 'the capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    check('the capture field can hold accessibility focus', focusedField.role === 'AXTextField')

    postKeys(handle, 'text:Prove the screen reader layer')
    await sleep(300)
    const typed = await waitFor('the typed title to reach the capture field', async () => {
      const node = findNode(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL)
      return node && node.value === 'Prove the screen reader layer' ? node : null
    })
    check('real CGEvent keystrokes reach the capture field and are readable as AXValue', typed.value === 'Prove the screen reader layer')
    const armed = findNode(webNodes(handle), (node) => node.role === 'AXButton' && node.title === 'Add Task')
    check('the Add Task button announces the state change to enabled once there is something to add', armed?.enabled === true)

    await tabUntil(handle, 'the Add Task button', (node) => node.role === 'AXButton' && node.title === 'Add Task')
    postKeys(handle, 'space')
    const row = await waitFor('the captured task to appear', async () =>
      taskRows(handle).find((entry) => entry.text.includes('Prove the screen reader layer')) ?? null)
    check('the captured task announces its title', row.text.includes('Prove the screen reader layer'))
    check(
      'the post-submit "Saved on this Mac" status is discoverable in the same announcement, without a second interaction',
      row.text.includes('Saved on this Mac'),
      `row announcement was "${row.text}"`,
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

    const rows = taskRows(handle)
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
    await sleep(400)
    const movedRow = focusedElement(handle)
    check('arrow-key navigation moves accessibility focus between rows', movedRow.title !== firstRow.title, `stayed on "${movedRow.title}"`)
    check('arrow-key navigation still selects nothing', movedRow.ariaCurrent === undefined)

    postKeys(handle, 'return')
    await sleep(600)
    const selectedRows = taskRows(handle).filter((row) => row.ariaCurrent === 'true')
    check('Return selects exactly one task -- the roving-focused one', selectedRows.length === 1, `saw ${selectedRows.length} selected`)
    const movedTitle = String(movedRow.title ?? '').split(' Saved')[0]
    check(
      'the selected task is the row focus had reached, by stable identity',
      selectedRows[0] !== undefined && selectedRows[0].text.includes(movedTitle),
      `selected "${selectedRows[0]?.text ?? ''}" after focusing "${movedTitle}"`,
    )

    postKeys(handle, 'up')
    await sleep(400)
    const focusedAfter = focusedElement(handle)
    check(
      'the SELECTED task stays distinguishable from the VoiceOver-focused row (D-05)',
      focusedAfter.ariaCurrent === undefined && taskRows(handle).some((row) => row.ariaCurrent === 'true'),
      `focused row reported ariaCurrent=${focusedAfter.ariaCurrent ?? 'unset'}`,
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
    await sleep(1200)
    const quickEntryField = await waitFor('the Quick Entry window', async () => {
      const node = findNode(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL && ancestryText(entry).includes('Quick Entry'))
      return node ?? (findNodes(webNodes(handle), (entry) => entry.role === 'AXTextField' && entry.title === CAPTURE_FIELD_LABEL).length > 1 ? true : null)
    })
    check('the real global accelerator opens Quick Entry', quickEntryField !== null)

    await tabUntil(handle, 'the Quick Entry capture field', (node) => node.role === 'AXTextField' && node.title === CAPTURE_FIELD_LABEL)
    postKeys(handle, 'text:Draft to discard')
    await sleep(300)
    await tabUntil(handle, 'the Discard Draft button', (node) => node.role === 'AXButton' && (node.title ?? '').startsWith('Discard Draft'))
    postKeys(handle, 'space')
    await sleep(600)

    const discardFocus = focusedElement(handle)
    check('the discard-draft confirmation moves focus into itself', discardFocus !== null && (discardFocus.title ?? '') === 'Keep Draft')
    check(
      'a screen reader hears the dialog heading immediately, without exploring the window',
      ancestryText(discardFocus).includes('Discard Quick Entry Draft?'),
      `ancestry was "${ancestryText(discardFocus)}"`,
    )
    postKeys(handle, 'space')
    await sleep(400)
    postKeys(handle, 'escape')
    await sleep(400)

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
    const focused = focusedElement(conflictHandle)
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
    await sleep(500)

    const titleField = await tabUntil(handle, 'the task title editor', (node) => node.role === 'AXTextField' && node.title === 'Title')
    check('the task title editor is reachable by keyboard and exposes its label', titleField.title === 'Title')
    postKeys(handle, 'text: unsaved')
    await sleep(300)

    // Navigate away using the destination control itself, reached by
    // keyboard. (The Cmd-2 accelerator routes straight through
    // `facade.setRoute` in the desktop shell and therefore bypasses the
    // unsaved-changes guard entirely -- recorded as a finding rather than
    // silently worked around; see this plan's SUMMARY.)
    await tabUntil(handle, 'the Today destination button', (node) => node.role === 'AXButton' && node.title === 'Today', { key: 'shift+tab', limit: 24 })
    postKeys(handle, 'space')
    await sleep(800)

    const nodes = webNodes(handle)
    const dialog = findNode(nodes, (node) => (node.description ?? '') === 'Discard unsaved changes?' || (node.title ?? '') === 'Discard unsaved changes?')
    check('navigating away with unsaved edits raises the unsaved-changes dialog', dialog !== null)

    const focused = focusedElement(handle)
    check(
      'the unsaved-changes dialog moves focus INTO itself (previously a disclosed gap, fixed in 03-15)',
      focused !== null && (focused.title ?? '') === 'Keep Editing',
      `focus was on ${focused ? `${focused.role} "${focused.title ?? ''}"` : 'nothing'}`,
    )
    check(
      'the safe, non-destructive action is the one focus lands on',
      (focused?.title ?? '') === 'Keep Editing',
    )
    check(
      'a screen reader hears the dialog heading immediately',
      ancestryText(focused).includes('Discard unsaved changes?'),
      `ancestry was "${ancestryText(focused)}"`,
    )

    postKeys(handle, 'space')
    await sleep(600)
    const afterClose = focusedElement(handle)
    check(
      'closing the dialog leaves focus on a visible, operable element -- never the application element, never a removed node',
      afterClose !== null && afterClose.role !== 'AXApplication' && (afterClose.frame?.width ?? 0) > 0 && (afterClose.frame?.height ?? 0) > 0,
      `focus was on ${afterClose ? `${afterClose.role} "${afterClose.title ?? ''}"` : 'nothing'}`,
    )
  } finally {
    await quitApplication(handle)
  }
})

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const ROW_IMPLEMENTATIONS = { A1: rowA1, A2: rowA2, A3: rowA3, A4: rowA4 }

const cleanUp = async () => {
  for (const handle of [...liveApplications]) await quitApplication(handle)
  for (const path of disposableProfiles.splice(0)) rmSync(path, { force: true, recursive: true })
}

const main = async () => {
  const swiftVersion = requireSwiftc()
  const manifest = loadManifest()
  const axProbe = compileProbe('AXProbe')

  const permission = runProbe(axProbe.binaryPath, ['permission'])
  if (permission.value.trusted !== true) {
    const chain = (permission.value.ancestry ?? []).map((entry) => entry.name).join(' <- ')
    console.error(`macOS integration lane failed: accessibility_permission_denied (process chain: ${chain})\n\n${ACCESSIBILITY_GRANT_INSTRUCTION}`)
    process.exit(1)
  }

  console.log(`LANE_INPUT swiftc="${swiftVersion}" probe_digest=${axProbe.digest}`)
  console.log(`LANE_ARTIFACT application_digest=${manifest.applicationDigestSha256} executable=${manifest.executablePath} source_revision=${manifest.sourceRevision}`)

  const context = { axProbe: axProbe.binaryPath, manifest }
  const rows = requestedRows.filter((row) => ROW_IMPLEMENTATIONS[row] !== undefined)
  const unimplemented = requestedRows.filter((row) => ROW_IMPLEMENTATIONS[row] === undefined)
  if (unimplemented.length > 0) fail(`row(s) ${unimplemented.join(',')} have no implementation -- an unimplemented row is a failure, never a skip`)

  for (const row of rows) await ROW_IMPLEMENTATIONS[row](context)
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

if (rowResults.length !== requestedRows.length) {
  console.error(`macOS integration lane failed: ${requestedRows.length} row(s) were requested but ${rowResults.length} reported -- a row that did not run is never a skip`)
  exitCode = 1
}
if (totalCases <= 0) {
  console.error('macOS integration lane failed: zero cases were executed')
  exitCode = 1
}
if (exitCode !== 0 || failedRows.length > 0) {
  console.error('macOS integration lane: FAILED')
  process.exit(1)
}
console.log(`macOS integration lane: PASSED cases=${totalCases}`)
process.exit(0)
