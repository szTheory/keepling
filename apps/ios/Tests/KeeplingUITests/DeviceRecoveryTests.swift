import XCTest

/// Durability and recovery on **real hardware** (04-16-PLAN.md Task 3,
/// IOS-02, D-22 Criterion 2).
///
/// The simulator cannot produce the two things this suite needs. It has no
/// real flash storage, so a write that "completed" there proves nothing
/// about a write that completed on a phone; and it has no no-notice process
/// death, so a relaunch there is a cooperative restart wearing a crash's
/// name. `devicectl device process terminate` sends a real signal to a real
/// process on the phone -- the on-device analogue of the Phase 3 hard kill,
/// and the stricter case: an app killed this way runs no shutdown path at
/// all, so anything that survives was already durable before the kill.
///
/// WHAT THIS SUITE DOES **NOT** PROVE -- disclosed, not implied
/// -----------------------------------------------------------
/// The server-driven half of D-22 Criterion 2 -- authentication expiry,
/// account fencing, duplicate replay, and structured conflict injected
/// SERVER-SIDE through the recording proxy -- is **BLOCKED** and is
/// deliberately absent from this file rather than faked client-side.
///
/// The reason is measured, not assumed, by
/// `tooling/verify-real-stack-ios.mjs`: `KeeplingSyncAdapter`'s constructor
/// refuses any non-HTTPS base URL whose host is not `127.0.0.1`/`localhost`
/// (T-04-01-03/T-04-05-04), and a physical phone can only reach the build
/// Mac at a LAN address. Over HTTP nothing leaves the phone; over HTTPS the
/// phone genuinely connects but URLSession rejects the lane's self-signed
/// certificate. Writing those four cases here against `StateInjection`
/// would assert the CLIENT's opinion of a server it never spoke to -- which
/// is precisely the "assert against a client-side status" failure
/// 04-16-PLAN.md's own acceptance criteria forbid. They stay BLOCKED until
/// the transport-trust decision is made. See `docs/testing/ios-dogfood.md`.
final class DeviceRecoveryTests: XCTestCase {

    private var expectedDigest: String? {
        ProcessInfo.processInfo.environment["KEEPLING_EXPECTED_BUILD_DIGEST"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "DeviceRecoveryTests is the PHYSICAL-DEVICE suite (04-16-PLAN.md Task 3). A simulator has no " +
            "real flash storage and no no-notice process death, so running it there would name a device " +
            "claim over simulator evidence. The simulator equivalents are SyncRecoveryTests and " +
            "StorageTests/CrashRecoveryTests."
        )
        #endif
    }

    private func launchBoundToInstalledBuild(resetStore: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if resetStore { app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1" }
        app.launchEnvironment["KEEPLING_DEVICE_ATTESTATION_PROBE"] = "1"
        app.launch()

        guard let expectedDigest, !expectedDigest.isEmpty else {
            XCTFail(
                "KEEPLING_EXPECTED_BUILD_DIGEST was not supplied to this device run -- evidence could not " +
                "be bound to the installed build (D-21)."
            )
            return app
        }
        let probe = app.staticTexts[BuildAttestationIdentifiers.probe]
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "no build-attestation probe on the running app")
        XCTAssertEqual(probe.label, expectedDigest, "this phone is running a different build than the one under test")
        return app
    }

    private func capture(_ app: XCUIApplication, title: String) {
        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 20))
        newTaskButton.tap()
        let titleField = app.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 10))
        addTaskButton.tap()
    }

    // MARK: - A mutation made with no server survives a hard kill

    /// The offline half of Criterion 2 that IS provable without reaching a
    /// server: a mutation accepted locally with no `KEEPLING_SERVER_URL`
    /// configured (so the app is genuinely offline -- no adapter exists at
    /// all) must survive `terminate` + relaunch.
    ///
    /// `app.terminate()` is XCTest's own kill of the target process; it
    /// does not deliver a cooperative shutdown to the app the way a user
    /// swipe-close does. The lane ALSO drives
    /// `devicectl device process terminate` around this suite
    /// (`tooling/ios-lanes/device.mjs`), which is the out-of-process,
    /// signal-based kill; both paths are exercised and the doc names which
    /// is which rather than letting "hard kill" cover both silently.
    func testOfflineMutationSurvivesHardKillAndRelaunchOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild(resetStore: true)

        capture(app, title: "Durable across a kill")
        XCTAssertTrue(
            app.staticTexts["task-row-Durable across a kill"].waitForExistence(timeout: 15),
            "the mutation was never accepted locally, so the durability claim would be vacuous"
        )

        app.terminate()

        // Relaunch WITHOUT resetting the store -- the whole point.
        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["KEEPLING_DEVICE_ATTESTATION_PROBE"] = "1"
        relaunched.launch()

        XCTAssertTrue(
            relaunched.staticTexts["task-row-Durable across a kill"].waitForExistence(timeout: 25),
            "a locally accepted mutation did not survive a hard kill and relaunch on real flash storage"
        )
    }

    /// Exactly once, not at least once. A relaunch that replays its own
    /// durable state must not project the same mutation twice -- the
    /// on-device analogue of the restored-backup replay prohibition. This
    /// asserts against the rendered list, which is the only surface a
    /// duplicate could reach without a server.
    func testRelaunchDoesNotDuplicateADurableMutationOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild(resetStore: true)

        capture(app, title: "Exactly once")
        XCTAssertTrue(app.staticTexts["task-row-Exactly once"].waitForExistence(timeout: 15))

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["KEEPLING_DEVICE_ATTESTATION_PROBE"] = "1"
        relaunched.launch()

        XCTAssertTrue(relaunched.staticTexts["task-row-Exactly once"].waitForExistence(timeout: 25))
        XCTAssertEqual(
            relaunched.staticTexts.matching(identifier: "task-row-Exactly once").count, 1,
            "the relaunch projected the same durable mutation more than once"
        )
    }

    /// A durable capture DRAFT (D-35) is the piece of state a person is
    /// most likely to lose to a no-notice kill, because it is the one they
    /// have not committed yet. It must survive on real storage.
    func testUnsentCaptureDraftSurvivesAHardKillOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild(resetStore: true)

        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 20))
        newTaskButton.tap()
        let titleField = app.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText("Half-typed thought")

        // Killed mid-capture: no Add, no dismissal, no cooperative save.
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["KEEPLING_DEVICE_ATTESTATION_PROBE"] = "1"
        relaunched.launch()
        relaunched.buttons["new-task-button"].tap()

        let restored = relaunched.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 20))
        XCTAssertEqual(
            restored.value as? String, "Half-typed thought",
            "a durable capture draft did not survive a no-notice kill on the device"
        )
    }

    // MARK: - Reconnect restores correctness with no background wake

    /// Criterion 3's reconnect half, in the form that is honestly provable
    /// here: the app is backgrounded, foregrounded, and must render its
    /// persisted state correctly with no background wake having been
    /// scheduled or fired. Real BGTaskScheduler wake scheduling is NOT
    /// asserted -- Apple schedules it opportunistically and it is not
    /// assertable (disclosed by name in docs/testing/ios-dogfood.md).
    func testBackgroundAndForegroundRestoresCorrectnessOnPhysicalDevice() throws {
        let app = launchBoundToInstalledBuild(resetStore: true)

        capture(app, title: "Survives a background trip")
        XCTAssertTrue(app.staticTexts["task-row-Survives a background trip"].waitForExistence(timeout: 15))

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            app.staticTexts["task-row-Survives a background trip"].waitForExistence(timeout: 20),
            "state was not correct after a real background/foreground trip on device"
        )
    }
}
