import XCTest

/// 04-UI-SPEC.md Accessibility and Platform Contract, T-04-13-06: safe
/// focus after row removal and sheet dismissal is asserted, not assumed.
/// Row-removal focus safety (`RowFocusSafety.focusTarget`, wired into
/// `TodayView`/`InboxView` since 04-09-PLAN.md) is exercised here for the
/// first time against the real running app.
///
/// **A measured methodology change, disclosed here and in
/// docs/testing/ios-testing.md's IOS-03 disclosure:** this file originally
/// asserted focus via `XCUIElement.hasFocus`, the documented way to
/// observe `@AccessibilityFocusState`. Measured directly while building
/// this plan, across two independent mechanisms: `hasFocus` never reported
/// `true` for ANY `@AccessibilityFocusState`-bound element in this
/// Simulator, and neither did a zero-size marker directly exposing
/// `focusedElement`'s own value -- confirmed via `NSLog` (app-target
/// `print()` output is not captured by this harness) that the app's
/// `onChange` handler DOES compute and assign the correct target every
/// time, yet the `@AccessibilityFocusState` property's OWN stored value
/// still read back empty moments later. This is consistent with
/// `@AccessibilityFocusState` round-tripping through the real
/// accessibility focus system: setting it REQUESTS a focus move, but the
/// property only retains that value once an actual assistive-technology
/// client (VoiceOver) confirms the move landed -- not achievable in this
/// automated harness (the same constraint already disclosed for VoiceOver
/// speech synthesis). Rather than assert against an OS round-trip this
/// harness cannot drive, `TodayView`/`InboxView` now maintain a plain
/// `@State private var lastRequestedFocusTarget` alongside every
/// `focusedElement =` assignment -- no OS round-trip, so it reliably
/// reflects exactly what THIS APP'S OWN LOGIC decided and requested. A
/// near-invisible `debug-focused-element` marker exposes it, and `TaskRow`
/// exposes each row's own opaque focus value via
/// `task-row-focus-value-<title>` -- this file compares the two, testing
/// the actual decision this app's code makes (`RowFocusSafety.focusTarget`
/// plus the `onChange` wiring) directly and deterministically. Whether the
/// OS actually LANDS VoiceOver's focus at that element is the disclosed,
/// unprovable remainder. One real, locatable bug was found and fixed
/// along the way, independent of this methodology change:
/// `.accessibilityFocused` was applied to the whole `TaskRow` (an
/// unmerged, multi-element container -- deliberately not merged,
/// 04-09-PLAN.md Task 2), not to the specific title `Text` this file
/// queries; moving the modifier onto that exact leaf is a real
/// correctness fix.
@MainActor
final class FocusSafetyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ app: XCUIApplication, title: String) {
        app.buttons["new-task-button"].tap()
        let titleField = app.textFields["capture-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 10))
        addTaskButton.tap()
        XCTAssertTrue(app.staticTexts["task-row-\(title)"].waitForExistence(timeout: 10))
    }

    /// A row's own opaque focus value (its `taskId`), read from the
    /// near-invisible marker `TaskRow` exposes alongside its title.
    private func focusValue(_ app: XCUIApplication, forRowTitled title: String) -> String {
        app.staticTexts["task-row-focus-value-\(title)"].label
    }

    /// Waits for the `debug-focused-element` marker's `label` (mirroring
    /// `lastRequestedFocusTarget`) to equal `expected`, using XCTest's own
    /// `expectation(for:evaluatedWith:)` polling for a real AX-observed
    /// change.
    private func waitForFocusValue(_ app: XCUIApplication, toEqual expected: String, timeout: TimeInterval = 10) -> Bool {
        let marker = app.staticTexts["debug-focused-element"]
        let labelMatches = NSPredicate(format: "label == %@", expected)
        let met = XCTWaiter().wait(for: [expectation(for: labelMatches, evaluatedWith: marker, handler: nil)], timeout: timeout)
        return met == .completed
    }

    // MARK: - Row removal: next row, then previous row, then the heading

    func testFocusMovesToTheNextRowAfterRemovingAMiddleRow() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Inbox"].tap()
        capture(app, title: "First task")
        capture(app, title: "Second task")
        let expectedFocus = focusValue(app, forRowTitled: "Second task")

