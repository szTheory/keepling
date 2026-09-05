/**
 * AccessoryAbsenceProbeTests: the measured answer to whether
 * `tabViewBottomAccessory` can be genuinely absent on this Mac's pinned
 * SDK, plus the permanent regression on the named achieving configuration
 * (04-04-PLAN.md Task 1).
 */
export default function accessoryProbeLane({ repositoryRoot, xcodebuildSummary }) {
  return {
    command: 'xcodebuild',
    args: [
      'test',
      '-project', 'apps/ios/Keepling.xcodeproj',
      '-scheme', 'Keepling',
      '-destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest',
      '-only-testing:KeeplingUITests/AccessoryAbsenceProbeTests',
    ],
    cwd: repositoryRoot,
    name: 'accessory-probe',
    parse: xcodebuildSummary,
    trackedInputPaths: [
      'apps/ios/project.yml',
      'apps/ios/Sources/Keepling/App',
      'apps/ios/Sources/Keepling/SyncRecovery',
      'apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift',
    ],
  }
}
