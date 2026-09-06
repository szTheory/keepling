/**
 * KeeplingUITests/TracerCaptureUITests: the capture flow driven end to end
 * on the simulator (04-01-PLAN.md Task 3). Named `tracer-e2e` because this
 * plan's whole point is proving one path -- capture -- through every layer
 * at once.
 *
 * FIXED 04-17-PLAN.md Task 1: this lane's `-only-testing` argument named
 * the WHOLE `KeeplingUITests` target rather than `TracerCaptureUITests`
 * specifically -- a real bug, discovered only once 04-17 assembled every
 * lane into one run for the first time (each prior plan had only ever run
 * its OWN `--lane <name>` in isolation, never the full glob together). The
 * unscoped filter silently re-ran every other UI-test lane's test classes
 * under this lane's name too, several times slower than intended and
 * duplicating (never contradicting) their own dedicated lanes' coverage --
 * this is what docs/testing/ios-testing.md's lane table already documented
 * this lane as proving (`TracerCaptureUITests` only), so the fix restores
 * the lane to its documented, narrower scope (Rule 1).
 */
export default function tracerE2ELane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/TracerCaptureUITests',
    ],
    cwd: repositoryRoot,
    name: 'tracer-e2e',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Sources/Keepling',
      'apps/ios/Sources/KeeplingCore',
      'apps/ios/Tests/KeeplingUITests',
    ],
  }
}
