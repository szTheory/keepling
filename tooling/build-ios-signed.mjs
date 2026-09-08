#!/usr/bin/env node
/**
 * The development-signed device build, and the provenance record that
 * makes its evidence bindable (04-16-PLAN.md Task 2, D-18/D-19/D-21).
 *
 * ---------------------------------------------------------------------
 * WHY THERE IS NO REPRODUCIBILITY CHECK HERE -- read before "fixing" this
 * ---------------------------------------------------------------------
 * `tooling/verify-package-reproducibility.mjs` exists because the Electron
 * package genuinely SHOULD hash identically twice, and Plan 03-25 was right
 * to make it. Do not add its equivalent here, and do not treat the absence
 * of one as an oversight.
 *
 * A signed iOS artifact is inherently NOT byte-reproducible:
 *
 *   - the CMS (RFC 5652) code signature embeds a **signing timestamp**;
 *   - each signing operation draws a fresh **per-build nonce**;
 *   - `embedded.mobileprovision` is re-fetched/re-stamped by automatic
 *     provisioning, so its bytes move even when nothing in the app did.
 *
 * Two builds of byte-identical source therefore hash differently, always.
 * That is a property of Apple's signing format, not a defect in this
 * script, and no amount of hermetic input control removes it. D-21's answer
 * is to replace reproducibility with **attestation**: this script computes a
 * digest over the build's real source inputs, injects it into the app's
 * `Info.plist` as `KeeplingBuildDigest`, and
 * `tooling/ios-device/attestation.mjs` reads that value back OUT OF THE
 * RUNNING PROCESS on the phone and refuses the lane on mismatch. Identity is
 * proven by what the shipped process says about itself, not by a hash that
 * physically cannot be stable.
 *
 * The manifest still records an `appBundleAdvisorySha256` computed with
 * `_CodeSignature/` and `embedded.mobileprovision` EXCLUDED. It is named
 * "advisory" deliberately: it is stable across re-signings of the same
 * compiled output and is useful for spotting an unexpected code change, but
 * it is NOT an identity claim and nothing gates on it.
 *
 * ---------------------------------------------------------------------
 * INSTALL PATH: devicectl direct install, and nothing else (D-19)
 * ---------------------------------------------------------------------
 * TestFlight and the App Store are deferred to Phase 6. Upload plus
 * processing latency plus a 90-day build expiry buy this phase no
 * evidentiary value at all -- the claim under test is "the loop runs on
 * Jon's actual phone", and a direct install proves exactly that, sooner.
 * Do not add an App Store Connect upload, an `altool`/`notarytool`
 * invocation, or an `app-store`/`ad-hoc`/`enterprise` export method to this
 * script. `tooling/ios-lanes/device.mjs` asserts their absence.
 *
 * Usage:
 *   node tooling/build-ios-signed.mjs             # build, export, install, write manifest
 *   node tooling/build-ios-signed.mjs --no-install  # build and export only
 */
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

import { resolveDevice } from './ios-device/resolve-devices.mjs'

const repositoryRoot = resolve(import.meta.dirname, '..')
const iosRoot = join(repositoryRoot, 'apps', 'ios')
const artifactsRoot = join(repositoryRoot, '.artifacts', 'ios')
/**
 * The configuration this script archives. Named once, passed explicitly to
 * `xcodebuild`, and recorded in the manifest so the attestation can refuse
 * a build compiled from anything else.
 */
const ARCHIVE_CONFIGURATION = 'Release'

const archivePath = join(artifactsRoot, 'Keepling.xcarchive')
const exportPath = join(artifactsRoot, 'export')
const derivedDataPath = join(artifactsRoot, 'DerivedData')
export const manifestPath = join(artifactsRoot, 'build-manifest.json')

const fail = (message) => {
  console.error(`iOS signed build failed: ${message}`)
  process.exit(1)
}

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, { cwd: repositoryRoot, encoding: 'utf8', ...options })
  if (result.error) fail(`could not run \`${command}\`: ${result.error.message}`)
  return result
}

