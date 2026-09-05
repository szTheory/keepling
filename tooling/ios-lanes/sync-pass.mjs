/**
 * sync-pass lane (04-08-PLAN.md Task 2): runs `SyncPassTests` -- the bounded
 * pull-before-push orchestrator, the three-state transmission machine
 * (queued -> in_flight -> settled/uncertain, never back to queued), FIFO
 * lane ordering within a resource key, concurrency-safe claiming, fence
 * refusal, and authentication-required handling.
 */
export default function syncPassLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/SyncPassTests',
    ],
    cwd: repositoryRoot,
    name: 'sync-pass',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift',
      'apps/ios/Sources/KeeplingCore/Application/SyncPassScheduler.swift',
      'apps/ios/Sources/KeeplingCore/Application/OutboundCommands.swift',
      'apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift',
      'apps/ios/Sources/KeeplingCore/Transport/WireMappers.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Sources/KeeplingCore/Sync/SyncReducer.swift',
      'apps/ios/Tests/KeeplingCoreTests/SyncPassTests.swift',
      'packages/contracts/openapi/keepling.yaml',
    ],
  }
}
