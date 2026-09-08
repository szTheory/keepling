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
 * WHY THIS LANE NO LONGER REPORTS `BLOCKED`
 * ---------------------------------------------------------------------
 * D-22 Criterion 2 has two halves. The OFFLINE half -- a mutation made
 * with no server, a hard kill, a relaunch, exactly-once projection, a
 * durable capture draft, foreground resume -- runs here on the physical
 * phone and always did.
 *
 * The SERVER-DRIVEN half -- authentication expiry, account fencing,
 * duplicate replay, and structured conflict, injected server-side through
 * the recording proxy and asserted against what the proxy recorded -- now
 * runs too, in `server-driven-device`, and this lane no longer stands in
 * for its absence. That half turned out not to be blocked by the phone or
 * by TLS at all: the Swift client had never spoken to a real server on ANY
 * destination, could not attach a credential, could not decode the
 * server's timestamps, and could not decode a sync page. Those were fixed;
 * the transport was then solved by reaching this Mac over the tailnet with
 * a real Let's Encrypt certificate, so the phone validates with the
 * SHIPPING trust path and no test-only trust code exists anywhere.
 *
 * This lane therefore returns its genuine case count. The BLOCKED
 * convention remains for conditions that genuinely prevent evidence --
 * a locked phone, an absent device -- and `lock-probe.mjs` now names the
 * most frequent of those in seconds rather than after a 300-second
 * destination timeout.
 *
 * DISCLOSED RESIDUAL: the suites below run in the Debug configuration
 * (the scheme's TestAction), which `xcodebuild test` rebuilds and
 * reinstalls over the Release archive this lane attests. That
 * substitution is now attested rather than silent -- see the
 * `-configuration` comment below -- but proving the RELEASE binary's
 * behaviour on hardware remains open and is claimed nowhere.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
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
      // IOS-04 names FIVE states -- local, syncing, conflict,
      // authentication-expired, unrecoverable -- and names "a physical
      // iPhone" explicitly. `server-driven-device` proves those states
      // ARRIVE and are CLASSIFIED correctly on hardware against a real
      // server; these four cases prove the user can TELL THEM APART on
      // hardware, by exact copy and named recovery action. They are
      // launch-argument driven (`StateInjection`), so they need no server
      // and no Mac filesystem, and they run unchanged on device.
      // Method-granular on purpose: the rest of `SyncStateMatrixTests`
      // (zero/one/many shapes, draft and editor preservation) has no
      // device dimension this requirement names, and the `state-matrix`
      // lane still runs the whole suite on the simulator.
      '-only-testing:KeeplingUITests/SyncStateMatrixTests/testPopulatedRendersTheRealTaskListWithNoVisibleSyncCopy',
      '-only-testing:KeeplingUITests/SyncStateMatrixTests/testUpdatingOfflineAndLocalAcceptanceRenderTheirExactCopyWithNoRecoveryAction',
      '-only-testing:KeeplingUITests/SyncStateMatrixTests/testEveryActionableExceptionRendersItsExactCopyAndNamedRecoveryAction',
      '-only-testing:KeeplingUITests/SyncStateMatrixTests/testUnrecoverableRendersItsExactCopyAndAllThreeNamedRecoveryActions',
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
      'apps/ios/Tests/KeeplingUITests/SyncStateMatrixTests.swift',
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
        // A device run is expensive (~19 minutes) and its `.xcresult` is
        // overwritten by the next run in the same DerivedData, so a failure
        // that is only summarised as a tail is a failure that has to be
        // REPRODUCED before it can be diagnosed. Measured during 04-18: a
        // `DynamicTypeSnapshotTests` failure inside the full gate could not
        // be read afterwards at all, because the tail printed the LAST
        // suite's log and the `.xcresult` was already gone. Keep the whole
        // log, the way `tooling/ios-device/server-driven-run.mjs` already
        // does for its own runs, and name the failing tests inline.
        const logPath = join(repositoryRoot, '.artifacts', 'ios', 'device-last-run.log')
        let saved = null
        try {
          mkdirSync(join(repositoryRoot, '.artifacts', 'ios'), { recursive: true })
          writeFileSync(logPath, output)
          saved = logPath
        } catch {
          // Never let a diagnostics write turn a test failure into a
          // confusing tooling failure -- the thrown message below still
          // carries the failing test names either way.
        }
        const failing = output.match(/Failing tests:\n([\s\S]*?)\n\n/)?.[1]?.trim().split('\n').map((line) => line.trim()).join(', ')
        throw new Error(
          `the device suite exited ${exitStatus ?? 'without status'}` +
            (failing ? `; failing: ${failing}` : '') +
            (saved ? `; full log: ${saved}` : ''),
        )
      }
      // RETIRED (04-18-PLAN.md Task 7). This lane used to report BLOCKED
      // no matter how many device cases passed, because the server-driven
      // half of D-22 Criterion 2 could not run at all. It now runs, on this
      // phone, in the `server-driven-device` lane -- over the tailnet with
      // a publicly-trusted certificate, through the unmodified shipping
      // transport. This lane returns its genuine case count, exactly as
      // this file's own header instructed once the transport decision
      // landed.
      return xcodebuildSummary(stdout)
    },
  }
}
