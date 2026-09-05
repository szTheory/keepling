/**
 * StorageTests: GRDB durability/migration-ledger tests (G1-G8 gates,
 * 04-CONTEXT.md D-04), simulator-hosted because GRDB opens a real file on
 * the simulator's filesystem.
 */
export default function storageLane({ repositoryRoot, xcodebuildSummary }) {
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
    name: 'storage',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Storage',
      'apps/ios/Tests/StorageTests',
    ],
  }
}
