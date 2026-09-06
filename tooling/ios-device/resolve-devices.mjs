#!/usr/bin/env node
/**
 * Two identifier spaces, never one (04-16-PLAN.md Task 2, T-04-16-02).
 *
 * 04-RESEARCH.md § Common Pitfalls, Pitfall 3: a physical iPhone is named
 * by TWO different identifiers that look alike (both are uppercase hex
 * with dashes) and are not interchangeable:
 *
 *   - the HARDWARE UDID (e.g. `<REDACTED-DEVICE-UDID>`) -- what
 *     `xcodebuild -destination 'platform=iOS,id=...'` and
 *     `xctrace list devices` speak, and what appears in a provisioning
 *     profile's `ProvisionedDevices` array;
 *   - the COREDEVICE identifier (e.g. `455FFAE9-...`) -- what
 *     `devicectl --device` speaks for install, launch, and terminate.
 *
 * Passing one where the other belongs fails with an opaque
 * "no matching destination" error, or -- far worse on a Mac with more
 * than one paired phone -- silently targets a DIFFERENT device, which
 * would produce evidence about hardware nobody meant to test.
 *
 * So this resolver never returns a single interchangeable `id`. It
 * returns `hardwareUdid` and `devicectlIdentifier` as separately named
 * fields, and it FAILS LOUDLY if the two are equal: on this device they
 * genuinely differ, and a run where they happened to coincide would let
 * a wrong "they're the same thing" assumption survive undetected into
 * the next device.
 *
 * Both values are cross-checked against `xctrace list devices`, which is
 * an independent source for the hardware UDID. A disagreement between
 * the two Apple tools is a refusal, not a preference.
 *
 * Usage:
 *   node tooling/ios-device/resolve-devices.mjs                 # human-readable + JSON
 *   node tooling/ios-device/resolve-devices.mjs --hardware-udid # just the UDID (for -destination)
 *   node tooling/ios-device/resolve-devices.mjs --devicectl-id  # just the CoreDevice id
 *   node tooling/ios-device/resolve-devices.mjs --json          # machine-readable object
 */
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const fail = (message) => {
  console.error(`iOS device resolution failed: ${message}`)
  process.exit(1)
}

/**
 * `devicectl`'s JSON output is the ONLY interface Apple documents as
 * supported for scripts (its own `--json-output` help text says so), so
 * this never scrapes the human-readable table.
 */
const devicectlDevices = () => {
  const scratch = mkdtempSync(join(tmpdir(), 'keepling-devicectl-'))
  const outputPath = join(scratch, 'devices.json')
  try {
    const result = spawnSync(
      'xcrun',
      ['devicectl', 'list', 'devices', '--quiet', '--json-output', outputPath],
      { encoding: 'utf8' },
    )
    if (result.error) fail(`could not run \`xcrun devicectl list devices\`: ${result.error.message}`)
    if (result.status !== 0) {
      fail(`\`xcrun devicectl list devices\` exited ${result.status}: ${(result.stderr ?? '').trim()}`)
    }
    let parsed
    try {
      parsed = JSON.parse(readFileSync(outputPath, 'utf8'))
    } catch (error) {
      fail(`devicectl produced unreadable JSON: ${error instanceof Error ? error.message : String(error)}`)
    }
    return parsed?.result?.devices ?? []
  } finally {
    rmSync(scratch, { force: true, recursive: true })
  }
}

/**
 * The independent cross-check. `xctrace` reports a device as
 * `Name (osVersion) (hardwareUDID)`; it is the tool whose identifier
 * space `xcodebuild -destination` shares, so agreement here is what
 * proves the UDID this resolver hands to `xcodebuild` is the one
 * `xcodebuild` itself would recognize.
 *
 * A wirelessly-paired iPhone is listed by `xctrace` under its
 * `== Devices Offline ==` heading even while CoreDevice holds a live
 * tunnel to it, so this parses every device line rather than only the
 * ones under `== Devices ==` -- treating the heading as authoritative
 * would reject a perfectly reachable phone.
 */
