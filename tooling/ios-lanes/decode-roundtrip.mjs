/**
 * decode-roundtrip lane (04-05-PLAN.md Task 1): runs `DecodeRoundTripTests`
 * -- decode/round-trip proof over every wire-shaped fixture this plan's
 * scope reaches, plus the committed `Fixtures/nullable-coverage.json`
 * explicit-null corpus and the structural proof that the 13 files under
 * `packages/contracts/vectors/` contain zero literal wire-DTO payloads
 * (04-05-SUMMARY.md discloses why the corpus lives in this test file's own
 * fixtures rather than the vectors directory).
 */
export default function decodeRoundtripLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/DecodeRoundTripTests',
    ],
    cwd: repositoryRoot,
    name: 'decode-roundtrip',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Transport/Generated',
      'apps/ios/Tests/KeeplingCoreTests/RepositoryRoot.swift',
      'apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json',
      'packages/contracts/openapi/keepling.yaml',
      'packages/contracts/vectors',
    ],
  }
}
