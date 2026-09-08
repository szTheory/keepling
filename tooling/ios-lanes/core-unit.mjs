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
      // `ServerDrivenTests` needs a live backend behind the recording proxy
      // and a real device-grant credential, which the `server-driven-sim`
      // lane supplies and this one does not. It FAILS rather than skips when
      // that environment is absent -- deliberately, because it exists only
      // to prove the server-driven half and a skip there would publish a
      // green run that proved nothing (D-24). So the exclusion belongs here,
      // stated once, rather than being bought by weakening that suite.
      '-skip-testing:KeeplingCoreTests/ServerDrivenTests',
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
