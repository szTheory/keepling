import SwiftUI

/// Which named configuration (or the no-accessory baseline) this probe
/// launch renders. Selected exclusively by the
/// `KEEPLING_ACCESSORY_PROBE_MODE` launch-environment variable, which only
/// `AccessoryAbsenceProbeTests`' launch configuration sets (04-04-PLAN.md
/// Task 1, threat T-04-04-03: unreachable without that variable, so this
/// scene is never reachable in ordinary use).
public enum AccessoryProbeMode: String {
    /// No `tabViewBottomAccessory` modifier applied at all -- the
    /// comparison baseline every configuration's tab-bar top edge is
    /// measured against.
    case baseline
    case conditionalContent
    case conditionalModifier
    case isEnabledParameter

    init?(environment: [String: String]) {
        guard let raw = environment["KEEPLING_ACCESSORY_PROBE_MODE"] else { return nil }
        self.init(rawValue: raw)
    }
}

/// Hosts a minimal two-tab `TabView` under each of the three named
/// `tabViewBottomAccessory` configurations plus a no-accessory baseline, so
/// `AccessoryAbsenceProbeTests` can measure rendered geometry and
/// hit-testability rather than trusting an assumption (04-RESEARCH.md
/// Pitfall 1's exact false-green warning: a check on emptied *text*
/// content passes even while an empty capsule visibly persists).
public struct AccessoryProbeRootView: View {
    let mode: AccessoryProbeMode

    public init(mode: AccessoryProbeMode) {
        self.mode = mode
    }

    public var body: some View {
        TabView {
            Tab("First", systemImage: "1.circle") {
                probeContent
            }
            Tab("Second", systemImage: "2.circle") {
                probeContent
            }
        }
        .modifier(AccessoryProbeModifier(mode: mode))
    }

    private var probeContent: some View {
        VStack {
            Text("Probe scene")
            // Exposes AccessoryHostability's own declared capability as an
            // accessibility value so the UI test (a separate process that
            // cannot `import Keepling`) can read the single named constant
            // rather than duplicating its logic.
            Text(currentAccessoryHostability.probeDescription)
                .accessibilityIdentifier("current-hostability")
                .accessibilityValue(currentAccessoryHostability.probeDescription)
        }
    }
}

/// The marker placed inside the accessory content closure for every
/// non-baseline configuration. `.frame(maxWidth: .infinity, maxHeight:
/// .infinity)` imposes no size of its own: the frame
/// `AccessoryAbsenceProbeTests` measures on `accessory-marker` reflects
/// exactly what the accessory container allocates, never a size this view
/// chooses -- the frame/hit-region measurement 04-RESEARCH.md's Pitfall 1
/// requires, as opposed to a text-content check.
private struct AccessoryMarker: View {
    let showsVisibleContent: Bool

    var body: some View {
        ZStack {
            if showsVisibleContent {
                Text("Status").accessibilityIdentifier("accessory-visible-text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("accessory-marker")
    }
}

private struct AccessoryProbeModifier: ViewModifier {
    let mode: AccessoryProbeMode

    func body(content: Content) -> some View {
        switch mode {
        case .baseline:
            content

        case .conditionalContent:
            // Configuration 1: the modifier is always applied; content
            // conditionally renders nothing when healthy (the shape
            // 04-RESEARCH.md Pitfall 1 names as reproducing the defect).
            content.tabViewBottomAccessory {
                AccessoryMarker(showsVisibleContent: false)
            }

        case .conditionalModifier:
            // Configuration 2: the modifier itself is applied only when
            // state warrants it. This probe's healthy state never
            // warrants it, so the modifier is absent from the view tree
            // entirely here, not merely emptied.
            content

        case .isEnabledParameter:
            // Configuration 3: the modifier is always applied, but with
            // `isEnabled: false` when healthy. The overload requires iOS
            // 26.1+; if unavailable, fall back to no accessory and the
            // regression test's `#available` gate records that explicitly
            // rather than silently skipping the case.
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled: false) {
                    AccessoryMarker(showsVisibleContent: true)
                }
            } else {
                content
            }
        }
    }
}
