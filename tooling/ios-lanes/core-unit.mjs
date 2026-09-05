/**
 * KeeplingCoreTests: pure-Swift unit tests, no simulator storage/UI
 * dependency beyond the simulator process itself (04-RESEARCH.md
 * "Recommended Project Structure").
 */
export default function coreUnitLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests',
    ],
    cwd: repositoryRoot,
    name: 'core-unit',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore',
      'apps/ios/Tests/KeeplingCoreTests',
    ],
  }
}
