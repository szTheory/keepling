import Foundation

/// Which of the probe's named `tabViewBottomAccessory` configurations
/// achieves genuine layout/hit-test absence, if any (04-04-PLAN.md Task 1).
/// `Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift` is the
/// executable measurement this case set names; `AccessoryProbeRootView`
/// hosts each configuration under a launch-argument-selected probe scene.
public enum AccessoryAbsenceConfiguration: String, Equatable, Sendable, CaseIterable {
    /// The `.tabViewBottomAccessory { }` modifier is always applied; its
    /// content closure conditionally renders nothing when healthy.
    case conditionalContent

    /// The `.tabViewBottomAccessory { }` modifier itself is applied only
    /// when the state warrants it -- absent from the view tree entirely
    /// when healthy, not merely emptied.
    case conditionalModifier

    /// The `.tabViewBottomAccessory(isEnabled:content:)` overload (iOS
    /// 26.1+) is always applied with `isEnabled: false` when healthy.
    case isEnabledParameter
}

/// The single named capability value Plan 04-10 reads to decide how to
/// render synchronization state (D-38, D-40) -- one place, not scattered
/// conditionals. Exactly two cases, each carrying the measured SDK version
/// string this session's measurement ran against.
public enum AccessoryHostability: Equatable, Sendable {
    /// Absence is achievable via the named configuration, measured on
    /// `measuredSDKVersion`.
    case absenceAchievable(via: AccessoryAbsenceConfiguration, measuredSDKVersion: String)

    /// No configuration achieves absence on `measuredSDKVersion`. The
    /// fallback is an empty, non-interactive, accessibility-hidden strip
    /// carrying no text, glyph, or count -- never a repurposed healthy
    /// status badge (D-40).
    case absenceNotAchievable(measuredSDKVersion: String)

    /// A short, stable string this scene exposes as an accessibility value
    /// so `AccessoryAbsenceProbeTests`' permanent regression test can read
    /// the app's own declared capability without cross-process imports
    /// (a UI test bundle cannot `import` the app target's module).
    public var probeDescription: String {
        switch self {
        case let .absenceAchievable(configuration, sdkVersion):
            "absenceAchievable:\(configuration.rawValue):\(sdkVersion)"
        case let .absenceNotAchievable(sdkVersion):
            "absenceNotAchievable:\(sdkVersion)"
        }
    }
}

/// Measured 2026-09-04 on this Mac's pinned Xcode 26.6 / iOS SDK 26.5
/// (`xcrun --sdk iphoneos --show-sdk-version`), against the iPhone 17
/// simulator, per `AccessoryAbsenceProbeTests`. See
/// `docs/testing/ios-testing.md` for the full measured numbers and, if
/// applicable, the disclosure this constant's `.absenceNotAchievable` case
/// requires.
public let currentAccessoryHostability = AccessoryHostability.absenceAchievable(
    via: .conditionalModifier,
    measuredSDKVersion: "26.5"
)
