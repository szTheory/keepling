#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { existsSync, lstatSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { isAbsolute, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const packagedTestDir = join(desktopRoot, 'test', 'packaged')

const fail = (message) => {
  console.error(`Packaged desktop smoke failed: ${message}`)
  process.exit(1)
}

// Every packaged spec file is eligible by name (offline-capture, daily-loop,
// security, ...) -- never hardcode a single scenario, or adding a new
// packaged spec silently stops being selectable by name.
const packagedSpecFiles = readdirSync(packagedTestDir)
  .filter((entry) => entry.endsWith('.spec.ts'))
  .sort()
if (packagedSpecFiles.length === 0) fail('no packaged spec files exist under test/packaged')
const knownScenarios = new Map(packagedSpecFiles.map((file) => [file.replace(/\.spec\.ts$/, ''), file]))
const requestedScenarioArg = process.argv.slice(2).find((argument) => knownScenarios.has(argument))
const requestedScenario = requestedScenarioArg ?? null

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

const assertOutsideRepository = (path, label) => {
  const candidate = resolve(path)
  const fromRepository = relative(repositoryRoot, candidate)
  if (fromRepository === '' || (!fromRepository.startsWith(`..${sep}`) && !isAbsolute(fromRepository))) {
    fail(`${label} must be outside the source repository`)
  }
  return candidate
}

const copiedApplicationPath = assertOutsideRepository(manifest.copiedApplicationPath, 'copied application')
const executablePath = assertOutsideRepository(manifest.executablePath, 'packaged executable')
if (!copiedApplicationPath.endsWith('.app') || !existsSync(copiedApplicationPath)) fail('manifest does not select an existing copied .app')
if (!existsSync(executablePath)) fail('manifest-selected executable does not exist')
const executableFromApplication = relative(copiedApplicationPath, executablePath)
if (executableFromApplication.startsWith(`..${sep}`) || isAbsolute(executableFromApplication)) {
  fail('manifest-selected executable is outside the copied application')
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')
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

if (hashDirectory(copiedApplicationPath) !== manifest.applicationDigestSha256) fail('copied application digest does not match the package manifest')
if (sha256(readFileSync(executablePath)) !== manifest.executableDigestSha256) fail('executable digest does not match the package manifest')

// Anti-vacuous discipline applies to EVERY packaged spec, not just one: each
// must launch a disposable profile, and at least one must assert the real
// packaged runtime flag.
let anyAssertsIsPackaged = false
for (const file of packagedSpecFiles) {
  const source = readFileSync(join(packagedTestDir, file), 'utf8')
  if (!source.includes('--user-data-dir')) fail(`${file} omits the disposable profile argument`)
  if (source.includes('app.isPackaged')) anyAssertsIsPackaged = true
}
if (!anyAssertsIsPackaged) fail('no packaged spec asserts app.isPackaged')

const profilePath = mkdtempSync(join(tmpdir(), 'keepling-packaged-smoke-profile-'))
const forbiddenUserDataDir = resolve(homedir(), 'Library', 'Application Support', 'Keepling')
if (resolve(profilePath) === forbiddenUserDataDir) fail('packaged smoke refused the normal Keepling profile')

try {
  const argumentsForPlaywright = [
    'exec',
    'playwright',
    'test',
    ...(requestedScenario ? [`${requestedScenario}.spec.ts`] : []),
    '--config',
    'playwright.config.ts',
    '--project',
    'packaged',
  ]
  const result = spawnSync('pnpm', argumentsForPlaywright, {
    cwd: desktopRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      KEEPLING_PACKAGE_MANIFEST: manifestPath,
      KEEPLING_FORBIDDEN_USER_DATA_DIR: forbiddenUserDataDir,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  process.stdout.write(result.stdout)
  process.stderr.write(result.stderr)
  if (result.error || result.status !== 0) fail(`packaged Playwright scenario exited ${result.status ?? 'without status'}`)
  // Anti-vacuous, generalized across every packaged spec: Playwright's own
  // summary line must report a positive pass count and zero failures --
  // never a hardcoded single-scenario marker string that silently stops
  // covering new packaged specs.
  const passedMatch = result.stdout.match(/(\d+) passed/)
  const failedMatch = result.stdout.match(/(\d+) failed/)
  const passedCount = passedMatch ? Number(passedMatch[1]) : 0
  const failedCount = failedMatch ? Number(failedMatch[1]) : 0
  if (passedCount <= 0) fail('packaged suite reported zero passing tests')
  if (failedCount > 0) fail(`packaged suite reported ${failedCount} failing test(s)`)
  console.log(
    `Packaged desktop smoke passed: digest=${manifest.applicationDigestSha256} executable=${executablePath} passed=${passedCount}`,
  )
} finally {
  rmSync(profilePath, { force: true, recursive: true })
}
