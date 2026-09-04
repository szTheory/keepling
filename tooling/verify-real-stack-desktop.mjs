#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

/**
 * The PACKAGED Mac app against a REAL Phoenix server on REAL PostgreSQL
 * (O-34/O-37, D-49).
 *
 * Every guard below exists because of something that actually went wrong.
 * The lane this replaces was named `real-stack-sync` and stubbed its
 * transport against a deliberately non-resolving host, and its NAME was
 * enough to get a requirement checked on a false citation. So this runner
 * refuses to take the lane's word for anything:
 *
 *   - the spec must not set `KEEPLING_TEST_SYNC_MODE`, and neither may the
 *     environment -- with it set, the app runs an inline stub and the whole
 *     lane is theatre;
 *   - the spec must not stub `fetch` or point at a `.invalid` host;
 *   - the spec must import the SHARED backend harness, so it cannot quietly
 *     grow its own drifting copy of "a real server";
 *   - Playwright must report a positive pass count and zero failures;
 *   - and the spec must print a `REAL_STACK_SYNC` line reporting what it
 *     observed. A run that passes without that line did not do the work.
 *
 * An absent capability is a LOUD FAILURE here, never a skip. If PostgreSQL
 * or Phoenix cannot start, this exits non-zero with the real error.
 */

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const specDir = join(desktopRoot, 'test', 'real-stack')

const fail = (message) => {
  console.error(`Desktop real-stack lane failed: ${message}`)
  process.exit(1)
}

const specFiles = existsSync(specDir)
  ? readdirSync(specDir).filter((entry) => entry.endsWith('.spec.ts')).sort()
  : []
if (specFiles.length === 0) fail('no real-stack spec files exist under test/real-stack')

if (process.env.KEEPLING_TEST_SYNC_MODE !== undefined) {
  fail('KEEPLING_TEST_SYNC_MODE is set in the environment -- the real adapter would not run')
}

