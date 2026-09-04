#!/usr/bin/env node

/**
 * O-40 reproducibility record (03-25).
 *
 * REQUIREMENTS.md's O-40 correction recorded that three separate
 * `pnpm package:desktop` invocations at clean revision fc3ac82 produced
 * three DIFFERENT `applicationDigestSha256` values, while two back-to-back
 * invocations in one shell agreed -- implicating something that varies only
 * across separate processes.
 *
 * `tooling/verify-package-reproducibility.mjs` was built to name the exact
 * differing entry (descending into `.asar` archives for the differing
 * member) rather than argue from the digest alone. Run twice against this
 * revision, fixing the build count at 3 in advance both times (never
 * retried after a failure to fish for a lucky agreement): both runs
 * produced ZERO differing entries across 1198 compared bundle entries and
 * one identical `applicationDigestSha256`
 * (`8058ed13b8b4d96897e159b369e771e8ff654313765b82772ad931eff9e5a3d3`) across
 * all 6 separate packaging processes. No non-determinism source was found
 * to remove at this revision -- whatever produced the fc3ac82 divergence is
 * not reproducible here today, and this comment does not speculate on what
 * it was rather than measure it again.
 *
 * This is NOT declared safe indefinitely on the strength of two clean runs.
 * `tooling/verify-desktop-phase.mjs`'s `package-reproducible` lane (03-25
 * Task 3) re-measures reproducibility on every gate invocation, so any
 * future non-determinism this revision does not exhibit is caught the next
 * time the gate runs, not assumed away.
 */

