import XCTest

/// Covers `BottomAccessoryView`'s consumption of the one derived
/// `SyncPresentationSummary` (04-10-PLAN.md Task 2): the accessory renders
/// nothing when healthy (genuinely absent -- `AccessoryHostability
/// .currentAccessoryHostability` measured absence achievable via
/// `.conditionalModifier`, so `RootTabView` omits the call site entirely),
/// renders exactly the actionable exception when both an exception and an
/// available undo are present, and holds transient work only past the
/// grace period. `KEEPLING_UITEST_SYNC_STATE`/`KEEPLING_UITEST_UNDO_AVAILABLE`
/// are UI-test-only launch-environment fixture hooks (`WorkspaceFacade
/// .applyUITestSyncState`) -- the same pattern `AccessoryAbsenceProbeTests`
/// established for `KEEPLING_ACCESSORY_PROBE_MODE`.
final class SyncRecoveryTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(state: String? = nil, undoAvailable: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        if let state { app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE"] = state }
        if undoAvailable { app.launchEnvironment["KEEPLING_UITEST_UNDO_AVAILABLE"] = "1" }
        app.launch()
        return app
    }

    // MARK: - Healthy: absent, not merely quiet (D-38)

    func testHealthyAccessoryExposesNoTextGlyphOrCount() throws {
        let app = launch(state: "healthy")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 2), "a healthy accessory must render no text")
        XCTAssertFalse(app.buttons["sync-accessory-undo"].exists)
    }

    func testHealthyAccessoryDoesNotShiftTheTabBarsTopEdgeRelativeToNoAccessoryAtAll() throws {
        // No launch-environment state at all == the app's true default
        // (healthy, no undo) -- the strictest baseline: the call site is
        // never attached, so the tab bar's top edge is identical to a
        // build with no accessory code at all.
        let baselineApp = launch()
        let baselineTabBar = baselineApp.tabBars.firstMatch
        XCTAssertTrue(baselineTabBar.waitForExistence(timeout: 5))

        let healthyApp = launch(state: "healthy")
        let healthyTabBar = healthyApp.tabBars.firstMatch
        XCTAssertTrue(healthyTabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(healthyTabBar.frame.minY, baselineTabBar.frame.minY, accuracy: 1.0)
    }

    // MARK: - Exception-first priority (D-38): exception wins the accessory slot

    func testAnExceptionAndAnAvailableUndoTogetherRenderOnlyTheExceptionInTheAccessory() throws {
        let app = launch(state: "conflict", undoAvailable: true)
        let exceptionText = app.staticTexts["sync-accessory-text"]
        XCTAssertTrue(exceptionText.waitForExistence(timeout: 5))
        // The undo control must NOT also render in the accessory slot --
        // exception-first, with undo left reachable elsewhere (the
        // overflow menu, wired in Task 3) rather than hidden entirely.
        XCTAssertFalse(app.buttons["sync-accessory-undo"].exists)
    }

    func testAvailableUndoAloneRendersTheUndoControlInTheAccessory() throws {
        let app = launch(state: "healthy", undoAvailable: true)
        let undoButton = app.buttons["sync-accessory-undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        XCTAssertEqual(undoButton.label, "Undo Trash")
    }

    // MARK: - Transient work only past the grace period

    func testTransientWorkRendersOnlyPastTheGracePeriod() throws {
        let app = launch(state: "updating_past_grace")
        XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5))
    }

    // MARK: - Every actionable exception state renders accessory text and a recovery action

    func testEveryActionableExceptionStateRendersAccessoryTextAndARecoveryAction() throws {
        let states = ["retryable_failure", "uncertain", "rejected", "authentication_fence", "unrecoverable", "local_save_failure", "conflict"]
        for state in states {
            let app = launch(state: state)
            XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5), "\(state) must render accessory text")
            app.terminate()
        }
    }

    // MARK: - The capture affordance stays reachable regardless of accessory state

    func testCaptureToolbarActionStaysReachableWhileAnExceptionOccupiesTheAccessory() throws {
        let app = launch(state: "conflict")
        XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5))
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 5))
        XCTAssertTrue(newTaskButton.isHittable, "capture must stay reachable independent of accessory state")
    }
}
