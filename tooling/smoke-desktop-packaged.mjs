#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { createRequire } from 'node:module'
import { existsSync, lstatSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const requireFromDesktop = createRequire(join(desktopRoot, 'package.json'))

const fail = (message) => {
  console.error(`Packaged desktop smoke failed: ${message}`)
  process.exit(1)
}

const manifestFlag = process.argv.indexOf('--manifest')
if (manifestFlag === -1 || manifestFlag !== process.argv.length - 2) {
  fail('usage: node tooling/smoke-desktop-packaged.mjs --manifest /absolute/path/package-manifest.json')
}

const manifestPath = resolve(process.argv[manifestFlag + 1])
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

const profilePath = mkdtempSync(join(tmpdir(), 'keepling-packaged-smoke-profile-'))
const forbiddenUserDataDir = resolve(homedir(), 'Library', 'Application Support', 'Keepling')
if (resolve(profilePath) === forbiddenUserDataDir) fail('packaged smoke refused the normal Keepling profile')

let electronApplication
try {
  const { _electron: electron } = requireFromDesktop('playwright')
  electronApplication = await electron.launch({
    args: [`--user-data-dir=${profilePath}`],
    cwd: dirname(executablePath),
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_FORBIDDEN_USER_DATA_DIR: forbiddenUserDataDir,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    executablePath,
    timeout: 30_000,
  })
  const runtime = await electronApplication.evaluate(({ app }) => ({
    isPackaged: app.isPackaged,
    versions: process.versions,
  }))
  if (runtime.isPackaged !== true) fail('app.isPackaged was not true for the manifest-selected executable')
  for (const [name, expected] of Object.entries(manifest.embeddedVersions)) {
    if (runtime.versions[name] !== expected) fail(`embedded ${name} version differs from the package manifest`)
  }
  console.log(`Packaged desktop smoke passed: ${manifest.applicationDigestSha256}`)
} finally {
  await electronApplication?.close().catch(() => undefined)
  rmSync(profilePath, { force: true, recursive: true })
}
