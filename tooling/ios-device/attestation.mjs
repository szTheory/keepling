#!/usr/bin/env node
/**
 * The refusal gate (04-16-PLAN.md Task 2/3, D-21, T-04-16-01).
 *
 * Launches the installed app on the phone, reads `KeeplingBuildDigest`
 * back OUT OF THE RUNNING PROCESS, and compares it with the digest in
 * `.artifacts/ios/build-manifest.json`. On mismatch it exits non-zero and
 * the device lane never runs a test.
 *
 * Refusal-on-mismatch is the entire point. Without it, a device lane's
 * "PASS" means "some build of this app passed at some time" -- which is a
 * claim about nothing. `tooling/ios-lanes/device.mjs` calls this FIRST,
 * before any test executes: a lane that runs its suite and then checks
 * identity has already spent the evidence it was supposed to be
 * protecting.
 *
 * The read is from the PROCESS, not from the installed bundle on disk. Two
 * independent channels, because each fails differently:
 *
 *   1. `devicectl device process launch --console` captures the app's own
 *      stdout, where `BuildAttestation.emit()` writes the value at launch.
 *      A stale bundle cannot answer for a process it is not running.
 *   2. `devicectl device copy from` pulls the receipt the same launch wrote
 *      into the app's container. This one does not depend on console
 *      capture timing, and it proves the running process could actually
 *      write to its own protected container.
 *
 * Channel 1 is required. Channel 2 is corroborating: when it is readable it
 * must AGREE, and a disagreement between the two is itself a refusal.
 *
 * Usage:
 *   node tooling/ios-device/attestation.mjs --expect-installed
 *   node tooling/ios-device/attestation.mjs --expect-digest <value>
 *   node tooling/ios-device/attestation.mjs --json
 */
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

import { resolveDevice } from './resolve-devices.mjs'

const repositoryRoot = resolve(import.meta.dirname, '..', '..')
const manifestPath = join(repositoryRoot, '.artifacts', 'ios', 'build-manifest.json')
const BUNDLE_ID = 'com.szTheory.keepling'
const CONSOLE_PREFIX = 'KEEPLING_BUILD_ATTESTATION'
const RECEIPT_FILENAME = 'build-attestation.json'

const refuse = (message) => {
  console.error(`ATTESTATION REFUSED: ${message}`)
  process.exit(1)
}

const readManifest = () => {
  if (!existsSync(manifestPath)) {
    refuse(
      'no .artifacts/ios/build-manifest.json exists. Run `node tooling/build-ios-signed.mjs` first -- ' +
        'there is nothing to attest against, and a lane with nothing to compare to must never pass.',
    )
  }
  try {
    return JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    refuse(`the build manifest is unreadable: ${error instanceof Error ? error.message : String(error)}`)
  }
}

/**
 * Launches the app attached to the console and reads the attestation line.
 *
 * `--console` blocks until the app exits, and this app does not exit on its
 * own, so the launch is killed once the line has been seen (or once the
 * timeout expires). A timeout is a refusal, never a pass: an app that never
 * printed its digest is indistinguishable from one that has none.
 */
const launchOnce = (devicectlIdentifier, timeoutMs) => {
  const result = spawnSync(
    'xcrun',
    [
      'devicectl', 'device', 'process', 'launch',
      '--device', devicectlIdentifier,
      '--console',
      '--terminate-existing',
      BUNDLE_ID,
    ],
    { encoding: 'utf8', timeout: timeoutMs, killSignal: 'SIGKILL' },
  )
  return `${result.stdout ?? ''}\n${result.stderr ?? ''}`
}

/**
 * A wirelessly-paired iPhone's CoreDevice tunnel drops occasionally --
 * "The device disconnected immediately after connecting"
 * (`com.apple.dt.CoreDeviceError error 4000`), observed on this exact
 * device during this plan's execution. That is a transport flake, not
 * evidence about the build.
 *
 * The retry is deliberately narrow: it fires ONLY when no attestation line
 * was seen AND the output names a transport failure. A digest that was read
 * and did not MATCH is never retried -- retrying a mismatch until it
 * happened to pass would defeat the entire refusal.
 */
const TRANSPORT_FLAKE = /disconnected immediately after connecting|CoreDeviceError error 4000|Could not acquire tunnel|connection was interrupted/i

/**
 * iOS refuses to launch ANY app on a locked device
 * (`FBSOpenApplicationErrorDomain error 7`, "Unable to launch ... because
 * the device was not, or could not be, unlocked"). Unlocking needs the
 * passcode, which no tool can supply.
 *
 * Without this check the symptom surfaces as "the running process never
 * reported a build digest", which reads like a broken build and sends a
 * reader hunting through `BuildAttestation.swift` for a bug that is not
 * there. It is named separately because it is the one condition in this
 * lane whose remedy is "unlock the phone", not "fix something".
 */
const DEVICE_LOCKED = /could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i