const xctraceHardwareUdids = () => {
  const result = spawnSync('xcrun', ['xctrace', 'list', 'devices'], { encoding: 'utf8' })
  if (result.error) fail(`could not run \`xcrun xctrace list devices\`: ${result.error.message}`)
  // xctrace writes its device table to stderr on some Xcode versions.
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`
  const udids = new Set()
  let inSimulators = false
  for (const line of output.split('\n')) {
    if (line.includes('== Simulators ==')) inSimulators = true
    else if (line.includes('== Devices')) inSimulators = false
    if (inSimulators) continue
    const match = line.match(/\(([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})\)\s*$/)
    if (match) udids.add(match[1])
  }
  return udids
}

const resolve = () => {
  const devices = devicectlDevices()
  const phones = devices.filter((device) => {
    const hardware = device?.hardwareProperties ?? {}
    return hardware.deviceType === 'iPhone' && hardware.reality === 'physical'
  })

  if (phones.length === 0) {
    fail(
      'no physical iPhone is paired with this Mac. Attach and trust one iPhone running iOS 26 or later ' +
        '(04-16-PLAN.md Task 1) -- this lane refuses to fall back to a simulator, which cannot model real ' +
        'flash storage, real provisioning, or a real no-notice process kill.',
    )
  }

  const selector = process.env.KEEPLING_IOS_DEVICE
  const selected = selector
    ? phones.find(
        (device) =>
          device.identifier === selector ||
          device?.hardwareProperties?.udid === selector ||
          device?.deviceProperties?.name === selector,
      )
    : phones[0]

  if (!selected) fail(`KEEPLING_IOS_DEVICE=${selector} matched none of the ${phones.length} paired iPhone(s)`)
  if (!selector && phones.length > 1) {
    // Never guess between phones: the wrong one produces evidence about
    // hardware nobody meant to test (T-04-16-02).
    fail(
      `${phones.length} physical iPhones are paired; set KEEPLING_IOS_DEVICE to one of ` +
        `${phones.map((device) => device.identifier).join(', ')} to choose deliberately`,
    )
  }

  const devicectlIdentifier = selected.identifier
  const hardwareUdid = selected?.hardwareProperties?.udid
  if (!devicectlIdentifier) fail('devicectl reported a device with no CoreDevice identifier')
  if (!hardwareUdid) fail('devicectl reported a device with no hardware UDID')

  // The assertion that keeps the distinction visible. If these ever came
  // back equal, every later "pass the right id to the right tool" line in
  // this lane would be untested, and the next device -- where they differ
  // again -- would fail confusingly.
  if (devicectlIdentifier === hardwareUdid) {
    fail(
      'the CoreDevice identifier and the hardware UDID are equal on this device. They are different ' +
        'identifier spaces (RESEARCH Pitfall 3) and this lane refuses to run where that distinction is ' +
        'invisible -- it would let an interchange bug survive undetected.',
    )
  }

  const crossChecked = xctraceHardwareUdids()
  if (crossChecked.size > 0 && !crossChecked.has(hardwareUdid)) {
    fail(
      `devicectl reports hardware UDID ${hardwareUdid} but \`xctrace list devices\` does not list it ` +
        `(it lists ${[...crossChecked].join(', ') || 'no physical device'}). ` +
        'xctrace shares xcodebuild\'s identifier space, so this disagreement means the UDID handed to ' +
        '`xcodebuild -destination` would not match anything.',
    )
  }

  const osVersion = selected?.deviceProperties?.osVersionNumber ?? null
  const majorVersion = Number.parseInt(String(osVersion ?? '0'), 10)
  if (!Number.isFinite(majorVersion) || majorVersion < 26) {
    fail(`the attached iPhone runs iOS ${osVersion ?? 'unknown'}; this app's deployment target is iOS 26.0`)
  }

  return {
    bootState: selected?.deviceProperties?.bootState ?? null,
    devicectlIdentifier,
    developerModeStatus: selected?.deviceProperties?.developerModeStatus ?? null,
    hardwareUdid,
    marketingName: selected?.hardwareProperties?.marketingName ?? null,
    name: selected?.deviceProperties?.name ?? null,
    osVersion,
    pairingState: selected?.connectionProperties?.pairingState ?? null,
    xctraceCrossChecked: crossChecked.has(hardwareUdid),
  }
}

/**
 * `devicectl device info lockState` reports `passcodeRequired`, which is
 * the machine-readable answer to the one prerequisite 04-16-PLAN.md Task 1
 * otherwise had to take a human's word for. Gate G7's locked-device
 * assertion is meaningless without a passcode, so the device lane asks the
 * device rather than assuming.
 */
const lockState = (devicectlIdentifier) => {
  const scratch = mkdtempSync(join(tmpdir(), 'keepling-lockstate-'))
  const outputPath = join(scratch, 'lock.json')
  try {
    const result = spawnSync(
      'xcrun',
      ['devicectl', 'device', 'info', 'lockState', '--device', devicectlIdentifier, '--quiet', '--json-output', outputPath],
      { encoding: 'utf8' },
    )
    if (result.status !== 0) return { available: false, passcodeRequired: null, unlockedSinceBoot: null }
    const parsed = JSON.parse(readFileSync(outputPath, 'utf8'))
    return {
      available: true,
      passcodeRequired: parsed?.result?.passcodeRequired ?? null,
      unlockedSinceBoot: parsed?.result?.unlockedSinceBoot ?? null,
    }
  } catch {
    return { available: false, passcodeRequired: null, unlockedSinceBoot: null }
  } finally {
    rmSync(scratch, { force: true, recursive: true })
  }
}

const resolveDevice = () => {
  const device = resolve()
  return { ...device, lockState: lockState(device.devicectlIdentifier) }
}

export { resolveDevice }

if (import.meta.url === `file://${process.argv[1]}`) {
  const device = resolveDevice()
  if (process.argv.includes('--hardware-udid')) {
    process.stdout.write(`${device.hardwareUdid}\n`)
  } else if (process.argv.includes('--devicectl-id')) {
    process.stdout.write(`${device.devicectlIdentifier}\n`)
  } else if (process.argv.includes('--json')) {
    process.stdout.write(`${JSON.stringify(device, null, 2)}\n`)
  } else {
    console.log(`IOS_DEVICE name=${JSON.stringify(device.name)} model=${JSON.stringify(device.marketingName)} os=${device.osVersion}`)
    console.log(`IOS_DEVICE hardware_udid=${device.hardwareUdid}    (for xcodebuild -destination and provisioning)`)
    console.log(`IOS_DEVICE devicectl_identifier=${device.devicectlIdentifier}    (for devicectl --device)`)
    console.log(
      `IOS_DEVICE identifiers_distinct=true xctrace_cross_checked=${device.xctraceCrossChecked} ` +
        `pairing=${device.pairingState} boot=${device.bootState} developer_mode=${device.developerModeStatus}`,
    )
    console.log(
      `IOS_DEVICE passcode_required=${device.lockState.passcodeRequired} ` +
        `unlocked_since_boot=${device.lockState.unlockedSinceBoot}`,
    )
    console.log(JSON.stringify(device))
  }
}
