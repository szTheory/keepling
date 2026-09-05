/**
 * auth lane (04-07-PLAN.md): runs the native device-grant identity test
 * classes -- `DeviceGrantTests` (PKCE exchange, rotation, replay/
 * authentication-required classification), `CredentialStoreTests`
 * (Keychain accessibility, before-first-unlock, and the full-cycle leak
 * scan), `NamespaceFencingTests` (server-only namespace activation and
 * account-switch fencing), and `SignOutFenceTests` (sign-out ordering and
 * structurally transport-free local-data removal).
 */
export default function authLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingCoreTests/DeviceGrantTests',
      '-only-testing:KeeplingCoreTests/CredentialStoreTests',
      '-only-testing:KeeplingCoreTests/NamespaceFencingTests',
      '-only-testing:StorageTests/SignOutFenceTests',
    ],
    cwd: repositoryRoot,
    name: 'auth',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Package.swift',
      'apps/ios/Sources/KeeplingCore/Auth',
      'apps/ios/Sources/Keepling/Auth',
      'apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift',
      'apps/ios/Tests/KeeplingCoreTests/DeviceGrantTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/CredentialStoreTests.swift',
      'apps/ios/Tests/KeeplingCoreTests/NamespaceFencingTests.swift',
      'apps/ios/Tests/StorageTests/SignOutFenceTests.swift',
      'packages/contracts/openapi/keepling.yaml',
      'apps/server/lib/keepling/accounts/device_grant.ex',
      'apps/server/config/runtime.exs',
    ],
  }
}
