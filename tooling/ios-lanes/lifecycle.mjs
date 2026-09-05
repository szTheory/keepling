/**
 * lifecycle lane (04-08-PLAN.md Task 3): runs `BackgroundAccelerationTests`
 * -- the scene-phase driver and background refresh handler both call the
 * identical `runSyncPass` entry point, every supported behavior is correct
 * with the background path disabled entirely, and a background expiration
 * leaves every outbox row in a legal state.
 */
export default function lifecycleLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/BackgroundAccelerationTests',
    ],
    cwd: repositoryRoot,
    name: 'lifecycle',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/Keepling/App/ScenePhaseDriver.swift',
      'apps/ios/Sources/Keepling/App/BackgroundRefresh.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift',
      'apps/ios/Sources/KeeplingCore/Application/SyncPassScheduler.swift',
      'apps/ios/Tests/KeeplingCoreTests/BackgroundAccelerationTests.swift',
      'docs/testing/ios-testing.md',
    ],
  }
}
