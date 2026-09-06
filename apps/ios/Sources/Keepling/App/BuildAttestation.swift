import SwiftUI

/// D-21: what binds a physical-device evidence run to the exact bytes that
/// produced it.
///
/// iOS artifacts are **not byte-reproducible** -- the CMS code signature
/// carries a signing timestamp and a per-build nonce, so two builds of
/// identical source hash differently no matter how hermetic the inputs
/// are. That is a property of Apple's signing format, not a packaging
/// defect of the kind Plan 03-25 correctly fixed for the Electron app, and
/// it cannot be engineered away from outside Apple. So identity here is
/// proven by **attestation** instead: `tooling/build-ios-signed.mjs`
/// computes a digest over the build's real source inputs, injects it into
/// `Info.plist` as `KeeplingBuildDigest` at build time, and this type reads
/// it back **out of the running process on the phone**.
///
/// The read-back is what makes stale evidence *refusable* rather than
/// merely unlikely: `tooling/ios-device/attestation.mjs` refuses the whole
/// lane when the value this type reports does not match the build manifest,
/// before a single test runs (T-04-16-01).
///
/// Three independent channels carry the same value out of the process,
/// because each is readable by a different consumer:
///
///  1. **stdout** -- captured by `devicectl device process launch --console`.
///     This is a read from the *process*, not from the installed bundle on
///     disk: a tampered-with or stale bundle cannot answer for a process it
///     is not running.
///  2. **a file in the app's own container** -- copied back off the device
///     with `devicectl device copy from`, an independent confirmation that
///     does not depend on console capture timing.
///  3. **an accessibility element** -- so `DeviceCoreLoopTests` /
///     `DeviceRecoveryTests` can bind *their own* evidence to the digest.
///     `xcodebuild test` reinstalls the app it just built, so a UI-test run
///     is a different installation event from the lane's own attestation
///     and needs its own binding.
enum BuildAttestation {

    /// The accessibility identifier the device UI suites query. Rendered
    /// only when the launch environment asks for it, so no existing
    /// simulator suite, snapshot, or accessibility audit sees a new
    /// element.
    static let probeIdentifier = "build-attestation-digest"

    /// The launch-environment key the device lane sets to render the probe.
    static let probeEnvironmentKey = "KEEPLING_DEVICE_ATTESTATION_PROBE"

    /// The single line `attestation.mjs` greps out of the console stream.
    static let consolePrefix = "KEEPLING_BUILD_ATTESTATION"

    /// The filename written into the app container for channel 2.
    static let receiptFilename = "build-attestation.json"

    /// The digest compiled into this build, read from the running
    /// process's own bundle. `nil` only if the Info.plist key is missing
    /// entirely -- which is itself a refusable condition, never a pass.
    static var digest: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KeeplingBuildDigest") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "unknown" }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Emits channels 1 and 2. Called once per launch.
    ///
    /// The explicit `fflush` is not decoration: stdout is fully buffered
    /// when it is not a terminal, and `devicectl --console` is a pipe. A
    /// line left sitting in the buffer would read to the lane exactly like
    /// a build that carries no digest at all -- an attestation channel that
    /// silently fails closed is fine, but one that silently fails *open*
    /// would be worse than none, so the value is flushed the moment it is
    /// written.
    static func emit() {
        let reportedDigest = digest ?? "absent"
        print("\(consolePrefix) digest=\(reportedDigest) bundle=\(bundleIdentifier) short_version=\(shortVersion) build_version=\(buildVersion)")
        fflush(stdout)
        writeReceipt(digest: reportedDigest)
    }

    private static func writeReceipt(digest: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let payload: [String: Any] = [
            "bundleIdentifier": bundleIdentifier,
            "buildVersion": buildVersion,
            "keeplingBuildDigest": digest,
            "observedAt": ISO8601DateFormatter().string(from: Date()),
            "shortVersion": shortVersion,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent(receiptFilename), options: .atomic)
    }
}

/// Channel 3. Attached once, at the app's root, in `KeeplingApp`.
///
/// The probe element is a zero-opacity, layout-neutral `Text` in an
/// `overlay` -- it adds no frame, reserves no space, and is only present at
/// all when `KEEPLING_DEVICE_ATTESTATION_PROBE` is set, which only the
/// device lane sets. `.allowsHitTesting(false)` keeps it out of every
/// gesture path, and because it is an overlay rather than a wrapper it
/// cannot collapse a child's accessibility identifiers the way a container
/// identifier does (the failure mode `RootTabView.loadingOverlay` already
/// documents from measurement).
struct BuildAttestationProbe: ViewModifier {
    private var probeRequested: Bool {
        ProcessInfo.processInfo.environment[BuildAttestation.probeEnvironmentKey] == "1"
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if probeRequested {
                    Text(BuildAttestation.digest ?? "absent")
                        .font(.system(size: 1))
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier(BuildAttestation.probeIdentifier)
                }
            }
            .onAppear { BuildAttestation.emit() }
    }
}

extension View {
    /// Applies the read-back attestation channels (D-21).
    func buildAttestationProbe() -> some View { modifier(BuildAttestationProbe()) }
}