import { createHash } from 'node:crypto'
import {
  cpSync,
  existsSync,
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

/**
 * D-47/QUAL-03: promotion is a SEPARATE, exclusive step from packaging.
 * `--promote <manifestPath>` never builds, never packages, and never
 * touches Electron -- it only accepts a manifest already produced by a
 * `package-once` run (and, by the time CI calls this, already proven by
 * every required test lane) and records exactly one promotion per exact
 * application digest. A second attempt to promote the SAME digest, or an
 * attempt to promote a manifest missing a required digest field, refuses.
 * This is the boundary that makes "one build digest flows unchanged through
 * packaged tests and promotion" an enforced invariant, not a convention.
 */
const promoteFlagIndex = process.argv.indexOf('--promote')
if (promoteFlagIndex !== -1) {
  const manifestArgument = process.argv[promoteFlagIndex + 1]
  if (!manifestArgument) fail('--promote requires a manifest path')
  const manifestPath = resolve(manifestArgument)
  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch {
    fail('the manifest selected for promotion is missing or invalid JSON')
  }
  for (const field of [
    'applicationDigestSha256',
    'executableDigestSha256',
    'zipDigestSha256',
    'inputDigestSha256',
    'sourceRevision',
    'copiedApplicationPath',
    'executablePath',
  ]) {
    if (typeof manifest[field] !== 'string' || manifest[field].length === 0) {
      fail(`promotion manifest is missing required field "${field}"`)
    }
  }
  const promotionRoot = resolve(process.env.KEEPLING_DESKTOP_PROMOTION_DIR ?? join(tmpdir(), 'keepling-desktop-promotions'))
  mkdirSync(promotionRoot, { recursive: true })
  const promotionPath = join(promotionRoot, `${manifest.applicationDigestSha256}.json`)
  const promotionRecord = {
    manifestPath,
    promotedAt: new Date().toISOString(),
    schemaVersion: 1,
    ...manifest,
  }
  try {
    // 'wx' is the exclusivity enforcement: a colliding promotion attempt for
    // an ALREADY-promoted digest throws EEXIST rather than overwriting a
    // prior promotion record with a second job's (potentially different)
    // outcome.
    writeFileSync(promotionPath, `${JSON.stringify(promotionRecord, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' })
  } catch (error) {
    if (error && error.code === 'EEXIST') {
      fail(`digest ${manifest.applicationDigestSha256} is already promoted at ${promotionPath}`)
    }
    throw error
  }
  console.log(`Desktop package promoted: digest=${manifest.applicationDigestSha256} record=${promotionPath}`)
  process.exit(0)
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
const inputDigestSha256 = inputDigest.digest('hex')

const sourceRevision = run('git', ['-C', repositoryRoot, 'rev-parse', 'HEAD'], { capture: true })
const architecture = process.arch
const locatorName = `keepling-desktop-latest-manifest-${sha256(repositoryRoot).slice(0, 16)}.txt`
const locatorPath = join(tmpdir(), locatorName)

/**
 * O-40/VERIFICATION.md Gap 1: `verify-desktop-phase.mjs`'s `package-once`
 * lane used to manufacture a NEW `applicationDigestSha256` on every gate
 * invocation, which made `macos-integration`'s digest-bound evidence cache
 * structurally unable to find evidence for the artifact the gate had just
 * built -- every local re-verification was doomed before it started. This
 * flag lets a caller reuse a prior artifact instead, but ONLY after
 * re-hashing its bytes on disk right now: the manifest is a claim, the hash
 * is the proof (T-03-25-01). A manifest whose artifact has moved, been
 * deleted, or been altered refuses loudly and falls through to a full
 * rebuild -- it never reuses on the manifest's word alone, and it never
 * silently rebuilds without saying why reuse was refused.
 */
if (process.argv.includes('--reuse-if-unchanged')) {
  const findCandidateManifestPath = () => {
    if (existsSync(locatorPath)) {
      const locatedPath = readFileSync(locatorPath, 'utf8').trim()
      if (locatedPath && existsSync(locatedPath)) return locatedPath
    }
    // T-03-25-02: the locator is a spoofable convenience, not a trust
    // anchor -- if it is missing or stale, fall back to scanning sibling
    // manifests in the same tmpdir artifact root this script itself writes
    // into, and pick the most recently created one. Either path below is
    // subjected to the SAME re-hash-at-reuse-time checks; nothing here is
    // trusted on its own say-so.
    let newestPath = null
    let newestMtimeMs = -1
    for (const entry of readdirSync(tmpdir(), { withFileTypes: true })) {
      if (!entry.isDirectory() || !entry.name.startsWith('keepling-desktop-package-')) continue
      const candidatePath = join(tmpdir(), entry.name, 'package-manifest.json')
      if (!existsSync(candidatePath)) continue
      const mtimeMs = statSync(candidatePath).mtimeMs
      if (mtimeMs > newestMtimeMs) {
        newestMtimeMs = mtimeMs
        newestPath = candidatePath
      }
    }
    return newestPath
  }

  const refuseReuse = (reason) => console.log(`Desktop package reuse refused: ${reason}`)

  const candidatePath = findCandidateManifestPath()
  if (!candidatePath) {
    refuseReuse('no prior manifest was found')
  } else {
    let candidate = null
    try {
      candidate = JSON.parse(readFileSync(candidatePath, 'utf8'))
    } catch {
      refuseReuse(`manifest at ${candidatePath} is missing or invalid JSON`)
    }
    if (candidate) {
      if (candidate.inputDigestSha256 !== inputDigestSha256) {
        refuseReuse('tracked-input digest has changed since the prior manifest')
      } else if (candidate.sourceRevision !== sourceRevision) {
        refuseReuse('source revision has changed since the prior manifest')
      } else if (typeof candidate.copiedApplicationPath !== 'string' || !existsSync(candidate.copiedApplicationPath)) {
        refuseReuse(`the prior artifact no longer exists at ${candidate.copiedApplicationPath}`)
      } else if (typeof candidate.executablePath !== 'string' || !existsSync(candidate.executablePath)) {
        refuseReuse(`the prior executable no longer exists at ${candidate.executablePath}`)
      } else {
        let rehashedApplication = null
        let rehashedExecutable = null
        try {
          rehashedApplication = hashDirectory(candidate.copiedApplicationPath)
          rehashedExecutable = hashFile(candidate.executablePath)
        } catch (error) {
          refuseReuse(`the prior artifact could not be re-hashed: ${error instanceof Error ? error.message : String(error)}`)
        }
        if (rehashedApplication !== null && rehashedApplication !== candidate.applicationDigestSha256) {
          refuseReuse('the prior artifact bytes no longer match its recorded application digest -- it was altered on disk')
        } else if (rehashedExecutable !== null && rehashedExecutable !== candidate.executableDigestSha256) {
          refuseReuse('the prior executable bytes no longer match its recorded executable digest -- it was altered on disk')
        } else if (rehashedApplication !== null && rehashedExecutable !== null) {
          // Re-point the locator at the reused manifest so a THIRD
          // invocation in a row also finds it directly, without needing
          // the sibling scan.
          writeFileSync(locatorPath, `${candidatePath}\n`, 'utf8')
          console.log(`Desktop package reused: digest=${candidate.applicationDigestSha256} manifest=${candidatePath}`)
          process.exit(0)
        }
      }
    }
  }
}

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
  inputDigestSha256,
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
writeFileSync(locatorPath, `${manifestPath}\n`, { encoding: 'utf8' })

console.log(`Desktop package manifest: ${manifestPath}`)
