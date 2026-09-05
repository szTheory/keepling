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

    private func launch(state: String? = nil, undoAvailable: Bool = false, seedConflict: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        if let state { app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE"] = state }
        if undoAvailable { app.launchEnvironment["KEEPLING_UITEST_UNDO_AVAILABLE"] = "1" }
        if seedConflict { app.launchEnvironment["KEEPLING_UITEST_SEED_CONFLICT"] = "1" }
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

    // MARK: - Persistent overflow-menu `Sync & Recovery` row (D-39) -- present even when quiet

    func testOverflowMenuOffersSyncRecoveryRowEvenWhenHealthy() throws {
        let app = launch(state: "healthy")
        let overflow = app.buttons["overflow-menu"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5))
        overflow.tap()
        XCTAssertTrue(app.buttons["overflow-sync-recovery"].waitForExistence(timeout: 5))
    }

    func testOverflowMenuIsPresentOnBothTabs() throws {
        let app = launch(state: "healthy")
        XCTAssertTrue(app.buttons["overflow-menu"].waitForExistence(timeout: 5))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["overflow-menu"].waitForExistence(timeout: 5))
    }

    // MARK: - Sync & Recovery sheet: no-exceptions empty state, never a completeness claim

    func testSyncRecoverySheetShowsNoChangesEmptyStateWhenNothingNeedsAttention() throws {
        let app = launch(state: "healthy")
        app.buttons["overflow-menu"].tap()
        app.buttons["overflow-sync-recovery"].tap()
        XCTAssertTrue(app.staticTexts["sync-recovery-no-changes-heading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sync-recovery-no-changes-heading"].label, "No Changes Need Your Attention")
    }

    func testSyncRecoverySheetPresentsFullScreen() throws {
        let app = launch(state: "healthy")
        app.buttons["overflow-menu"].tap()
        app.buttons["overflow-sync-recovery"].tap()
        let navBar = app.navigationBars["Sync & Recovery"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5))
        // The presented content reaches the very top of the display,
        // right up to (not below) the status bar -- a `.sheet`'s "large
        // detent" card is always inset from the top edge by a visible
        // margin and rounded corners; `.fullScreenCover` (used here
        // instead of `.sheet`) is not.
        XCTAssertLessThan(navBar.frame.minY, 80, "full-screen presentation must not be inset from the top the way a card sheet is")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the root tab bar must not be reachable underneath a full-screen cover")
    }

    // MARK: - No navigation bar carries a persistent synchronization status glyph (D-40)

    func testNoNavigationBarContainsASynchronizationStatusGlyph() throws {
        let app = launch(state: "conflict")
        XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.images["sync-status-glyph"].exists)
        XCTAssertFalse(app.navigationBars.otherElements["sync-status-glyph"].exists)
    }

    // MARK: - A seeded per-task conflict lists in the sheet and deep-links both ways

    func testASeededConflictAppearsInlineAndInTheSyncRecoverySheetWithWorkingDeepLinks() throws {
        let app = launch(seedConflict: true)
        let exceptionRow = app.buttons["task-exception-Conflicted Task"]
        XCTAssertTrue(exceptionRow.waitForExistence(timeout: 10), "the seeded conflict must render its inline exception row")

        // Deep link forward: tapping the inline exception opens the sheet
        // at that entry.
        exceptionRow.tap()
        let sheetRow = app.staticTexts["sync-recovery-row-title-Conflicted Task"]
        XCTAssertTrue(sheetRow.waitForExistence(timeout: 5), "the sheet must list the seeded conflict")

        // Deep link onward: tapping the sheet's entry navigates to that
        // task's detail view.
        sheetRow.tap()
        XCTAssertTrue(app.textFields["detail-title-field"].waitForExistence(timeout: 5), "tapping the sheet entry must navigate to the task detail")
    }
}
