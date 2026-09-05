import XCTest

/// Measures, on this Mac's pinned iOS SDK, whether `tabViewBottomAccessory`
/// can be made genuinely absent -- zero reserved frame, zero hit-testable
/// region -- for each of three named configurations plus a no-accessory
/// baseline (04-04-PLAN.md Task 1, closing 04-RESEARCH.md Open Question 1).
///
/// Every assertion here is on rendered geometry and hit-testability, never
/// on text content -- 04-RESEARCH.md Pitfall 1's exact false-green warning
/// is that a check on emptied *text* passes while an empty capsule visibly
/// persists. `AccessoryProbeRootView` hosts each configuration under a
/// launch-argument-selected probe scene reachable only via
/// `KEEPLING_ACCESSORY_PROBE_MODE`.
final class AccessoryAbsenceProbeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private struct Measurement {
        let markerExists: Bool
        let markerFrameHeight: CGFloat
        let markerFrameWidth: CGFloat
        let markerIsHittable: Bool
        let tabBarTopY: CGFloat
    }

    private func launchProbe(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_ACCESSORY_PROBE_MODE"] = mode
        app.launch()
        return app
    }

    private func measure(_ app: XCUIApplication) -> Measurement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "tab bar must exist to record its top edge")
        let marker = app.otherElements["accessory-marker"]
        let exists = marker.waitForExistence(timeout: 2)
        return Measurement(
            markerExists: exists,
            markerFrameHeight: exists ? marker.frame.height : 0,
            markerFrameWidth: exists ? marker.frame.width : 0,
            markerIsHittable: exists && marker.isHittable,
            tabBarTopY: tabBar.frame.minY
        )
    }

    private func hostabilityDescription(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["current-hostability"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return label.value as? String ?? label.label
    }

    // MARK: - Baseline

    func testBaselineHasNoAccessoryMarker() throws {
        let app = launchProbe(mode: "baseline")
        let result = measure(app)
        print("ACCESSORY_PROBE mode=baseline exists=\(result.markerExists) height=\(result.markerFrameHeight) width=\(result.markerFrameWidth) hittable=\(result.markerIsHittable) tabBarTopY=\(result.tabBarTopY)")
        XCTAssertFalse(result.markerExists, "baseline renders no accessory modifier at all")
    }

    // MARK: - Configuration 1: conditional content

    func testConditionalContentConfigurationMeasuresFrameAndHitRegion() throws {
        let baseline = measure(launchProbe(mode: "baseline"))
        let app = launchProbe(mode: "conditionalContent")
        let result = measure(app)
        print("ACCESSORY_PROBE mode=conditionalContent exists=\(result.markerExists) height=\(result.markerFrameHeight) width=\(result.markerFrameWidth) hittable=\(result.markerIsHittable) tabBarTopY=\(result.tabBarTopY) baselineTabBarTopY=\(baseline.tabBarTopY)")
        // Recorded, not asserted here: whether this configuration achieves
        // absence is exactly the open question this test measures. The
        // named outcome lives in AccessoryHostability.swift and is pinned
        // as a permanent regression by testNamedAchievedConfigurationStaysAbsent below.
    }

    // MARK: - Configuration 2: conditional modifier

    func testConditionalModifierConfigurationAchievesAbsenceByOmittingTheModifier() throws {
        let baseline = measure(launchProbe(mode: "baseline"))
        let app = launchProbe(mode: "conditionalModifier")
        let result = measure(app)
        print("ACCESSORY_PROBE mode=conditionalModifier exists=\(result.markerExists) height=\(result.markerFrameHeight) width=\(result.markerFrameWidth) hittable=\(result.markerIsHittable) tabBarTopY=\(result.tabBarTopY) baselineTabBarTopY=\(baseline.tabBarTopY)")
        XCTAssertFalse(result.markerExists, "omitting the modifier entirely must not create an accessory element")
        XCTAssertEqual(result.markerFrameHeight, 0)
        XCTAssertFalse(result.markerIsHittable)
        XCTAssertEqual(result.tabBarTopY, baseline.tabBarTopY, accuracy: 1.0, "omitting the modifier must not shift the tab bar's top edge relative to the no-accessory baseline")
    }

    // MARK: - Configuration 3: isEnabled parameter

    func testIsEnabledParameterConfigurationMeasuresFrameAndHitRegion() throws {
        let baseline = measure(launchProbe(mode: "baseline"))
        let app = launchProbe(mode: "isEnabledParameter")
        let result = measure(app)
        print("ACCESSORY_PROBE mode=isEnabledParameter exists=\(result.markerExists) height=\(result.markerFrameHeight) width=\(result.markerFrameWidth) hittable=\(result.markerIsHittable) tabBarTopY=\(result.tabBarTopY) baselineTabBarTopY=\(baseline.tabBarTopY)")
        // The `isEnabled:` overload exists on this SDK (confirmed by
        // direct inspection of SwiftUI.swiftinterface for iOS SDK 26.5:
        // `tabViewBottomAccessory<Content>(isEnabled:content:)`, available
        // iOS 26.1+) so this configuration always exercises the real
        // overload on this build -- there is no "overload absent" branch
        // to record for this SDK.
    }

    // MARK: - Permanent regression on the named achieving configuration

    /// Reads `AccessoryHostability`'s own declared capability from the app
    /// (via an accessibility value, since a UI test bundle cannot `import`
    /// the app target's module) and pins its measured outcome as a
    /// permanent regression: if absence is achievable, the named
    /// configuration must keep measuring a nonexistent/zero-frame,
    /// non-hittable marker; if not achievable, the day a future SDK fixes
    /// it this assertion flips and prompts picking up the fix.
    func testNamedAchievedConfigurationStaysAbsent() throws {
        let probeApp = launchProbe(mode: "baseline")
        let description = hostabilityDescription(probeApp)
        print("ACCESSORY_PROBE currentHostability=\(description)")

        let parts = description.split(separator: ":").map(String.init)
        XCTAssertFalse(parts.isEmpty, "AccessoryHostability.probeDescription must not be empty")

        switch parts.first {
        case "absenceAchievable":
            guard parts.count >= 2 else {
                XCTFail("absenceAchievable description missing configuration: \(description)")
                return
            }
            let app = launchProbe(mode: parts[1])
            let result = measure(app)
            print("ACCESSORY_PROBE regression mode=\(parts[1]) exists=\(result.markerExists) height=\(result.markerFrameHeight) hittable=\(result.markerIsHittable)")
            XCTAssertFalse(result.markerExists, "the named achieving configuration (\(parts[1])) regressed to a present accessory element")
            XCTAssertEqual(result.markerFrameHeight, 0)
            XCTAssertFalse(result.markerIsHittable)

        case "absenceNotAchievable":
            let app = launchProbe(mode: "conditionalContent")
            let result = measure(app)
            print("ACCESSORY_PROBE regression (not-achievable check) mode=conditionalContent exists=\(result.markerExists) height=\(result.markerFrameHeight)")
            XCTAssertTrue(
                result.markerExists && result.markerFrameHeight > 0,
                "absence was recorded as not-achievable, but conditionalContent now measures a zero/nonexistent marker -- re-run Task 1's measurement and update AccessoryHostability.swift"
            )

        default:
            XCTFail("unrecognized AccessoryHostability.probeDescription: \(description)")
        }
    }
}