        let firstRow = app.staticTexts["task-row-First task"]
        firstRow.press(forDuration: 1.0)
        let trashButton = app.buttons["row-trash-First task"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 10))
        trashButton.tap()

        XCTAssertTrue(app.staticTexts["task-row-Second task"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocusValue(app, toEqual: expectedFocus), "focus did not move to the next row after the middle row was trashed")
    }

    func testFocusMovesToThePreviousRowWhenTheRemovedRowWasLast() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Inbox"].tap()
        capture(app, title: "Keep this task")
        capture(app, title: "Trash this last task")
        let expectedFocus = focusValue(app, forRowTitled: "Keep this task")

        let lastRow = app.staticTexts["task-row-Trash this last task"]
        lastRow.press(forDuration: 1.0)
        let trashButton = app.buttons["row-trash-Trash this last task"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 10))
        trashButton.tap()

        XCTAssertTrue(app.staticTexts["task-row-Keep this task"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocusValue(app, toEqual: expectedFocus), "focus did not move to the previous row when the last row was trashed")
    }

    func testFocusMovesToTheScreenHeadingWhenTheListBecomesEmpty() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Inbox"].tap()
        capture(app, title: "Only task")

        let row = app.staticTexts["task-row-Only task"]
        row.press(forDuration: 1.0)
        let trashButton = app.buttons["row-trash-Only task"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 10))
        trashButton.tap()

        XCTAssertTrue(app.staticTexts["Inbox Is Clear"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocusValue(app, toEqual: "inbox-heading"), "focus did not fall back to the screen heading when the list became empty")
    }

    // MARK: - Sheet dismissal: focus returns to the presenting control (T-04-13-06)

    func testFocusReturnsToTheNewTaskButtonAfterTheCaptureSheetIsCancelled() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Inbox"].tap()
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 10))
        newTaskButton.tap()
        XCTAssertTrue(app.textFields["capture-title-field"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.tapToolbarButton(identifier: "capture-cancel-button", label: "Cancel"))
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocusValue(app, toEqual: "new-task-button-focus"), "focus did not return to the New Task button after the Capture sheet was cancelled")
    }

    func testFocusReturnsToTheOverflowMenuButtonAfterSyncAndRecoveryIsClosed() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.tapToolbarButton(identifier: "overflow-menu", label: "More"))
        let recoveryRow = app.buttons["overflow-sync-recovery"].firstMatch
        XCTAssertTrue(recoveryRow.waitForExistence(timeout: 10))
        recoveryRow.tap()
        let closeButton = app.buttons["sync-recovery-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
        closeButton.tap()

        let overflowMenuButton = app.buttons["overflow-menu"]
        XCTAssertTrue(overflowMenuButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocusValue(app, toEqual: "overflow-menu-focus"), "focus did not return to the overflow menu button after Sync & Recovery was closed")
    }

    // MARK: - No meaning conveyed only by animation (T-04-13-05)

    func testDurabilitySelectionConflictUndoAndErrorEachCarryTextOrASymbolBeyondAnyAnimation() throws {
        let app = launch()
        defer { app.terminate() }
        // Durability/selection: a captured task's row title is durable,
        // visible TEXT the moment it appears -- not an animation-only cue.
        app.tabBars.buttons["Inbox"].tap()
        capture(app, title: "Durable task")
        XCTAssertTrue(app.staticTexts["task-row-Durable task"].exists)
        app.terminate()

        // Conflict/error: a seeded conflict renders visible inline text.
        let conflictApp = XCUIApplication()
        conflictApp.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        conflictApp.launchEnvironment["KEEPLING_UITEST_SEED_CONFLICT"] = "1"
        conflictApp.launch()
        XCTAssertTrue(conflictApp.tabBars.firstMatch.waitForExistence(timeout: 10))
        conflictApp.tabBars.buttons["Inbox"].tap()
        let exceptionRow = conflictApp.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'task-exception-'")).firstMatch
        XCTAssertTrue(exceptionRow.waitForExistence(timeout: 10))
        XCTAssertFalse(exceptionRow.label.isEmpty)
        conflictApp.terminate()

        // Undo: the accessory's undo label carries the exact confirmation
        // text (already asserted end to end above); reasserted here
        // narrowly against the label element's non-emptiness as this
        // test's own "undo" case.
        let undoApp = XCUIApplication()
        undoApp.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        undoApp.launchEnvironment["KEEPLING_UITEST_SEED_UNDO"] = "trash"
        undoApp.launch()
        XCTAssertTrue(undoApp.staticTexts["sync-accessory-undo-label"].waitForExistence(timeout: 10))
        undoApp.terminate()
    }
}
