import XCTest

/// The closed list of supported screens (04-UI-SPEC.md Accessibility and
/// Platform Contract, D-48). Every suite in this plan --
/// `AccessibilityAuditTests`, `DynamicTypeSnapshotTests`, `ReduceMotionTests`
/// -- iterates this list rather than hand-listing screens per file, so
/// coverage cannot silently shrink as new suites are added or old ones
/// drift. `AccessibilityAuditTests
/// .testEveryTopLevelViewUnderSourcesKeeplingIsInTheInventoryOrExplicitlyExcluded`
/// is the completeness guard that keeps this list honest against the real
/// source tree.
@MainActor
struct SupportedScreen {
    let name: String
    /// Additional launch-environment keys this screen's fixture needs,
    /// beyond `KEEPLING_UITEST_RESET_STORE=1` (always set by every caller
    /// of `SupportedScreen.launch(_:)`).
    let launchEnvironment: [String: String]
    /// Navigates the freshly launched app (already on its default tab) to
    /// this screen. Left ON this screen when the closure returns -- no
    /// dismissal performed here.
    let navigate: (XCUIApplication) throws -> Void

    /// Launches a fresh app configured for this screen's fixture and
    /// navigates to it. `continueAfterFailure` is left to the caller.
    @discardableResult
    func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        for (key, value) in launchEnvironment { app.launchEnvironment[key] = value }
        app.launch()
        // Every fixture that seeds data asynchronously (conflict/undo
        // seeding, mirroring KeeplingApp.swift's own Task.detached fixture
        // hooks) needs a moment to land before navigation reads the list;
        // waiting on the tab bar's existence below is the real
        // synchronization point every other UI test in this codebase
        // already relies on (`waitForExistence`), so no arbitrary sleep is
        // added here.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "\(name): tab bar never appeared")
        try navigate(app)
        // A settle after navigation completes -- `waitForExistence`
        // above only proves an element APPEARED, not that a still-running
        // presentation/transition animation (a `.sheet` sliding into
        // place, a keyboard-avoidance resize) has finished. Measured
        // directly while building this plan: a screenshot/audit taken
        // immediately after `waitForExistence` succeeds can still catch
        // a mid-transition frame (motion blur, background content
        // bleeding through), which is a property of the animation, not
        // of the resting UI this suite audits.
        Thread.sleep(forTimeInterval: 0.5)
        return app
    }

    /// Taps the first task row's title text, wherever the row currently
    /// sits (Today, Inbox, or the `Sync & Recovery` sheet's exception
    /// list) -- all three lists render the identical
    /// `task-row-<title>` / `sync-recovery-row-title-<title>`-prefixed
    /// leaf identifier convention `TaskRow`/`SyncRecoverySheet` establish.
    private static func tapFirstTaskRow(_ app: XCUIApplication, identifierPrefix: String = "task-row-") {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let row = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no row found with identifier prefix \(identifierPrefix)")
        row.tap()
    }

    /// A seeded task title distinctive enough that it can never collide
    /// with any other fixture's default text, and reused directly in
    /// `AccessibilityAuditTests`' distinctive-title leak check (that test
    /// asserts this exact string is never found in a nav/screen title).
    static let distinctiveConflictTitle = "Conflicted Task"

    static let all: [SupportedScreen] = [
        SupportedScreen(name: "Today", launchEnvironment: [:], navigate: { app in
            app.tabBars.buttons["Today"].tap()
        }),
        SupportedScreen(name: "Inbox", launchEnvironment: [:], navigate: { app in
            app.tabBars.buttons["Inbox"].tap()
        }),
        SupportedScreen(
            name: "Capture sheet",
            launchEnvironment: [:],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                let newTask = app.buttons["new-task-button"]
                XCTAssertTrue(newTask.waitForExistence(timeout: 10))
                newTask.tap()
                XCTAssertTrue(app.textFields["capture-title-field"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Task detail and editor",
            launchEnvironment: [:],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                app.buttons["new-task-button"].tap()
                let titleField = app.textFields["capture-title-field"]
                XCTAssertTrue(titleField.waitForExistence(timeout: 10))
                titleField.tap()
                titleField.typeText("Task detail audit fixture")
                let addTaskButton = app.buttons["add-task-button"]
                XCTAssertTrue(addTaskButton.waitForExistence(timeout: 10))
                addTaskButton.tap()
                tapFirstTaskRow(app)
                XCTAssertTrue(app.textFields["detail-title-field"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Conflict resolver",
            launchEnvironment: ["KEEPLING_UITEST_SEED_CONFLICT": "1"],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                // `KEEPLING_UITEST_SEED_CONFLICT` seeds the conflict
                // asynchronously (mirrors `KeeplingApp.swift`'s own
                // `Task.detached` fixture hook). Reaching the detail view
                // through the row's OWN `.onTapGesture` -- measured
                // directly while building this plan across many isolated
                // `xcodebuild` runs -- intermittently failed to navigate
                // once the row also carries the inline exception
                // indicator (`TaskExceptionRow`), even with a literal
                // identifier lookup. `SyncRecoveryTests
                // .testASeededConflictAppearsInlineAndInTheSyncRecoverySheetWithWorkingDeepLinks`
                // already established a reliably working deep-link path
                // for this exact seeded state: the exception indicator's
                // OWN tap opens `Sync & Recovery`, whose row is a real
                // `NavigationLink` (not a plain `.onTapGesture`) into the
                // identical task detail view -- reused here rather than
                // re-diagnosing the row-tap gesture conflict.
                let exceptionRow = app.buttons["task-exception-\(distinctiveConflictTitle)"]
                XCTAssertTrue(exceptionRow.waitForExistence(timeout: 10), "the seeded conflict must render its inline exception row before navigating in")
                exceptionRow.tap()
                let sheetRow = app.staticTexts["sync-recovery-row-title-\(distinctiveConflictTitle)"]
                XCTAssertTrue(sheetRow.waitForExistence(timeout: 10), "Sync & Recovery must list the seeded conflict")
                sheetRow.tap()
                XCTAssertTrue(app.textFields["detail-title-field"].waitForExistence(timeout: 10), "the Sync & Recovery deep link must reach the task detail view")
                XCTAssertTrue(app.buttons["conflict-use-mine-button"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Sync & Recovery sheet",
            launchEnvironment: ["KEEPLING_UITEST_SEED_CONFLICT": "1"],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                XCTAssertTrue(app.tapToolbarButton(identifier: "overflow-menu", label: "More"))
                let recoveryRow = app.buttons["overflow-sync-recovery"].firstMatch
                XCTAssertTrue(recoveryRow.waitForExistence(timeout: 10))
                recoveryRow.tap()
                XCTAssertTrue(app.navigationBars["Sync & Recovery"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Bottom accessory",
            launchEnvironment: ["KEEPLING_UITEST_SYNC_STATE": "conflict"],
            navigate: { app in
                app.tabBars.buttons["Today"].tap()
                XCTAssertTrue(app.staticTexts["sync-accessory-text"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Discard draft dialog",
            launchEnvironment: [:],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                app.buttons["new-task-button"].tap()
                let titleField = app.textFields["capture-title-field"]
                XCTAssertTrue(titleField.waitForExistence(timeout: 10))
                titleField.tap()
                titleField.typeText("Draft for the audit")
                let discardButton = app.buttons["discard-draft-button"]
                XCTAssertTrue(discardButton.waitForExistence(timeout: 10))
                discardButton.tap()
                XCTAssertTrue(app.staticTexts["Discard Quick Entry Draft?"].waitForExistence(timeout: 10))
            }
        ),
        SupportedScreen(
            name: "Discard changes dialog",
            launchEnvironment: [:],
            navigate: { app in
                app.tabBars.buttons["Inbox"].tap()
                app.buttons["new-task-button"].tap()
                let titleField = app.textFields["capture-title-field"]
                XCTAssertTrue(titleField.waitForExistence(timeout: 10))
                titleField.tap()
                titleField.typeText("Task to edit")
                let addTaskButton = app.buttons["add-task-button"]
                XCTAssertTrue(addTaskButton.waitForExistence(timeout: 10))
                addTaskButton.tap()
                tapFirstTaskRow(app)
                let detailTitleField = app.textFields["detail-title-field"]
                XCTAssertTrue(detailTitleField.waitForExistence(timeout: 10))
                detailTitleField.tap()
                detailTitleField.typeText(" edited")
                XCTAssertTrue(app.tapToolbarButton(identifier: "cancel-editing-button", label: "Cancel Editing"))
                XCTAssertTrue(app.staticTexts["Discard Unsaved Changes?"].waitForExistence(timeout: 10))
            }
        ),
    ]

    /// Top-level `View` filenames under `Sources/Keepling` that are
    /// intentionally excluded from `all` above, with the reason recorded
    /// inline -- read by the completeness guard in
    /// `AccessibilityAuditTests` so an exclusion is a recorded decision,
    /// never a silent gap.
    static let recordedExclusions: [String: String] = [
        // AccessoryProbeRootView is reachable ONLY when
        // KEEPLING_ACCESSORY_PROBE_MODE is set (T-04-04-03) -- never in
        // any ordinary app launch path, so it carries no user-facing
        // accessibility surface to audit.
        "AccessoryProbeRootView.swift": "probe-only scene, never reachable in a shipped launch path (T-04-04-03)",
        // TaskListEmptyState/TaskRow/TaskExceptionRow are child views
        // composed INTO Today/Inbox/the detail view, not independently
        // navigable screens of their own -- their accessibility surface is
        // exercised as part of auditing the screens that host them.
        "TaskRow.swift": "a row composed into Today/Inbox, audited as part of those screens",
        "TaskExceptionRow.swift": "a row composed into Today/Inbox/the Sync & Recovery sheet, audited as part of those screens",
        "BottomAccessoryView.swift": "composed into the tab shell, audited as the 'Bottom accessory' inventory entry via RootTabView",
        "ConflictResolverSection.swift": "a section composed into the task detail view, audited as part of the 'Conflict resolver' inventory entry",
        "UndoControl.swift": "a control composed into the accessory and overflow menu, audited as part of the screens that host it",
        "RootTabView.swift": "the tab shell itself, audited as part of every tab entry (Today/Inbox/Bottom accessory) it hosts",
        // A pre-existing, disclosed gap (04-07/04-09-SUMMARY.md): SignInFlow
        // is not yet wired into root navigation, so no launch path in this
        // shipped app reaches it -- there is nothing for this plan's
        // inventory-driven suites to navigate to. Out of this plan's
        // authorized scope to wire in; a future plan resolving that gap
        // must also add SignInFlow to the inventory before this exclusion
        // can be removed.
        "SignInFlow.swift": "not yet wired into root navigation (04-07/04-09 disclosed gap) -- no reachable launch path exists to audit",
    ]
}
