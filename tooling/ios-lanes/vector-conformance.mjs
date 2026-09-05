/**
 * VectorConformanceTests: proves the Swift `SyncReducer` agrees with the
 * Elixir reference model and the TypeScript desktop consumer on
 * `packages/contracts/vectors/sync.json` -- the one vector file that binds
 * `sync-state-machine.schema.json` among the repository's 13 vector files
 * (04-03-PLAN.md Task 3; the per-file disposition of all 13 is recorded in
 * `packages/contracts/vectors/manifest.json` and 04-03-SUMMARY.md).
 *
 * DISCLOSED DEVIATION from the plan's literal "case count at least equal to
 * the total number of cases across all 13 files": that bar assumes every
 * vector file is this harness's to drive. It is not -- 12 of the 13 files
 * bind entirely different schemas/reducers (task lifecycle, conflicts,
 * organizations, undo, ...) owned by Elixir. This lane instead uses the
 * SAME convention every other iOS lane in this directory uses (`cases` is
 * the count of executed XCTest test methods, via `xcodebuildSummary`) --
 * a lane that reports zero is still a hard failure, per D-45/D-46.
 */
export default function vectorConformanceLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/VectorConformanceTests',
    ],
    cwd: repositoryRoot,
    name: 'vector-conformance',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Sync',
      'apps/ios/Tests/KeeplingCoreTests/RepositoryRoot.swift',
      'apps/ios/Tests/KeeplingCoreTests/VectorConformanceTests.swift',
      'packages/contracts/schemas/sync-state-machine.schema.json',
      'packages/contracts/vectors/sync.json',
      'packages/contracts/vectors/manifest.json',
    ],
  }
}
