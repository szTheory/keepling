/**
 * app-intents lane (04-12-PLAN.md): runs all three test classes this plan
 * introduces in one `xcodebuild` invocation -- `CaptureIntentTests`,
 * `CompleteIntentTests` (both AppIntentsTests), and `IntentPrivacyTests`
 * (D-23/D-36 on the App Intents surface) -- so one lane run proves the
 * whole plan's `<verify>` surface: Capture and Complete driven through the
 * one shared in-process store handle, and no credential/token/cursor/
 * fingerprint or deferred-surface leak.
 */
export default function appIntentsLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:AppIntentsTests/CaptureIntentTests',
      '-only-testing:AppIntentsTests/CompleteIntentTests',
      '-only-testing:AppIntentsTests/IntentPrivacyTests',
    ],
    cwd: repositoryRoot,
    name: 'app-intents',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift',
      'apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift',
      'apps/ios/Sources/KeeplingCore/AppIntents/KeeplingShortcuts.swift',
      'apps/ios/Sources/KeeplingCore/AppIntents/IntentStoreAccess.swift',
      'apps/ios/Sources/KeeplingCore/Application/OutboundCommands.swift',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift',
      'apps/ios/Sources/KeeplingCore/Auth/KeychainCredentialStore.swift',
      'apps/ios/Sources/Keepling/App/KeeplingApp.swift',
      'apps/ios/Tests/AppIntentsTests/CaptureIntentTests.swift',
      'apps/ios/Tests/AppIntentsTests/CompleteIntentTests.swift',
      'apps/ios/Tests/AppIntentsTests/IntentPrivacyTests.swift',
    ],
  }
}
