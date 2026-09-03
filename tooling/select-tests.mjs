#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import process from 'node:process'

/**
 * `pnpm test:changed` -- run the minimum set of lanes that can ACTUALLY
 * observe the current working-tree changes, and say why each was chosen.
 *
 * This is a local convenience, NOT a gate. `node tooling/verify-desktop-phase.mjs`
 * remains the authority and is printed as the escape hatch on every run.
 *
 * Design rule, in priority order:
 *   1. Never silently under-select. A path that cannot be confidently
 *      attributed widens to EVERY lane, with the reason printed.
 *   2. Never silently run something that takes over the machine. Lanes that
 *      seize the screen/keyboard (the macOS integration rows, the Elixir
 *      server suite) are SELECTED and printed but not executed unless
 *      `--include-manual` is passed. They are reported as NOT RUN, loudly --
 *      an unrun lane is never counted as a pass.
 */

const REPOSITORY_ROOT = fileURLToPath(new URL('../', import.meta.url))
const GATE = 'node tooling/verify-desktop-phase.mjs'

// --------------------------------------------------------------------------
// Lane registry. Every lane is a real, runnable command -- no lane exists
// here that cannot be executed and observed.
// --------------------------------------------------------------------------
const LANES = {
  contracts: { commands: [['pnpm', 'contracts:check']], label: 'contracts:check' },
  e2e: {
    commands: [['node', 'tooling/run-tests.mjs', 'e2e']],
    label: 'Electron E2E (Playwright)',
    windowed: true,
  },
  ipc: { commands: [['node', 'tooling/run-tests.mjs', 'ipc']], label: 'hostile preload/main bridge' },
  'macos-integration': {
    commands: [['node', 'tooling/verify-macos-integration.mjs', '--all']],
    label: 'macOS integration rows A1-A15',
    manual: 'posts real OS keystrokes and mutates real system settings -- it takes over the machine',
  },
  packaged: {
    commands: [
      ['pnpm', 'package:desktop'],
      ['pnpm', 'smoke:desktop:packaged'],
    ],
    label: 'packaged .app bytes',
    manual: 'rebuilds and launches the packaged app (slow, presents windows)',
    windowed: true,
  },
  server: {
    commands: [['./tooling/runtime-preflight.sh', '--exec', '--', 'sh', '-c', 'cd apps/server && mix test']],
    label: 'Elixir server suite',
    manual: 'needs the container runtime preflight, not just node',
  },
  'typecheck-desktop': { commands: [['pnpm', 'typecheck:desktop']], label: 'desktop typecheck' },
  'typecheck-web': { commands: [['pnpm', 'typecheck:web']], label: 'web typecheck' },
  'unit-all': { commands: [['node', 'tooling/run-tests.mjs', 'unit']], label: 'all five vitest desktop projects' },
  'unit-application': {
    commands: [['node', 'tooling/run-tests.mjs', 'unit', '--project=application']],
    label: 'vitest application project',
  },
  'unit-performance': {
    commands: [['node', 'tooling/run-tests.mjs', 'unit', '--project=performance']],
    label: 'vitest performance project',
  },
  'unit-renderer': {
    commands: [['node', 'tooling/run-tests.mjs', 'unit', '--project=renderer']],
    label: 'vitest renderer project',
  },
  'unit-store': {
    commands: [['node', 'tooling/run-tests.mjs', 'unit', '--project=store']],
    label: 'vitest store project (real SQLite)',
  },
  'web-unit': { commands: [['pnpm', '--dir', 'apps/web', 'test']], label: 'web vitest suite' },
}

const EVERY_LANE = Object.keys(LANES).sort()

const DESKTOP_TYPECHECK = 'typecheck-desktop'

