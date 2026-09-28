#!/usr/bin/env node

import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')

const fail = (message) => {
  throw new Error(message)
}

const option = (name) => {
  const index = process.argv.indexOf(name)
  if (index === -1 || !process.argv[index + 1]) fail(`missing required argument ${name}`)
  return resolve(process.argv[index + 1])
}

const manifestJson = (path, label) => {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    fail(`${label} package manifest is missing or invalid`)
  }
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')

const runQuiet = (command, args, label) => {
  const result = spawnSync(command, args, { encoding: 'utf8' })
  if (result.error || result.status !== 0) fail(`${label} failed`)
  return `${result.stdout ?? ''}\n${result.stderr ?? ''}`
}

const assertPackageState = (manifest, label, expectedRevision) => {
  if (!/^[0-9a-f]{40}$/i.test(manifest.sourceRevision ?? '')) {
    fail(`${label} package source revision is missing or malformed`)
  }
  if (manifest.sourceRevision !== expectedRevision) {
    fail(`${label} package does not match its GitHub Actions run revision`)
  }
  if (manifest.platform !== 'darwin' || manifest.codeSigning?.developerIdSigned !== true) {
    fail(`${label} package is not Developer ID signed for macOS`)
  }
  if (manifest.codeSigning?.hardenedRuntime !== true) {
    fail(`${label} package is missing the hardened runtime`)
  }
  if (
    manifest.notarization?.attempted !== true
    || manifest.notarization?.status !== 'Accepted'
    || manifest.notarization?.stapled !== true
  ) {
    fail(`${label} package is not accepted and stapled by notarization`)
  }
  if (!/^[0-9a-f]+$/i.test(manifest.codeDirectoryHash ?? '')) {
    fail(`${label} package is missing its recorded code-directory hash`)
  }
}

const assertSiblingArtifact = (manifestPath, artifactPath, label) => {
  const manifestDirectory = dirname(resolve(manifestPath))
  const resolvedArtifact = resolve(artifactPath ?? '')
  if (dirname(resolvedArtifact) !== manifestDirectory || !existsSync(resolvedArtifact)) {
    fail(`${label} stapled archive is missing from its downloaded artifact directory`)
  }
  return resolvedArtifact
}

const extractPackage = (manifestPath, manifest, label, temporaryRoot) => {
  const archivePath = assertSiblingArtifact(
    manifestPath,
    manifest.stapledArchivePath,
    label,
  )
  if (sha256(readFileSync(archivePath)) !== manifest.stapledArchiveDigestSha256) {
    fail(`${label} stapled archive digest does not match its package manifest`)
  }

  const expansionRoot = join(temporaryRoot, label)
  mkdirSync(expansionRoot)
  const ditto = spawnSync('ditto', ['-x', '-k', archivePath, expansionRoot], { encoding: 'utf8' })
  if (ditto.error || ditto.status !== 0) fail(`${label} stapled archive could not be expanded`)

  const bundles = readdirSync(expansionRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.endsWith('.app'))
    .map((entry) => join(expansionRoot, entry.name))
  if (bundles.length !== 1) fail(`${label} archive must contain exactly one packaged app`)

  const applicationPath = bundles[0]
  const executablePath = join(applicationPath, 'Contents', 'MacOS', 'Keepling')
  if (!existsSync(executablePath)) fail(`${label} packaged executable is missing`)
  runQuiet('codesign', ['--verify', '--deep', '--strict', applicationPath], `${label} code-signature verification`)
  runQuiet('xcrun', ['stapler', 'validate', applicationPath], `${label} notarization-ticket validation`)
  runQuiet('spctl', ['--assess', '--type', 'execute', applicationPath], `${label} Gatekeeper assessment`)

  const codeSignFacts = runQuiet('codesign', ['-dv', '--verbose=4', applicationPath], `${label} code-signature inspection`)
  const actualCodeDirectoryHash = /^CDHash=([0-9a-f]+)$/im.exec(codeSignFacts)?.[1]
  if (actualCodeDirectoryHash?.toLowerCase() !== manifest.codeDirectoryHash.toLowerCase()) {
    fail(`${label} packaged code-directory hash differs from the manifest`)
  }

  const requirementFacts = runQuiet('codesign', ['-dr', '-', applicationPath], `${label} designated-requirement inspection`)
  const designatedRequirement = /^designated => (.+)$/m.exec(requirementFacts)?.[1]
  if (!designatedRequirement?.includes('identifier "dev.keepling.desktop"')) {
    fail(`${label} app does not carry Keepling's expected designated requirement`)
  }

  const normalizedManifestPath = join(temporaryRoot, `${label}-package-manifest.json`)
  writeFileSync(
    normalizedManifestPath,
    `${JSON.stringify({
      ...manifest,
      copiedApplicationPath: applicationPath,
      executablePath,
      stapledApplicationPath: applicationPath,
    }, null, 2)}\n`,
  )
  return { designatedRequirement, executablePath, manifestPath: normalizedManifestPath }
}

