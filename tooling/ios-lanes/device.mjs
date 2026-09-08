/**
 * device lane -- the one lane in this gate bound to a PHYSICAL iPhone
 * rather than a simulator (04-16-PLAN.md Task 3; supersedes the
 * always-BLOCKED placeholder 04-17-PLAN.md left here while 04-16 was
 * unexecuted).
 *
 * ORDER MATTERS: the attestation refusal runs FIRST, before any test.
 * `tooling/ios-device/attestation.mjs --expect-installed` reads
 * `KeeplingBuildDigest` back out of the process running on the phone and
 * exits non-zero on mismatch, and the shell chain below is `&&`-joined so a
 * refusal short-circuits every later step. A lane that runs its suite and
 * THEN checks identity has already spent the evidence it was protecting
 * (D-21, T-04-16-01).
 *
 * The two identifier spaces are honoured throughout (T-04-16-02,
 * RESEARCH Pitfall 3): `xcodebuild -destination` gets the HARDWARE UDID and
 * `devicectl --device` gets the COREDEVICE identifier, each resolved by
 * `tooling/ios-device/resolve-devices.mjs`, which refuses to run if the two
 * are equal.
 *
 * ---------------------------------------------------------------------
 * WHY THIS LANE STILL REPORTS `BLOCKED` AFTER RUNNING REAL DEVICE TESTS
 * ---------------------------------------------------------------------
 * D-22 Criterion 2 has two halves. The OFFLINE half -- a mutation made with
 * no server, a hard kill, a relaunch, exactly-once projection, a durable
 * capture draft, foreground resume -- runs here for real on Jon's phone and
 * passes. The SERVER-DRIVEN half -- authentication expiry, account fencing,
 * duplicate replay, and structured conflict injected server-side through
 * the recording proxy and asserted against what the proxy recorded -- does
 * NOT, and cannot yet.
 *
 * `tooling/verify-real-stack-ios.mjs` measures why rather than asserting
 * it: `KeeplingSyncAdapter`'s constructor refuses any non-HTTPS base URL
 * whose host is not `127.0.0.1`/`localhost` (T-04-01-03/T-04-05-04), and a
 * physical phone can only reach the build Mac at a LAN address. Over plain
 * HTTP nothing leaves the phone; over TLS the phone genuinely connects (so
 * routing works) and URLSession rejects the lane's self-signed certificate.
 * Closing that needs a decision Plan 04-16 did not make, and widening the
 * production transport guard to make this lane green is refused.
 *
 * So this lane runs everything it genuinely can, reports the case count it
 * genuinely achieved IN ITS MESSAGE, and then throws `BLOCKED:` -- which
 * `tooling/verify-ios-phase.mjs` labels distinctly from a bug while still
 * failing the overall run. The alternative -- returning a positive count
 * and letting the gate go green -- would let IOS-02's server-driven half
 * look proven forever on the strength of its offline half. That is the
 * exact failure this project's BLOCKED convention exists to prevent.
 *
 * When the transport-trust decision lands, delete `SERVER_DRIVEN_BLOCKER`
 * below and return `cases` directly.
 */
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

/**
 * The literal `DeviceCoreLoopTests`/`DeviceRecoveryTests` query for. A
 * UI-test bundle is hosted by the app but does not link its module, so the
 * identifier cannot be shared as a symbol -- it is mirrored, and mirrored
 * strings drift. This lane refuses to run on drift rather than letting the
 * device suites silently stop finding the probe (which would look like "the
 * app has no attestation" and fail confusingly).
 */
const PROBE_IDENTIFIER = 'build-attestation-digest'

/**
 * D-19: the install path is `devicectl` direct install and nothing else.
 * TestFlight and the App Store are deferred to Phase 6 -- upload plus
 * processing latency plus a 90-day build expiry buy this phase no
 * evidentiary value. Asserted here, not merely written in a comment,
 * because a distribution step added later would silently change what
 * "installed build" means.
 */
const FORBIDDEN_DISTRIBUTION_TOKENS = ['altool', 'notarytool', 'App Store Connect', 'app-store', 'ad-hoc', 'enterprise']

const SERVER_DRIVEN_BLOCKER =
  'the server-driven half of D-22 Criterion 2 (authentication expiry, account fencing, duplicate replay, ' +
  'structured conflict -- injected server-side and asserted against the recording proxy) cannot run: the ' +
  'phone cannot reach a Mac-hosted proxy. `KeeplingSyncAdapter` refuses any non-HTTPS base URL whose host ' +
  'is not 127.0.0.1/localhost (T-04-01-03/T-04-05-04), and over TLS URLSession rejects the lane\'s ' +
  'self-signed certificate. `node tooling/verify-real-stack-ios.mjs` measures both halves and prints the ' +
  'evidence. This is disclosed missing evidence, not a code defect, and it is NOT closed by relaxing the ' +
  'transport guard.'

