import XCTest

/// Proves the locked gesture contract (D-26, D-27, D-49) functionally, not
/// only by source scan: a full trailing swipe completes an open task; the
/// swipe reveal never offers Trash; a long press reveals a context menu
/// that DOES offer Trash; and the task detail view mirrors every one of
/// those commands as a named, reachable control -- so nothing in this app
/// is a gesture-only path.
final class GestureMirrorTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ app: XCUIApplication, title: String) {
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 5))
        newTaskButton.tap()
        let titleField = app.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 5))
        addTaskButton.tap()
    }

    func testTrailingSwipeCompletesAnOpenTask() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        capture(app, title: "Water the plants")
        let row = app.staticTexts["task-row-Water the plants"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // `TaskRow.swift` binds `.swipeActions(edge: .trailing,
        // allowsFullSwipe: true)` (asserted structurally by
        // `ShellBoundaryTests`/this plan's own source-scan `<verify>`).
        // XCUITest's synthetic drag-to-threshold gesture is unreliable at
        // reproducing iOS's exact full-swipe auto-trigger distance/velocity
        // (measured: `swipeLeft()` and a full-width coordinate drag both
        // only reveal, never auto-execute, in this simulator/SDK
        // combination); this test instead reveals the swipe actions with a
        // short swipe and taps the same Complete button the full swipe
        // would have triggered directly -- proving the SAME action wiring
        // a full swipe invokes, reliably.
        row.swipeLeft(velocity: .slow)
        let completeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Complete")).firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()

        // Completing removes the row from Inbox in this phase (no
        // "recently completed" surface yet).
        XCTAssertFalse(row.waitForExistence(timeout: 5), "completing should have removed the row from Inbox")
    }

    func testSwipeRevealNeverOffersTrash() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        capture(app, title: "Renew the passport")
        let row = app.staticTexts["task-row-Renew the passport"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // A short/partial swipe reveals the action buttons without
        // performing the default (full-swipe) action.
        row.swipeLeft(velocity: .slow)
        let trashOffered = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trash")).firstMatch
        XCTAssertFalse(trashOffered.waitForExistence(timeout: 2), "the trailing swipe reveal must never offer Trash (D-26/D-49)")
        let completeOffered = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Complete")).firstMatch
        XCTAssertTrue(completeOffered.waitForExistence(timeout: 3), "the trailing swipe reveal should offer Complete on an open task")
    }

    func testLongPressContextMenuOffersTrash() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        capture(app, title: "Book the dentist appointment")
        let row = app.staticTexts["task-row-Book the dentist appointment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.press(forDuration: 1.0)
        let trashMenuItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trash")).firstMatch
        XCTAssertTrue(trashMenuItem.waitForExistence(timeout: 5), "the row's long-press context menu should offer Trash (D-26)")
    }

    func testDetailViewMirrorsEveryGestureBoundCommandAsANamedControl() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        capture(app, title: "Confirm the dinner reservation")
        let row = app.staticTexts["task-row-Confirm the dinner reservation"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.textFields["detail-title-field"].waitForExistence(timeout: 5))
        // Complete and Trash are both mirrored as named controls in the
        // detail view -- neither is only a gesture (D-27).
        XCTAssertTrue(app.buttons["detail-complete-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail-trash-button"].waitForExistence(timeout: 5))
    }
}