const readDigestFromRunningProcess = (devicectlIdentifier, timeoutMs) => {
  let output = ''
  let match = null
  for (let attempt = 0; attempt < 3; attempt += 1) {
    output = launchOnce(devicectlIdentifier, timeoutMs)
    match = output.match(new RegExp(`${CONSOLE_PREFIX} digest=(\\S+) bundle=(\\S+) short_version=(\\S+) build_version=(\\S+)`))
    if (match) break
    if (DEVICE_LOCKED.test(output)) {
      refuse(
        'BLOCKED: the iPhone is LOCKED. iOS refuses to launch any app on a locked device, so the running ' +
          'process cannot be asked what build it is. Unlock the phone (the passcode is the one thing no tool ' +
          'here can supply) and re-run. This is not a build defect and not an attestation mismatch -- no ' +
          'digest was read at all. Note that `devicectl device info lockState` reports only ' +
          '`passcodeRequired`/`unlockedSinceBoot`; it does not report the CURRENT lock state, which is why ' +
          'this is detected from the launch refusal itself.',
      )
    }
    if (!TRANSPORT_FLAKE.test(output)) break
    console.error(`attestation: CoreDevice transport flake on attempt ${attempt + 1}, retrying`)
    spawnSync('sleep', ['5'])
  }
  if (!match) {
    refuse(
      'the running process never reported a build digest on the console. Either the app is not installed, ' +
        'or it did not launch, or this build predates BuildAttestation.emit(). Console tail:\n' +
        output.trim().slice(-2000),
    )
  }
  if (match[1] === 'absent') {
    refuse('the running process reports KeeplingBuildDigest=absent -- the Info.plist key was never populated')
  }
  return { buildVersion: match[4], bundleIdentifier: match[2], digest: match[1], shortVersion: match[3] }
}

/**
 * Channel 2. Pulls the receipt the launch above wrote into the app's own
 * Documents container. A `devicectl device copy from` failure is reported,
 * not fatal -- the container is only reachable for a development-signed
 * app and the channel is corroborating by design -- but a receipt that
 * DISAGREES with the console is always a refusal.
 */
const readReceiptFromDeviceContainer = (devicectlIdentifier) => {
  const scratch = mkdtempSync(join(tmpdir(), 'keepling-attestation-'))
  const destination = join(scratch, RECEIPT_FILENAME)
  try {
    const result = spawnSync(
      'xcrun',
      [
        'devicectl', 'device', 'copy', 'from',
        '--device', devicectlIdentifier,
        '--domain-type', 'appDataContainer',
        '--domain-identifier', BUNDLE_ID,
        '--source', `Documents/${RECEIPT_FILENAME}`,
        '--destination', destination,
        '--quiet',
      ],
      { encoding: 'utf8', timeout: 90_000 },
    )
    if (result.status !== 0 || !existsSync(destination)) {
      return { available: false, digest: null, reason: (result.stderr ?? '').trim().slice(-400) || 'copy failed' }
    }
    const parsed = JSON.parse(readFileSync(destination, 'utf8'))
    return { available: true, digest: parsed.keeplingBuildDigest ?? null, observedAt: parsed.observedAt ?? null, reason: null }
  } catch (error) {
    return { available: false, digest: null, reason: error instanceof Error ? error.message : String(error) }
  } finally {
    rmSync(scratch, { force: true, recursive: true })
  }
}

const attest = ({ expectedDigest, timeoutMs = 120_000 } = {}) => {
  const device = resolveDevice()
  const manifest = expectedDigest ? null : readManifest()
  const expected = expectedDigest ?? manifest?.keeplingBuildDigest
  if (!expected) refuse('no expected digest -- the manifest carries no keeplingBuildDigest')

  const observed = readDigestFromRunningProcess(device.devicectlIdentifier, timeoutMs)

  if (observed.bundleIdentifier !== BUNDLE_ID) {
    refuse(`the running process reports bundle ${observed.bundleIdentifier}, expected ${BUNDLE_ID}`)
  }

  if (observed.digest !== expected) {
    refuse(
      `the build running on ${device.marketingName} reports KeeplingBuildDigest=${observed.digest} but the ` +
        `expected build is ${expected}. This is EXACTLY the case D-21 exists to catch: evidence gathered ` +
        'now would describe a different set of bytes than the ones under test. Re-run ' +
        '`node tooling/build-ios-signed.mjs` to install the current build.',
    )
  }

  const receipt = readReceiptFromDeviceContainer(device.devicectlIdentifier)
  if (receipt.available && receipt.digest !== expected) {
    refuse(
      `the app container receipt reports ${receipt.digest} while the console reported ${observed.digest}. ` +
        'The two read-back channels disagree; neither can be trusted.',
    )
  }

  return {
    consoleDigest: observed.digest,
    devicectlIdentifier: device.devicectlIdentifier,
    deviceName: device.name,
    expectedDigest: expected,
    hardwareUdid: device.hardwareUdid,
    matched: true,
    receiptAvailable: receipt.available,
    receiptDigest: receipt.digest,
    receiptUnavailableReason: receipt.reason,
  }
}

export { attest }

if (import.meta.url === `file://${process.argv[1]}`) {
  const expectIndex = process.argv.indexOf('--expect-digest')
  const expectedDigest = expectIndex === -1 ? undefined : process.argv[expectIndex + 1]
  if (expectIndex !== -1 && !expectedDigest) refuse('--expect-digest requires a value')
  if (expectIndex === -1 && !process.argv.includes('--expect-installed') && !process.argv.includes('--json')) {
    refuse('pass --expect-installed (compare against the build manifest) or --expect-digest <value>')
  }
  const result = attest({ expectedDigest })
  if (process.argv.includes('--json')) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`)
  } else {
    console.log(
      `ATTESTATION matched=true digest=${result.consoleDigest} device=${JSON.stringify(result.deviceName)} ` +
        `hardware_udid=${result.hardwareUdid} receipt_channel=${result.receiptAvailable ? 'agreed' : 'unavailable'}`,
    )
  }
}
