#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import process from 'node:process'

/**
 * Run only the lanes the working-tree changes can actually affect.
 *
 * This is a FAST FEEDBACK tool, not a gate. It answers "did I just break
 * something obvious", in seconds, so the fifty-times-a-day loop stays cheap.
 * `node tooling/verify-desktop-phase.mjs` remains the only authoritative
 * answer and always runs everything.
 *
 * The mapping is deliberately CONSERVATIVE -- when a path could plausibly
 * affect a lane, the lane runs. A selector that is too clever is worse than
 * no selector, because a missed lane is a silent false pass, and this
 * repository has spent a whole phase removing checks that pass by observing
 * nothing.
 *
 * The Electron E2E lane is excluded by default because it is the slow one
 * (tens of seconds, real windows, real store). Pass `--e2e` to include it, or
 * change a spec under `test/e2e/` and it selects itself.
 */

const REPOSITORY_ROOT = fileURLToPath(new URL('../', import.meta.url))

// Ordered cheapest-first so the fastest disproof arrives first.
const RULES = [
  {
    lane: 'unit',
    reason: 'application, renderer, store or performance code',
    test: (path) =>
      path.startsWith('apps/desktop/main/') ||
      path.startsWith('apps/desktop/renderer/') ||
      path.startsWith('packages/web-ui/') ||
      path.startsWith('apps/desktop/test/application/') ||
      path.startsWith('apps/desktop/test/renderer/') ||
      path.startsWith('apps/desktop/test/store/') ||
      path.startsWith('apps/desktop/test/performance/'),
  },
  {
    lane: 'ipc',
    reason: 'the preload bridge or IPC protocol',
    test: (path) =>
      path.startsWith('apps/desktop/preload/') ||
      path === 'apps/desktop/main/protocol.ts' ||
      path.startsWith('apps/desktop/test/ipc/'),
  },
  {
    lane: 'e2e',
    reason: 'an Electron E2E spec',
    slow: true,
    test: (path) => path.startsWith('apps/desktop/test/e2e/'),
  },
]

const changedFiles = () => {
  const result = spawnSync('git', ['status', '--porcelain=v1', '--untracked-files=all'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  })
  if (result.status !== 0) {
    console.error('test-changed: `git status` failed, so the change set is unknown.')
    console.error('Refusing to report a scoped pass against an unknown change set -- run the full gate instead.')
    process.exit(2)
  }
  // Porcelain v1: two status columns, a space, then the path. Renames carry
  // `old -> new`; the destination is what was actually written.
  return result.stdout
    .split('\n')
    .filter((line) => line.length > 3)
    .map((line) => line.slice(3).trim())
    .map((path) => (path.includes(' -> ') ? path.split(' -> ')[1] : path))
    .map((path) => path.replaceAll('"', ''))
}

const wantsE2e = process.argv.includes('--e2e')
const files = changedFiles()

if (files.length === 0) {
  console.log('test-changed: the working tree is clean -- nothing changed, so nothing is worth running.')
  process.exit(0)
}

const selected = RULES.filter((rule) => (rule.slow && wantsE2e) || files.some((file) => rule.test(file)))

console.log(`test-changed: ${files.length} changed path(s).`)
if (selected.length === 0) {
  console.log('test-changed: no desktop test lane covers these paths, so no lane ran.')
  console.log('That is NOT a pass. Run `node tooling/verify-desktop-phase.mjs` before believing anything is green.')
  process.exit(0)
}

const skippedSlow = RULES.filter((rule) => rule.slow && !selected.includes(rule))
for (const rule of selected) console.log(`  will run ${rule.lane} -- ${rule.reason} changed`)
for (const rule of skippedSlow) console.log(`  skipping ${rule.lane} (slow; add --e2e to include it)`)

for (const rule of selected) {
  console.log(`\n=== ${rule.lane} ===`)
  const result = spawnSync('node', ['tooling/run-tests.mjs', rule.lane], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
    stdio: 'inherit',
  })
  if (result.status !== 0) {
    console.error(`\ntest-changed: the ${rule.lane} lane FAILED. Stopping here.`)
    process.exit(result.status ?? 1)
  }
}

console.log('\ntest-changed: every selected lane passed.')
console.log('Scoped run only -- `node tooling/verify-desktop-phase.mjs` is still the authoritative gate.')
