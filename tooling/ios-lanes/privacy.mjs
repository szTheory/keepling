/**
 * privacy lane (04-15-PLAN.md): runs both test classes this plan introduces
 * in one `xcodebuild` invocation -- `DiagnosticCoverageTests` (every
 * meaningful transition leaves a trace) and `DiagnosticPrivacyTests` (no
 * task content, credential, cursor, or fingerprint reaches any
 * diagnostic-adjacent surface) -- so one lane run proves the whole plan's
 * `<verify>` surface.
 */
export default function privacyLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/DiagnosticCoverageTests',
      '-only-testing:KeeplingCoreTests/DiagnosticPrivacyTests',
    ],
    cwd: repositoryRoot,
    name: 'privacy',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticEvent.swift',
      'apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticLog.swift',
      'apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticExport.swift',
      'apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Sources/KeeplingCore/Storage/StoreUnrecoverable.swift',
      'apps/ios/Sources/KeeplingCore/Presentation/AnnouncementDebouncer.swift',
      'apps/ios/Tests/KeeplingCoreTests/DiagnosticCoverageTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift',
    ],
  }
}
