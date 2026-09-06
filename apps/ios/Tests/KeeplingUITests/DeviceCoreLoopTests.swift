import XCTest

/// The full supported daily loop, on **Jon's actual iPhone**, against the
/// installed development-signed build (04-16-PLAN.md Task 3, IOS-01,
/// D-22 Criterion 1).
///
/// This is deliberately not a copy of `CoreLoopTests` with a different
/// destination. The simulator suite already proves the loop's LOGIC; what
/// only hardware can add is that the same sequence survives real flash
/// storage contention, a real GPU/compositor, real touch delivery, and a
/// real code signature. So every case here begins by binding itself to the
/// exact installed bytes (`assertBoundToInstalledBuild`) and ends on a
/// state the app had to persist to real storage to reach.
///
/// Every case is scripted. Attaching the phone is the only non-automated
/// act in this lane (`docs/testing/ios-dogfood.md` says so explicitly, and
/// the project's zero-human-UAT constraint is why).
final class DeviceCoreLoopTests: XCTestCase {

    /// The digest the lane injected into this build and reads back out of
    /// the running process. Supplied by `tooling/ios-lanes/device.mjs` as a
    /// `xcodebuild test` environment variable; when it is absent the
    /// binding assertion below fails LOUDLY rather than passing silently --
    /// an unbound device run is exactly the stale evidence D-21 refuses.
    private var expectedDigest: String? {
        ProcessInfo.processInfo.environment["KEEPLING_EXPECTED_BUILD_DIGEST"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "DeviceCoreLoopTests is the PHYSICAL-DEVICE suite (04-16-PLAN.md Task 3). Running it on a " +
            "simulator would produce evidence about a simulator while carrying a device suite's name -- " +
            "the exact false attribution this suite exists to prevent. The simulator equivalent is " +
            "CoreLoopTests."
        )
        #endif
    }

    /// Launches with the attestation probe rendered and asserts the running
    /// app reports the digest this lane built.
    ///
    /// `tooling/ios-device/attestation.mjs` already refuses a mismatched
    /// build before any test runs. This is a SECOND, independent binding
    /// and not a redundant one: `xcodebuild test` re-installs the app it
    /// just built, which is a different installation event from the one the
    /// lane attested. Without this, a `xcodebuild test` that quietly
    /// installed something else would still report green.
    private func launchBoundToInstalledBuild(resetStore: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if resetStore { app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1" }
        app.launchEnvironment["KEEPLING_DEVICE_ATTESTATION_PROBE"] = "1"
        app.launch()

        guard let expectedDigest, !expectedDigest.isEmpty else {
            XCTFail(
                "KEEPLING_EXPECTED_BUILD_DIGEST was not supplied to this device run. Evidence gathered now " +
                "could not be bound to the installed build (D-21), so this suite refuses to report a pass."
            )
            return app
        }

        let probe = app.staticTexts[BuildAttestationIdentifiers.probe]
        XCTAssertTrue(
            probe.waitForExistence(timeout: 20),
            "the running app rendered no build-attestation probe -- it is not the build this lane produced"
        )
        XCTAssertEqual(
            probe.label, expectedDigest,
            "the app running on this phone reports a different KeeplingBuildDigest than the build under test"
        )
        return app
    }

    private func capture(_ app: XCUIApplication, title: String) {
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 20), "Inbox never reached a capturable state on device")
        newTaskButton.tap()

