#!/usr/bin/env node
/**
 * Answers ONE question, in seconds: is the attached iPhone unlocked right
 * now? (04-18-PLAN.md Task 5.)
 *
 * WHY THIS EXISTS AS ITS OWN STEP
 * -------------------------------
 * A locked phone is the single most frequent reason a device lane in this
 * repository has produced no evidence, and it has never announced itself
 * as one. `xcodebuild` waits out its `-destination-timeout` -- 300 seconds
 * -- and then reports "Timed out waiting for all destinations to become
 * available", which reads like the phone is absent, or asleep, or that the
 * CoreDevice tunnel is broken. Measured repeatedly during Plan 04-16: five
 * minutes spent, nothing learned, and the message pointing at the wrong
 * layer.
 *
 * Run this FIRST in every device lane. It costs a few seconds and turns
 * that five-minute misdirection into a named BLOCKED with the remedy
 * attached.
 *
 * WHY THE LOCK STATE IS DETECTED FROM A LAUNCH REFUSAL
 * ----------------------------------------------------
 * `devicectl device info lockState` reports `passcodeRequired` and
 * `unlockedSinceBoot`, NEITHER of which is the CURRENT lock state: a phone
 * that was unlocked after boot and has since re-locked still reports
 * `unlockedSinceBoot: true`. iOS refuses to launch any app on a locked
 * device, so attempting a launch is the only reliable question, and its
 * refusal is the answer. `attestation.mjs` already discovered this by
 * measurement; the detection is extracted here rather than duplicated so
 * the two cannot drift into disagreeing about what "locked" looks like.
 */
import { spawnSync } from 'node:child_process'
import { resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..', '..')
const BUNDLE_ID = 'com.szTheory.keepling'

/**
 * The launch refusal iOS emits for a locked device. Exported so every
 * device lane recognises a lock by the SAME pattern -- a second, drifting
 * definition of "locked" would put a lane back to reporting a timeout.
 */
export const DEVICE_LOCKED = /could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i

/**
 * The remedy, stated once. Says what to do NOW and what to change so it
 * never recurs -- the recurring manual step is the thing this project is
 * built to remove, and "unlock it again" is not a fix.
 */
export const LOCKED_MESSAGE =
  'the iPhone is LOCKED. iOS refuses to launch any app on a locked device, so this lane could learn ' +
  'nothing at all -- this is not a build defect, a test failure, or a missing device. Unlock the phone ' +
  'and re-run; the passcode is the one input no tool here can supply. To stop this recurring, set ' +
  'Settings > Display & Brightness > Auto-Lock to Never and keep the phone on power while lanes run.'

export const probeLockState = ({ devicectlIdentifier, timeoutMs = 30_000 }) => {
  const launch = spawnSync(
    'xcrun',
    ['devicectl', 'device', 'process', 'launch', '--device', devicectlIdentifier, '--terminate-existing', BUNDLE_ID],
    { encoding: 'utf8', timeout: timeoutMs },
  )
  const output = `${launch.stdout ?? ''}\n${launch.stderr ?? ''}`
  if (DEVICE_LOCKED.test(output)) return { locked: true, output }
  return { locked: false, output }
}

if (import.meta.filename === process.argv[1]) {
  const { resolveDevice } = await import(`${repositoryRoot}/tooling/ios-device/resolve-devices.mjs`)
  let device
  try {
    device = resolveDevice()
  } catch (error) {
    console.error(`BLOCKED: no physical iPhone could be resolved -- ${error instanceof Error ? error.message : String(error)}`)
    process.exit(1)
  }
  const { locked } = probeLockState({ devicectlIdentifier: device.devicectlIdentifier })
  if (locked) {
    console.error(`BLOCKED: ${LOCKED_MESSAGE}`)
    process.exit(1)
  }
  console.log(`LOCK_PROBE device=${JSON.stringify(device.name)} locked=false`)
}
