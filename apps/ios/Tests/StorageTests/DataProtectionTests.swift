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

    // MARK: - Device-only half: a locked-device background write must not I/O-error or 0xdead10cc

    /// This assertion can only be genuinely observed on a physical device
    /// with a passcode set: the simulator has no lock state and enforces
    /// no Data Protection at all (`FileProtectionType` attributes can be
    /// set and read back, but iOS never actually restricts file access on
    /// the simulator the way it does on a locked device). Plan 04-16's
    /// physical-device lane is the one place this can be driven for real
    /// (`devicectl device process terminate`-style real lock-state
    /// control, not available to an XCTest host process here) -- see
    /// docs/testing/ios-testing.md's G7 disclosure. Recorded as a named
    /// skip rather than a false green in every lane this plan's own
    /// verification runs.
    func testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate() throws {
        throw XCTSkip(
            "G7's locked-device write proof requires a physical device with a passcode set and real " +
            "lock-state control this test target cannot exercise (simulator: no lock state/Data Protection " +
            "enforcement at all; this build: no devicectl-driven lock harness yet -- Plan 04-16 supplies it). " +
            "See docs/testing/ios-testing.md."
        )
    }
}
