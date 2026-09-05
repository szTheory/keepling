import XCTest
@testable import KeeplingCore

/// `DurableUnit`'s own unit tests: the db/-wal/-shm all-or-none contract
/// for `move`/`copy`/`delete`, isolated from the settlement/backup-replay
/// scenarios `SettlementTests`/`BackupReplayTests` build on top of it
/// (04-06-PLAN.md Task 2 acceptance criteria).
final class DurableUnitTests: XCTestCase {
    private func makeUnitDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ contents: String, to path: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testCopyActsOnAllThreeExistingMembersOrThrowsWithoutActingOnAny() throws {
        let sourceDir = makeUnitDirectory()
        let destDir = makeUnitDirectory()
        let sourceDb = sourceDir.appendingPathComponent("db.sqlite").path
        try write("db", to: sourceDb)
        try write("wal", to: sourceDb + "-wal")
        try write("shm", to: sourceDb + "-shm")

        let unit = DurableUnit(databasePath: sourceDb)
        let destDb = destDir.appendingPathComponent("db.sqlite").path

        // Force the copy to fail on the SECOND member (-wal) after the
        // first (the database file) has already copied -- proves the
        // already-copied member is rolled back, not left behind.
        XCTAssertThrowsError(try unit.copy(to: destDb, __test_failAt: .wal)) { error in
            XCTAssertEqual(error as? DurableUnit.DurableUnitError, .partialOperationPrevented(.wal))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb), "a forced mid-copy failure must leave the destination database file absent")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb + "-shm"))

        // Sanity: an unforced copy succeeds and copies all three.
        try unit.copy(to: destDb)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb + "-shm"))
        // The source is untouched by a copy.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDb))
    }

    func testMoveActsOnAllThreeExistingMembersOrThrowsWithoutActingOnAny() throws {
        let sourceDir = makeUnitDirectory()
        let destDir = makeUnitDirectory()
        let sourceDb = sourceDir.appendingPathComponent("db.sqlite").path
        try write("db", to: sourceDb)
        try write("wal", to: sourceDb + "-wal")
        try write("shm", to: sourceDb + "-shm")

        let unit = DurableUnit(databasePath: sourceDb)
        let destDb = destDir.appendingPathComponent("db.sqlite").path

        XCTAssertThrowsError(try unit.move(to: destDb, __test_failAt: .shm)) { error in
            XCTAssertEqual(error as? DurableUnit.DurableUnitError, .partialOperationPrevented(.shm))
        }
        // A rolled-back move must leave every member back at the SOURCE,
        // not merely absent from the destination -- a move that "fails"
        // by losing data is worse than one that never started.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDb))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDb + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDb + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDb + "-shm"))

        try unit.move(to: destDb)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceDb), "an unforced move must remove the source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDb + "-shm"))
    }

    func testDeleteActsOnAllThreeExistingMembersOrThrowsWithoutActingOnAny() throws {
        let directory = makeUnitDirectory()
        let db = directory.appendingPathComponent("db.sqlite").path
        try write("db", to: db)
        try write("wal", to: db + "-wal")
        try write("shm", to: db + "-shm")

        let unit = DurableUnit(databasePath: db)
        XCTAssertThrowsError(try unit.delete(__test_failAt: .shm)) { error in
            XCTAssertEqual(error as? DurableUnit.DurableUnitError, .partialOperationPrevented(.shm))
        }
        // A rolled-back delete must leave every member exactly as it was.
        XCTAssertTrue(FileManager.default.fileExists(atPath: db))
        XCTAssertTrue(FileManager.default.fileExists(atPath: db + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: db + "-shm"))

        try unit.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: db))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db + "-shm"))
    }

    func testDeleteToleratesAMissingSidecarWithoutTreatingItAsAFailure() throws {
        let directory = makeUnitDirectory()
        let db = directory.appendingPathComponent("db.sqlite").path
        try write("db", to: db) // No -wal/-shm sidecars at all.

        try DurableUnit(databasePath: db).delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: db))
    }

    func testExcludeFromBackupMarksEveryExistingMember() throws {
        let directory = makeUnitDirectory()
        let db = directory.appendingPathComponent("db.sqlite").path
        try write("db", to: db)
        try write("wal", to: db + "-wal")

        let unit = DurableUnit(databasePath: db)
        try unit.excludeFromBackup()
        XCTAssertTrue(try unit.isFullyExcludedFromBackup())

        let values = try URL(fileURLWithPath: db).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
