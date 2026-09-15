/**
 * decode-roundtrip lane (04-05-PLAN.md Task 1): runs `DecodeRoundTripTests`
 * -- decode/round-trip proof over every wire-shaped fixture this plan's
 * scope reaches, plus the committed `Fixtures/nullable-coverage.json`
 * explicit-null corpus, and a round trip of every wire payload found IN
 * `packages/contracts/vectors/` itself. That last part used to be the
 * opposite assertion -- a tripwire proving the vector files contained ZERO
 * literal wire-DTO payloads, which was true when 04-05-SUMMARY.md disclosed
 * it. 05-11's `mcp-tools.json` made it false, the tripwire fired on the
 * first CI run that ever executed this lane, and the test now performs the
 * coverage it was holding a place for.
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
