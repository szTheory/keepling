import XCTest

/// Drives the capture sheet on the simulator end to end -- a person
/// capturing a task in the running app, not a headless unit test
/// (04-01-PLAN.md Task 3's `<behavior>` UI half).
final class TracerCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturingATaskShowsItInTheInboxList() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 5))
        newTaskButton.tap()

        let titleField = app.textFields["capture-title-field"].firstMatch
        if !titleField.waitForExistence(timeout: 5) {
            // TextField with axis: .vertical can present as a text view on
            // some SDKs -- fall back to the generic text-input query rather
            // than asserting on a query kind that is an implementation
            // detail of SwiftUI's rendering choice.
            let anyField = app.textViews["capture-title-field"].firstMatch
            XCTAssertTrue(anyField.waitForExistence(timeout: 5))
            anyField.tap()
            anyField.typeText("Call the dentist")
        } else {
            titleField.tap()
            titleField.typeText("Call the dentist")
        }

        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 5))
        XCTAssertTrue(addTaskButton.isEnabled)
        addTaskButton.tap()

        let capturedRow = app.staticTexts["task-row-Call the dentist"]
        XCTAssertTrue(capturedRow.waitForExistence(timeout: 5))
    }
}
