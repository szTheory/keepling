/**
 * sync-presentation lane (04-10-PLAN.md): runs all three test classes this
 * plan introduces in one `xcodebuild` invocation -- `SyncPresentationTests`
 * (the authoritative projection, grace-period absorption, copy vocabulary,
 * KeeplingCoreTests), `AnnouncementTests` (the debounced-announcement
 * batching logic, KeeplingUITests), and `SyncRecoveryTests` (the
 * accessory/sheet/overflow-menu/per-task-exception behavior, also
 * KeeplingUITests) -- so one lane run proves the whole plan's `<verify>`
 * surface, not just one task's slice of it.
 */
export default function syncPresentationLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/SyncPresentationTests',
      '-only-testing:KeeplingUITests/AnnouncementTests',
      '-only-testing:KeeplingUITests/SyncRecoveryTests',
    ],
    cwd: repositoryRoot,
    name: 'sync-presentation',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/SyncCopy.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/AnnouncementDebouncer.swift',
      'apps/ios/Sources/KeeplingCore/Application/SyncPassScheduler.swift',
      'apps/ios/Sources/KeeplingCore/Storage/StoreUnrecoverable.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift',
      'apps/ios/Sources/Keepling/Shared/TaskExceptionRow.swift',
      'apps/ios/Sources/Keepling/Shared/TaskRow.swift',
      'apps/ios/Sources/Keepling/App/RootTabView.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/Today/TodayView.swift',
      'apps/ios/Sources/Keepling/Inbox/InboxView.swift',
      'apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift',
      'apps/ios/Tests/KeeplingCoreTests/SyncPresentationTests.swift',
      'apps/ios/Tests/KeeplingUITests/AnnouncementTests.swift',
      'apps/ios/Tests/KeeplingUITests/SyncRecoveryTests.swift',
    ],
  }
}
