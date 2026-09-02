#!/usr/bin/env node

import { createHash } from 'node:crypto'
import {
  cpSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, join, relative, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const outRoot = join(desktopRoot, 'out')

const fail = (message) => {
  console.error(`Desktop package failed: ${message}`)
  process.exit(1)
}

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    cwd: desktopRoot,
    encoding: 'utf8',
    stdio: options.capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    ...options,
  })
  if (result.error || result.status !== 0) {
    fail(`${command} ${args.join(' ')} exited ${result.status ?? 'without status'}${result.stderr ? `: ${result.stderr.trim()}` : ''}`)
  }
  return result.stdout?.trim() ?? ''
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')
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

const trackedInputs = run(
  'git',
  [
    '-C',
    repositoryRoot,
    'ls-files',
    '-z',
    'apps/desktop',
    '.npmrc',
    'package.json',
    'pnpm-lock.yaml',
    'pnpm-workspace.yaml',
    'tooling/package-desktop.mjs',
    'tooling/smoke-desktop-packaged.mjs',
  ],
  { capture: true },
)
  .split('\0')
  .filter(Boolean)
  .sort()

if (trackedInputs.length === 0) fail('the package input set is empty')
const dirtyInputs = run(
  'git',
  ['-C', repositoryRoot, 'status', '--porcelain', '--untracked-files=no', '--', ...trackedInputs],
  { capture: true },
)
if (dirtyInputs !== '') fail('package inputs must be committed before package-once records a source revision')

const inputDigest = createHash('sha256')
for (const relativePath of trackedInputs) {
  inputDigest.update(`${relativePath}\0`)
  inputDigest.update(readFileSync(join(repositoryRoot, relativePath)))
  inputDigest.update('\0')
}

const sourceRevision = run('git', ['-C', repositoryRoot, 'rev-parse', 'HEAD'], { capture: true })
const architecture = process.arch
const startedAt = Date.now()

run('pnpm', ['run', 'build'])
run('pnpm', ['exec', 'electron-forge', 'make', '--platform', 'darwin', '--arch', architecture])

const findOutputs = (root, predicate, descendIntoMatch = true) => {
  const outputs = []
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name)
      if (predicate(path, entry)) outputs.push(path)
      if (entry.isDirectory() && (descendIntoMatch || !predicate(path, entry))) visit(path)
    }
  }
  visit(root)
  return outputs
}

const newestOutput = (paths, label) => {
  const fresh = paths.filter((path) => statSync(path).mtimeMs >= startedAt - 2_000)
  if (fresh.length !== 1) fail(`expected exactly one fresh ${label}, found ${fresh.length}`)
  return fresh[0]
}

const applicationPath = newestOutput(
  findOutputs(outRoot, (path, entry) => entry.isDirectory() && path.endsWith('.app'), false),
  'Keepling application',
)
const zipPath = newestOutput(
  findOutputs(outRoot, (path, entry) => entry.isFile() && path.endsWith('.zip')),
  'ZIP artifact',
)

const executableName = basename(applicationPath, '.app')
const builtExecutablePath = join(applicationPath, 'Contents', 'MacOS', executableName)
const artifactRoot = mkdtempSync(join(tmpdir(), 'keepling-desktop-package-'))
const copiedApplicationPath = join(artifactRoot, basename(applicationPath))
cpSync(applicationPath, copiedApplicationPath, {
  dereference: false,
  errorOnExist: true,
  recursive: true,
  verbatimSymlinks: true,
})
const executablePath = join(copiedApplicationPath, 'Contents', 'MacOS', executableName)

const applicationDigestSha256 = hashDirectory(applicationPath)
if (hashDirectory(copiedApplicationPath) !== applicationDigestSha256) fail('the copied application digest differs from the built application')
if (hashFile(builtExecutablePath) !== hashFile(executablePath)) fail('the copied executable differs from the built executable')

const versionsJson = run(
  executablePath,
  ['-p', 'JSON.stringify(process.versions)'],
  { capture: true, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' } },
)
let processVersions
try {
  processVersions = JSON.parse(versionsJson)
} catch {
  fail('the packaged executable did not report embedded process versions')
}

const embeddedVersions = {
  chrome: processVersions.chrome,
  electron: processVersions.electron,
  node: processVersions.node,
  v8: processVersions.v8,
}
if (Object.values(embeddedVersions).some((value) => typeof value !== 'string' || value.length === 0)) {
  fail('the packaged executable omitted an embedded runtime version')
}

const manifest = {
  applicationDigestSha256,
  applicationPath,
  architecture,
  copiedApplicationPath,
  createdAt: new Date().toISOString(),
  embeddedVersions,
  executableDigestSha256: hashFile(executablePath),
  executablePath,
  inputDigestSha256: inputDigest.digest('hex'),
  platform: 'darwin',
  schemaVersion: 1,
  sourceRevision,
  trackedInputs,
  zipDigestSha256: hashFile(zipPath),
  zipPath,
}
const manifestPath = join(artifactRoot, 'package-manifest.json')
mkdirSync(artifactRoot, { recursive: true })
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' })
const locatorName = `keepling-desktop-latest-manifest-${sha256(repositoryRoot).slice(0, 16)}.txt`
writeFileSync(join(tmpdir(), locatorName), `${manifestPath}\n`, { encoding: 'utf8' })

console.log(`Desktop package manifest: ${manifestPath}`)
