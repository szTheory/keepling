import Foundation
import GRDB

/// The app-owned `schema_migrations(version, checksum, applied_at)` ledger
/// (D-04 G4, D-37). GRDB's own `DatabaseMigrator` provides ordering and
/// idempotent apply semantics; it is deliberately NOT used as the source of
/// truth here (04-PATTERNS.md) because this ledger must be externally
/// provable -- a plain table any SQLite tool can inspect -- and must halt
/// rather than repair on drift, which is the opposite of what
/// `DatabaseMigrator.eraseDatabaseOnSchemaChange` does.
///
/// Extracted out of `GRDBLocalStore` so it is independently testable
/// against a bare `DatabasePool` and a synthetic migration list, without
/// needing to fabricate an entire `GRDBLocalStore`.
public enum MigrationLedger {
    /// One migration this build knows how to apply. Distinct from the
    /// concrete `Migration000NFoo` enums under `Storage/Migrations/` --
    /// this is the shape the ledger operates on, so a test can hand it a
    /// synthetic (including deliberately broken) migration list.
    public struct MigrationDefinition: Sendable {
        public let version: Int
        public let sql: String

        public init(version: Int, sql: String) {
            self.version = version
            self.sql = sql
        }
    }

    /// Applies every migration in `migrations` (in the order given) that
    /// this database has not yet recorded, each inside its OWN immediate
    /// transaction -- never one shared transaction across the whole list.
    /// A failure applying migration N never touches migration N-1's
    /// already-committed state (D-04 G4 "schema unchanged from before that
    /// migration").
    ///
    /// Checks for an ahead-of-ledger version FIRST, on a read-only
    /// connection, before attempting to write anything: a database a newer
    /// build already migrated must never be opened for writes by an older
    /// one (D-37).
    public static func apply(_ migrations: [MigrationDefinition], to dbPool: DatabasePool) throws {
        try dbPool.read { db in
            try checkNotAheadOfLedger(migrations, db: db)
        }

        for migration in migrations {
            try dbPool.write { db in
                try applyOne(migration, db: db)
            }
        }

        // A second, post-apply check: a migration's own SQL is trusted
        // input from this build, but nothing prevents the ledger already
        // recording a version above `migrations.count` even after every
        // known migration above has been (idempotently) confirmed --
        // e.g. a database this same build partially wrote before a crash
        // mid-upgrade, then later mutated externally. Cheap, and correct
        // to re-check.
        try dbPool.read { db in
            try checkNotAheadOfLedger(migrations, db: db)
        }
    }

    private static func applyOne(_ migration: MigrationDefinition, db: Database) throws {
        let checksum = sha256Hex(migration.sql)
        if try db.tableExists("schema_migrations") {
            let existingChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum FROM schema_migrations WHERE version = ?",
                arguments: [migration.version]
            )
            if let existingChecksum {
                guard existingChecksum == checksum else {
                    throw StoreUnrecoverable.checksumDrift(version: migration.version)
                }
                // Already applied with a matching checksum -- apply
                // nothing, mutate no row.
                return
            }
        }

        do {
            try db.execute(sql: migration.sql)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (?, ?, ?)",
                arguments: [migration.version, checksum, ISO8601DateFormatter().string(from: Date())]
            )
        } catch {
            throw StoreUnrecoverable.migrationMidApplyFailure(version: migration.version)
        }
    }

    private static func checkNotAheadOfLedger(_ migrations: [MigrationDefinition], db: Database) throws {
        guard try db.tableExists("schema_migrations") else { return }
        let knownMax = migrations.map(\.version).max() ?? 0
        if let ahead = try Int.fetchOne(
            db,
            sql: "SELECT version FROM schema_migrations WHERE version > ? ORDER BY version LIMIT 1",
            arguments: [knownMax]
        ) {
            throw StoreUnrecoverable.aheadOfLedger(foundVersion: ahead, knownVersionCount: migrations.count)
        }
    }
}
