/**
 * device lane (04-17-PLAN.md): the one lane in this gate bound to a
 * physical iPhone rather than a simulator. Plan 04-16 is the plan that
 * builds this lane's real evidence -- `tooling/ios-device/attestation.mjs`,
 * `tooling/ios-device/resolve-devices.mjs`, and the device-bound
 * `DeviceCoreLoopTests`/`DeviceRecoveryTests` UI-test targets -- gated on a
 * paid Apple Developer Program membership, a `DEVELOPMENT_TEAM` configured
 * in `apps/ios/project.yml`, and a trusted, online physical iPhone.
 *
 * As of this plan, 04-16 has NOT completed: it halted at a genuine
 * human-action checkpoint (no confirmed paid membership, no
 * `DEVELOPMENT_TEAM` set, and Jon's iPhone paired but offline). Rather than
 * silently omitting a "device" row from the gate -- which would let every
 * later run of this gate look complete while the physical-device half of
 * IOS-01, IOS-02, IOS-04, and the SRV-02 iPhone adapter proof was never
 * once exercised -- this lane always runs, and always reports BLOCKED
 * (never PASS, never a quiet skip) until 04-16's evidence exists.
 *
 * BLOCKED is not the ordinary FAIL a broken test produces: `runLane` in
 * tooling/verify-ios-phase.mjs recognizes any thrown message prefixed
 * "BLOCKED:" and labels the LANE line accordingly, so a human reading gate
 * output can tell "this is missing hardware/credentials" apart from "this
 * is a bug" at a glance -- while the run still refuses to report overall
 * success either way (per D-24 and the orchestrator note in
 * 04-17-PLAN.md).
 *
 * Once 04-16 lands: this file should be replaced with a real lane that
 * runs the device-bound UI tests via tooling/build-ios-signed.mjs and
 * tooling/verify-real-stack-ios.mjs, and asserts the attestation's
 * recorded `KeeplingBuildDigest` matches the current build manifest before
 * accepting its evidence as current (T-04-17-02).
 */
import { existsSync } from 'node:fs'
import { join } from 'node:path'

export default function deviceLane({ repositoryRoot }) {
  const attestationPath = join(repositoryRoot, 'tooling', 'ios-device', 'attestation.mjs')
  const resolveDevicesPath = join(repositoryRoot, 'tooling', 'ios-device', 'resolve-devices.mjs')
  const devicePlanSummaryPath = join(
    repositoryRoot,
    '.planning',
    'phases',
    'KPL-04-native-iphone-daily-loop',
    '04-16-SUMMARY.md',
  )

  const evidenceReady = existsSync(attestationPath) && existsSync(resolveDevicesPath) && existsSync(devicePlanSummaryPath)

  return {
    // No real work to spawn while blocked -- `true` always exits 0 so the
    // BLOCKED determination comes entirely from `parse` throwing, never
    // from a manufactured non-zero exit that would read like a crash.
    command: 'true',
    args: [],
    cwd: repositoryRoot,
    name: 'device',
    trackedInputPaths: ['tooling/ios-device', 'tooling/ios-lanes/device.mjs'],
    parse: () => {
      if (!evidenceReady) {
        const missing = [
          !existsSync(devicePlanSummaryPath) ? '04-16-SUMMARY.md (Plan 04-16 has not completed)' : null,
          !existsSync(attestationPath) ? 'tooling/ios-device/attestation.mjs' : null,
          !existsSync(resolveDevicesPath) ? 'tooling/ios-device/resolve-devices.mjs' : null,
        ].filter(Boolean)
        throw new Error(
          'BLOCKED: physical-device evidence not available -- ' +
            `missing: ${missing.join(', ')}. Requires an active Apple Developer Program membership, ` +
            '`DEVELOPMENT_TEAM` configured in apps/ios/project.yml, and a trusted, online physical iPhone ' +
            'running iOS 26+ (see 04-16-PLAN.md, which halted at a genuine human-action checkpoint). ' +
            'This is disclosed missing evidence, not a code defect -- re-run this lane after Plan 04-16 ' +
            'produces its SUMMARY and the attestation tooling.',
        )
      }
      // Once 04-16 lands, this branch should invoke the real device-bound
      // xcodebuild run and its attestation-digest binding check instead of
      // returning a fixed count.
      return 0
    },
  }
}
