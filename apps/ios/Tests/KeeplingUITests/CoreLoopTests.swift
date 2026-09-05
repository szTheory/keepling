import XCTest

/// Drives the full supported daily loop end to end on the simulator
/// (04-09-PLAN.md Task 2): capture, appearance in Inbox, open, edit, save,
/// complete, reopen, trash, and restore.
///
/// Complete and trash both remove a task from Today/Inbox in this phase (no
/// "recently completed" or Trash-browsing surface exists yet -- the
/// UI-SPEC explicitly defers a standalone Trash tab, D-49's own "not a
/// standalone empty tab" language). The task detail view stays pushed
/// across every one of these transitions, so `testFullCoreLoopViaDetailView`
/// drives complete -> reopen -> trash -> restore entirely through the
/// detail screen's own named controls, which is genuinely reachable
/// end to end without inventing an undeclared browsing surface. A second,
/// independent test (`testTrashViaTheRowsContextMenuRemovesItFromInbox`)
/// separately proves the row's long-press context-menu path -- disclosed
/// in 04-09-SUMMARY.md as two focused tests rather than one because the
/// context-menu path and the persisted-restore path are not simultaneously
/// reachable from a single list-only navigation sequence.
final class CoreLoopTests: XCTestCase {
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
        XCTAssertTrue(addTaskButton.isEnabled)
        addTaskButton.tap()
    }

    func testFullCoreLoopViaDetailView() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        // Capture -> appears in Inbox.
        capture(app, title: "Call the dentist")
        let row = app.staticTexts["task-row-Call the dentist"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Open.
        row.tap()
        let titleField = app.textFields["detail-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))

        // Edit -> save (an Inbox task's clarify action). The Save/Cancel
        // toolbar buttons can collapse into iOS's automatic nav-bar
        // overflow ("More") on a compact width -- `tapToolbarButton`
        // handles both cases.
        let notesField = app.textFields["detail-notes-field"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText("Ask about the appointment time")
        XCTAssertTrue(app.tapToolbarButton(identifier: "save-and-move-button", label: "Save & Move Out of Inbox"))

        // Complete.
        let completeButton = app.buttons["detail-complete-button"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        // Reopen.
        let reopenButton = app.buttons["detail-reopen-button"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 5))
        reopenButton.tap()

        // Trash (via the detail view's own named control).
        let trashButton = app.buttons["detail-trash-button"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 5))
        trashButton.tap()

        // Restore -- the SAME pushed detail screen now offers it.
        let restoreButton = app.buttons["detail-restore-button"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5))
        restoreButton.tap()

        // Back to an active, untrashed, uncompleted task, still reachable.
        XCTAssertTrue(app.buttons["detail-complete-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail-trash-button"].waitForExistence(timeout: 5))
    }

    func testTrashViaTheRowsContextMenuRemovesItFromInbox() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        capture(app, title: "Pick up dry cleaning")
        let row = app.staticTexts["task-row-Pick up dry cleaning"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.press(forDuration: 1.0)
        let trashMenuItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trash")).firstMatch
        XCTAssertTrue(trashMenuItem.waitForExistence(timeout: 5), "long-press context menu did not offer Trash")
        trashMenuItem.tap()

        XCTAssertFalse(row.waitForExistence(timeout: 3), "trashed row should disappear from Inbox")
    }
}