export default function deviceLane({ repositoryRoot, xcodebuildSummary }) {
  const manifestPath = join(repositoryRoot, '.artifacts', 'ios', 'build-manifest.json')
  const attestationPath = join(repositoryRoot, 'tooling', 'ios-device', 'attestation.mjs')
  const resolvePath = join(repositoryRoot, 'tooling', 'ios-device', 'resolve-devices.mjs')

  const preflightError = (() => {
    for (const [label, path] of [['attestation.mjs', attestationPath], ['resolve-devices.mjs', resolvePath]]) {
      if (!existsSync(path)) return `BLOCKED: tooling/ios-device/${label} is missing -- the device lane has no way to bind evidence to a build.`
    }
    if (!existsSync(manifestPath)) {
      return (
        'BLOCKED: no .artifacts/ios/build-manifest.json. Run `node tooling/build-ios-signed.mjs` first -- ' +
        'without a manifest there is no digest to attest against, and an unbound device run is exactly the ' +
        'stale evidence D-21 refuses.'
      )
    }

    // Drift guard on the mirrored probe identifier.
    const swiftSource = readFileSync(join(repositoryRoot, 'apps/ios/Sources/Keepling/App/BuildAttestation.swift'), 'utf8')
    if (!swiftSource.includes(`"${PROBE_IDENTIFIER}"`)) {
      return `BLOCKED: BuildAttestation.swift no longer declares the probe identifier "${PROBE_IDENTIFIER}" this lane and the device suites mirror.`
    }
    for (const testFile of ['DeviceCoreLoopTests.swift', 'DeviceRecoveryTests.swift']) {
      const path = join(repositoryRoot, 'apps/ios/Tests/KeeplingUITests', testFile)
      if (!existsSync(path)) return `BLOCKED: ${testFile} is missing -- the device suite this lane names does not exist.`
    }

    // D-19 install-path assertion.
    for (const script of ['tooling/build-ios-signed.mjs', 'tooling/verify-real-stack-ios.mjs', 'tooling/ios-device/attestation.mjs']) {
      const source = readFileSync(join(repositoryRoot, script), 'utf8')
      // Skip prose that explicitly REFUSES these paths: the check is for a
      // real invocation, and the header comments name the forbidden tools
      // precisely so a future reader knows not to add them.
      const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')
      for (const token of FORBIDDEN_DISTRIBUTION_TOKENS) {
        if (code.includes(token)) {
          return `BLOCKED: ${script} references ${token}. D-19 defers TestFlight/App Store to Phase 6; the install path is devicectl direct install only.`
        }
      }
    }
    return null
  })()

  const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : {}
  const digest = manifest.keeplingBuildDigest ?? ''
  // Only the HARDWARE UDID is needed here: `xcodebuild -destination` speaks
  // that space. The CoreDevice identifier is never interpolated into this
  // chain -- `hard-kill.mjs` and `attestation.mjs` each resolve their own
  // from `resolve-devices.mjs`, so neither identifier can be handed to the
  // wrong tool from here (T-04-16-02).
  const hardwareUdid = manifest?.device?.hardwareUdid ?? ''

  // `TEST_RUNNER_`-prefixed host variables are how xcodebuild hands an
  // environment value to the UI-test RUNNER process (the one that reads
  // `KEEPLING_EXPECTED_BUILD_DIGEST`). Setting the bare name would put it
  // on xcodebuild's own process and the runner would never see it.
  const chain = [
    // FIRST, before anything that can take minutes. A locked phone otherwise
    // surfaces 300 seconds later as "Timed out waiting for all destinations
    // to become available", which reads like an absent device and sends a
    // reader debugging the tunnel (04-18-PLAN.md Task 5).
    `node tooling/ios-device/lock-probe.mjs`,
    `node tooling/ios-device/attestation.mjs --expect-installed --expect-configuration Release`,
    // The out-of-process, signal-based hard kill -- the on-device analogue
    // of the Phase 3 kill, and stricter than a cooperative quit: SIGKILL
    // cannot be caught, so the app runs no shutdown path at all. Run BEFORE
    // the suite so every case starts from a genuinely cold process, and so
    // the attestation launch immediately above is the process being killed.
    'node tooling/ios-device/hard-kill.mjs --require-running',
    [
      `TEST_RUNNER_KEEPLING_EXPECTED_BUILD_DIGEST=${digest}`,
      'xcodebuild test',
      // `xcodebuild test` REBUILDS and REINSTALLS the app. Without this the
      // reinstalled app would carry project.yml's fallback
      // `$(MARKETING_VERSION)+$(CURRENT_PROJECT_VERSION)` digest, the
      // device suites' own binding assertion would fail against the
      // manifest, and the failure would look like a mismatched build rather
      // than a missing build setting. Injecting the SAME digest keeps the
      // installed bytes and the attested value in step.
      `KEEPLING_BUILD_DIGEST=${digest}`,
      '-project apps/ios/Keepling.xcodeproj',
      '-scheme Keepling',
      // EXPLICIT (04-18-PLAN.md Task 6). This was implicit, and therefore
      // invisible: with no `-configuration`, `xcodebuild test` takes the
      // scheme's TestAction configuration, which is Debug -- while
      // `build-ios-signed.mjs` archives Release. Since `xcodebuild test`
      // REBUILDS AND REINSTALLS (see the digest injection below), the
      // Release build this lane just attested is replaced by a Debug build
      // before a single test runs. The attested bytes were not the tested
      // bytes, and the source-content digest could not tell them apart.
      //
      // Debug is KEPT deliberately rather than "fixed" to Release:
      // `DeviceRecoveryTests` and the whole `KEEPLING_UITEST_*` fixture
      // family live inside `#if DEBUG`, and release-type configurations set
      // `ENABLE_TESTABILITY = NO`, which the `@testable import KeeplingCore`
      // files require. Moving this lane to Release would break the 22 tests
      // that pass today and is a separate decision.
      //
      // What changed is that the substitution is now STATED and attested
      // rather than silent: `BuildAttestation.configuration` is compiled in
      // from a `#if`, the console line carries it, and
      // `attestation.mjs --expect-configuration` refuses a mismatch.
      // DISCLOSED RESIDUAL: the device suites therefore exercise a Debug
      // binary. Proving the Release binary's behaviour on hardware remains
      // open and is not claimed anywhere by this lane.
      '-configuration Debug',
      `-destination "platform=iOS,id=${hardwareUdid}"`,
      // A wirelessly-paired iPhone is not instantly "available" to
      // xcodebuild even while CoreDevice holds a live tunnel to it: the
      // default destination wait expires and the run dies with "Timed out
      // waiting for all destinations ... to become available", which reads
      // like the phone is absent when it is merely waking (measured during
      // this plan's execution on this exact device).
      '-destination-timeout 300',
      '-allowProvisioningUpdates',
      '-only-testing:KeeplingUITests/DeviceCoreLoopTests',
      '-only-testing:KeeplingUITests/DeviceRecoveryTests',
      '-only-testing:StorageTests/DataProtectionTests',
      // D-22 Criterion 4's ONE physical-device confirmation run of the
      // Plan 04-13 accessibility suites. Confirmation, not replacement:
      // the `accessibility` lane still runs them on the simulator.
      '-only-testing:KeeplingUITests/AccessibilityAuditTests',
      // ...except its source-tree inventory check, which walks
      // `apps/ios/Sources/Keepling` on the BUILD MAC's filesystem. That
      // path does not exist inside the app process on a physical iPhone,
      // so on device it fails with "path resolution is broken" -- a
      // property of where the test runs, not of the app. It is a static
      // repo assertion with no device dimension, and the `accessibility`
      // lane still runs it on the simulator where the path resolves.
      '-skip-testing:KeeplingUITests/AccessibilityAuditTests/testEveryTopLevelViewUnderSourcesKeeplingIsInTheInventoryOrExplicitlyExcluded',
      '-only-testing:KeeplingUITests/DynamicTypeSnapshotTests',
    ].join(' '),
  ].join(' && ')

  return {
    command: 'sh',
    args: ['-c', chain],
    cwd: repositoryRoot,
    name: 'device',
    trackedInputPaths: [
      'tooling/ios-device',
      'tooling/ios-lanes/device.mjs',
      'tooling/build-ios-signed.mjs',
      'tooling/verify-real-stack-ios.mjs',
      'apps/ios/Sources/Keepling/App/BuildAttestation.swift',
      'apps/ios/Tests/KeeplingUITests/DeviceCoreLoopTests.swift',
      'apps/ios/Tests/KeeplingUITests/DeviceRecoveryTests.swift',
      'apps/ios/Tests/StorageTests/DataProtectionTests.swift',
    ],
    parse: (stdout, stderr, exitStatus) => {
      if (preflightError) throw new Error(preflightError)
      const output = `${stdout}\n${stderr}`
      if (/ATTESTATION REFUSED: BLOCKED:/.test(output)) {
        // Propagated verbatim so the gate's own `status=BLOCKED` label
        // matches the underlying condition (a locked phone) rather than
        // reporting it as an ordinary FAIL.
        throw new Error(output.match(/ATTESTATION REFUSED: (BLOCKED:[\s\S]*?)(?:\n\n|$)/)?.[1] ?? 'BLOCKED: the device could not be reached')
      }
      if (/ATTESTATION REFUSED/.test(output)) {
        throw new Error(
          'the attestation refused this run: the build running on the phone is not the build under test ' +
            '(D-21). No test result from this run may be attributed to the current build.',
        )
      }
      if (exitStatus !== 0 && !/\*\* TEST SUCCEEDED \*\*/.test(output)) {
        throw new Error(`the device suite exited ${exitStatus ?? 'without status'}`)
      }
      const cases = xcodebuildSummary(stdout)
      throw new Error(
        `BLOCKED: ${cases} physical-device case(s) passed on the installed build ` +
          `(KeeplingBuildDigest=${digest}), but ${SERVER_DRIVEN_BLOCKER}`,
      )
    },
  }
}
