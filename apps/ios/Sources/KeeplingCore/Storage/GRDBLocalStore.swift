import CryptoKit
import Foundation
import GRDB

/// GRDB-backed `LocalStorePort` (D-01). Mirrors
/// `apps/desktop/store-worker/local-store.ts`'s `NodeSqliteLocalStore`
/// invariants exactly (04-PATTERNS.md): every PRAGMA set before any
/// migration runs, one `BEGIN IMMEDIATE`-equivalent transaction
/// (`dbPool.write { }`) per local mutation, an app-owned checksummed
/// migration ledger layered on top of GRDB's raw `Database` access (GRDB's
/// own migrator is not used as the source of truth for that ledger --
/// 04-PATTERNS.md "GRDB's own internal migration-tracking table is not the
/// D-37 schema_migrations(version, checksum, applied_at) ledger this phase
/// requires"), and terminal-acknowledgement settlement that is a no-op on
/// exact replay (D-09).
public final class GRDBLocalStore: LocalStorePort, @unchecked Sendable {
    private let dbPool: DatabasePool

    public enum StoreError: Error, Equatable {
        case fencedForWrites(String)
        case fingerprintMismatch
        case mutationIdentityMismatch
        case unknownAcknowledgementMutation
        case migrationChecksumMismatch(version: Int)
        case migrationSetAheadOfLedger(foundVersion: Int, knownVersionCount: Int)
        case invalidPullPage
    }

    /// Opens (creating if needed) the store at `path`. Every PRAGMA D-04 G1
    /// requires is set inside `prepareDatabase`, which GRDB calls for EVERY
    /// connection `DatabasePool` opens (writer and every reader) -- not
    /// just the writer -- satisfying "verified per connection" before any
    /// migration runs.
    public init(path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.busyMode = .timeout(2.5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }
        dbPool = try DatabasePool(path: path, configuration: configuration)
        try Self.applyMigrations(dbPool)
        // D-08: the store file carries iOS file-protection, never
        // SQLCipher (D-07 rejects SQLCipher explicitly). Plan 04-06 asserts
        // the exact protection class; this call sets the class this plan
        // already commits to so a later assertion has something real to
        // check, rather than leaving the file at the platform default.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
    }

    // MARK: - Migration ledger (D-04 G4, D-37)

    private static let migrations: [(version: Int, sql: String)] = [
        (Migration0001Initial.version, Migration0001Initial.sql),
        (Migration0002OutboxState.version, Migration0002OutboxState.sql),
    ]

    private static func applyMigrations(_ dbPool: DatabasePool) throws {
        try dbPool.write { db in
            let ledgerPresent = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations')
                """) ?? false

            for migration in migrations {
                let checksum = sha256Hex(migration.sql)
                var present = ledgerPresent
                // The ledger table itself is created BY migration 1, so it
                // is absent for the very first iteration on a fresh store.
                if try db.tableExists("schema_migrations") { present = true }
                if present {
                    let existingChecksum = try String.fetchOne(
                        db,
                        sql: "SELECT checksum FROM schema_migrations WHERE version = ?",
                        arguments: [migration.version]
                    )
                    if let existingChecksum {
                        if existingChecksum != checksum {
                            throw StoreError.migrationChecksumMismatch(version: migration.version)
                        }
                        continue
                    }
                }
                try db.execute(sql: migration.sql)
                try db.execute(
                    sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (?, ?, ?)",
                    arguments: [migration.version, checksum, ISO8601DateFormatter().string(from: Date())]
                )
            }

            if try db.tableExists("schema_migrations") {
                let ahead = try Int.fetchOne(
                    db,
                    sql: "SELECT version FROM schema_migrations WHERE version > ? ORDER BY version LIMIT 1",
                    arguments: [migrations.count]
                )
                if let ahead {
                    throw StoreError.migrationSetAheadOfLedger(foundVersion: ahead, knownVersionCount: migrations.count)
                }
            }
        }
    }

    // MARK: - Fencing (D-03 namespace fencing)

    private func assertNotFenced(_ db: Database) throws {
        let fenced = try String.fetchOne(db, sql: "SELECT value FROM namespace_metadata WHERE key = 'sync_fence'")
        if let fenced { throw StoreError.fencedForWrites(fenced) }
    }

    // MARK: - Capture / acceptance (D-03/D-04 G2)

    public func acceptMutation(_ mutation: LocalMutation) throws -> LocalAcceptance {
        let computedFingerprint = sha256Hex(mutation.commandBytes)
        guard computedFingerprint == mutation.fingerprint else { throw StoreError.fingerprintMismatch }

        try dbPool.write { db in
            try self.assertNotFenced(db)
            let effectSnapshotJSON = "{\"id\":\"\(mutation.taskId)\",\"revision\":0,\"title\":\(jsonStringLiteral(mutation.title))}"
            try db.execute(
                sql: """
                INSERT INTO immutable_commands(
                  mutation_id, task_id, command_bytes, fingerprint, accepted_at,
                  resource_keys_json, effect_snapshot_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    mutation.mutationId, mutation.taskId, mutation.commandBytes, mutation.fingerprint,
                    mutation.acceptedAt, jsonArrayLiteral(mutation.resourceKeys), effectSnapshotJSON,
                ]
            )
            try db.execute(
                sql: "INSERT INTO mutation_journal(mutation_id, outcome, terminal_snapshot_json) VALUES (?, 'pending', NULL)",
                arguments: [mutation.mutationId]
            )
            try db.execute(
                sql: "INSERT INTO visible_projection(task_id, title, sync_status) VALUES (?, ?, 'saved_on_this_mac')",
                arguments: [mutation.taskId, mutation.title]
            )
            try db.execute(
                sql: "INSERT INTO outbox(mutation_id, sequence) VALUES (?, COALESCE((SELECT MAX(sequence) + 1 FROM outbox), 1))",
                arguments: [mutation.mutationId]
            )
            // This return is the D-03 boundary: nothing above may report
            // local acceptance to the caller ahead of this closure
            // returning, because GRDB only commits once it returns
            // normally.
        }

