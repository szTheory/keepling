import Foundation
import GRDB
@testable import KeeplingCore

/// Generates the two committed adversarial fixture databases under
/// `Tests/StorageTests/Fixtures/` the FIRST time any test needs them, using
/// the real production migration/store code paths rather than hand-crafted
/// SQL -- so the fixtures are byte-for-byte what this build's own code
/// would produce, never an approximation. Once generated, the files are
/// committed to git and every subsequent test run finds them already
/// present and reuses them unchanged (`ensure*` is idempotent: a fixture
/// that already exists on disk is never regenerated or touched).
///
/// iOS Simulator test hosts run as ordinary macOS processes with full host
/// filesystem access (there is no on-device-style container boundary), so
/// `#filePath` -- resolved at compile time to this very file's absolute
/// path in the checked-out repository -- is a reliable way to locate the
/// repository root without any bundle-resource plumbing.
enum FixtureFactory {
    static var fixturesDirectory: URL {
        // #filePath == .../apps/ios/Tests/StorageTests/FixtureFactory.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StorageTests
            .appendingPathComponent("Fixtures")
    }

    static var migration1FixturePath: String {
        fixturesDirectory.appendingPathComponent("migration-1.sqlite").path
    }

    static var corruptedChecksumFixturePath: String {
        fixturesDirectory.appendingPathComponent("corrupted-checksum.sqlite").path
    }

    /// A committed database file created at migration 1 only, which
    /// `MigrationLedgerTests` proves migrates forward to 2 cleanly.
    static func ensureMigration1Fixture() throws {
        let path = migration1FixturePath
        guard !FileManager.default.fileExists(atPath: path) else { return }

        let workingPath = tempPath()
        defer { try? FileManager.default.removeItem(atPath: workingPath) }

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }
        try FileManager.default.createDirectory(
            atPath: (workingPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let pool = try DatabasePool(path: workingPath, configuration: configuration)
        try MigrationLedger.apply(
            [MigrationLedger.MigrationDefinition(version: Migration0001Initial.version, sql: Migration0001Initial.sql)],
            to: pool
        )
        try pool.writeWithoutTransaction { db in _ = try db.checkpoint(.truncate) }

        try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: workingPath, toPath: path)
    }

    /// A committed database file, fully migrated, whose `schema_migrations`
    /// checksum for version 1 has been corrupted -- adversarial, not
    /// illustrative: `MigrationLedgerTests` proves opening it throws the
    /// checksum-drift case and leaves the file byte-identical afterwards.
    static func ensureCorruptedChecksumFixture() throws {
        let path = corruptedChecksumFixturePath
        guard !FileManager.default.fileExists(atPath: path) else { return }

        let workingPath = tempPath()
        defer { try? FileManager.default.removeItem(atPath: workingPath) }

        let store = try GRDBLocalStore(path: workingPath)
        try store.__test_executeRawSQL(
            "UPDATE schema_migrations SET checksum = ? WHERE version = 1",
            arguments: [String(repeating: "0", count: 64)]
        )
        try store.__test_checkpointTruncate()

        try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: workingPath, toPath: path)

        // Stabilize: opening a freshly-checkpointed WAL database for the
        // very first time can grow the main file by one page as a SQLite
        // implementation detail (unrelated to this ledger's own writes --
        // the open throws checksum-drift before the ledger executes any
        // SQL of its own). Pre-touch the committed copy here, once, during
        // fixture generation, so the byte-identical assertion a real test
        // makes compares two genuinely stable states rather than crossing
        // that one-time growth itself.
        _ = try? GRDBLocalStore(path: path)
        var rawConfiguration = Configuration()
        rawConfiguration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let rawPool = try DatabasePool(path: path, configuration: rawConfiguration)
        try rawPool.writeWithoutTransaction { db in _ = try db.checkpoint(.truncate) }
    }

    /// A private, writable COPY of a committed fixture, plus its `-wal`
    /// and `-shm` siblings when they exist.
    ///
    /// Every consumer must open a copy, never the committed file itself.
    /// Opening the committed file in place is what made
    /// `testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row`
    /// vacuous: the open MIGRATES the database, so the committed fixture
    /// arrived at `[1, 2, 3]` and the assertion then compared an
    /// already-migrated file against the migrated state it expected --
    /// passing without a migration ever running. The mutated file was
    /// subsequently committed, which made every fresh checkout tautological
    /// too, not merely every run after the first. It also dirtied the
    /// working tree on every test run.
    static func writableCopy(ofFixtureAtPath path: String) throws -> String {
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let name = (path as NSString).lastPathComponent
        let destination = destinationDirectory.appendingPathComponent(name).path
        try FileManager.default.copyItem(atPath: path, toPath: destination)
        // A WAL database is a three-file durable unit. Copying only the main
        // file would silently discard committed-but-uncheckpointed pages.
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
            try FileManager.default.copyItem(atPath: path + suffix, toPath: destination + suffix)
        }
        return destination
    }

    /// A writable copy of the migration-1 fixture, generating the committed
    /// original first if this checkout has never produced it.
    static func migration1FixtureCopy() throws -> String {
        try ensureMigration1Fixture()
        return try writableCopy(ofFixtureAtPath: migration1FixturePath)
    }

    /// A writable copy of the corrupted-checksum fixture, generating the
    /// committed original first if this checkout has never produced it.
    static func corruptedChecksumFixtureCopy() throws -> String {
        try ensureCorruptedChecksumFixture()
        return try writableCopy(ofFixtureAtPath: corruptedChecksumFixturePath)
    }

    private static func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("fixture-source.sqlite").path
    }
}
