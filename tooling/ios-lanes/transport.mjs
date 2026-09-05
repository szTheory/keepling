/**
 * transport lane (04-05-PLAN.md Task 2/3): runs the wire-client test
 * classes -- `RefusalClassificationTests` (the closed unreachable/refused
 * classification table), `TransportGuardTests` (the HTTPS-only guard), and
 * `WireMapperBoundaryTests` (the generated-DTO-never-reaches-persistence
 * structural scan). `DecodeRoundTripTests` has its own `decode-roundtrip`
 * lane -- kept separate so a failure in one is never masked by a pass in
 * the other.
 */
export default function transportLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/RefusalClassificationTests',
      '-only-testing:KeeplingCoreTests/TransportGuardTests',
      '-only-testing:KeeplingCoreTests/WireMapperBoundaryTests',
    ],
    cwd: repositoryRoot,
    name: 'transport',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Transport',
      'apps/ios/Tests/KeeplingCoreTests/RepositoryRoot.swift',
      'apps/ios/Tests/KeeplingCoreTests/RefusalClassificationTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/TransportGuardTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/WireMapperBoundaryTests.swift',
      'packages/contracts/openapi/keepling.yaml',
      'apps/desktop/main/adapters/server-refusal.ts',
      'apps/desktop/main/adapters/sync.ts',
    ],
  }
}
