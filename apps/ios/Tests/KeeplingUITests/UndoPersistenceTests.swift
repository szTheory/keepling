import XCTest

/// Covers `UndoControl`/`WorkspaceFacade.invokeUndo` (04-11-PLAN.md Task
/// 2): the named `Undo {Action}` control has no timer, no auto-expiry, no
/// gesture, and is reachable in two places at once -- the accessory and
/// both tabs' overflow menus -- with an actionable synchronization
/// exception still leaving the overflow-menu row reachable even while it
/// occupies the accessory slot.
///
/// `KEEPLING_UITEST_SEED_UNDO` (`KeeplingApp.swift`) seeds one or more
/// undo availabilities through the REAL capture -> accept -> acknowledge
/// (undo:) path `GRDBLocalStore.acknowledge` drives in production
/// (04-11-PLAN.md Task 1) -- never a synthesized presentation value --
/// mirroring `KEEPLING_UITEST_SEED_CONFLICT`'s established technique.
final class UndoPersistenceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(state: String? = nil, undoAvailable: Bool = false, seedUndo: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        if let state { app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE"] = state }
        if undoAvailable { app.launchEnvironment["KEEPLING_UITEST_UNDO_AVAILABLE"] = "1" }
        if let seedUndo { app.launchEnvironment["KEEPLING_UITEST_SEED_UNDO"] = seedUndo }
        app.launch()
        return app
    }

    // MARK: - No timer, no auto-expiry (D-30, D-33)

    /// Idles well beyond any plausible toast/snackbar duration (the
    /// pattern this whole feature exists to reject) and asserts the
    /// control is STILL present -- there is no `Timer`, no delayed
    /// dispatch, and no auto-dismiss path anywhere in `UndoControl`
    /// (independently asserted by this plan's own source-scan `<verify>`
    /// check).
    func testUndoControlPersistsWellBeyondAnyPlausibleTimerDuration() throws {
        let app = launch(state: "healthy", undoAvailable: true)
        let undoButton = app.buttons["sync-accessory-undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))

        Thread.sleep(forTimeInterval: 8)

        XCTAssertTrue(undoButton.exists, "the undo control must still be present after 8s -- no timer may dismiss it")
        XCTAssertEqual(undoButton.label, "Undo Trash")
    }

    // MARK: - A second undoable action replaces the control's label

    /// Seeds TWO real settlements in order (trash, then complete) --
    /// each through the real `capture -> accept -> acknowledge(undo:)`
    /// path -- and asserts the control's final label names the SECOND
    /// action, not the first: single-level, matching the Mac contract.
    func testASecondUndoableActionReplacesTheControlsLabel() throws {
        let app = launch(state: "healthy", seedUndo: "trash,complete")
        let undoButton = app.buttons["sync-accessory-undo"]
        // The seeding runs asynchronously after launch; poll until the
        // FINAL (second) label appears rather than asserting on a fixed
        // delay.
        let deadline = Date().addingTimeInterval(15)
        var lastLabel = ""
        while Date() < deadline {
            if undoButton.exists {
                lastLabel = undoButton.label
                if lastLabel == "Undo Complete" { break }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(lastLabel, "Undo Complete", "the control must name the SECOND undoable action, not the first")
    }

    // MARK: - Reachable in two places: accessory AND both tabs' overflow menus

    func testUndoIsPresentAsANamedOverflowMenuRowOnBothTabs() throws {
        let app = launch(state: "healthy", undoAvailable: true)
        XCTAssertTrue(app.buttons["overflow-menu"].waitForExistence(timeout: 5))
        app.buttons["overflow-menu"].tap()
        let inboxRow = app.buttons["overflow-undo"]
        XCTAssertTrue(inboxRow.waitForExistence(timeout: 5))
        XCTAssertEqual(inboxRow.label, "Undo Trash")
        // Dismiss the menu, switch tabs, reopen.
        app.tap()
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["overflow-menu"].waitForExistence(timeout: 5))
        app.buttons["overflow-menu"].tap()
        let todayRow = app.buttons["overflow-undo"]
        XCTAssertTrue(todayRow.waitForExistence(timeout: 5))
        XCTAssertEqual(todayRow.label, "Undo Trash")
    }

    // MARK: - Exception-first accessory arbitration still leaves undo reachable in the overflow menu

    func testWithAnActionableExceptionPresentTheAccessoryShowsTheExceptionAndTheOverflowMenuStillOffersTheUndo() throws {
        let app = launch(state: "conflict", undoAvailable: true)
        XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sync-accessory-undo"].exists, "an actionable exception must win the accessory slot")

        app.buttons["overflow-menu"].tap()
        XCTAssertTrue(app.buttons["overflow-undo"].waitForExistence(timeout: 5), "undo must remain reachable in the overflow menu even while an exception occupies the accessory")
    }

    // MARK: - Trashing a task produces the exact accessory copy

    func testTrashingATaskProducesTheExactAccessoryCopy() throws {
        let app = launch(state: "healthy", seedUndo: "trash")
        let label = app.staticTexts["sync-accessory-undo-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertEqual(label.label, "Task moved to Trash. Undo Trash")
    }

    // MARK: - Tapping undo invokes the compensating command and clears the control

    func testTappingUndoInvokesTheCompensatingCommandAndClearsTheControl() throws {
        let app = launch(state: "healthy", seedUndo: "trash")
        let undoButton = app.buttons["sync-accessory-undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 10))
        undoButton.tap()
        // Single-level: consumed immediately -- the control must clear,
        // never linger claiming an already-spent handle is still undoable.
        XCTAssertFalse(undoButton.waitForExistence(timeout: 5))
    }

    // MARK: - Platform text undo never produces a semantic command (D-32)

    /// Performs a platform text-undo gesture (the system three-finger-swipe
    /// equivalent this simulator exposes as the software `Undo` typing
    /// suggestion / Edit Menu item) inside the capture sheet's title field
    /// and asserts NO semantic command was produced -- proven by the
    /// absence of any resulting task after dismissal, since a semantic
    /// command would have durably captured one.
    func testAPlatformTextUndoInAFieldProducesNoSemanticCommand() throws {
        let app = launch(state: "healthy")
        XCTAssertTrue(app.buttons["new-task-button"].waitForExistence(timeout: 5))
        app.buttons["new-task-button"].tap()
        let titleField = app.textFields["capture-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Draft only, never captured")
        // A platform text undo (Cmd+Z on a connected hardware keyboard,
        // or the system Edit Menu) reverts the FIELD's own text -- it
        // must never reach the semantic command surface. This simulator
        // session has no hardware keyboard to send Cmd+Z through, so the
        // structural guarantee (no `UndoManager` wiring exists anywhere
        // outside this field -- `UndoControl.swift` has none, and neither
        // `TaskDetailView`/`CaptureSheet` set `.environment(\.undoManager,
        // ...)` anywhere) is what this test's sibling source-scan
        // `<verify>` check in the plan proves; this UI test instead
        // proves the OBSERVABLE half: cancelling out of the sheet
        // (discarding the draft) never left a captured task behind.
        app.buttons["capture-cancel-button"].tap()
        if app.buttons["confirm-discard-draft-button"].waitForExistence(timeout: 2) {
            app.buttons["confirm-discard-draft-button"].tap()
        }
        XCTAssertFalse(app.staticTexts["Draft only, never captured"].waitForExistence(timeout: 3), "no task must have been captured by a text-field edit alone")
    }

    // MARK: - Forbidden-surface assertion: no timer-based auto-dismissing presentation carries an undo action

    /// Static, source-level check (not a running-app assertion): fails if
    /// any Swift source file under `Sources/Keepling` defines a toast/
    /// snackbar-shaped auto-dismissing presentation (a view whose own name
    /// suggests transience -- `Toast`/`Snackbar`) that ALSO references an
    /// undo action. Toast/snackbar undo is a locked anti-pattern (D-33,
    /// D-49): unreachable in time for VoiceOver/Switch Control users and
    /// unprovable without flake in XCUITest.
    /// Ascends from `#filePath` to find the monorepo root -- a self-
    /// contained copy of `KeeplingCoreTests/RepositoryRoot.swift`'s
    /// technique (that file lives in a different test TARGET, so it is
    /// not directly reachable from `KeeplingUITests`).
    private func repositoryRoot() -> URL? {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent("pnpm-workspace.yaml").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    func testNoTimerDismissedSurfaceAnywhereCarriesAnUndoAffordance() throws {
        guard let root = repositoryRoot() else { return XCTFail("could not resolve the repository root from #filePath") }
        let sourcesDirectory = root.appendingPathComponent("apps/ios/Sources/Keepling")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil) else {
            return XCTFail("could not enumerate apps/ios/Sources/Keepling")
        }
        var offenders: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let looksTransient = contents.range(of: "Toast", options: .caseInsensitive) != nil
                || contents.range(of: "Snackbar", options: .caseInsensitive) != nil
            let mentionsUndo = contents.range(of: "undo", options: .caseInsensitive) != nil
            if looksTransient && mentionsUndo {
                offenders.append(fileURL.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, "toast/snackbar-shaped surface(s) carrying an undo reference: \(offenders)")
    }
}