        let titleField = app.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)

        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 10))
        XCTAssertTrue(addTaskButton.isEnabled)
        addTaskButton.tap()
    }

    // MARK: - Criterion 1: the full supported loop, on hardware

    func testFullSupportedLoopOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild()

        capture(app, title: "Device loop task")
        let row = app.staticTexts["task-row-Device loop task"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the captured task never appeared in Inbox on device")

        row.tap()
        XCTAssertTrue(app.textFields["detail-title-field"].waitForExistence(timeout: 10))

        let notesField = app.textFields["detail-notes-field"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 10))
        notesField.tap()
        notesField.typeText("Written on real hardware")
        XCTAssertTrue(app.tapToolbarButton(identifier: "save-and-move-button", label: "Save & Move Out of Inbox"))

        let completeButton = app.buttons["detail-complete-button"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 10))
        completeButton.tap()

        let reopenButton = app.buttons["detail-reopen-button"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 10))
        reopenButton.tap()

        let trashButton = app.buttons["detail-trash-button"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 10))
        trashButton.tap()

        let restoreButton = app.buttons["detail-restore-button"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 10))
        restoreButton.tap()

        XCTAssertTrue(app.buttons["detail-complete-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["detail-trash-button"].waitForExistence(timeout: 10))
    }

    /// The row's long-press context menu -- the ONLY gesture path to Trash
    /// (D-31: a swipe never trashes). Real touch delivery and a real
    /// long-press timing threshold are precisely what a simulator does not
    /// model, so this case earns its place on hardware.
    func testTrashViaContextMenuOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild()

        capture(app, title: "Device context menu task")
        let row = app.staticTexts["task-row-Device context menu task"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        row.press(forDuration: 1.0)
        let trashMenuItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trash")).firstMatch
        XCTAssertTrue(trashMenuItem.waitForExistence(timeout: 10), "long-press context menu did not offer Trash on device")
        trashMenuItem.tap()

        XCTAssertFalse(row.waitForExistence(timeout: 5), "the trashed row should disappear from Inbox on device")
    }

    /// Today is one of the two locked destinations (D-25). Planning a task
    /// for Today and finding it there is half the daily loop, and it is
    /// driven here on the device rather than assumed from the simulator.
    func testPlanForTodayAndFindItOnTheTodayTabOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild()

        capture(app, title: "Device today task")
        let row = app.staticTexts["task-row-Device today task"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        // Queried by identifier across ANY element type, not as
        // `app.switches[...]`. The control is a `Button` carrying an
        // `accessibilityValue` of On/Off, not a system `Toggle` -- both
        // here and in `CaptureSheet`, which it deliberately mirrors -- so
        // it surfaces to XCUITest as `.button`. A system `Toggle`'s label
        // and its automatic disabled dim both render below WCAG 2.2 AA in
        // a Form row (T-04-13 findings), which is why the app does not use
        // one; the original `app.switches` query encoded a control shape
        // this app had already rejected on accessibility grounds.
        let todayToggle = app.descendants(matching: .any)["add-to-today-toggle"].firstMatch
        XCTAssertTrue(todayToggle.waitForExistence(timeout: 10), "the detail view offered no Add to Today control")
        todayToggle.tap()

        app.tabBars.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["task-row-Device today task"].waitForExistence(timeout: 15),
            "a task planned for Today did not appear on the Today tab on device"
        )
    }

    // MARK: - Criterion 3: foreground launch and resume restore correctness

    /// D-22 Criterion 3, the honest half: correctness must survive a
    /// backgrounding and a foreground resume WITHOUT any background wake
    /// having been scheduled or fired. Real `BGTaskScheduler` wake
    /// scheduling is opportunistic and is NOT asserted anywhere in this
    /// lane (`docs/testing/ios-dogfood.md` discloses that by name); the
    /// claim proved here is the weaker, checkable one: correctness does not
    /// REQUIRE a background wake.
    func testForegroundResumeRestoresStateWithoutABackgroundWake() throws {
        let app = launchBoundToInstalledBuild()

        capture(app, title: "Device resume task")
        XCTAssertTrue(app.staticTexts["task-row-Device resume task"].waitForExistence(timeout: 15))

        XCUIDevice.shared.press(.home)
        // A real backgrounding, then a real foreground activation. This is
        // an app-lifecycle transition on the device, not a relaunch: the
        // process is expected to still be alive.
        app.activate()

        XCTAssertTrue(
            app.staticTexts["task-row-Device resume task"].waitForExistence(timeout: 20),
            "a resumed app did not restore the task it had already persisted"
        )
    }
}

/// Kept in the UI-test target on purpose. A UI-test bundle is hosted BY the
/// app but does not link its module, so `BuildAttestation.probeIdentifier`
/// is not visible here -- the literal is mirrored, and
/// `ShellBoundaryTests`-style drift is prevented by
/// `tooling/ios-lanes/device.mjs`, which asserts the two spellings match
/// before the lane runs.
enum BuildAttestationIdentifiers {
    static let probe = "build-attestation-digest"
}
