/**
 * StorageTests, full suite (04-02-PLAN.md Task 3): the D-04 G1-G6
 * durability-gate proof -- migration ledger, crash-recovery matrix,
 * durability posture, and source discipline -- as its own named lane
 * distinct from the tracer-era `storage` lane (04-01-PLAN.md), so this
 * phase's own gate has a lane name to point at (`--lane storage-gates`)
 * without renaming or removing the earlier lane other plans may still
 * reference.
 */
export default function storageGatesLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:StorageTests',
    ],
    cwd: repositoryRoot,
    name: 'storage-gates',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Storage',
      'apps/ios/Tests/StorageTests',
    ],
  }
}