// --------------------------------------------------------------------------
// Path -> lane rules. ALL matching rules apply (union), never first-match,
// so an ambiguous path accumulates coverage instead of losing it.
// A path matching NO rule selects every lane.
// --------------------------------------------------------------------------
const RULES = [
  // -- shared packages ----------------------------------------------------
  {
    glob: 'packages/web-ui/**',
    lanes: ['unit-renderer', 'unit-application', 'web-unit', 'typecheck-web', DESKTOP_TYPECHECK, 'e2e'],
    reason: 'the shared presentation slice is load-bearing on BOTH desktop and web',
  },
  {
    glob: 'packages/contracts/**',
    lanes: ['contracts', 'unit-application', 'ipc', DESKTOP_TYPECHECK, 'typecheck-web', 'server'],
    reason: 'cross-runtime contract truth: every consumer of the generated types plus the server',
  },
  {
    glob: 'packages/design-tokens/**',
    lanes: ['web-unit', 'unit-renderer', 'typecheck-web'],
    reason: 'token outputs feed both renderer surfaces',
  },

  // -- desktop main process ----------------------------------------------
  {
    glob: 'apps/desktop/main/protocol.ts',
    lanes: ['ipc', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'the IPC/protocol boundary the hostile-bridge lane owns',
  },
  {
    glob: 'apps/desktop/main/windows/**',
    lanes: ['unit-application', 'e2e', DESKTOP_TYPECHECK, 'packaged', 'macos-integration'],
    reason: 'window construction/presentation: only the real Electron app and the real window server can observe it',
  },
  {
    glob: 'apps/desktop/main/**',
    lanes: ['unit-application', 'ipc', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'main-process code ships inside the packaged bytes and is exercised end to end',
  },
  {
    glob: 'apps/desktop/preload/**',
    lanes: ['ipc', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'the preload contract is exactly what the hostile-bridge lane and the real app exercise',
  },
  {
    glob: 'apps/desktop/store-worker/**',
    lanes: ['unit-store', 'unit-application', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'real SQLite adapter and worker protocol',
  },
  {
    glob: 'apps/desktop/migrations/**',
    lanes: ['unit-store', 'e2e', 'packaged'],
    reason: 'migrations are only observable against a real store and a real launch',
  },
  {
    glob: 'apps/desktop/renderer/**',
    lanes: ['unit-renderer', 'unit-application', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'renderer sources are covered by the renderer project, the application project (keyboardCommands), and the real app',
  },

  // -- desktop tests own their lane --------------------------------------
  { glob: 'apps/desktop/test/application/**', lanes: ['unit-application'], reason: 'the test files of that project' },
  { glob: 'apps/desktop/test/renderer/**', lanes: ['unit-renderer'], reason: 'the test files of that project' },
  { glob: 'apps/desktop/test/store/**', lanes: ['unit-store'], reason: 'the test files of that project' },
  { glob: 'apps/desktop/test/performance/**', lanes: ['unit-performance'], reason: 'the test files of that project' },
  { glob: 'apps/desktop/test/ipc/**', lanes: ['ipc'], reason: 'the test files of that lane' },
  { glob: 'apps/desktop/test/e2e/**', lanes: ['e2e'], reason: 'the test files of that lane' },
  { glob: 'apps/desktop/test/packaged/**', lanes: ['packaged'], reason: 'the test files of that lane' },
  {
    glob: 'apps/desktop/test/fixtures/**',
    lanes: ['unit-all', 'ipc', 'e2e'],
    reason: 'shared fixtures: any lane may import them, so none can be ruled out',
  },

  // -- desktop build/config: widens to every desktop lane -----------------
  {
    glob: 'apps/desktop/*',
    lanes: ['unit-all', 'ipc', 'e2e', DESKTOP_TYPECHECK, 'packaged'],
    reason: 'desktop build/config/manifest change: it can alter what every desktop lane even builds',
  },

  // -- other apps ---------------------------------------------------------
  { glob: 'apps/web/**', lanes: ['web-unit', 'typecheck-web'], reason: 'web-only sources' },
  { glob: 'apps/server/**', lanes: ['server'], reason: 'server-only sources' },
  {
    glob: 'apps/ios/**',
    lanes: [],
    reason: 'no JavaScript lane in this repository can observe iOS sources',
  },
  {
    glob: 'apps/android/**',
    lanes: [],
    reason: 'no JavaScript lane in this repository can observe Android sources',
  },

  // -- tooling: specific before generic -----------------------------------
  {
    glob: 'tooling/run-tests.mjs',
    lanes: ['unit-all', 'ipc', 'e2e'],
    reason: 'it is the entry point every desktop test lane now goes through',
  },
  { glob: 'tooling/select-tests.mjs', lanes: [], reason: 'this selector itself runs no product code' },
  { glob: 'tooling/package-desktop.mjs', lanes: ['packaged'], reason: 'it builds the packaged bytes' },
  { glob: 'tooling/smoke-desktop-packaged.mjs', lanes: ['packaged'], reason: 'it drives the packaged bytes' },
  {
    glob: 'tooling/verify-macos-integration.mjs',
    lanes: ['macos-integration'],
    reason: 'it is the macOS row harness',
  },
  { glob: 'tooling/macos-integration/**', lanes: ['macos-integration'], reason: 'the Swift probes the rows use' },
  {
    glob: 'tooling/verify-desktop-phase.mjs',
    lanes: [],
    reason: `the gate itself -- verify it by running it: ${GATE}`,
  },
  { glob: 'tooling/**', lanes: [], reason: 'operational tooling with no product test lane' },

  // -- non-code -----------------------------------------------------------
  { glob: '.github/**', lanes: [], reason: 'CI definition: only a real CI run can observe it' },
  { glob: 'docs/**', lanes: [], reason: 'documentation' },
  { glob: '.planning/**', lanes: [], reason: 'planning artifacts' },
  { glob: 'infra/**', lanes: [], reason: 'infrastructure definitions have their own shell verifiers' },
  { glob: '*.md', lanes: [], reason: 'documentation' },

  // -- anything that can change resolution for everything -----------------
  {
    glob: 'pnpm-lock.yaml',
    lanes: EVERY_LANE,
    reason: 'a dependency graph change can alter the behaviour of every lane',
  },
  { glob: 'package.json', lanes: EVERY_LANE, reason: 'the workspace root manifest affects every lane' },
  { glob: 'pnpm-workspace.yaml', lanes: EVERY_LANE, reason: 'workspace resolution affects every lane' },
]

/** Prints a command so it can be copied and pasted back verbatim. */
const shellQuote = (command) =>
  command.map((token) => (/[\s'"$&|<>()]/.test(token) ? `'${token.replaceAll("'", String.raw`'\''`)}'` : token)).join(' ')

const globToRegExp = (glob) => {
  const pattern = glob
    .split('**')
    .map((segment) =>
      segment
        .split('*')
        .map((piece) => piece.replaceAll(/[.+?^${}()|[\]\\]/g, String.raw`\$&`))
        .join('[^/]*'),
    )
    .join('.*')
  return new RegExp(`^${pattern}$`)
}
const compiledRules = RULES.map((rule) => ({ ...rule, matcher: globToRegExp(rule.glob) }))

const lanesFor = (path) => {
  const matched = compiledRules.filter((rule) => rule.matcher.test(path))
  if (matched.length === 0) {
    return [
      {
        glob: '(no rule)',
        lanes: EVERY_LANE,
        reason: 'UNMATCHED path -- widening to every lane rather than guessing; add a rule to tooling/select-tests.mjs',
      },
    ]
  }
  return matched
}

// --------------------------------------------------------------------------
// Working-tree change discovery: staged + unstaged + untracked, vs HEAD.
// --------------------------------------------------------------------------
const git = (...args) => {
  const result = spawnSync('git', ['-C', REPOSITORY_ROOT, ...args], { encoding: 'utf8' })
  if (result.status !== 0) {
    console.error(`select-tests: \`git ${args.join(' ')}\` failed: ${(result.stderr ?? '').trim()}`)
    process.exit(2)
  }
  return result.stdout.split('\0').filter(Boolean)
}

const argv = process.argv.slice(2).filter((argument) => argument !== '--')
const dryRun = argv.includes('--dry-run')
const includeManual = argv.includes('--include-manual')
const pathsFlagIndex = argv.indexOf('--paths')
const explicitPaths = pathsFlagIndex === -1 ? null : argv.slice(pathsFlagIndex + 1).filter((a) => !a.startsWith('--'))

const changedPaths =
  explicitPaths !== null && explicitPaths.length > 0
    ? explicitPaths
    : [...new Set([...git('diff', '--name-only', '-z', 'HEAD'), ...git('ls-files', '--others', '--exclude-standard', '-z')])].sort()

console.log('=== changed paths -> lanes ===')
if (changedPaths.length === 0) {
  console.log('(working tree is clean against HEAD -- nothing to select)')
}

const selected = new Map()
for (const path of changedPaths) {
  for (const rule of lanesFor(path)) {
    const laneList = rule.lanes.length === 0 ? '(none)' : rule.lanes.join(', ')
    console.log(`  ${path}\n      via ${rule.glob} -> ${laneList}\n      because ${rule.reason}`)
    for (const lane of rule.lanes) {
      if (!selected.has(lane)) selected.set(lane, new Set())
      selected.get(lane).add(path)
    }
  }
}

// `unit-all` subsumes the per-project vitest lanes; running both would run
// the same files twice and report inflated confidence.
if (selected.has('unit-all')) {
  for (const lane of [...selected.keys()]) {
    if (lane.startsWith('unit-') && lane !== 'unit-all') selected.delete(lane)
  }
}

const selectedLanes = [...selected.keys()].sort()
const autoLanes = selectedLanes.filter((lane) => !LANES[lane].manual)
const manualLanes = selectedLanes.filter((lane) => LANES[lane].manual)

console.log('\n=== selection ===')
if (selectedLanes.length === 0) console.log('  no lane can observe these changes')
for (const lane of selectedLanes) {
  const marker = LANES[lane].manual ? 'NOT RUN' : 'run'
  console.log(`  [${marker}] ${lane} -- ${LANES[lane].label}`)
}
if (manualLanes.length > 0) {
  console.log('\n  Selected but NOT run automatically (an unrun lane is not a pass):')
  for (const lane of manualLanes) {
    console.log(`    ${lane}: ${LANES[lane].manual}`)
    for (const command of LANES[lane].commands) console.log(`      $ ${shellQuote(command)}`)
  }
  console.log('    Pass --include-manual to run them here instead.')
}
console.log(`\n  This is NOT the gate. The authority is: ${GATE}`)
console.log('  Run it before you call a phase or plan done.\n')

if (dryRun) process.exit(0)

const toRun = includeManual ? selectedLanes : autoLanes
let failed = false
for (const lane of toRun) {
  for (const command of LANES[lane].commands) {
    console.log(`\n--- ${lane}: ${shellQuote(command)} ---`)
    const result = spawnSync(command[0], command.slice(1), { cwd: REPOSITORY_ROOT, stdio: 'inherit' })
    if ((result.status ?? 1) !== 0) {
      failed = true
      console.error(`select-tests: lane ${lane} FAILED`)
      break
    }
  }
}

console.log('\n=== result ===')
console.log(`  ran: ${toRun.length === 0 ? '(nothing)' : toRun.join(', ')}`)
if (manualLanes.length > 0 && !includeManual) {
  console.log(`  NOT run: ${manualLanes.join(', ')} -- these are still outstanding`)
}
console.log(`  full authority: ${GATE}`)
process.exit(failed ? 1 : 0)
