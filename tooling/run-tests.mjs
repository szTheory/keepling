#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import process from 'node:process'

/**
 * One argument-forwarding entry point for every desktop test lane.
 *
 * Why this exists (measured, Plan 03-17 Task 1): `pnpm <script> -- <filter>`
 * does NOT drop the arguments -- pnpm appends them to the script command
 * VERBATIM, bare `--` included. The runner is what loses them:
 *
 *   * vitest (cac) treats everything after a bare `--` as passthrough args,
 *     never as a test-name filter, so `vitest run ... -- keyboardCommands`
 *     silently ran all 18 files / 164 tests instead of 1 file / 19.
 *   * Playwright's `--project` is VARIADIC, so a bare positional following
 *     `--project electron` is parsed as a second PROJECT name
 *     (`Project(s) "keyboard-menus" not found`), and after a bare `--` the
 *     filter -- and even `--list` -- is ignored entirely.
 *
 * Both failures are silent, which is the actual harm: a scoped-looking
 * command reports full-suite counts. This wrapper removes bare `--`
 * separators (announcing that it did) and always uses `--project=<name>` so
 * a trailing positional stays a positional.
 */

const REPOSITORY_ROOT = fileURLToPath(new URL('../', import.meta.url))
const DESKTOP_ROOT = join(REPOSITORY_ROOT, 'apps', 'desktop')

const LANES = {
  e2e: {
    binary: 'playwright',
    args: ['test', '--config', 'playwright.config.ts', '--project=electron'],
    filterHint: 'a file-path substring, e.g. `keyboard-menus`',
  },
  ipc: {
    binary: 'vitest',
    args: ['run', '--config', 'vitest.config.ts', '--project=ipc'],
    filterHint: 'a file-path substring, e.g. `protocol-contract`',
  },
  unit: {
    binary: 'vitest',
    args: [
      'run',
      '--config',
      'vitest.config.ts',
      '--project=application',
      '--project=renderer',
      '--project=store',
      '--project=performance',
    ],
    filterHint: 'a file-path substring, e.g. `keyboardCommands`',
  },
}

const [laneName, ...rawArguments] = process.argv.slice(2)
const lane = Object.hasOwn(LANES, laneName) ? LANES[laneName] : undefined
if (lane === undefined) {
  console.error(`run-tests: unknown lane "${laneName ?? ''}" (expected one of: ${Object.keys(LANES).sort().join(', ')})`)
  process.exit(2)
}

// Strip bare `--` separators only. A flag that merely STARTS with `--`
// (`--reporter=json`, `--headed`) is a real runner flag and is forwarded
// untouched; only the standalone separator is dropped, because that is the
// token both runners mis-handle.
const forwarded = rawArguments.filter((argument) => argument !== '--')
if (forwarded.length !== rawArguments.length) {
  console.log(
    `run-tests: dropped a bare \`--\` separator so ${lane.binary} sees the remaining arguments as ${lane.filterHint}.`,
  )
}

const binaryPath = join(REPOSITORY_ROOT, 'node_modules', '.bin', lane.binary)
if (!existsSync(binaryPath)) {
  console.error(`run-tests: ${lane.binary} is not installed at ${binaryPath} -- run \`pnpm install\` first.`)
  process.exit(2)
}

// An explicit `--project=<name>` REPLACES the lane's default project set
// rather than adding to it, so `tooling/select-tests.mjs` can narrow a lane
// to the single vitest project that can observe a change. Without this an
// extra `--project` would union with the defaults and narrow nothing.
const overridesProjects = forwarded.some((argument) => argument.startsWith('--project'))
const laneArguments = overridesProjects
  ? lane.args.filter((argument) => !argument.startsWith('--project'))
  : lane.args

const argv = [...laneArguments, ...forwarded]
console.log(`run-tests: ${lane.binary} ${argv.join(' ')}`)
const result = spawnSync(binaryPath, argv, { cwd: DESKTOP_ROOT, stdio: 'inherit' })
if (result.error) {
  console.error(`run-tests: failed to start ${lane.binary}: ${result.error.message}`)
  process.exit(2)
}
process.exit(result.status ?? 1)
