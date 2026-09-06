#!/usr/bin/env node
/**
 * The no-notice hard kill, out of process (04-16-PLAN.md Task 3).
 *
 * `XCUIApplication.terminate()` kills the app from inside the test host and
 * is what `DeviceRecoveryTests` uses between its own cases. This is the
 * STRONGER, out-of-process form: `devicectl device process terminate --kill`
 * sends SIGKILL to the real process on the phone, which the app cannot
 * catch and cannot run any shutdown path for. It is the exact on-device
 * analogue of the Phase 3 desktop hard kill, and it is what makes "survived
 * a no-notice termination" a claim about durability rather than about an
 * orderly quit.
 *
 * It exists as its own file rather than as a shell pipeline inside
 * `tooling/ios-lanes/device.mjs` because `devicectl terminate` takes a PID,
 * not a bundle identifier, so the PID has to be looked up first -- and
 * `devicectl`'s own help says JSON output is the only supported interface
 * for scripts, which is not something to inline as a `grep`.
 *
 * D-22 Criterion 2 disclosure, restated where it is easy to find: this
 * proves the SIGNAL-based no-notice kill. It does NOT induce OS-initiated
 * jetsam under memory pressure, which cannot be requested on demand. SIGKILL
 * is the stricter case of the two (jetsam gives an app a chance to have been
 * suspended cleanly first; SIGKILL never does), so the weaker case is not
 * silently claimed -- it is named as not covered.
 *
 * Usage:
 *   node tooling/ios-device/hard-kill.mjs                    # kill Keepling if running
 *   node tooling/ios-device/hard-kill.mjs --require-running  # fail if it was not running
 */
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

import { resolveDevice } from './resolve-devices.mjs'

const BUNDLE_EXECUTABLE_SUFFIX = 'Keepling.app/Keepling'

const runningPid = (devicectlIdentifier) => {
  const scratch = mkdtempSync(join(tmpdir(), 'keepling-procs-'))
  const outputPath = join(scratch, 'processes.json')
  try {
    const result = spawnSync(
      'xcrun',
      ['devicectl', 'device', 'info', 'processes', '--device', devicectlIdentifier, '--quiet', '--json-output', outputPath],
      { encoding: 'utf8', timeout: 120_000 },
    )
    if (result.status !== 0) return null
    const parsed = JSON.parse(readFileSync(outputPath, 'utf8'))
    const match = (parsed?.result?.runningProcesses ?? []).find((entry) =>
      String(entry?.executable ?? '').endsWith(BUNDLE_EXECUTABLE_SUFFIX),
    )
    return match?.processIdentifier ?? null
  } catch {
    return null
  } finally {
    rmSync(scratch, { force: true, recursive: true })
  }
}

const hardKill = () => {
  const device = resolveDevice()
  const pid = runningPid(device.devicectlIdentifier)
  if (pid === null) return { killed: false, pid: null }
  const result = spawnSync(
    'xcrun',
    ['devicectl', 'device', 'process', 'terminate', '--device', device.devicectlIdentifier, '--pid', String(pid), '--kill', '--quiet'],
    { encoding: 'utf8', timeout: 120_000 },
  )
  if (result.status !== 0) {
    console.error(`hard kill failed: devicectl terminate exited ${result.status}: ${(result.stderr ?? '').trim()}`)
    process.exit(1)
  }
  return { killed: true, pid }
}

export { hardKill, runningPid }

if (import.meta.url === `file://${process.argv[1]}`) {
  const outcome = hardKill()
  if (!outcome.killed && process.argv.includes('--require-running')) {
    console.error('hard kill failed: Keepling was not running, so no no-notice termination was performed')
    process.exit(1)
  }
  console.log(`IOS_HARD_KILL killed=${outcome.killed} pid=${outcome.pid ?? 'none'} signal=SIGKILL jetsam_induced=false`)
}
