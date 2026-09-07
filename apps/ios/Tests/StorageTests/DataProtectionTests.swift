import XCTest
@testable import KeeplingCore

/// D-04 gate G7: the store file's requested protection class. Split
/// honestly between what THIS lane (simulator) can prove and what only a
/// physical device with a passcode set can (docs/testing/ios-testing.md
/// carries the same disclosure, 04-06-PLAN.md Task 2).
final class DataProtectionTests: XCTestCase {

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("data-protection-test.sqlite").path
    }

    // MARK: - Simulator-provable half: the requested protection class

    /// Reads back via `URL.resourceValues(forKeys: [.fileProtectionKey])`,
    /// NOT `FileManager.attributesOfItem`'s `.protectionKey` -- empirically
    /// confirmed (this plan's own execution) that `attributesOfItem`
    /// reads back `nil` on the iOS Simulator's host filesystem even
    /// immediately after a successful `setAttributes` call, while the
    /// `URLResourceValues` accessor reads back the real value. Disclosed
    /// in docs/testing/ios-testing.md so a future test reaching for the
    /// `FileManager` accessor does not reintroduce a false negative.
    private func offMain<T>(_ work: @escaping () throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        DispatchQueue.global().async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    func testStoreFileRequestsCompleteUntilFirstUserAuthenticationProtection() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)

        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileProtectionKey])
        XCTAssertEqual(
            values.fileProtection, .completeUntilFirstUserAuthentication,
            "the store file must request .completeUntilFirstUserAuthentication (D-04 G7)"
        )
        XCTAssertNotEqual(
            values.fileProtection, .complete,
            "G7 explicitly rejects .complete -- it would block sync while the device is locked"
        )
    }

    func testDurableUnitReportsFullyExcludedFromBackupOnceOpened() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)
        XCTAssertTrue(try DurableUnit(databasePath: path).isFullyExcludedFromBackup())
    }

    // MARK: - Device-only half (04-16-PLAN.md Task 3)

    /// G7 on REAL HARDWARE, where Data Protection is genuinely enforced.
    ///
    /// The `testStoreFileRequests...` case above runs everywhere, but on the
    /// simulator it proves only that an attribute round-trips: iOS never
    /// actually restricts file access on the simulator the way it does on a
    /// device, so the value read back there is a bookkeeping fact, not a
    /// protection fact. On a physical device the same read-back is the real
    /// class the kernel will enforce -- which is why this case exists
    /// separately and refuses to run on a simulator rather than being
    /// folded into the one above.
    ///
    /// It also asserts the class is NOT `.complete`: `.complete` would make
    /// the store unreadable while the phone is locked and would break sync
    /// on a phone in a pocket, which is exactly why G7 names
    /// `.completeUntilFirstUserAuthentication` instead.
    func testStoreProtectionClassOnPhysicalDeviceIsEnforceable() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "This is the PHYSICAL-DEVICE half of G7. On a simulator the protection class is bookkeeping " +
            "only -- iOS enforces no Data Protection there -- so passing here would attribute a hardware " +
            "claim to a simulator. Run it through `node tooling/verify-ios-phase.mjs --lane device`."
        )
        #else
        let path = storePath()
        let store = try GRDBLocalStore(path: path)

        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileProtectionKey])
        XCTAssertEqual(
            values.fileProtection, .completeUntilFirstUserAuthentication,
            "on real hardware the store must request .completeUntilFirstUserAuthentication (D-04 G7)"
        )
        XCTAssertNotEqual(
            values.fileProtection, .complete,
            "G7 rejects .complete on hardware: it would block sync whenever the phone is locked"
        )

        // A write that genuinely reaches real flash, so the class above is
        // proved on a file the store actually uses rather than on an empty
        // one it merely created.
        // `offMain`, matching every sibling suite in this target.
        // `GRDBLocalStore` asserts it is never entered from the main
        // thread, and XCTest runs test methods ON the main thread. A bare
        // call survived only because the guard's DEBUG escape hatch
        // (`mainThreadViolationHandler`) is compiled out of the Release
        // build installed on a device -- so this line passed on the
        // Simulator and hard-crashed the host the first time the bundle
        // was actually allowed to run on hardware:
        //   Fatal error: GRDBLocalStore.currentUndoAvailability() must
        //   never be called from the main thread
        XCTAssertNoThrow(try offMain { try store.currentUndoAvailability() })
        XCTAssertTrue(try DurableUnit(databasePath: path).isFullyExcludedFromBackup())

        // `unlockedSinceBoot` is the precondition that makes
        // `.completeUntilFirstUserAuthentication` readable at all. It is
        // recorded by `tooling/ios-device/resolve-devices.mjs` before the
        // lane runs (`devicectl device info lockState`), because this
        // process cannot observe the device's lock state from inside its
        // own sandbox.
        #endif
    }

    /// G7's remaining half -- a write performed WHILE THE DEVICE IS LOCKED
    /// -- is **BLOCKED**, and this is a deliberate, named skip rather than
    /// a silent omission or a false green.
    ///
    /// What is genuinely missing, precisely:
    ///
    ///  - a unit-test bundle cannot lock the device. `XCUIDevice`'s lock
    ///    control lives in the UI-testing framework, which this target does
    ///    not link, and `devicectl` exposes no lock verb at all (it exposes
    ///    `info lockState` -- a READ -- plus install, launch, terminate,
    ///    signal, reboot, and orientation; there is no `lock`);
    ///  - driving it from the UI-test target instead would need an
    ///    app-side, launch-env-gated "write on
    ///    protectedDataWillBecomeUnavailable" hook that does not exist, and
    ///    inventing one inside a test plan would be new production surface
    ///    added to make a gate go green.
    ///
    /// What IS proven, and recorded in the SUMMARY: the attached phone
    /// reports `passcodeRequired: true` from `devicectl device info
    /// lockState` (so the protection class is genuinely enforceable, not
    /// nominal), and the class itself reads back correctly on hardware in
    /// the case above.
    func testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate() throws {
        throw XCTSkip(
            "BLOCKED (not skipped for convenience): G7's locked-device WRITE requires locking a real phone " +
            "under program control. A unit-test bundle cannot -- XCUIDevice is UI-testing-only -- and " +
            "`devicectl` has no lock verb (only `info lockState`, a read). Driving it from the UI-test " +
            "target would require a new app-side protected-data hook, i.e. new production surface added " +
            "solely to pass a gate. The enforceable-class half runs on hardware in " +
            "testStoreProtectionClassOnPhysicalDeviceIsEnforceable, and the phone's passcodeRequired=true " +
            "is recorded by tooling/ios-device/resolve-devices.mjs. See docs/testing/ios-dogfood.md."
        )
    }
}
