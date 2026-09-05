/**
 * core-loop lane (04-09-PLAN.md Task 2): runs `CoreLoopTests` and
 * `GestureMirrorTests` -- the full supported daily loop (capture, appear in
 * Inbox, open, edit, save, complete, reopen, trash, restore) driven
 * end to end on the simulator, plus the locked gesture contract (Complete/
 * Reopen only on a full trailing swipe, Trash never on a swipe, always
 * reachable via the row's long-press context menu and the task detail
 * view's named controls).
 */
export default function coreLoopLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/CoreLoopTests',
      '-only-testing:KeeplingUITests/GestureMirrorTests',
    ],
    cwd: repositoryRoot,
    name: 'core-loop',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/Keepling/App/RootTabView.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift',
      'apps/ios/Sources/Keepling/Shared/TaskRow.swift',
      'apps/ios/Sources/Keepling/Today/TodayView.swift',
      'apps/ios/Sources/Keepling/Inbox/InboxView.swift',
      'apps/ios/Sources/Keepling/Detail/TaskDetailView.swift',
      'apps/ios/Sources/Keepling/Detail/ConflictResolverSection.swift',
      'apps/ios/Sources/Keepling/Capture/CaptureSheet.swift',
      'apps/ios/Sources/KeeplingCore/Application/OutboundCommands.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Tests/KeeplingUITests/CoreLoopTests.swift',
      'apps/ios/Tests/KeeplingUITests/GestureMirrorTests.swift',
    ],
  }
}