const temporaryRoot = mkdtempSync(join(tmpdir(), 'keepling-signed-upgrade-'))
try {
  const previousManifestPath = option('--previous-manifest')
  const currentManifestPath = option('--current-manifest')
  const previousRevision = process.env.PREVIOUS_SOURCE_REVISION ?? ''
  const currentRevision = process.env.CURRENT_SOURCE_REVISION ?? ''
  if (previousRevision === currentRevision) fail('upgrade evidence must cover two distinct source revisions')
  if (!/^[0-9a-f]{40}$/i.test(currentRevision)) fail('current GitHub Actions source revision is invalid')
  if (!/^[0-9a-f]{40}$/i.test(previousRevision)) fail('previous GitHub Actions source revision is invalid')

  const previousManifest = manifestJson(previousManifestPath, 'previous')
  const currentManifest = manifestJson(currentManifestPath, 'current')
  assertPackageState(previousManifest, 'previous', previousRevision)
  assertPackageState(currentManifest, 'current', currentRevision)

  const previous = extractPackage(previousManifestPath, previousManifest, 'previous', temporaryRoot)
  const current = extractPackage(currentManifestPath, currentManifest, 'current', temporaryRoot)
  if (previous.designatedRequirement !== current.designatedRequirement) {
    fail('the signed builds do not share a stable macOS designated requirement')
  }

  const profilePath = join(temporaryRoot, 'disposable-profile')
  const forbiddenProfile = resolve(homedir(), 'Library', 'Application Support', 'Keepling')
  const fromTemporaryRoot = relative(temporaryRoot, profilePath)
  if (
    resolve(profilePath) === forbiddenProfile
    || fromTemporaryRoot === '..'
    || fromTemporaryRoot.startsWith(`..${sep}`)
    || isAbsolute(fromTemporaryRoot)
  ) {
    fail('refusing to use Keepling’s normal user profile')
  }

  const result = spawnSync(
    'pnpm',
    [
      '--dir', desktopRoot,
      'exec', 'playwright', 'test',
      'test/packaged-upgrade/continuity.spec.ts',
      '--config', 'playwright.config.ts',
      '--project', 'packaged-upgrade',
    ],
    {
      cwd: repositoryRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        KEEPLING_FORBIDDEN_USER_DATA_DIR: forbiddenProfile,
        KEEPLING_PACKAGE_MANIFEST: current.manifestPath,
        KEEPLING_PREVIOUS_PACKAGE_MANIFEST: previous.manifestPath,
        KEEPLING_TEST_USER_DATA_DIR: profilePath,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  )
  process.stdout.write(result.stdout ?? '')
  process.stderr.write(result.stderr ?? '')
  if (result.error || result.status !== 0) fail('the packaged credential-continuity test failed')
  const passedCount = Number(/(\d+) passed/.exec(result.stdout ?? '')?.[1] ?? 0)
  const failedCount = Number(/(\d+) failed/.exec(result.stdout ?? '')?.[1] ?? 0)
  if (passedCount !== 1 || failedCount !== 0) {
    fail(`the packaged-upgrade suite did not report exactly one passing case (passed=${passedCount}, failed=${failedCount})`)
  }

  console.log(
    `KPL03_UPGRADE_CONTINUITY result=PASS cases=1 previous_revision=${previousRevision} current_revision=${currentRevision}`,
  )
} catch (error) {
  const message = error instanceof Error ? error.message : 'unknown failure'
  console.error(`KPL-03 signed packaged upgrade continuity failed: ${message}`)
  process.exitCode = 1
} finally {
  rmSync(temporaryRoot, { force: true, recursive: true })
}
