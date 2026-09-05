/**
 * durability-posture lane (04-06-PLAN.md): the two D-04 durability gates
 * the tracer (04-01) and the storage-gates plan (04-02) left open --
 * settlement (G8) and at-rest posture (G7) -- plus the D-09 adversarial
 * proof that a hand-restored store cannot double-apply an accepted
 * command or cross an account namespace fence. Kept as its own named lane
 * (distinct from `storage-gates`) so a regression here is never masked by
 * the broader `StorageTests` suite passing for unrelated reasons.
 */
export default function durabilityPostureLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:StorageTests/SettlementTests',
      '-only-testing:StorageTests/DurableUnitTests',
      '-only-testing:StorageTests/BackupReplayTests',
      '-only-testing:StorageTests/DataProtectionTests',
    ],
    cwd: repositoryRoot,
    name: 'durability-posture',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Sources/KeeplingCore/Storage/DurableUnit.swift',
      'apps/ios/Tests/StorageTests/SettlementTests.swift',
      'apps/ios/Tests/StorageTests/DurableUnitTests.swift',
      'apps/ios/Tests/StorageTests/BackupReplayTests.swift',
      'apps/ios/Tests/StorageTests/DataProtectionTests.swift',
      'apps/desktop/store-worker/local-store.ts',
      'apps/desktop/main/application/DesktopApplication.ts',
    ],
  }
}
