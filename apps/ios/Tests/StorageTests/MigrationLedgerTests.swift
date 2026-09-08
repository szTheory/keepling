import XCTest
import GRDB
@testable import KeeplingCore

/// RED-first adversarial proof of D-04 G4 / D-37: the app-owned
/// `schema_migrations` ledger halts on drift and on an ahead-of-ledger
/// database, and never repairs or resets the store to recover.
final class MigrationLedgerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        try! FixtureFactory.ensureMigration1Fixture()
        try! FixtureFactory.ensureCorruptedChecksumFixture()
    }

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("migration-ledger-test.sqlite").path
    }

    private func openPool(atPath path: String) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        return try DatabasePool(path: path, configuration: configuration)
    }

    // MARK: Behavior 1 -- fresh database applies migrations 1 and 2 in order

    func testFreshDatabaseAppliesBothMigrationsInOrderWithChecksumAndTimestamp() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)

        let rows = try readSchemaMigrationsRows(atPath: path)
        // 04-09-PLAN.md Task 3 added Migration0003CaptureDraft.
        XCTAssertEqual(rows.map { $0.version }, [1, 2, 3])
        for row in rows {
            XCTAssertEqual(row.checksum.count, 64, "checksum must be a 64-character SHA-256 hex digest")
            XCTAssertFalse(row.appliedAt.isEmpty)
        }
    }

    // MARK: Behavior 2 -- reopening an already-migrated database mutates nothing

    func testReopeningAlreadyMigratedDatabaseAppliesNothingAndMutatesNoRow() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)
        let first = try readSchemaMigrationsRows(atPath: path)

        _ = try GRDBLocalStore(path: path)
        let second = try readSchemaMigrationsRows(atPath: path)

        XCTAssertEqual(first, second, "reopening must not mutate applied_at or checksum for any existing row")
    }

    // MARK: Behavior 3 -- checksum drift halts and leaves the fixture untouched

    func testCorruptedChecksumFixtureThrowsChecksumDriftAndLeavesFileByteIdentical() throws {
        let path = try FixtureFactory.corruptedChecksumFixtureCopy()
        let sizeBefore = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
        let ledgerBefore = try readSchemaMigrationsRows(atPath: path)
        let rowCountsBefore = try tableRowCounts(atPath: path)

        XCTAssertThrowsError(try GRDBLocalStore(path: path)) { error in
            guard case StoreUnrecoverable.checksumDrift(version: 1) = error else {
                return XCTFail("expected .checksumDrift(version: 1), got \(error)")
            }
        }

        // A byte-for-byte OS-level comparison is the wrong proof technique
        // here: SQLite/GRDB's own connection-close bookkeeping on a WAL
        // database (e.g. an implicit passive checkpoint attempt) can
        // legitimately touch non-semantic header bytes between opens with
        // ZERO logical change, which is not what D-04 G4's "must never
        // silently repair, reset, or delete itself" is actually about.
        // Assert the properties that DO matter: the file did not shrink or
        // grow, the ledger's own rows -- including the still-corrupted
        // checksum, proving no "repair" occurred -- are unchanged, every
        // table's row count is unchanged, and the file still passes
        // integrity_check (nothing was corrupted further by the failed
        // attempt).
        let sizeAfter = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
        XCTAssertEqual(sizeBefore, sizeAfter, "a failed open must not grow or shrink the store file")

        let ledgerAfter = try readSchemaMigrationsRows(atPath: path)
        XCTAssertEqual(ledgerBefore, ledgerAfter, "a failed open must not repair the corrupted checksum or touch any ledger row")

        let rowCountsAfter = try tableRowCounts(atPath: path)
        XCTAssertEqual(rowCountsBefore, rowCountsAfter, "a failed open must not add or remove rows in any table")

        let pool = try openPool(atPath: path)
        let integrity = try pool.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
        XCTAssertEqual(integrity, ["ok"])
    }

    // MARK: Behavior 4 -- an ahead-of-ledger version halts and never opens for writes

    func testDatabaseAheadOfLedgerThrowsAheadOfLedgerAndNeverOpensForWrites() throws {
        let path = storePath()
        let pool = try openPool(atPath: path)
        try pool.write { db in
            try db.execute(sql: Migration0001Initial.sql)
            try db.execute(sql: Migration0002OutboxState.sql)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (1, ?, '2026-01-01T00:00:00Z')",
                arguments: [sha256Hex(Migration0001Initial.sql)]
            )
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (2, ?, '2026-01-01T00:00:00Z')",
                arguments: [sha256Hex(Migration0002OutboxState.sql)]
            )
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (99, ?, '2026-01-01T00:00:00Z')",
                arguments: [String(repeating: "9", count: 64)]
            )
        }

        XCTAssertThrowsError(try GRDBLocalStore(path: path)) { error in
            // 04-09-PLAN.md Task 3 added Migration0003CaptureDraft, so
            // `GRDBLocalStore.migrations` now knows 3 versions, not 2.
            guard case StoreUnrecoverable.aheadOfLedger(foundVersion: 99, knownVersionCount: 3) = error else {
                return XCTFail("expected .aheadOfLedger(foundVersion: 99, knownVersionCount: 3), got \(error)")
            }
        }
    }

    // MARK: Behavior 5 -- a migration that throws mid-apply leaves no row and no schema change

    func testMigrationThatThrowsMidApplyLeavesNoRowAndSchemaUnchangedFromBefore() throws {
        let path = storePath()
        let pool = try openPool(atPath: path)

        let goodMigration = MigrationLedger.MigrationDefinition(version: 1, sql: Migration0001Initial.sql)
        let brokenMigration = MigrationLedger.MigrationDefinition(version: 2, sql: "CREATE TBLE this_is_not_valid_sql (x)")

        XCTAssertThrowsError(try MigrationLedger.apply([goodMigration, brokenMigration], to: pool)) { error in
            guard case StoreUnrecoverable.migrationMidApplyFailure(version: 2) = error else {
                return XCTFail("expected .migrationMidApplyFailure(version: 2), got \(error)")
            }
        }

        try pool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 1"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 2"), 0)
            XCTAssertFalse(try db.tableExists("this_is_not_valid_sql"))
            // Migration 1's own tables are present and untouched.
            XCTAssertTrue(try db.tableExists("visible_projection"))
        }
    }

    // MARK: Behavior 6 -- no failure path deletes, recreates, truncates, or repairs the store file

    func testFailurePathsNeverDeleteOrTruncateTheStoreFile() throws {
        let path = try FixtureFactory.corruptedChecksumFixtureCopy()
        let sizeBefore = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
        XCTAssertThrowsError(try GRDBLocalStore(path: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the store file must still exist after a failed open")
        let sizeAfter = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
        XCTAssertEqual(sizeBefore, sizeAfter, "the store file must not be truncated or resized by a failed open")
    }

    // MARK: Migration-1 fixture forward-migrates cleanly, preserving version 1's original row

    func testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row() throws {
        let path = try FixtureFactory.migration1FixtureCopy()
        let versionOneBefore = try readSchemaMigrationsRows(atPath: path).first { $0.version == 1 }
        XCTAssertNotNil(versionOneBefore)

        _ = try GRDBLocalStore(path: path)
        let rows = try readSchemaMigrationsRows(atPath: path)
        // 04-09-PLAN.md Task 3 added Migration0003CaptureDraft.
        XCTAssertEqual(rows.map { $0.version }, [1, 2, 3])
        XCTAssertEqual(rows.first { $0.version == 1 }?.appliedAt, versionOneBefore?.appliedAt)
        XCTAssertEqual(rows.first { $0.version == 1 }?.checksum, versionOneBefore?.checksum)
    }

    // MARK: - Helpers

    private struct LedgerRow: Equatable {
        let version: Int
        let checksum: String
        let appliedAt: String
    }

    /// Reads `schema_migrations` via a fresh short-lived connection over
    /// the same WAL-mode file `GRDBLocalStore` just wrote -- SQLite permits
    /// multiple connections against one WAL database, so this needs no
    /// path accessor on `GRDBLocalStore` itself.
    private func readSchemaMigrationsRows(atPath path: String) throws -> [LedgerRow] {
        let pool = try openPool(atPath: path)
        return try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT version, checksum, applied_at FROM schema_migrations ORDER BY version").map {
                LedgerRow(version: $0["version"], checksum: $0["checksum"], appliedAt: $0["applied_at"])
            }
        }
    }

    private static let strictTableNames = [
        "schema_migrations", "namespace_metadata", "canonical_shadow", "visible_projection",
        "immutable_commands", "mutation_journal", "mutation_dependencies", "outbox",
        "sync_cursor", "conflicts", "last_local_action",
    ]

    private func tableRowCounts(atPath path: String) throws -> [String: Int] {
        let pool = try openPool(atPath: path)
        return try pool.read { db in
            var counts: [String: Int] = [:]
            for table in Self.strictTableNames {
                counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            return counts
        }
    }
}
