import XCTest

/// Proves the durable capture draft (D-35, T-04-09-04): a nonempty draft
/// survives backgrounding and sheet dismissal, and is removed only by a
/// confirmed `Discard Draft`; an empty draft never shows a confirmation.
final class CaptureDraftTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openCapture(_ app: XCUIApplication) {
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 5))
        newTaskButton.tap()
        XCTAssertTrue(app.textFields["capture-title-field"].firstMatch.waitForExistence(timeout: 5))
    }

    func testANonemptyDraftSurvivesABackgroundAndForegroundCycle() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        openCapture(app)
        let titleField = app.textFields["capture-title-field"].firstMatch
        titleField.tap()
        titleField.typeText("Draft surviving backgrounding")

        // Background the app, then foreground it again.
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()

        XCTAssertTrue(app.textFields["capture-title-field"].firstMatch.waitForExistence(timeout: 5))
        let valueAfterForeground = app.textFields["capture-title-field"].firstMatch.value as? String
        XCTAssertEqual(valueAfterForeground, "Draft surviving backgrounding")
    }

    func testANonemptyDraftSurvivesSheetDismissalAndReappearsOnReopen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        openCapture(app)
        let titleField = app.textFields["capture-title-field"].firstMatch
        titleField.tap()
        titleField.typeText("Draft surviving dismissal")

        // Dismiss via Cancel -- a nonempty draft must NOT be silently
        // discarded (only an explicit, confirmed Discard Draft removes it).
        app.buttons["capture-cancel-button"].tap()

        openCapture(app)
        let reopenedField = app.textFields["capture-title-field"].firstMatch
        XCTAssertEqual(reopenedField.value as? String, "Draft surviving dismissal")
    }

    func testConfirmedDiscardDraftRemovesItAndAnEmptyDraftIsDiscardedSilently() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        openCapture(app)
        let titleField = app.textFields["capture-title-field"].firstMatch
        titleField.tap()
        titleField.typeText("Draft to discard")

        let discardDraftButton = app.buttons["discard-draft-button"]
        XCTAssertTrue(discardDraftButton.waitForExistence(timeout: 5))
        discardDraftButton.tap()

        let dialogHeading = app.staticTexts["Discard Quick Entry Draft?"]
        XCTAssertTrue(dialogHeading.waitForExistence(timeout: 5))
        let confirmButton = app.buttons["confirm-discard-draft-button"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        // The sheet dismisses after a confirmed discard.
        XCTAssertFalse(app.textFields["capture-title-field"].firstMatch.waitForExistence(timeout: 3))

        // Reopening shows an empty draft -- no confirmation dialog appears
        // for an empty draft when the sheet is dismissed via Cancel.
        openCapture(app)
        let reopenedField = app.textFields["capture-title-field"].firstMatch
        // An empty draft never shows the previously-discarded text. XCUITest
        // reports an empty text field's own placeholder as its `.value`, so
        // this asserts non-equality to the discarded text rather than
        // equality to `""`.
        XCTAssertNotEqual(reopenedField.value as? String, "Draft to discard")
        app.buttons["capture-cancel-button"].tap()
        XCTAssertFalse(app.staticTexts["Discard Quick Entry Draft?"].waitForExistence(timeout: 2))
    }
}
