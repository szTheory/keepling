/**
 * accessibility lane (04-13-PLAN.md): runs the full D-48 accessibility
 * release-evidence suite this plan introduces in one `xcodebuild`
 * invocation -- `AccessibilityAuditTests` (the seven-type audit across the
 * closed screen inventory, plus icon-only naming and title-leak checks),
 * `DynamicTypeSnapshotTests` (the Dynamic Type matrix including
 * accessibility sizes and the Differentiate Without Color pass), and
 * `ReduceMotionTests`/`FocusSafetyTests` (the motion gate and the
 * three-step focus fallback) -- so one lane run proves the whole plan's
 * `<verify>` surface, not just one task's slice of it. Each `-only-testing`
 * entry is added as its own test file lands (Task 1 authored this lane
 * with only `AccessibilityAuditTests`; Tasks 2/3 extend the same file
 * rather than replace it).
 */
export default function accessibilityLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/AccessibilityAuditTests',
      '-only-testing:KeeplingUITests/DynamicTypeSnapshotTests',
      '-only-testing:KeeplingUITests/ReduceMotionTests',
      '-only-testing:KeeplingUITests/FocusSafetyTests',
    ],
    cwd: repositoryRoot,
    name: 'accessibility',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/Keepling/Shared/Motion.swift',
      'apps/ios/Sources/Keepling/Shared/TaskRow.swift',
      'apps/ios/Sources/Keepling/Shared/TaskExceptionRow.swift',
      'apps/ios/Sources/Keepling/Today/TodayView.swift',
      'apps/ios/Sources/Keepling/Inbox/InboxView.swift',
      'apps/ios/Sources/Keepling/Detail/TaskDetailView.swift',
      'apps/ios/Sources/Keepling/Detail/ConflictResolverSection.swift',
      'apps/ios/Sources/Keepling/Capture/CaptureSheet.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift',
      'apps/ios/Sources/Keepling/App/RootTabView.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift',
      'apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift',
      'apps/ios/Sources/Keepling/DesignTokens/TokenSemantics.swift',
      'apps/ios/Tests/KeeplingUITests/Support/ScreenInventory.swift',
      'apps/ios/Tests/KeeplingUITests/AccessibilityAuditTests.swift',
      'apps/ios/Tests/KeeplingUITests/DynamicTypeSnapshotTests.swift',
      'apps/ios/Tests/KeeplingUITests/ReduceMotionTests.swift',
      'apps/ios/Tests/KeeplingUITests/FocusSafetyTests.swift',
    ],
  }
}
