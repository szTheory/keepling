/**
 * undo lane (04-11-PLAN.md): runs both test classes this plan introduces
 * in one `xcodebuild` invocation -- `UndoReconciliationTests` (compensating
 * commands through the server handle, KeeplingCoreTests) and
 * `UndoPersistenceTests` (the named, timerless control and its
 * accessibility mirror, KeeplingUITests) -- so one lane run proves the
 * whole plan's `<verify>` surface.
 */
export default function undoLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/UndoReconciliationTests',
      '-only-testing:KeeplingUITests/UndoPersistenceTests',
    ],
    cwd: repositoryRoot,
    name: 'undo',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Application/UndoAvailability.swift',
      'apps/ios/Sources/KeeplingCore/Application/CompensatingCommands.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift',
      'apps/ios/Sources/Keepling/Undo/UndoControl.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift',
      'apps/ios/Sources/Keepling/App/RootTabView.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/Today/TodayView.swift',
      'apps/ios/Sources/Keepling/Inbox/InboxView.swift',
      'apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift',
      'apps/ios/Sources/Keepling/Detail/TaskDetailView.swift',
      'apps/ios/Sources/Keepling/Capture/CaptureSheet.swift',
      'packages/contracts/vectors/undo.json',
      'apps/ios/Tests/KeeplingCoreTests/UndoReconciliationTests.swift',
      'apps/ios/Tests/KeeplingUITests/UndoPersistenceTests.swift',
    ],
  }
}