for (const file of specFiles) {
  const source = readFileSync(join(specDir, file), 'utf8')
  if (!source.includes('--user-data-dir')) fail(`${file} omits the disposable profile argument`)
  // The point of the lane is that the REAL adapter runs. Any of these would
  // silently turn it back into the fake it exists to replace.
  if (/KEEPLING_TEST_SYNC_MODE:\s*['"]/.test(source)) {
    fail(`${file} sets KEEPLING_TEST_SYNC_MODE -- the real adapter would not run`)
  }
  if (source.includes('.invalid')) fail(`${file} references a non-resolving .invalid host`)
  if (/fetch:\s*(async\s*)?\(/.test(source)) fail(`${file} injects a stubbed fetch into the adapter`)
  if (!source.includes("from '../../../web/e2e/support/backend.ts'")) {
    fail(`${file} does not use the shared real backend harness`)
  }
}

const manifestFlag = process.argv.indexOf('--manifest')
const locatorName = `keepling-desktop-latest-manifest-${createHash('sha256').update(repositoryRoot).digest('hex').slice(0, 16)}.txt`
const selectedManifest = manifestFlag === -1
  ? readFileSync(join(tmpdir(), locatorName), 'utf8').trim()
  : process.argv[manifestFlag + 1]
if (!selectedManifest) fail('a package manifest must be selected explicitly or by the package-once locator')
const manifestPath = resolve(selectedManifest)

let manifest
try {
  manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
} catch {
  fail('the package manifest is missing or invalid JSON')
}
if (!existsSync(manifest.executablePath)) fail('manifest-selected executable does not exist')

const profilePath = mkdtempSync(join(tmpdir(), 'keepling-real-stack-profile-'))
const forbiddenUserDataDir = resolve(homedir(), 'Library', 'Application Support', 'Keepling')
if (resolve(profilePath) === forbiddenUserDataDir) fail('the real-stack lane refused the normal Keepling profile')

try {
  const laneEnvironment = { ...process.env }
  delete laneEnvironment.KEEPLING_TEST_SYNC_MODE

  const result = spawnSync(
    'pnpm',
    ['exec', 'playwright', 'test', '--config', 'playwright.config.ts', '--project', 'real-stack'],
    {
      cwd: desktopRoot,
      encoding: 'utf8',
      env: {
        ...laneEnvironment,
        KEEPLING_FORBIDDEN_USER_DATA_DIR: forbiddenUserDataDir,
        KEEPLING_PACKAGE_MANIFEST: manifestPath,
        KEEPLING_TEST_USER_DATA_DIR: profilePath,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  )
  process.stdout.write(result.stdout ?? '')
  process.stderr.write(result.stderr ?? '')
  if (result.error || result.status !== 0) {
    fail(`the real-stack Playwright project exited ${result.status ?? 'without status'}`)
  }

  const stdout = result.stdout ?? ''
  const passedMatch = stdout.match(/(\d+) passed/)
  const failedMatch = stdout.match(/(\d+) failed/)
  const passedCount = passedMatch ? Number(passedMatch[1]) : 0
  if (failedMatch) fail(`the real-stack suite reported ${failedMatch[1]} failing test(s)`)
  if (passedCount <= 0) fail('the real-stack suite reported zero passing tests')

  // The evidence lines the spec prints only after it has genuinely settled
  // something against the real server. Without them a green run means
  // nothing -- a suite that executed and asserted nothing still exits 0.
  const evidence = stdout.match(
    /REAL_STACK_SYNC synced=(\d+) pushed_exact_bytes=(\d+) outcomes=(\S+) server_origin=(\S+)/,
  )
  if (!evidence) fail('the real-stack suite never reported a REAL_STACK_SYNC evidence line')
  if (Number(evidence[1]) <= 0) fail('the real-stack suite settled zero mutations')
  if (Number(evidence[2]) <= 0) fail('the real-stack suite proved no exact-bytes retry')

  // O-41. `capture_task` was the ONLY command type this client could ever
  // construct, and the whole point of closing it is that the others reach a
  // real server. A run that observed only captures has not proved that, so
  // the lane names every type it must have seen ARRIVE rather than trusting
  // that a green suite exercised them.
  const mutations = stdout.match(/REAL_STACK_MUTATIONS command_types=(\S+) final_revision=(\d+) outbox=(\d+)/)
  if (!mutations) fail('the real-stack suite never reported a REAL_STACK_MUTATIONS evidence line')
  const observedTypes = mutations[1].split(',')
  const requiredTypes = [
    'capture_task', 'complete_task', 'edit_task', 'plan_for_today',
    'reopen_task', 'restore_task', 'trash_task', 'unplan_task',
  ]
  for (const type of requiredTypes) {
    if (!observedTypes.includes(type)) fail(`the real server never received a ${type} command`)
  }
  if (Number(mutations[2]) <= 1) fail('the real server never advanced the task revision -- nothing was accepted')
  if (Number(mutations[3]) !== 0) fail('the real-stack suite left unsent commands in the outbox')

  // O-38. The conflict must come from the REAL server refusing a REAL
  // second writer. A lane that reported a conflict without one would be
  // asserting a fixture.
  const conflict = stdout.match(
    /REAL_STACK_CONFLICT ordering=(\S+) outcomes=(\S+) conflicts=(\d+) second_writer=(\S+)/,
  )
  if (!conflict) fail('the real-stack suite never reported a REAL_STACK_CONFLICT evidence line')
  if (conflict[1] !== 'capture_task,edit_task') fail('the real-stack suite did not prove capture-before-edit ordering')
  if (!conflict[2].split(',').includes('conflict')) fail('the real-stack suite observed no conflict outcome')
  if (Number(conflict[3]) <= 0) fail('the real-stack suite surfaced zero conflicts')
  if (conflict[4] !== 'real') fail('the conflict was not produced by a real second writer')

  console.log(
    `Desktop real-stack lane passed: cases=${passedCount} synced=${evidence[1]} ` +
      `exact_bytes=${evidence[2]} outcomes=${evidence[3]},${conflict[2]} server_origin=${evidence[4]} ` +
      `command_types=${observedTypes.length} conflicts=${conflict[3]} ` +
      `digest=${manifest.applicationDigestSha256}`,
  )
} finally {
  rmSync(profilePath, { force: true, recursive: true })
}
