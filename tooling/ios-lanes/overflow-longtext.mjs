/**
 * overflow-longtext lane (04-14-PLAN.md Task 2): the held-out overflow and
 * long-text suite -- `OverflowAndLongTextTests` attacks all eight
 * UI-SPEC elements with content at the contract's maximum lengths, at the
 * largest accessibility Dynamic Type category, using a fixture no other
 * suite references.
 */
export default function overflowLongtextLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/OverflowAndLongTextTests',
    ],
    cwd: repositoryRoot,
    name: 'overflow-longtext',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Sources/Keepling/Detail/TaskDetailView.swift',
      'apps/ios/Sources/KeeplingCore/Application/OutboundCommands.swift',
      'apps/ios/Tests/KeeplingUITests/OverflowAndLongTextTests.swift',
      'apps/ios/Tests/KeeplingUITests/Fixtures/long-text.json',
    ],
  }
}
