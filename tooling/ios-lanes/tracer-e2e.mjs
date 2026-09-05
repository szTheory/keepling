/**
 * KeeplingUITests: the capture flow driven end to end on the simulator
 * (04-01-PLAN.md Task 3). Named `tracer-e2e` because this plan's whole
 * point is proving one path -- capture -- through every layer at once.
 */
export default function tracerE2ELane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests',
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
