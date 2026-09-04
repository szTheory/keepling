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

  // The evidence line the spec prints only after it has genuinely settled a
  // mutation against the real server. Without it a green run means nothing.
  const evidence = stdout.match(
    /REAL_STACK_SYNC synced=(\d+) pushed_exact_bytes=(\d+) outcomes=(\S+) server_origin=(\S+)/,
  )
  if (!evidence) fail('the real-stack suite never reported a REAL_STACK_SYNC evidence line')
  if (Number(evidence[1]) <= 0) fail('the real-stack suite settled zero mutations')
  if (Number(evidence[2]) <= 0) fail('the real-stack suite proved no exact-bytes retry')

  console.log(
    `Desktop real-stack lane passed: cases=${passedCount} synced=${evidence[1]} ` +
      `exact_bytes=${evidence[2]} outcomes=${evidence[3]} server_origin=${evidence[4]} ` +
      `digest=${manifest.applicationDigestSha256}`,
  )
} finally {
  rmSync(profilePath, { force: true, recursive: true })
}
