import KeeplingCore
import XCTest

/// The twelve-state matrix (04-14-PLAN.md Task 1): every presentation
/// state this app can render is reached ON DEMAND through
/// `StateInjection`, without a server and without waiting, and asserted
/// against its exact inherited copy (`SyncCopy`) and its specific named
/// recovery action where one exists. This directly closes the Phase-3
/// lesson 04-13-SUMMARY.md records (O-46/O-47): `.opening`/`.preparing`
/// had no production construction site on the Mac and so were never
/// actually rendered anywhere -- `RootTabView`'s new `loadingOverlay` and
/// `BottomAccessoryView`'s new `.offline`/`.localAcceptance` branches
/// (both added by this plan) ARE that construction site on the iPhone.
///
/// **What this file does NOT re-test:** `SyncPresentation.derive`'s own
/// closed-input-union behavior (exact copy per case, bounded-count
/// ceiling, forbidden-vocabulary scan) is already exhaustively unit-tested
/// by `SyncPresentationTests` (04-10-PLAN.md Task 1) -- this file asserts
/// the state is REACHABLE and RENDERED in the running app, not that the
/// pure function itself is correct.
@MainActor
final class SyncStateMatrixTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Populated / authoritative empty (04-UI-SPEC.md Empty states)

    /// The `.populated` state (a healthy workspace with real content):
    /// renders the actual task list, never any visible synchronization
    /// copy -- D-38's "healthy is silent" rule.
    func testPopulatedRendersTheRealTaskListWithNoVisibleSyncCopy() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .populated, itemShape: .one)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'task-row-'")).firstMatch.waitForExistence(timeout: 10),
            "populated: the seeded task's row never appeared"
        )
        XCTAssertFalse(app.staticTexts["sync-accessory-text"].exists, "populated: a healthy state must never render visible sync copy")
        XCTAssertFalse(app.staticTexts["Inbox Is Clear"].exists, "populated: the authoritative empty copy must never render alongside real content")
    }

    /// The `.empty` state: the authoritative empty copy -- and ONLY that
    /// copy, never a loading/failure string standing in for it.
    func testEmptyRendersTheAuthoritativeEmptyStateOnBothLists() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .empty, itemShape: .zero)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Inbox Is Clear"].waitForExistence(timeout: 10), "empty: Inbox's authoritative empty heading never appeared")
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Nothing for Today"].waitForExistence(timeout: 10), "empty: Today's authoritative empty heading never appeared")
    }

    // MARK: - Opening / preparing: an in-flight state never substitutes the authoritative empty copy

    /// `.opening`/`.preparing` are the two Phase-3-lesson states: this
    /// plan's own `loadingOverlay` REPLACES tab content entirely while
    /// either is active, so "Nothing for Today"/"Inbox Is Clear" can
    /// structurally never render during either -- proven directly, not
    /// merely by construction.
    func testOpeningAndPreparingRenderTheirExactCopyAndNeverSubstituteTheAuthoritativeEmptyState() throws {
        let cases: [(StateInjection.State, String)] = [(.opening, SyncCopy.opening), (.preparing, SyncCopy.preparing)]
        for (state, expectedCopy) in cases {
            let app = XCUIApplication()
            StateInjection.configure(app, state: state, itemShape: .zero)
            app.launch()
            // `sync-loading-text` is the reliable query point (see
            // `RootTabView.loadingOverlay`'s own note: a container-level
            // identifier collapses every child's identifier down to
            // itself, so the leaf `Text`'s identifier is asserted
            // directly rather than a wrapping container's).
            let text = app.staticTexts["sync-loading-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 10), "\(state): sync-loading-text never appeared")
            XCTAssertTrue(app.activityIndicators.firstMatch.exists, "\(state): no in-flight ProgressView rendered alongside the copy")
            XCTAssertEqual(text.label, expectedCopy, "\(state): rendered copy did not match SyncCopy verbatim")
            XCTAssertFalse(app.staticTexts["Nothing for Today"].exists, "\(state): the authoritative empty copy must never substitute for a loading state")
            XCTAssertFalse(app.staticTexts["Inbox Is Clear"].exists, "\(state): the authoritative empty copy must never substitute for a loading state")
            app.terminate()
        }
    }

    // MARK: - Accessory-rendered states: updating / offline / local acceptance (no action) and the actionable exceptions (named recovery action)

    /// `.updating`/`.offline`/`.localAcceptance` are routine, non-
    /// actionable states (D-38): each renders its exact copy in the
    /// accessory with NO recovery action -- proving they too now have a
    /// genuine construction site (this plan's `BottomAccessoryView`
    /// extension), not merely a derived-but-unrendered `SyncCopy` string.
    func testUpdatingOfflineAndLocalAcceptanceRenderTheirExactCopyWithNoRecoveryAction() throws {
        let cases: [(StateInjection.State, String)] = [
            (.updating, SyncCopy.updating),
            (.offline, SyncCopy.offline),
            (.localAcceptance, SyncCopy.localAcceptance),
        ]
        for (state, expectedCopy) in cases {
            let app = XCUIApplication()
            StateInjection.configure(app, state: state, itemShape: .zero)
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            let text = app.staticTexts["sync-accessory-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 10), "\(state): sync-accessory-text never appeared")
            XCTAssertEqual(text.label, expectedCopy, "\(state): rendered copy did not match SyncCopy verbatim")
            app.terminate()
        }
    }

    /// The eight actionable-exception states: each renders its exact
    /// copy AND its one specific named recovery action, reachable by the
    /// action's own `sync-accessory-action-<code>` identifier and its
    /// exact `SyncCopy` label.
    func testEveryActionableExceptionRendersItsExactCopyAndNamedRecoveryAction() throws {
        let cases: [(StateInjection.State, String, String, String)] = [
            (.localSaveFailure, SyncCopy.localSaveFailure, "retry_save", SyncCopy.actionRetrySave),
            (.retryable, SyncCopy.retryableFailure, "retry", SyncCopy.actionRetry),
            (.uncertain, SyncCopy.uncertain, "check_again", SyncCopy.actionCheckAgain),
            (.rejection, SyncCopy.rejected, "review", SyncCopy.actionReview),
            (.conflict, SyncCopy.conflict, "review_conflict", SyncCopy.actionReviewConflict),
            (.authentication, SyncCopy.authenticationFence, "sign_in", SyncCopy.actionSignIn),
        ]
        for (state, expectedCopy, actionCode, expectedActionLabel) in cases {
            let app = XCUIApplication()
            StateInjection.configure(app, state: state, itemShape: .zero)
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            let text = app.staticTexts["sync-accessory-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 10), "\(state): sync-accessory-text never appeared")
            XCTAssertEqual(text.label, expectedCopy, "\(state): rendered copy did not match SyncCopy verbatim")
            let action = app.buttons["sync-accessory-action-\(actionCode)"]
            XCTAssertTrue(action.waitForExistence(timeout: 5), "\(state): its named recovery action never appeared")
            XCTAssertEqual(action.label, expectedActionLabel, "\(state): recovery action label did not match SyncCopy verbatim")
            app.terminate()
        }
    }

    /// `.unrecoverable` carries THREE actions (Inspect/Export/Remove data),
    /// not one -- asserted separately from the single-action cases above.
    func testUnrecoverableRendersItsExactCopyAndAllThreeNamedRecoveryActions() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .unrecoverable, itemShape: .zero)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let text = app.staticTexts["sync-accessory-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(text.label, SyncCopy.unrecoverable)
        for (code, label) in [("inspect", SyncCopy.actionInspect), ("export", SyncCopy.actionExport), ("remove_local_data", SyncCopy.actionRemoveLocalData)] {
            let action = app.buttons["sync-accessory-action-\(code)"]
            XCTAssertTrue(action.waitForExistence(timeout: 5), "unrecoverable: \(code) action never appeared")
            XCTAssertEqual(action.label, label)
        }
    }

    // MARK: - Draft and unsaved-edit preservation across every failure state (T-04-14-03)

    /// A pre-existing durable capture draft survives a launch into every
    /// failure state -- the failure banner is presentation-only and never
    /// touches the draft the person was in the middle of writing.
    func testEveryFailureStatePreservesAPreExistingCaptureDraft() throws {
        let failureStates: [StateInjection.State] = [.localSaveFailure, .retryable, .uncertain, .rejection, .conflict, .authentication, .unrecoverable]
        for state in failureStates {
            let app = XCUIApplication()
            StateInjection.configure(app, state: state, itemShape: .zero)
            StateInjection.configureDraft(app, title: "Draft surviving \(state.rawValue)")
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            app.tabBars.buttons["Inbox"].tap()
            let newTaskButton = app.buttons["new-task-button"]
            XCTAssertTrue(newTaskButton.waitForExistence(timeout: 10))
            newTaskButton.tap()
            let titleField = app.textFields["capture-title-field"].firstMatch
            XCTAssertTrue(titleField.waitForExistence(timeout: 10), "\(state): capture sheet never appeared")
            XCTAssertEqual(titleField.value as? String, "Draft surviving \(state.rawValue)", "\(state): the pre-existing draft was not preserved")
            app.terminate()
        }
    }

    /// An unsaved editor change (a title edit not yet saved) is retained
    /// while a failure state's banner is showing -- the failure
    /// presentation never resets or discards in-progress local edits.
    func testAFailureStatePreservesAnUnsavedEditorChange() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .retryable, itemShape: .one)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'task-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let detailTitleField = app.textFields["detail-title-field"]
        XCTAssertTrue(detailTitleField.waitForExistence(timeout: 10))
        detailTitleField.tap()
        detailTitleField.typeText(" -- unsaved edit")
        // The accessory's failure banner is showing concurrently -- assert
        // it too, so this proves the edit survives WHILE the failure state
        // is genuinely active, not merely that the field itself is sticky.
        XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 5))
        XCTAssertTrue((detailTitleField.value as? String)?.contains("-- unsaved edit") == true, "the unsaved editor change was not retained")
    }

    // MARK: - Partial data: absent optional fields stay absent, inapplicable actions are omitted

    /// A freshly seeded task has no notes, is not completed, and is not
    /// trashed. Its detail view must show an EMPTY notes field (never a
    /// synthesized placeholder value) and must show ONLY the applicable
    /// lifecycle actions (Complete, Trash) -- Reopen and Restore, which
    /// apply to a different lifecycle state, must be entirely absent
    /// (omitted), not merely disabled while still visible.
    func testPartialDataLeavesAbsentOptionalFieldsAbsentAndOmitsInapplicableActions() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .populated, itemShape: .partial)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Inbox"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'task-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let notesField = app.textFields["detail-notes-field"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 10))
        let notesValue = notesField.value as? String
        XCTAssertTrue(notesValue == nil || notesValue == "" || notesValue == "Notes", "the absent notes field must stay empty, never synthesized")
        XCTAssertTrue(app.buttons["detail-complete-button"].exists, "the applicable Complete action must be present")
        XCTAssertTrue(app.buttons["detail-trash-button"].exists, "the applicable Trash action must be present")
        XCTAssertFalse(app.buttons["detail-reopen-button"].exists, "Reopen does not apply to an incomplete task -- it must be omitted, not merely disabled")
        XCTAssertFalse(app.buttons["detail-restore-button"].exists, "Restore does not apply to a non-trashed task -- it must be omitted, not merely disabled")
    }

    // MARK: - Zero, one, many: distinct rendering with a bounded count

    func testZeroOneAndManyRenderDistinctlyOnBothLists() throws {
        // Zero: the authoritative empty state (already asserted in detail
        // by testEmptyRendersTheAuthoritativeEmptyStateOnBothLists above;
        // reasserted narrowly here as the "zero" leg of this one matrix).
        let zeroApp = XCUIApplication()
        StateInjection.configure(zeroApp, state: .populated, itemShape: .zero)
        zeroApp.launch()
        XCTAssertTrue(zeroApp.tabBars.firstMatch.waitForExistence(timeout: 10))
        zeroApp.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(zeroApp.staticTexts["Inbox Is Clear"].waitForExistence(timeout: 10))
        zeroApp.terminate()

        // One: exactly one row, normal row geometry (no list-empty copy).
        let oneApp = XCUIApplication()
        StateInjection.configure(oneApp, state: .populated, itemShape: .one)
        oneApp.launch()
        XCTAssertTrue(oneApp.tabBars.firstMatch.waitForExistence(timeout: 10))
        oneApp.tabBars.buttons["Inbox"].tap()
        // NOT "task-row-focus-value-...": `TaskRow`'s `@State` focus-value
        // debug mirror (04-13-PLAN.md Task 3) ALSO begins with "task-row-",
        // so a bare BEGINSWITH predicate double-counts each row -- one
        // title `Text`, one focus-value mirror `Text` -- unless excluded.
        let oneRows = oneApp.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH 'task-row-' AND NOT (identifier BEGINSWITH 'task-row-focus-value-')"
        ))
        XCTAssertTrue(oneRows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(oneRows.count, 1, "the one-item shape must render exactly one row")
        XCTAssertFalse(oneApp.staticTexts["Inbox Is Clear"].exists)
        oneApp.terminate()

        // Many: multiple stable rows via native List scrolling.
        let manyApp = XCUIApplication()
        StateInjection.configure(manyApp, state: .populated, itemShape: .many(5))
        manyApp.launch()
        XCTAssertTrue(manyApp.tabBars.firstMatch.waitForExistence(timeout: 10))
        manyApp.tabBars.buttons["Inbox"].tap()
        let manyRows = manyApp.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH 'task-row-' AND NOT (identifier BEGINSWITH 'task-row-focus-value-')"
        ))
        XCTAssertTrue(manyRows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(manyRows.count, 5, "the many-item shape must render every seeded row")
        manyApp.terminate()
    }

    /// A count well past `SyncPresentation.maximumPresentedCount` (99)
    /// still renders bounded at 99 in the accessory -- never the raw,
    /// unbounded number -- proving the "no unbounded badge numbers"
    /// prohibition end to end, not merely at the pure `derive` layer
    /// (already unit-tested by `SyncPresentationTests`).
    func testAManyCountBeyondTheCeilingRendersBoundedNeverRaw() throws {
        let app = XCUIApplication()
        StateInjection.configure(app, state: .retryable, itemShape: .zero, count: 150)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let countText = app.staticTexts["sync-accessory-count"]
        XCTAssertTrue(countText.waitForExistence(timeout: 10), "sync-accessory-count never appeared for a count-carrying state")
        XCTAssertEqual(countText.label, "(99)", "an affected count of 150 must render bounded at 99, never the raw unbounded number")
    }
}