const runChecked = (label, command, args, options = {}) => {
  const result = run(command, args, options)
  if (result.status !== 0) {
    process.stderr.write(result.stdout ?? '')
    process.stderr.write(result.stderr ?? '')
    fail(`${label} exited ${result.status ?? 'without status'}`)
  }
  return result
}

/**
 * `--cached --others --exclude-standard`: tracked files PLUS untracked
 * files that are not gitignored. Restricting this to `--cached` would have
 * been a quiet correctness hole -- a source file added but not yet
 * committed would not move the digest, so two genuinely different builds
 * would attest to the same value and the read-back check would pass on a
 * build it should have refused.
 *
 * `--exclude-standard` is what keeps build output, DerivedData, and the
 * gitignored `Signing.local.xcconfig` out. That last one matters
 * specifically: the Apple Team ID must never become an input to a recorded
 * digest, and a plain filesystem walk would have swept it in.
 */
const gitLsFiles = (paths) => {
  const result = run('git', ['-C', repositoryRoot, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', ...paths])
  if (result.status !== 0) fail('`git ls-files` failed -- this must run inside the repository')
  return [...new Set(result.stdout.split('\0').filter(Boolean))].sort()
}

/** A content digest over the source files above, in a stable order. */
const digestOfTrackedPaths = (paths) => {
  const files = gitLsFiles(paths)
  if (files.length === 0) fail(`no tracked files under ${paths.join(', ')} -- the digest would be vacuous`)
  const digest = createHash('sha256')
  for (const relativePath of files) {
    digest.update(`${relativePath}\0`)
    // A tracked path deleted on disk still contributes its NAME, so the
    // deletion moves the digest rather than crashing the build.
    const absolute = join(repositoryRoot, relativePath)
    if (existsSync(absolute)) digest.update(readFileSync(absolute))
    digest.update('\0')
  }
  return digest.digest('hex')
}

const sha256OfFile = (path) => createHash('sha256').update(readFileSync(path)).digest('hex')

/**
 * The advisory bundle hash. Walks the exported `.app`, EXCLUDING the two
 * paths that move on every signing operation, so the value tracks compiled
 * output rather than signature freshness. Advisory only -- see the header.
 */
const advisoryBundleDigest = (appPath) => {
  const entries = []
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(directory, entry.name)
      const relativePath = relative(appPath, full)
      if (relativePath.startsWith('_CodeSignature') || relativePath === 'embedded.mobileprovision') continue
      if (entry.isDirectory()) walk(full)
      else if (entry.isFile()) entries.push(relativePath)
    }
  }
  walk(appPath)
  const digest = createHash('sha256')
  for (const relativePath of entries.sort()) {
    digest.update(`${relativePath}\0`)
    digest.update(readFileSync(join(appPath, relativePath)))
    digest.update('\0')
  }
  return digest.digest('hex')
}

