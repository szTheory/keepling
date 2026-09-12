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
 *
 * O-40 / T-06-02-01 (06-02 Task 3): `applicationDigestSha256` is correct and
 * caught a real transport defect -- `actions/upload-artifact`'s own zip of
 * a raw `.app` directory tree does not reliably preserve POSIX mode bits
 * and symlinks across the upload/download round trip, so a digest computed
 * before upload can legitimately disagree with the same digest computed
 * after download even though nothing about the *application* changed. The
 * fix is the pipe, never the binding: this script also produces a `ditto
 * -c -k --sequesterRsrc --keepParent` archive of the copied application and
 * records its own `archiveDigestSha256` alongside `applicationDigestSha256`.
 * `ditto` is Apple's own archiver and is mode/resource-fork-aware by
 * design; `tooling/smoke-desktop-packaged.mjs` expands that archive with
 * `ditto -x -k` and re-verifies the expanded tree against
 * `applicationDigestSha256` in addition to the archive's own digest, so a
 * transport that still loses bytes is caught at the consuming end.
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
  /**
   * D-17(b)/T-06-10-01 (06-10 Task 2): gate the SHIPPED STAPLED artifact on
   * the identity that survives stapling.
   *
   * `applicationDigestSha256` cannot do this job. Stapling mutates the
   * bundle irreducibly, so the directory digest of the shipped file provably
   * differs from the one every gate tested -- and chasing that stability is
   * the trap, not the fix. The code directory hash is invariant across
   * stapling, so it is what the shipped bytes are held to here.
   *
   * Fail-closed: a manifest that claims a Developer ID signature but offers
   * no reachable stapled artifact to check is REFUSED, not waved through.
   */
  if (manifest.codeSigning && manifest.codeSigning.developerIdSigned === true) {
    if (typeof manifest.codeDirectoryHash !== 'string' || manifest.codeDirectoryHash.length === 0) {
      fail('promotion manifest claims a Developer ID signature but is missing required field "codeDirectoryHash"')
    }

    let shippedBundlePath = null
    if (typeof manifest.stapledApplicationPath === 'string' && existsSync(manifest.stapledApplicationPath)) {
      shippedBundlePath = manifest.stapledApplicationPath
    } else if (typeof manifest.stapledArchivePath === 'string' && existsSync(manifest.stapledArchivePath)) {
      const expandedRoot = mkdtempSync(join(tmpdir(), 'keepling-promote-staple-'))
      const expanded = spawnSync('ditto', ['-x', '-k', manifest.stapledArchivePath, expandedRoot], { encoding: 'utf8' })
      if (expanded.error || expanded.status !== 0) {
        fail(`the stapled archive could not be expanded for the code directory hash gate: ${expanded.stderr?.trim() ?? 'unknown error'}`)
      }
      const bundles = readdirSync(expandedRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory() && entry.name.endsWith('.app'))
        .map((entry) => join(expandedRoot, entry.name))
      if (bundles.length !== 1) fail(`expected exactly one application bundle inside the stapled archive, found ${bundles.length}`)
      shippedBundlePath = bundles[0]
    }

    if (!shippedBundlePath) {
      fail('promotion manifest claims a Developer ID signature but names no reachable stapled artifact to check the code directory hash against')
    }

    const inspected = spawnSync('codesign', ['-dvvv', shippedBundlePath], { encoding: 'utf8' })
    const report = `${inspected.stdout ?? ''}${inspected.stderr ?? ''}`
    const shippedCodeDirectoryHash = /^CDHash=([0-9a-f]+)$/m.exec(report)?.[1] ?? null
    if (inspected.status !== 0 || shippedCodeDirectoryHash === null) {
      fail(`the shipped artifact at ${shippedBundlePath} reported no code directory hash, so it cannot be gated`)
    }
    if (shippedCodeDirectoryHash !== manifest.codeDirectoryHash) {
      fail(`the shipped stapled artifact's code directory hash ${shippedCodeDirectoryHash} does not match the tested ${manifest.codeDirectoryHash}`)
    }
    console.log(`Shipped stapled artifact gated: codeDirectoryHash=${shippedCodeDirectoryHash}`)
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

/**
 * This script -- not `forge.config.ts` -- is the single decider of whether
 * this build is signed, and it is deliberately the place that can FAIL.
 *
 * @electron/packager hardcodes `continueOnError: true` when it hands the
 * bundle to @electron/osx-sign, so a signing failure inside the packager step
 * produces a green build and a silently unsigned application. That is exactly
 * the vacuous green this project has been burned by. Resolving the identity
 * here, handing it to the packager through the environment, and then
 * asserting afterwards that the bundle really carries a Developer ID
 * signature turns that swallowed error back into a loud one.
 *
 * The identity is the certificate's SHA-1 fingerprint, never its common name:
 * the name embeds a legal name and a team id, and this repository is headed
 * for a public release. `security find-identity` only LISTS identities; no
 * whole-keychain verb (which would decrypt every unrelated identity present)
 * is ever used.
 */
const resolveSigningIdentity = () => {
  if (process.platform !== 'darwin') return null
  if (process.env.KEEPLING_MACOS_SKIP_SIGNING === '1') return null
  const override = process.env.KEEPLING_MACOS_SIGNING_IDENTITY
  if (override && override.length > 0) return override
  const listed = spawnSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' })
  if (listed.status !== 0 || typeof listed.stdout !== 'string') return null
  const fingerprints = listed.stdout
    .split('\n')
    .map((line) => /^\s*\d+\)\s+([0-9A-F]{40})\s+"Developer ID Application:/.exec(line))
    .filter((match) => match !== null)
    .map((match) => match[1])
  if (fingerprints.length !== 1) return null
  return fingerprints[0]
}

const signingIdentity = resolveSigningIdentity()
console.log(`Desktop package signing: ${signingIdentity ? 'Developer ID identity resolved' : 'no Developer ID identity -- this build will be UNSIGNED'}`)

run('pnpm', ['run', 'build'])
run('pnpm', ['exec', 'electron-forge', 'make', '--platform', 'darwin', '--arch', architecture], {
  env: { ...process.env, KEEPLING_MACOS_SIGNING_IDENTITY: signingIdentity ?? '' },
})

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

// T-06-02-01: produce the lossless transport archive from the SAME copied
// application whose directory digest was just verified, so
// `archiveDigestSha256` is bound to bytes already known to match
// `applicationDigestSha256` before it ever leaves this machine.
const archivePath = join(artifactRoot, `${executableName}.ditto.zip`)
run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', copiedApplicationPath, archivePath])
const archiveDigestSha256 = hashFile(archivePath)

/**
 * D-16/D-17 (06-10 Task 2): sign -> digest -> archive -> notarize -> staple
 * -> record the surviving identity.
 *
 * Steps 1-4 are already done by the time control reaches here: `osxSign` in
 * `forge.config.ts` signed the bundle INSIDE the packager step, so
 * `applicationDigestSha256` above describes the SIGNED bytes, and
 * `archiveDigestSha256` describes a lossless archive of those same bytes.
 * Steps 5-8 follow.
 *
 * Two bindings, deliberately kept apart, because they describe different
 * bytes on purpose:
 *
 *   applicationDigestSha256  pre-staple, step 3 -- what every gate tested
 *   codeDirectoryHash        the code directory hash -- the ONLY identity
 *                            that survives stapling, and therefore what a
 *                            launch-time check on the shipped file shows
 *
 * `xcrun stapler staple` mutates the bundle irreducibly, by design. This
 * code never re-hashes the directory after stapling and records the result
 * under `applicationDigestSha256`, and never chases directory-hash stability
 * across stapling -- that chase ends in a loosened binding, and the binding
 * it would loosen is the one that already caught a real artifact-transport
 * defect (T-06-02-01). The stapled artifact is gated on CDHash equality
 * instead, in `--promote` above.
 */
const collectCodesignFacts = (bundlePath) => {
  // `codesign -dvvv` writes its report to stderr. A non-zero status means
  // the bundle carries no signature at all.
  const result = spawnSync('codesign', ['-dvvv', bundlePath], { cwd: desktopRoot, encoding: 'utf8' })
  const report = `${result.stdout ?? ''}${result.stderr ?? ''}`
  if (result.status !== 0) return { signed: false, developerIdSigned: false, hardenedRuntime: false, codeDirectoryHash: null }
  const codeDirectoryHash = /^CDHash=([0-9a-f]+)$/m.exec(report)?.[1] ?? null
  return {
    signed: codeDirectoryHash !== null,
    // Only the BOOLEAN is kept. The authority line embeds a legal name and a
    // team id; this manifest is uploaded as a CI artifact and must never
    // carry either.
    developerIdSigned: /^Authority=Developer ID Application: /m.test(report),
    hardenedRuntime: /^CodeDirectory .*\bruntime\b/m.test(report),
    codeDirectoryHash,
  }
}

const signedFacts = collectCodesignFacts(applicationPath)
const codeDirectoryHash = signedFacts.codeDirectoryHash
// The loud half of the `continueOnError: true` workaround described above: an
// identity was resolvable, so a bundle that came back merely ad-hoc signed
// means the packager swallowed a signing failure.
if (signingIdentity && !signedFacts.developerIdSigned) {
  fail('a Developer ID identity was resolved but the packaged bundle is not Developer ID signed -- @electron/packager swallowed the signing failure (it hardcodes continueOnError)')
}
if (signedFacts.developerIdSigned && !signedFacts.hardenedRuntime) {
  fail('the bundle is Developer ID signed without the hardened runtime, which notarization rejects')
}
if (signedFacts.developerIdSigned && codeDirectoryHash === null) {
  fail('the signed bundle reported no code directory hash, so the identity that survives stapling cannot be recorded')
}

/**
 * Notarization is OPT-IN per invocation (`KEEPLING_MACOS_NOTARIZE=1`) because
 * a submission round trip to Apple takes minutes and every local
 * `pnpm package:desktop` would otherwise pay it. The manifest records what
 * actually happened either way -- `notarization.status` is `not-attempted`
 * when it was skipped, never an optimistic default. Nothing downstream may
 * read a signed-but-unnotarized build as notarized.
 */
const notarization = { attempted: false, status: 'not-attempted', stapled: false, submissionId: null }
let stapledApplicationPath = null
let stapledArchivePath = null
let stapledArchiveDigestSha256 = null

if (process.env.KEEPLING_MACOS_NOTARIZE === '1') {
  if (!signedFacts.developerIdSigned) {
    fail('notarization was requested but the bundle is not Developer ID signed; Apple rejects anything else')
  }
  // Credentials are read from the environment or from a stored keychain
  // profile and are NEVER echoed, recorded, or written to the manifest.
  const keychainProfile = process.env.KEEPLING_NOTARY_KEYCHAIN_PROFILE
  const credentialArguments = keychainProfile
    ? ['--keychain-profile', keychainProfile]
    : ['--apple-id', process.env.APPLE_ID ?? '', '--password', process.env.APPLE_APP_SPECIFIC_PASSWORD ?? '', '--team-id', process.env.APPLE_TEAM_ID ?? '']
  if (!keychainProfile && credentialArguments.some((value) => value === '')) {
    fail('notarization was requested without a keychain profile and without the three Apple credential environment variables')
  }

  notarization.attempted = true
  // Step 5: the ARCHIVE is what is submitted. Notarization mutates nothing
  // in the bundle; stapling (step 6) does.
  //
  // This deliberately does NOT go through `run`: that helper echoes the full
  // argument vector in its failure message, which would print the
  // app-specific password into the build log on any submission error.
  const submitted = spawnSync(
    'xcrun',
    ['notarytool', 'submit', archivePath, ...credentialArguments, '--wait', '--output-format', 'json'],
    { cwd: desktopRoot, encoding: 'utf8' },
  )
  if (submitted.error || submitted.status !== 0) {
    fail(`xcrun notarytool submit exited ${submitted.status ?? 'without status'}${submitted.stderr ? `: ${submitted.stderr.trim()}` : ''}`)
  }
  let submissionRecord
  try {
    submissionRecord = JSON.parse(submitted.stdout ?? '')
  } catch {
    fail('the notarization submission did not return parseable JSON')
  }
  notarization.status = submissionRecord.status ?? 'unknown'
  notarization.submissionId = submissionRecord.id ?? null
  if (notarization.status !== 'Accepted') {
    fail(`notarization returned status "${notarization.status}" (submission ${notarization.submissionId}); run \`xcrun notarytool log ${notarization.submissionId}\` for the reason`)
  }

  // Step 6: staple onto the BUILT bundle. The copied bundle under the
  // artifact root is deliberately left un-stapled: its digest is what
  // `--reuse-if-unchanged` re-hashes and what the transport archive was
  // made from, and mutating it would break both bindings.
  run('xcrun', ['stapler', 'staple', applicationPath])
  notarization.stapled = true
  stapledApplicationPath = applicationPath

  // Step 7: re-read the code directory hash from the STAPLED bundle and
  // prove it equals the pre-staple one. This is the claim -- "the code
  // directory hash is the identity that survives stapling" -- measured
  // rather than asserted, on every run.
  const stapledFacts = collectCodesignFacts(applicationPath)
  if (stapledFacts.codeDirectoryHash !== codeDirectoryHash) {
    fail(`the code directory hash changed across stapling (${codeDirectoryHash} -> ${stapledFacts.codeDirectoryHash}); the surviving-identity binding does not hold`)
  }

  // The shipped artifact. `ditto` of the already-notarized bundle re-packages
  // NOTHING -- it does not re-run the packager, re-sign, or alter a byte of
  // the bundle; it is the same lossless transport used for the tested
  // archive, applied to the stapled tree so a downloader receives a ticket
  // that works offline. Its digest is recorded separately and is NOT
  // interchangeable with `archiveDigestSha256`.
  stapledArchivePath = join(artifactRoot, `${executableName}.stapled.ditto.zip`)
  run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', applicationPath, stapledArchivePath])
  stapledArchiveDigestSha256 = hashFile(stapledArchivePath)
}

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
  archiveDigestSha256,
  archivePath,
  architecture,
  // D-17(b): the identity that survives stapling, recorded as a field
  // DISTINCT from `applicationDigestSha256`. The two describe different
  // bytes, on purpose.
  codeDirectoryHash,
  codeSigning: {
    // Only booleans and a kind. Never the certificate common name, which
    // embeds a legal name and a team id.
    signed: signedFacts.signed,
    developerIdSigned: signedFacts.developerIdSigned,
    hardenedRuntime: signedFacts.hardenedRuntime,
  },
  copiedApplicationPath,
  createdAt: new Date().toISOString(),
  embeddedVersions,
  executableDigestSha256: hashFile(executablePath),
  executablePath,
  inputDigestSha256,
  notarization,
  platform: 'darwin',
  schemaVersion: 2,
  sourceRevision,
  stapledApplicationPath,
  stapledArchiveDigestSha256,
  stapledArchivePath,
  trackedInputs,
  zipDigestSha256: hashFile(zipPath),
  zipPath,
}
const manifestPath = join(artifactRoot, 'package-manifest.json')
mkdirSync(artifactRoot, { recursive: true })
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' })
writeFileSync(locatorPath, `${manifestPath}\n`, { encoding: 'utf8' })

// A stable, well-known copy of the same manifest, so a gate can name the
// artifact without first scraping a tmpdir path out of this script's stdout.
// `apps/desktop/out/` is gitignored build output; the authoritative copy
// remains the one under the artifact root, and this one is never promoted.
writeFileSync(join(outRoot, 'keepling-package-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, { encoding: 'utf8' })

console.log(`Desktop package manifest: ${manifestPath}`)
