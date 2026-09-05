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
        case invalidPullPage
        case outboxTransitionRejected(from: String, to: String)
    }

    #if DEBUG
    /// Test-only fault-injection points inside `acceptMutation`'s single
    /// transaction (D-04 G3). Named after the table-boundary each brackets,
    /// per `<behavior>`'s enumerated list: projection, command bytes,
    /// journal, dependency edges, outbox.
    ///
    /// `#if DEBUG`-gated: this entire enum and the closure property below
    /// compile out of Release builds, which is what excludes the fault
    /// seam from a shipped (Release-configuration) `Keepling` app binary
    /// while still living in `KeeplingCore` for `StorageTests` to reach via
    /// `@testable import` in Debug test builds.
    public enum FaultInjectionPoint: String, Sendable {
        case beforeProjection
        case afterProjectionBeforeCommandBytes
        case afterCommandBytesBeforeJournal
        case afterJournalBeforeDependencyEdges
        case afterDependencyEdgesBeforeOutbox
    }

    /// Set by a test to throw at a named point inside the acceptance
    /// write. `nil` (the production default) never fires.
    public var __test_injectFailure: ((FaultInjectionPoint) throws -> Void)?

    /// Called, if set, as the very first statement inside
    /// `acceptMutation`'s write transaction, with the real `Database` --
    /// lets a test register `afterNextTransaction(onCommit:onRollback:)`
    /// on the SAME transaction the acceptance write runs in, which is the
    /// structural (not inferred) proof D-04 G2 requires.
    public var __test_onTransactionStart: ((Database) -> Void)?

    /// Substituted by a test so the main-thread precondition below can be
    /// observed tripping without actually trapping the test host process
    /// (iOS's Foundation carries no `Process`/fork API a test could use to
    /// catch a real signal). `nil` in production: a real violation really
    /// traps via `preconditionFailure`.
    nonisolated(unsafe) public static var mainThreadViolationHandler: (@Sendable () -> Void)?
    #endif

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

    static let migrations: [MigrationLedger.MigrationDefinition] = [
        MigrationLedger.MigrationDefinition(version: Migration0001Initial.version, sql: Migration0001Initial.sql),
        MigrationLedger.MigrationDefinition(version: Migration0002OutboxState.version, sql: Migration0002OutboxState.sql),
    ]

    private static func applyMigrations(_ dbPool: DatabasePool) throws {
        try MigrationLedger.apply(migrations, to: dbPool)
    }

    // MARK: - Fencing (D-03 namespace fencing)

    private func assertNotFenced(_ db: Database) throws {
        let fenced = try String.fetchOne(db, sql: "SELECT value FROM namespace_metadata WHERE key = 'sync_fence'")
        if let fenced { throw StoreError.fencedForWrites(fenced) }
    }

    // MARK: - Main-thread discipline (D-04 G5, D-34)

    /// Traps in Debug builds if entered from the main thread. `<action>`
    /// requires this cover every store method a caller can reach, not only
    /// the acceptance write, because a stall reading the workspace snapshot
    /// on the main thread is exactly as much of a UI freeze as a stall
    /// writing one. GRDB's own internal WAL auto-checkpoint runs on GRDB's
    /// dedicated writer dispatch queue, never on the calling thread, so
    /// there is no separate application-reachable "checkpoint callback"
    /// surface to guard independently from the write path itself -- the
    /// per-call guard below is this precondition's complete coverage.
    private func assertNotOnMainThread(_ function: StaticString = #function) {
        guard Thread.isMainThread else { return }
        #if DEBUG
        if let handler = Self.mainThreadViolationHandler {
            handler()
            return
        }
        #endif
        preconditionFailure("GRDBLocalStore.\(function) must never be called from the main thread")
    }

    // MARK: - Capture / acceptance (D-03/D-04 G2/G3)

    public func acceptMutation(_ mutation: LocalMutation) throws -> LocalAcceptance {
        assertNotOnMainThread()
        let computedFingerprint = sha256Hex(mutation.commandBytes)
        guard computedFingerprint == mutation.fingerprint else { throw StoreError.fingerprintMismatch }

        // The fence check runs on a READ connection, BEFORE `dbPool.write`
        // is ever called -- a fenced namespace refuses the write without
        // opening (and then rolling back) a transaction at all, which is
        // what makes "zero commits AND zero rollbacks" an observable,
        // structural property rather than an artifact of where inside the
        // transaction the check happens to sit (D-04 G3 fence ordering).
        try dbPool.read { db in try self.assertNotFenced(db) }

        try dbPool.write { db in
            #if DEBUG
            self.__test_onTransactionStart?(db)
            try self.__test_injectFailure?(.beforeProjection)
            #endif
            try db.execute(
                sql: "INSERT INTO visible_projection(task_id, title, sync_status) VALUES (?, ?, 'saved_on_this_mac')",
                arguments: [mutation.taskId, mutation.title]
            )

            #if DEBUG
            try self.__test_injectFailure?(.afterProjectionBeforeCommandBytes)
            #endif
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

            #if DEBUG
            try self.__test_injectFailure?(.afterCommandBytesBeforeJournal)
            #endif
            try db.execute(
                sql: "INSERT INTO mutation_journal(mutation_id, outcome, terminal_snapshot_json) VALUES (?, 'pending', NULL)",
                arguments: [mutation.mutationId]
            )

            #if DEBUG
            try self.__test_injectFailure?(.afterJournalBeforeDependencyEdges)
            #endif
            // Structural provenance only -- [Phase 03] "Outbound ordering
            // is enforced by resource key, never by a journal dependency"
            // stays true: these edges are an auditable record of which
            // still-outstanding mutation(s) touched the same resource
            // key(s) before this one, not the mechanism that gates outbox
            // draining.
            for resourceKey in mutation.resourceKeys {
                let priorMutationIds = try String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT immutable_commands.mutation_id
                    FROM immutable_commands
                    JOIN outbox ON outbox.mutation_id = immutable_commands.mutation_id,
                         json_each(immutable_commands.resource_keys_json) AS resource_key
                    WHERE resource_key.value = ? AND immutable_commands.mutation_id <> ?
                    """,
                    arguments: [resourceKey, mutation.mutationId]
                )
                for dependencyMutationId in priorMutationIds {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO mutation_dependencies(mutation_id, dependency_mutation_id) VALUES (?, ?)",
                        arguments: [mutation.mutationId, dependencyMutationId]
                    )
                }
            }

            #if DEBUG
            try self.__test_injectFailure?(.afterDependencyEdgesBeforeOutbox)
            #endif
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
        assertNotOnMainThread()
        throw UnimplementedInTracerError("applyPull")
    }

    public func undoLastLocalAction() throws -> UndoResult {
        assertNotOnMainThread()
        throw UnimplementedInTracerError("undoLastLocalAction")
    }

    public func resolveConflict(conflictId: String, selection: [String: String]) throws -> WorkspaceSnapshot {
        assertNotOnMainThread()
        throw UnimplementedInTracerError("resolveConflict")
    }

    public func syncState() throws -> LocalSyncState {
        assertNotOnMainThread()
        let outboxIds = try readyMutationsUnguarded()
        return try dbPool.read { db in
            let cursor = try String.fetchOne(db, sql: "SELECT cursor FROM sync_cursor WHERE singleton = 1")
            let allOutbox = try String.fetchAll(db, sql: "SELECT mutation_id FROM outbox ORDER BY sequence")
            return LocalSyncState(cursor: cursor, outbox: allOutbox, readyPushes: outboxIds.map(\.mutationId))
        }
    }

    // MARK: - Ready pushes (transport-agnostic outbox read)

    public func readyMutations() throws -> [LocalMutation] {
        assertNotOnMainThread()
        return try readyMutationsUnguarded()
    }

    private func readyMutationsUnguarded() throws -> [LocalMutation] {
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

    // MARK: - Outbox state machine (monotonic: queued -> in_flight/uncertain, never back to queued)

    /// Moves one outbox row's transmission state forward. `queued` is a
    /// one-way departure gate: once a row has left it, no caller -- not
    /// even a retry path -- may move it back, because a transport failure
    /// cannot distinguish "the request never left" from "it left and the
    /// answer was lost" ([Phase 03] D-52).
    @discardableResult
    public func setOutboxState(mutationId: String, to newState: String) throws -> Bool {
        assertNotOnMainThread()
        try dbPool.read { db in try self.assertNotFenced(db) }
        return try dbPool.write { db in
            guard let current = try String.fetchOne(
                db, sql: "SELECT state FROM outbox WHERE mutation_id = ?", arguments: [mutationId]
            ) else { return false }

            if newState == "queued" && current != "queued" {
                throw StoreError.outboxTransitionRejected(from: current, to: newState)
            }
            try db.execute(sql: "UPDATE outbox SET state = ? WHERE mutation_id = ?", arguments: [newState, mutationId])
            return true
        }
    }

    // MARK: - Settlement (D-04 G8 / D-09 replay-no-op)

    @discardableResult
    public func acknowledge(_ acknowledgement: SyncAcknowledgement) throws -> WorkspaceSnapshot {
        assertNotOnMainThread()
        try dbPool.read { db in try self.assertNotFenced(db) }
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
        return try snapshotUnguarded()
    }

    // MARK: - Snapshot

    public func snapshot() throws -> WorkspaceSnapshot {
        assertNotOnMainThread()
        return try snapshotUnguarded()
    }

    private func snapshotUnguarded() throws -> WorkspaceSnapshot {
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
    public func readDurabilityPosture() throws -> (foreignKeys: Bool, journalMode: String, synchronous: Int, busyTimeoutMs: Int) {
        try dbPool.read { db in try Self.readPosture(db) }
    }

    static func readPosture(_ db: Database) throws -> (foreignKeys: Bool, journalMode: String, synchronous: Int, busyTimeoutMs: Int) {
        let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
        let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
        let synchronous = try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1
        let busyTimeoutMs = try Int.fetchOne(db, sql: "PRAGMA busy_timeout") ?? -1
        return (foreignKeys == 1, journalMode, synchronous, busyTimeoutMs)
    }

    /// Test-only (G1): holds one real `DatabasePool` reader connection open
    /// until every participant named by `barrier`'s initial `enter()` count
    /// has itself entered this function -- proving `DatabasePool` was
    /// forced to open more than one concurrent reader connection, rather
    /// than serially reusing a single one, before reading the pragma on
    /// each (04-RESEARCH.md Open Question 3; mirrors the Phase 1 explicit
    /// reusable-barrier convention).
    public func __test_readPostureHoldingConnectionOpen(
        barrier: DispatchGroup,
        releaseSignal: DispatchSemaphore
    ) throws -> (foreignKeys: Bool, journalMode: String, synchronous: Int, busyTimeoutMs: Int) {
        try dbPool.read { db in
            let posture = try Self.readPosture(db)
            barrier.leave()
            releaseSignal.wait()
            return posture
        }
    }

    public func integrityCheckResults() throws -> [String] {
        try dbPool.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
    }

    public func foreignKeyCheckViolations() throws -> [Row] {
        try dbPool.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check") }
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

    /// Test-only: executes arbitrary SQL directly against the pool's writer
    /// connection -- used by `DurabilityPostureTests` to attempt an
    /// orphan-foreign-key insert and prove SQLite rejects it, without
    /// needing a dedicated production write method for every adversarial
    /// probe.
    public func __test_executeRawSQL(_ sql: String, arguments: StatementArguments = StatementArguments()) throws {
        try dbPool.write { db in try db.execute(sql: sql, arguments: arguments) }
    }

    /// Test-only: truncates the WAL into the main database file so a copy
    /// of just the `.sqlite` path (no `-wal`/`-shm` sidecars) is a complete,
    /// self-contained fixture -- used when generating the committed
    /// `Tests/StorageTests/Fixtures/` databases.
    public func __test_checkpointTruncate() throws {
        try dbPool.writeWithoutTransaction { db in _ = try db.checkpoint(.truncate) }
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