const plistValue = (path, key) => {
  const result = run('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, path])
  return result.status === 0 ? result.stdout.trim() : null
}

/**
 * Reads the embedded provisioning profile out of the EXPORTED app -- the
 * profile that will actually ship to the phone, not whatever is cached in
 * `~/Library/MobileDevice`. `security cms -D` decodes the CMS envelope the
 * `.mobileprovision` is wrapped in.
 */
const readProvisioningProfile = (appPath) => {
  const profilePath = join(appPath, 'embedded.mobileprovision')
  if (!existsSync(profilePath)) fail('the exported app carries no embedded.mobileprovision -- it is not device-signed')
  const decodedPath = join(artifactsRoot, 'embedded.provision.plist')
  const decoded = run('security', ['cms', '-D', '-i', profilePath])
  if (decoded.status !== 0) fail('could not decode the embedded provisioning profile')
  writeFileSync(decodedPath, decoded.stdout)
  const devices = run('/usr/libexec/PlistBuddy', ['-c', 'Print :ProvisionedDevices', decodedPath])
  return {
    creationDate: plistValue(decodedPath, 'CreationDate'),
    expirationDate: plistValue(decodedPath, 'ExpirationDate'),
    name: plistValue(decodedPath, 'Name'),
    provisionedDevices: devices.status === 0 ? devices.stdout : '',
    teamIdentifier: plistValue(decodedPath, 'TeamIdentifier:0'),
    uuid: plistValue(decodedPath, 'UUID'),
  }
}

/**
 * The signing identity's SHA-1 fingerprint. `codesign -dvvv` reports the
 * authority's COMMON NAME; the fingerprint is what uniquely identifies the
 * certificate, so the name is looked up against the keychain's own listing
 * rather than recorded as-is.
 *
 * T-04-16-07 (accepted, low): recording the fingerprint and the profile
 * UUID is deliberate. They are identity metadata, not credentials -- both
 * are already embedded in any copy of the shipped app -- and recording them
 * is precisely what makes a piece of evidence bindable to a build. The
 * Team ID is a different matter and is handled below.
 */
const signingIdentity = (appPath) => {
  const result = run('codesign', ['-dvvv', appPath])
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`
  const authority = output.match(/Authority=(Apple Development: [^\n]+)/)
  if (!authority) fail('the exported app is not signed by an Apple Development identity')
  const name = authority[1].trim()
  const identities = run('security', ['find-identity', '-v', '-p', 'codesigning']).stdout ?? ''
  const line = identities.split('\n').find((entry) => entry.includes(name))
  const fingerprint = line?.trim().match(/^\d+\)\s+([0-9A-F]{40})/)?.[1]
  if (!fingerprint) fail(`no keychain codesigning identity matches the app's authority ${JSON.stringify(name)}`)
  return { fingerprint, name }
}

const developmentTeam = () => {
  const result = run('xcodebuild', [
    '-showBuildSettings', '-project', join(iosRoot, 'Keepling.xcodeproj'), '-scheme', 'Keepling',
  ], { cwd: iosRoot })
  const match = (result.stdout ?? '').match(/\bDEVELOPMENT_TEAM = (\S+)/)
  if (!match) {
    fail(
      'no DEVELOPMENT_TEAM is configured. Create the gitignored apps/ios/Signing.local.xcconfig from ' +
        'Signing.local.xcconfig.example and re-run `xcodegen generate --spec project.yml --project .` ' +
        'from apps/ios. The Team ID lives ONLY in that gitignored file -- never in a committed one.',
    )
  }
  return match[1]
}

const main = () => {
  const device = resolveDevice()
  const teamId = developmentTeam()

  rmSync(archivePath, { force: true, recursive: true })
  rmSync(exportPath, { force: true, recursive: true })
  mkdirSync(artifactsRoot, { recursive: true })

  const keeplingBuildDigest = digestOfTrackedPaths(['apps/ios']).slice(0, 32)
  const laneSourceDigest = digestOfTrackedPaths([
    'tooling/build-ios-signed.mjs',
    'tooling/ios-device',
    'tooling/ios-lanes/device.mjs',
    'tooling/verify-real-stack-ios.mjs',
  ]).slice(0, 32)

  console.log(`IOS_BUILD digest=${keeplingBuildDigest} lane_source_digest=${laneSourceDigest} team_configured=true`)

  // `Keepling.xcodeproj` is gitignored and generated -- never hand-edited --
  // and XcodeGen enumerates sources at GENERATION time, not at build time.
  // A project regenerated before a source file was added compiles a stale
  // file list and fails with "has no member" errors that read like a Swift
  // bug rather than a stale project (measured during this plan's own
  // execution: `BuildAttestation.swift` existed on disk, was absent from
  // the compile list, and `buildAttestationProbe()` "did not exist").
  // Regenerating here also re-reads Signing.xcconfig, so a newly created
  // gitignored Signing.local.xcconfig takes effect without a separate step.
  runChecked('xcodegen generate', 'xcodegen', ['generate', '--spec', 'project.yml', '--project', '.'], {
    cwd: iosRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  // `-allowProvisioningUpdates` (D-18) is what makes profile management
  // unattended: without it, automatic signing cannot register a device or
  // refresh a profile from a non-interactive process and fails with a
  // "requires a development team"/"no profiles found" error that looks
  // like misconfiguration rather than a missing flag.
  runChecked('xcodebuild archive', 'xcodebuild', [
    'archive',
    '-project', 'Keepling.xcodeproj',
    '-scheme', 'Keepling',
    // EXPLICIT, not inherited from the scheme's ArchiveAction
    // (04-18-PLAN.md Task 6). Implicit configuration selection is the root
    // of a whole class of defect here: this step took Release from
    // ArchiveAction while the device lane's `xcodebuild test` took Debug
    // from TestAction, and because the digest hashes source content rather
    // than bytes, nothing could tell the two builds apart. "Which
    // configuration does this command build?" must never again be a
    // question answered by reading a scheme file.
    '-configuration', ARCHIVE_CONFIGURATION,
    '-destination', 'generic/platform=iOS',
    '-archivePath', archivePath,
    '-derivedDataPath', derivedDataPath,
    '-allowProvisioningUpdates',
    // The injection point. Overriding the build setting (rather than
    // rewriting Info.plist after the fact) means the value is baked in
    // BEFORE signing, so it is covered by the signature it attests to --
    // a post-signing plist edit would invalidate the signature and, worse,
    // would be a value anyone could change without rebuilding.
    `KEEPLING_BUILD_DIGEST=${keeplingBuildDigest}`,
  ], { cwd: iosRoot, stdio: ['ignore', 'pipe', 'pipe'] })

  // Generated at build time, never committed: it carries the Team ID, and
  // `.artifacts/` is gitignored. This is the same reason
  // `Signing.local.xcconfig` is gitignored -- the Team ID is a stable link
  // between this repository and one Apple account, and scrubbing it out of
  // git history later would mean rewriting history.
  const exportOptionsPath = join(artifactsRoot, 'ExportOptions.plist')
  writeFileSync(
    exportOptionsPath,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>${teamId}</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
`,
  )

  runChecked('xcodebuild -exportArchive', 'xcodebuild', [
    '-exportArchive',
    '-archivePath', archivePath,
    '-exportPath', exportPath,
    '-exportOptionsPlist', exportOptionsPath,
    '-allowProvisioningUpdates',
  ], { cwd: iosRoot, stdio: ['ignore', 'pipe', 'pipe'] })

  const ipaPath = join(exportPath, 'Keepling.ipa')
  if (!existsSync(ipaPath)) fail('the export produced no Keepling.ipa')

  const appPath = join(archivePath, 'Products', 'Applications', 'Keepling.app')
  if (!existsSync(appPath)) fail('the archive contains no Keepling.app')

  const infoPlist = join(appPath, 'Info.plist')
  const installedDigest = plistValue(infoPlist, 'KeeplingBuildDigest')
  if (installedDigest !== keeplingBuildDigest) {
    fail(
      `the built app carries KeeplingBuildDigest=${installedDigest} but this run computed ` +
        `${keeplingBuildDigest} -- the injection did not take effect, so nothing downstream could be bound to it`,
    )
  }

  const profile = readProvisioningProfile(appPath)
  const identity = signingIdentity(appPath)

  if (!profile.provisionedDevices.includes(device.hardwareUdid)) {
    fail(
      `the embedded provisioning profile does not list this phone's hardware UDID (${device.hardwareUdid}). ` +
        'Register the device in the developer account, or re-run with -allowProvisioningUpdates so automatic ' +
        'signing can add it.',
    )
  }

  // D-17, made checkable rather than asserted. A FREE personal-team profile
  // expires SEVEN DAYS after creation and hard-stops the installed app --
  // exactly the recurring manual step this project forbids, failing
  // precisely when a week away from the build Mac makes mobile capture
  // matter most. A paid Apple Developer Program profile runs a year. The
  // profile's own expiry window is therefore direct machine evidence of
  // which kind of membership signed this build; the lane does not take
  // anyone's word for it.
  const created = Date.parse(profile.creationDate ?? '')
  const expires = Date.parse(profile.expirationDate ?? '')
  const profileValidityDays = Number.isFinite(created) && Number.isFinite(expires)
    ? Math.round((expires - created) / 86_400_000)
    : null
  if (profileValidityDays === null) fail('could not read the provisioning profile validity window')
  if (profileValidityDays <= 30) {
    fail(
      `the embedded provisioning profile is valid for only ${profileValidityDays} days, which is a FREE ` +
        'personal-team profile. D-17 refuses it: a seven-day profile hard-stops the installed app and ' +
        'reintroduces the weekly-reinstall manual step this phase exists to remove. An active paid Apple ' +
        'Developer Program membership is required.',
    )
  }

  const xcodeVersionOutput = runChecked('xcodebuild -version', 'xcodebuild', ['-version']).stdout.trim()
  const sdkVersion = runChecked('xcodebuild -version -sdk iphoneos', 'xcodebuild', [
    '-version', '-sdk', 'iphoneos', 'SDKVersion',
  ]).stdout.trim()

  const manifest = {
    appBundleAdvisorySha256: advisoryBundleDigest(appPath),
    appBundleAdvisoryNote:
      'ADVISORY ONLY. Excludes _CodeSignature/ and embedded.mobileprovision. iOS artifacts are not ' +
      'byte-reproducible (CMS signature timestamp + per-build nonce); identity is proven by read-back ' +
      'attestation of keeplingBuildDigest, never by this hash (D-21).',
    archivePath: relative(repositoryRoot, ipaPath),
    archiveSha256: sha256OfFile(ipaPath),
    builtAt: new Date().toISOString(),
    cfBundleVersion: plistValue(infoPlist, 'CFBundleVersion'),
    // Recorded so `attestation.mjs --expect-installed` can refuse a running
    // build compiled from a different configuration than the one archived.
    configuration: ARCHIVE_CONFIGURATION,
    cfBundleShortVersionString: plistValue(infoPlist, 'CFBundleShortVersionString'),
    device: {
      devicectlIdentifier: device.devicectlIdentifier,
      hardwareUdid: device.hardwareUdid,
      marketingName: device.marketingName,
      osVersion: device.osVersion,
      passcodeRequired: device.lockState.passcodeRequired,
    },
    gitRevision: runChecked('git rev-parse HEAD', 'git', ['-C', repositoryRoot, 'rev-parse', 'HEAD']).stdout.trim(),
    installMethod: 'devicectl-direct-install',
    keeplingBuildDigest,
    laneSourceDigest,
    provisioningProfileName: profile.name,
    provisioningProfileUUID: profile.uuid,
    provisioningProfileValidityDays: profileValidityDays,
    sdkVersion,
    signingIdentityFingerprint: identity.fingerprint,
    signingIdentityName: identity.name,
    xcodeVersion: xcodeVersionOutput.replace(/\s+/g, ' '),
  }

  // The Team ID is recorded NOWHERE in this manifest, and the manifest is
  // itself under gitignored `.artifacts/`. The profile UUID and the
  // signing fingerprint are what bind evidence to a build; the Team ID
  // adds nothing to that and is the one value the committed/gitignored
  // split exists to keep out of the repository.
  if (JSON.stringify(manifest).includes(teamId)) {
    fail('the build manifest would record the Apple Team ID -- refusing to write it')
  }

  if (!process.argv.includes('--no-install')) {
    console.log(`IOS_BUILD installing onto ${device.marketingName} (devicectl ${device.devicectlIdentifier})`)
    runChecked('devicectl install', 'xcrun', [
      'devicectl', 'device', 'install', 'app', '--device', device.devicectlIdentifier, ipaPath,
    ], { stdio: ['ignore', 'pipe', 'pipe'] })
    manifest.installedAt = new Date().toISOString()
  } else {
    manifest.installedAt = null
  }

  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)

  console.log(
    `IOS_BUILD_MANIFEST digest=${manifest.keeplingBuildDigest} profile_uuid=${manifest.provisioningProfileUUID} ` +
      `profile_validity_days=${manifest.provisioningProfileValidityDays} ` +
      `identity=${manifest.signingIdentityFingerprint} archive_sha256=${manifest.archiveSha256.slice(0, 16)} ` +
      `installed=${manifest.installedAt !== null}`,
  )
  console.log(`IOS_BUILD wrote ${relative(repositoryRoot, manifestPath)} (${statSync(manifestPath).size} bytes)`)
}

if (import.meta.url === `file://${process.argv[1]}`) main()
