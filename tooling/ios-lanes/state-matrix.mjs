/**
 * state-matrix lane (04-14-PLAN.md Task 1): the deterministic state-
 * injection seam and the twelve-state matrix -- `SyncStateMatrixTests`
 * proves every presentation state this app can render is reachable on
 * demand, without a server, and renders its exact inherited copy and
 * named recovery action.
 */
export default function stateMatrixLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/SyncStateMatrixTests',
    ],
    cwd: repositoryRoot,
    name: 'state-matrix',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/SyncCopy.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/App/RootTabView.swift',
      'apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift',
      'apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift',
      'apps/ios/Tests/KeeplingUITests/Support/StateInjection.swift',
      'apps/ios/Tests/KeeplingUITests/SyncStateMatrixTests.swift',
    ],
  }
}