        return LocalAcceptance(
            mutationId: mutation.mutationId,
            fingerprint: mutation.fingerprint,
            taskId: mutation.taskId,
            title: mutation.title
        )
    }

    // MARK: - Not implemented in this tracer plan

    public func applyPull(_ page: PullPage) throws {
        throw UnimplementedInTracerError("applyPull")
    }

    public func undoLastLocalAction() throws -> UndoResult {
        throw UnimplementedInTracerError("undoLastLocalAction")
    }

    public func resolveConflict(conflictId: String, selection: [String: String]) throws -> WorkspaceSnapshot {
        throw UnimplementedInTracerError("resolveConflict")
    }

    public func syncState() throws -> LocalSyncState {
        let outboxIds = try readyMutations().map(\.mutationId)
        return try dbPool.read { db in
            let cursor = try String.fetchOne(db, sql: "SELECT cursor FROM sync_cursor WHERE singleton = 1")
            let allOutbox = try String.fetchAll(db, sql: "SELECT mutation_id FROM outbox ORDER BY sequence")
            return LocalSyncState(cursor: cursor, outbox: allOutbox, readyPushes: outboxIds)
        }
    }

    // MARK: - Ready pushes (transport-agnostic outbox read)

    public func readyMutations() throws -> [LocalMutation] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT immutable_commands.mutation_id, immutable_commands.task_id,
                       immutable_commands.command_bytes, immutable_commands.fingerprint,
                       immutable_commands.accepted_at, immutable_commands.resource_keys_json,
                       visible_projection.title
                FROM outbox
                JOIN immutable_commands USING (mutation_id)
                JOIN visible_projection ON visible_projection.task_id = immutable_commands.task_id
                WHERE outbox.state <> 'in_flight'
                ORDER BY outbox.sequence
                """)
            return rows.map { row in
                LocalMutation(
                    mutationId: row["mutation_id"],
                    taskId: row["task_id"],
                    commandBytes: row["command_bytes"],
                    fingerprint: row["fingerprint"],
                    acceptedAt: row["accepted_at"],
                    resourceKeys: decodeJSONStringArray(row["resource_keys_json"]),
                    title: row["title"]
                )
            }
        }
    }

    // MARK: - Settlement (D-04 G8 / D-09 replay-no-op)

    @discardableResult
    public func acknowledge(_ acknowledgement: SyncAcknowledgement) throws -> WorkspaceSnapshot {
        try dbPool.write { db in
            let pending = try Row.fetchOne(db, sql: """
                SELECT immutable_commands.fingerprint AS fingerprint, immutable_commands.task_id AS task_id
                FROM outbox JOIN immutable_commands USING (mutation_id)
                WHERE outbox.mutation_id = ?
                """, arguments: [acknowledgement.mutationId])

            guard let pending else {
                // Not pending -- either unknown, or already settled. A
                // replay of the SAME acknowledgement is a no-op success
                // (D-09); anything else is an error.
                let terminalOutcome = try String.fetchOne(
                    db, sql: "SELECT outcome FROM mutation_journal WHERE mutation_id = ?",
                    arguments: [acknowledgement.mutationId]
                )
                if terminalOutcome == acknowledgement.outcome.rawValue { return }
                throw StoreError.unknownAcknowledgementMutation
            }

            let pendingFingerprint: String = pending["fingerprint"]
            guard pendingFingerprint == acknowledgement.fingerprint else { throw StoreError.fingerprintMismatch }
            let taskId: String = pending["task_id"]

            if acknowledgement.outcome == .accepted || acknowledgement.outcome == .alreadySatisfied {
                try db.execute(
                    sql: """
                    INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
                    ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
                    """,
                    arguments: [taskId, acknowledgement.snapshotJSON]
                )
                try db.execute(
                    sql: "UPDATE visible_projection SET sync_status = 'synced' WHERE task_id = ?",
                    arguments: [taskId]
                )
            }

            try db.execute(
                sql: "UPDATE mutation_journal SET outcome = ?, terminal_snapshot_json = ? WHERE mutation_id = ?",
                arguments: [acknowledgement.outcome.rawValue, acknowledgement.snapshotJSON, acknowledgement.mutationId]
            )
            // Terminal for every outcome, exactly as the desktop store
            // does: the server has decided, and retrying the same
            // immutable bytes cannot change its mind.
            try db.execute(sql: "DELETE FROM outbox WHERE mutation_id = ?", arguments: [acknowledgement.mutationId])
        }
        return try snapshot()
    }

    // MARK: - Snapshot

    public func snapshot() throws -> WorkspaceSnapshot {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT task_id, title, sync_status, notes, completed_at, trashed_at, planned
                FROM visible_projection ORDER BY rowid
                """)
            let tasks = rows.map { row in
                ProjectionRow(
                    taskId: row["task_id"],
                    title: row["title"],
                    syncStatus: row["sync_status"],
                    notes: row["notes"],
                    completedAt: row["completed_at"],
                    trashedAt: row["trashed_at"],
                    planned: (row["planned"] as Int) == 1
                )
            }
            return WorkspaceSnapshot(tasks: tasks)
        }
    }

    // MARK: - Diagnostics used by StorageTests

    /// Exposed for G1/G6-style durability-posture assertions: reads every
    /// PRAGMA this store depends on directly off a real connection, rather
    /// than trusting `prepareDatabase` silently ran.
    public func readDurabilityPosture() throws -> (foreignKeys: Bool, journalMode: String, synchronous: Int) {
        try dbPool.read { db in
            let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
            let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
            let synchronous = try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1
            return (foreignKeys == 1, journalMode, synchronous)
        }
    }

    public func countRows(in table: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }

    public func outboxState(forMutationId mutationId: String) throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT state FROM outbox WHERE mutation_id = ?", arguments: [mutationId])
        }
    }

    public func journalOutcome(forMutationId mutationId: String) throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT outcome FROM mutation_journal WHERE mutation_id = ?", arguments: [mutationId])
        }
    }

    /// Test-only: sets the namespace fence directly, bypassing the (not yet
    /// implemented in this tracer) revocation flow, so
    /// `TracerDurabilityTests` can exercise `assertNotFenced` without
    /// waiting on Plan 04-06's real fencing trigger.
    public func __test_setFence(reason: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO namespace_metadata(key, value) VALUES ('sync_fence', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [reason]
            )
        }
    }
}

// MARK: - Small helpers (no third-party JSON dependency needed for these shapes)

func sha256Hex(_ string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func jsonStringLiteral(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let encoded = String(data: data, encoding: .utf8)!
    // Strip the surrounding array brackets `["..."]` -> `"..."`.
    return String(encoded.dropFirst().dropLast())
}

private func jsonArrayLiteral(_ values: [String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: values)
    return String(data: data, encoding: .utf8)!
}

private func decodeJSONStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [String]
    else { return [] }
    return array
}
