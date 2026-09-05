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

    /// The store's own durable-unit path, exposed so a caller (tests, and
    /// a future backup/restore feature) can build a `DurableUnit` against
    /// this exact store without re-deriving the path convention (04-06-PLAN.md
    /// Task 2).
    public let path: String

    /// The db/-wal/-shm treated as one durable unit (D-09). Never build a
    /// competing `DurableUnit(databasePath:)` elsewhere in `Sources` for
    /// THIS store's path -- this is the one accessor.
    public var durableUnit: DurableUnit { DurableUnit(databasePath: path) }

    public enum StoreError: Error, Equatable {
        case fencedForWrites(String)
        case fingerprintMismatch
        case mutationIdentityMismatch
        case unknownAcknowledgementMutation
        case invalidPullPage
        case outboxTransitionRejected(from: String, to: String)
        case incompleteNamespace
        case conflictDetailsEncodingFailed
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
        self.path = path
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
        // SQLCipher (D-07 rejects SQLCipher explicitly). G7 (D-04) asserted
        // by DataProtectionTests.swift: .completeUntilFirstUserAuthentication,
        // never .complete.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
        // D-09: the db/-wal/-shm durable unit is excluded from backup as
        // one unit, applied AFTER migrations run so the -wal/-shm sidecars
        // a WAL-mode connection creates already exist on disk to mark.
        // `try?` mirrors the file-protection call above: a backup-exclusion
        // failure must not prevent the store from opening -- it is the
        // belt (D-09), never the brace the replay-no-op proof is.
        try? DurableUnit(databasePath: path).excludeFromBackup()
    }

    // MARK: - Migration ledger (D-04 G4, D-37)

    static let migrations: [MigrationLedger.MigrationDefinition] = [
        MigrationLedger.MigrationDefinition(version: Migration0001Initial.version, sql: Migration0001Initial.sql),
        MigrationLedger.MigrationDefinition(version: Migration0002OutboxState.version, sql: Migration0002OutboxState.sql),
        MigrationLedger.MigrationDefinition(version: Migration0003CaptureDraft.version, sql: Migration0003CaptureDraft.sql),
    ]

    private static func applyMigrations(_ dbPool: DatabasePool) throws {
        try MigrationLedger.apply(migrations, to: dbPool)
    }

    // MARK: - Fencing (D-03 namespace fencing)

    private func assertNotFenced(_ db: Database) throws {
        let fenced = try String.fetchOne(db, sql: "SELECT value FROM namespace_metadata WHERE key = 'sync_fence'")
        if let fenced { throw StoreError.fencedForWrites(fenced) }
    }

    private func writeFence(_ db: Database, reason: String) throws {
        try db.execute(
            sql: "INSERT INTO namespace_metadata(key, value) VALUES ('sync_fence', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            arguments: [reason]
        )
    }

    /// The real D-09/D-03 fencing trigger (mirrors desktop's
    /// `bindNamespace`): binds this store to `namespace` the first time,
    /// and on every later call compares against what it is already bound
    /// to. A restored store carries the namespace it was bound to BEFORE
    /// the restore -- if the account signing in now disagrees, this fences
    /// the store for writes and returns `false` rather than silently
    /// letting a previous account's outbox push (04-06-PLAN.md Task 2).
    /// Throws on an incomplete tuple -- a partially-populated namespace
    /// would compare unequal to itself across launches for the wrong
    /// reason (a missing field, not a real account change).
    @discardableResult
    public func bindNamespace(_ namespace: SyncNamespace) throws -> Bool {
        assertNotOnMainThread()
        guard namespace.isComplete else { throw StoreError.incompleteNamespace }
        let serialized = try Self.serializeNamespace(namespace)
        return try dbPool.write { db in
            let existing = try String.fetchOne(db, sql: "SELECT value FROM namespace_metadata WHERE key = 'sync_namespace'")
            if let existing, existing != serialized {
                try self.writeFence(db, reason: "namespace_mismatch")
                return false
            }
            try db.execute(
                sql: "INSERT INTO namespace_metadata(key, value) VALUES ('sync_namespace', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [serialized]
            )
            return true
        }
    }

    /// Sets (`reason` non-`nil`) or clears (`reason == nil`) the
    /// synchronization fence directly -- the production counterpart of
    /// `__test_setFence`, for a caller (e.g. a future sign-out flow) that
    /// already knows the fence reason without going through
    /// `bindNamespace`'s comparison.
    public func setSyncFence(reason: String?) throws {
        assertNotOnMainThread()
        try dbPool.write { db in
            if let reason {
                try self.writeFence(db, reason: reason)
            } else {
                try db.execute(sql: "DELETE FROM namespace_metadata WHERE key = 'sync_fence'")
            }
        }
    }

    /// Wipes every row of this device's local intent for whatever
    /// namespace it currently holds, then clears the fence and the bound
    /// namespace itself so a fresh `bindNamespace` call starts clean.
    /// Deliberately synchronous, local-only SQL with NO transport or sync
    /// port parameter anywhere in its signature (04-07-PLAN.md Task 3,
    /// T-04-07-08): a server deletion is structurally UNREACHABLE from
    /// this call site, not merely uncalled.
    public func wipeAllLocalData() throws {
        assertNotOnMainThread()
        try dbPool.write { db in
            // Children referencing `immutable_commands` MUST be deleted
            // before it, or SQLite's foreign-key enforcement (PRAGMA
            // foreign_keys = ON, set on every connection) rejects the
            // delete.
            for table in [
                "mutation_dependencies", "outbox", "conflicts", "mutation_journal", "immutable_commands",
                "canonical_shadow", "visible_projection", "sync_cursor", "last_local_action",
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(sql: "INSERT INTO sync_cursor(singleton, cursor) VALUES (1, NULL)")
            try db.execute(sql: "INSERT INTO last_local_action(singleton, action_json) VALUES (1, NULL)")
            // 04-09-PLAN.md Task 3 (Rule 2 -- missing critical
            // functionality): a capture draft is account-scoped intent,
            // not device-scoped -- signing out one account and into
            // another on the same iPhone must never leak the first
            // account's unsent draft text into the second account's
            // capture sheet.
            try db.execute(sql: "UPDATE capture_draft SET title = '', add_to_today = 0, updated_at = NULL WHERE singleton = 1")
            try db.execute(sql: "DELETE FROM namespace_metadata")
        }
    }

    private static func serializeNamespace(_ namespace: SyncNamespace) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(namespace)
        return String(data: data, encoding: .utf8) ?? "{}"
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
            // An UPSERT, not a bare INSERT (04-08-PLAN.md Task 1): capture
            // is the only command that creates a brand-new row; every other
            // supported command (edit, clarify, return-to-inbox, plan,
            // unplan, complete, reopen, trash, restore) targets a task that
            // already has one. `effect` carries every projection column a
            // command that does not touch it must nonetheless preserve --
            // this is a replay of (basis + this command's change), never a
            // partial write that would blank an untouched column.
            try db.execute(
                sql: """
                INSERT INTO visible_projection(task_id, title, sync_status, notes, completed_at, trashed_at, planned)
                VALUES (?, ?, 'saved_on_this_mac', ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                  title = excluded.title,
                  sync_status = 'saved_on_this_mac',
                  notes = excluded.notes,
                  completed_at = excluded.completed_at,
                  trashed_at = excluded.trashed_at,
                  planned = excluded.planned
                """,
                arguments: [
                    mutation.taskId, mutation.title, mutation.effect.notes,
                    mutation.effect.completedAt, mutation.effect.trashedAt, mutation.effect.planned ? 1 : 0,
                ]
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

    // MARK: - Pull (04-08-PLAN.md Task 2)

    /// Applies a bounded pull page into the canonical shadow: only a change
    /// whose revision is `>=` the entity's existing shadow revision
    /// replaces it (last-writer-by-revision, mirrors `SyncReducer.pull`'s
    /// `apply_changes` rule -- never "last pull wins" by arrival order
    /// alone). The visible projection is recomputed from the new canonical
    /// value UNLESS the task still has an outstanding outbox mutation: an
    /// outstanding mutation's own optimistic effect must keep standing
    /// (the projection is a replay of canonical shadow + outbox, exactly as
    /// `SyncReducer.replayVisible` defines it) -- a pull must never
    /// overwrite a person's own unsent edit with a value the server has not
    /// yet seen it.
    public func applyPull(_ page: PullPage) throws {
        assertNotOnMainThread()
        try dbPool.read { db in try self.assertNotFenced(db) }
        try dbPool.write { db in
            for change in page.changes {
                let existingJSON = try String.fetchOne(
                    db, sql: "SELECT snapshot_json FROM canonical_shadow WHERE entity_id = ?", arguments: [change.entityId]
                )
                let existingRevision = existingJSON.flatMap { Self.intField("revision", inJSON: $0) } ?? -1
                let newRevision = Self.intField("revision", inJSON: change.snapshotJSON) ?? 0
                guard newRevision >= existingRevision else { continue }

                try db.execute(
                    sql: """
                    INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
                    ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
                    """,
                    arguments: [change.entityId, change.snapshotJSON]
                )

                let hasOutstandingMutation = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM outbox JOIN immutable_commands USING (mutation_id)
                    WHERE immutable_commands.task_id = ?
                    """,
                    arguments: [change.entityId]
                ) ?? 0

                guard hasOutstandingMutation == 0 else { continue }

                let title = Self.stringField("title", inJSON: change.snapshotJSON)
                let rowExists = try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM visible_projection WHERE task_id = ?)", arguments: [change.entityId]
                ) ?? false
                if rowExists {
                    if let title {
                        try db.execute(
                            sql: "UPDATE visible_projection SET title = ?, sync_status = 'synced' WHERE task_id = ?",
                            arguments: [title, change.entityId]
                        )
                    } else {
                        try db.execute(
                            sql: "UPDATE visible_projection SET sync_status = 'synced' WHERE task_id = ?",
                            arguments: [change.entityId]
                        )
                    }
                } else if let title {
                    // A pull can introduce a task this device has never
                    // captured locally (created on another device).
                    try db.execute(
                        sql: "INSERT INTO visible_projection(task_id, title, sync_status) VALUES (?, ?, 'synced')",
                        arguments: [change.entityId, title]
                    )
                }
            }
            if let cursor = page.cursor {
                try db.execute(sql: "UPDATE sync_cursor SET cursor = ? WHERE singleton = 1", arguments: [cursor])
            }
        }
    }

    private static func intField(_ field: String, inJSON json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let number = object[field] as? NSNumber { return number.intValue }
        return nil
    }

    // MARK: - Outbox claim (D-52 three-state transmission, concurrency-safe)

    /// The `queued`/`uncertain` -> `in_flight` claim, performed as ONE
    /// compare-and-swap update inside the selecting transaction: only a row
    /// whose CURRENT state is `queued` or `uncertain` is claimed, and
    /// `db.changesCount` (not merely "no error") is what reports success.
    /// A second concurrent pass racing for the SAME row finds it already
    /// `in_flight` and claims zero rows -- this update statement itself IS
    /// the lock (GRDB serializes all writers through the pool's single
    /// writer connection), not an external lock this plan would otherwise
    /// need to invent.
    @discardableResult
    public func claimForTransmission(mutationId: String) throws -> Bool {
        assertNotOnMainThread()
        try dbPool.read { db in try self.assertNotFenced(db) }
        return try dbPool.write { db in
            try db.execute(
                sql: "UPDATE outbox SET state = 'in_flight' WHERE mutation_id = ? AND state IN ('queued', 'uncertain')",
                arguments: [mutationId]
            )
            return db.changesCount > 0
        }
    }

    /// Every outstanding outbox mutation (any state, including `in_flight`),
    /// in sequence order, with its resource keys -- the full ordering
    /// context `SyncPassScheduler`'s lane-blocking computation needs.
    /// Unlike `readyMutations()` this does NOT exclude `in_flight` rows: an
    /// in-flight mutation on a resource key still blocks a later queued
    /// mutation on the SAME key from being selected concurrently (FIFO
    /// within a resource key, mirrors `SyncReducer.readyPushes`).
    public func allOutstandingMutationsInOrder() throws -> [(mutation: LocalMutation, state: String)] {
        assertNotOnMainThread()
        return try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT immutable_commands.mutation_id, immutable_commands.task_id,
                       immutable_commands.command_bytes, immutable_commands.fingerprint,
                       immutable_commands.accepted_at, immutable_commands.resource_keys_json,
                       visible_projection.title, outbox.state
                FROM outbox
                JOIN immutable_commands USING (mutation_id)
                JOIN visible_projection ON visible_projection.task_id = immutable_commands.task_id
                ORDER BY outbox.sequence
                """)
            return rows.map { row in
                let mutation = LocalMutation(
                    mutationId: row["mutation_id"], taskId: row["task_id"], commandBytes: row["command_bytes"],
                    fingerprint: row["fingerprint"], acceptedAt: row["accepted_at"],
                    resourceKeys: decodeJSONStringArray(row["resource_keys_json"]), title: row["title"]
                )
                return (mutation: mutation, state: row["state"])
            }
        }
    }

    // MARK: - Not implemented in this tracer plan

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
        try dbPool.read { db in try self.assertNotFenced(db) }
        let outboxIds = try readyMutationsUnguarded()
        return try dbPool.read { db in
            let cursor = try String.fetchOne(db, sql: "SELECT cursor FROM sync_cursor WHERE singleton = 1")
            let allOutbox = try String.fetchAll(db, sql: "SELECT mutation_id FROM outbox ORDER BY sequence")
            return LocalSyncState(cursor: cursor, outbox: allOutbox, readyPushes: outboxIds.map(\.mutationId))
        }
    }

    // MARK: - Ready pushes (transport-agnostic outbox read)

    /// NOTE (04-07-PLAN.md Task 3): deliberately NOT fence-gated, unlike
    /// `snapshot()`/`syncState()` below. 04-06-SUMMARY.md's own
    /// `BackupReplayTests.testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush`
    /// reads the ready rows AFTER a fence is set specifically to
    /// demonstrate, per mutation, that the WRITE path (`setOutboxState`)
    /// refuses -- gating this read too would make that established,
    /// already-verified 04-06 proof impossible to express. The write-path
    /// fence (`setOutboxState`/`acceptMutation`/`acknowledge`) is what
    /// makes the fenced rows unreachable for any real effect; this read
    /// alone cannot push, settle, or expose a value beyond mutation
    /// identity + already-durable command bytes.
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
            #if DEBUG
            // Structural (not inferred) proof that settlement is one
            // transaction, exactly the technique `acceptMutation` (D-04
            // G2) already established -- `SettlementTests` reuses it
            // rather than inferring the single-transaction claim.
            self.__test_onTransactionStart?(db)
            #endif

            let pending = try Row.fetchOne(db, sql: """
                SELECT immutable_commands.fingerprint AS fingerprint, immutable_commands.task_id AS task_id,
                       immutable_commands.effect_snapshot_json AS effect_snapshot_json
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
            let effectSnapshotJSON: String = pending["effect_snapshot_json"]

            if acknowledgement.outcome == .accepted || acknowledgement.outcome == .alreadySatisfied {
                try db.execute(
                    sql: """
                    INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
                    ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
                    """,
                    arguments: [taskId, acknowledgement.snapshotJSON]
                )
                // Recomputes the visible projection from the now-canonical
                // snapshot (D-04 G8 "recomputes the projection"), not only
                // its sync status -- an `already_satisfied` replay may be
                // settling bytes accepted in an earlier process, so the
                // title this projection shows must converge to what the
                // server actually holds, not merely what was proposed.
                if let canonicalTitle = Self.stringField("title", inJSON: acknowledgement.snapshotJSON) {
                    try db.execute(
                        sql: "UPDATE visible_projection SET title = ?, sync_status = 'synced' WHERE task_id = ?",
                        arguments: [canonicalTitle, taskId]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE visible_projection SET sync_status = 'synced' WHERE task_id = ?",
                        arguments: [taskId]
                    )
                }
            }
            // A `conflict`/`rejected` outcome deliberately touches NEITHER
            // canonical_shadow NOR visible_projection: the server's 409
            // body carries only the affected fields, and replaying that
            // partial body into either table would blank a field it never
            // named while a person's still-local edit is standing there --
            // exactly the "silent data-shaped lie" desktop's own acknowledge
            // disclosure warns against. The next real pull brings true
            // canonical state; until then the local row stands unmodified.

            if let undo = acknowledgement.undo {
                try db.execute(
                    sql: """
                    INSERT INTO namespace_metadata(key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: ["undo_handle:\(acknowledgement.mutationId)", Self.encodeUndoHandle(undo)]
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

            if acknowledgement.outcome == .conflict {
                let detailsJSON = try Self.buildConflictDetailsJSON(
                    affectedFields: acknowledgement.affectedFields,
                    mineSnapshotJSON: effectSnapshotJSON,
                    currentSnapshotJSON: acknowledgement.snapshotJSON
                )
                try db.execute(
                    sql: """
                    INSERT INTO conflicts(conflict_id, mutation_id, details_json) VALUES (?, ?, ?)
                    ON CONFLICT(conflict_id) DO UPDATE SET details_json = excluded.details_json
                    """,
                    arguments: ["conflict:\(acknowledgement.mutationId)", acknowledgement.mutationId, detailsJSON]
                )
            }
        }
        return try snapshotUnguarded()
    }

    /// Reads one string field out of a JSON object string. Used only to
    /// pull `title` back out of `snapshotJSON` for the projection recompute
    /// above -- returns `nil` (never throws, never defaults) for a field
    /// the snapshot does not carry, since not every acknowledgement carries
    /// a title (a conflict/rejection never reaches this call site at all).
    private static func stringField(_ field: String, inJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[field] as? String
    }

    private static func encodeUndoHandle(_ undo: SyncAcknowledgement.UndoAvailabilityHandle) -> String {
        let payload: [String: Any] = ["handle": undo.handle, "label": undo.label, "expiresAt": undo.expiresAt]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Builds the `conflicts.details_json` body: `mine` and `current` each
    /// restricted to exactly the server-named `affectedFields` -- never a
    /// field either side did not report, matching the same "only the
    /// affected fields" discipline `acknowledge` itself enforces on
    /// `canonical_shadow`/`visible_projection` above.
    private static func buildConflictDetailsJSON(
        affectedFields: [String],
        mineSnapshotJSON: String,
        currentSnapshotJSON: String
    ) throws -> String {
        func fields(from json: String) -> [String: Any] {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return object
        }
        let mineAll = fields(from: mineSnapshotJSON)
        let currentAll = fields(from: currentSnapshotJSON)
        var mine: [String: Any] = [:]
        var current: [String: Any] = [:]
        for field in affectedFields {
            if let value = mineAll[field] { mine[field] = value }
            if let value = currentAll[field] { current[field] = value }
        }
        let payload: [String: Any] = ["affected_fields": affectedFields, "mine": mine, "current": current]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw StoreError.conflictDetailsEncodingFailed }
        return string
    }

    // MARK: - Snapshot

    public func snapshot() throws -> WorkspaceSnapshot {
        assertNotOnMainThread()
        // 04-07-PLAN.md Task 3 (Rule 2 -- missing critical functionality):
        // a fenced store must refuse READS too, not only writes -- a
        // second account on the same phone must never be able to SEE the
        // first account's rows through this call, even though the write
        // path was already fenced by `bindNamespace` (T-04-07-04).
        try dbPool.read { db in try self.assertNotFenced(db) }
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

    // MARK: - Basis / conflict reads (04-09-PLAN.md Task 3)

    public func expectedRevision(forTaskId taskId: String) throws -> Int {
        assertNotOnMainThread()
        return try dbPool.read { db in
            let json = try String.fetchOne(db, sql: "SELECT snapshot_json FROM canonical_shadow WHERE entity_id = ?", arguments: [taskId])
            return json.flatMap { Self.intField("revision", inJSON: $0) } ?? 1
        }
    }

    public func activeConflict(forTaskId taskId: String) throws -> ConflictRecord? {
        assertNotOnMainThread()
        return try dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT conflicts.conflict_id AS conflict_id, conflicts.details_json AS details_json
                FROM conflicts JOIN immutable_commands ON immutable_commands.mutation_id = conflicts.mutation_id
                WHERE immutable_commands.task_id = ?
                ORDER BY conflicts.rowid DESC LIMIT 1
                """,
                arguments: [taskId]
            ) else { return nil }
            let conflictId: String = row["conflict_id"]
            let detailsJSON: String = row["details_json"]
            guard let data = detailsJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let affectedFields = object["affected_fields"] as? [String]
            else { return nil }
            func stringify(_ raw: Any?) -> [String: String] {
                guard let dictionary = raw as? [String: Any] else { return [:] }
                return dictionary.reduce(into: [:]) { accumulator, pair in accumulator[pair.key] = "\(pair.value)" }
            }
            return ConflictRecord(
                conflictId: conflictId,
                taskId: taskId,
                affectedFields: affectedFields,
                mine: stringify(object["mine"]),
                current: stringify(object["current"])
            )
        }
    }

    public func clearConflict(conflictId: String) throws {
        assertNotOnMainThread()
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM conflicts WHERE conflict_id = ?", arguments: [conflictId])
        }
    }

    // MARK: - Durable capture draft (D-35, 04-09-PLAN.md Task 3)

    public func saveDraft(_ draft: CaptureDraft) throws {
        assertNotOnMainThread()
        try dbPool.write { db in
            try db.execute(
                sql: """
                UPDATE capture_draft SET title = ?, add_to_today = ?, updated_at = ? WHERE singleton = 1
                """,
                arguments: [draft.title, draft.addToToday ? 1 : 0, ISO8601DateFormatter().string(from: Date())]
            )
        }
    }

    public func loadDraft() throws -> CaptureDraft {
        assertNotOnMainThread()
        return try dbPool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT title, add_to_today FROM capture_draft WHERE singleton = 1") else {
                return CaptureDraft(title: "", addToToday: false)
            }
            let title: String = row["title"]
            let addToToday: Int = row["add_to_today"]
            return CaptureDraft(title: title, addToToday: addToToday == 1)
        }
    }

    public func clearDraft() throws {
        assertNotOnMainThread()
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE capture_draft SET title = '', add_to_today = 0, updated_at = NULL WHERE singleton = 1"
            )
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

    /// Test-only: every row of a named table, ordered by `rowid` for
    /// deterministic before/after comparison. Used by `SettlementTests`'
    /// full-table-snapshot proof that a refused or replayed acknowledgement
    /// mutates nothing.
    public func __test_fetchAllRows(table: String) throws -> [Row] {
        try dbPool.read { db in try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid") }
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
