import XCTest
import GRDB
@testable import KeeplingCore

/// Generalizes the tracer's capture-only settlement (04-01/04-02) to the
/// full `acknowledge` surface (D-04 G8, D-09): identity + fingerprint
/// verification, canonical/conflict application, journal terminalization,
/// projection recompute, and exact-outbox-row deletion, all inside one
/// transaction -- asserted structurally via the same `afterNextTransaction`
/// hook `CrashRecoveryTests` established for `acceptMutation` (04-06-PLAN.md
/// Task 1 `<read_first>`).
final class SettlementTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settlement-test.sqlite").path
    }

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

    private func makeStore() throws -> GRDBLocalStore {
        try GRDBLocalStore(path: storePath())
    }

    private func accept(_ store: GRDBLocalStore, mutationId: String, taskId: String, title: String) throws -> LocalMutation {
        let commandBytes = #"{"mutation_id":"\#(mutationId)","task_id":"\#(taskId)","title":"\#(title)","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: mutationId, taskId: taskId, commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: ["task:\(taskId)"], title: title
        )
        _ = try offMain { try store.acceptMutation(mutation) }
        return mutation
    }

    /// Thread-safe commit/rollback counters, mirroring `CrashRecoveryTests`'
    /// own `Counters` type exactly (both fire synchronously on GRDB's
    /// writer queue, but the closures must still be `Sendable`).
    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var commits = 0
        private(set) var rollbacks = 0
        func recordCommit() { lock.lock(); commits += 1; lock.unlock() }
        func recordRollback() { lock.lock(); rollbacks += 1; lock.unlock() }
    }

    private func armTransactionHook(_ store: GRDBLocalStore) -> Counters {
        let counters = Counters()
        store.__test_onTransactionStart = { db in
            db.afterNextTransaction(onCommit: { _ in counters.recordCommit() }, onRollback: { _ in counters.recordRollback() })
        }
        return counters
    }

    /// A full snapshot of every table settlement can touch, for a
    /// byte-for-byte "mutates nothing" proof stronger than checking one
    /// named row. `Row` itself is `Equatable`, so `[String: [Row]]` is
    /// directly comparable across a before/after pair.
    private func fullTableSnapshot(_ store: GRDBLocalStore) throws -> [String: [Row]] {
        try offMain {
            var snapshot: [String: [Row]] = [:]
            for table in [
                "visible_projection", "immutable_commands", "mutation_journal",
                "mutation_dependencies", "outbox", "canonical_shadow", "conflicts", "namespace_metadata",
            ] {
                snapshot[table] = try store.__test_fetchAllRows(table: table)
            }
            return snapshot
        }
    }

    // MARK: - Behavior 1: identity + fingerprint verified, applies canonical, terminalizes, recomputes, deletes -- one transaction

    func testSuccessfulSettlementAppliesCanonicalTerminalizesRecomputesAndDeletesInOneTransaction() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-1", taskId: "t-1", title: "Water plants")
        let counters = armTransactionHook(store)

        let ack = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-1","revision":1,"title":"Water plants"}"#
        )
        _ = try offMain { try store.acknowledge(ack) }

        XCTAssertEqual(counters.commits, 1)
        XCTAssertEqual(counters.rollbacks, 0)
        XCTAssertEqual(try store.journalOutcome(forMutationId: "m-1"), "accepted")
        XCTAssertEqual(try offMain { try store.readyMutations() }.count, 0)
        XCTAssertEqual(try store.outboxState(forMutationId: "m-1"), nil)
        let snapshot = try offMain { try store.snapshot() }
        XCTAssertEqual(snapshot.tasks.first(where: { $0.taskId == "t-1" })?.syncStatus, "synced")
    }

    // MARK: - Behavior 2: fingerprint mismatch refuses and mutates nothing

    func testFingerprintMismatchRefusesAndMutatesNothing() throws {
        let store = try makeStore()
        _ = try accept(store, mutationId: "m-2", taskId: "t-2", title: "Feed cat")
        let before = try fullTableSnapshot(store)

        let ack = SyncAcknowledgement(
            mutationId: "m-2", fingerprint: sha256Hex("wrong bytes entirely"), outcome: .accepted,
            snapshotJSON: #"{"id":"t-2","revision":1,"title":"Feed cat"}"#
        )
        XCTAssertThrowsError(try offMain { try store.acknowledge(ack) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fingerprintMismatch)
        }

        let after = try fullTableSnapshot(store)
        XCTAssertEqual(before, after)
    }

    // MARK: - Behavior 3: absent from outbox, journal already matches -- no-op success

    func testUnknownOutboxButMatchingJournalOutcomeIsANoOpSuccess() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-3", taskId: "t-3", title: "Buy milk")
        let ack = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-3","revision":1,"title":"Buy milk"}"#
        )
        _ = try offMain { try store.acknowledge(ack) } // Settles once -- outbox row now gone.

        let counters = armTransactionHook(store)
        let before = try fullTableSnapshot(store)
        XCTAssertNoThrow(try offMain { try store.acknowledge(ack) }) // Replay of the SAME acknowledgement.
        let after = try fullTableSnapshot(store)

        XCTAssertEqual(before, after, "a replay of an already-terminal acknowledgement must change no row")
        XCTAssertEqual(counters.commits, 1)
        XCTAssertEqual(counters.rollbacks, 0)
    }

    // MARK: - Behavior 4: absent from outbox, journal outcome differs (or missing) -- named error

    func testUnknownOutboxWithDisagreeingJournalOutcomeThrowsNamedError() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-4", taskId: "t-4", title: "Walk dog")
        let acceptedAck = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-4","revision":1,"title":"Walk dog"}"#
        )
        _ = try offMain { try store.acknowledge(acceptedAck) } // Terminal outcome recorded: "accepted".

        // A disagreeing replay (different outcome for the same mutation id).
        let disagreeingAck = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .rejected,
            snapshotJSON: "null"
        )
        XCTAssertThrowsError(try offMain { try store.acknowledge(disagreeingAck) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .unknownAcknowledgementMutation)
        }
    }

    func testUnknownMutationIdentityWithNoJournalEntryAtAllThrowsNamedError() throws {
        let store = try makeStore()
        let ack = SyncAcknowledgement(
            mutationId: "never-accepted", fingerprint: sha256Hex("anything"), outcome: .accepted,
            snapshotJSON: #"{"id":"x","revision":1,"title":"y"}"#
        )
        XCTAssertThrowsError(try offMain { try store.acknowledge(ack) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .unknownAcknowledgementMutation)
        }
    }

    // MARK: - Behavior 5: conflict writes a linked conflict row, applies only affected fields, never blanks an unaffected field

    func testConflictSettlementRecordsOnlyAffectedFieldsAndLeavesUntouchedFieldByteIdentical() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-5", taskId: "t-5", title: "My title")
        // Simulate a person's separate local edit to a field the server
        // will NOT name as conflicted (`notes` has no acceptMutation path
        // yet -- Plans 04-09/04-11 add one -- so this uses the store's own
        // test-only raw-SQL seam, exactly as `DurabilityPostureTests` does
        // for its own adversarial probes, to model "a locally-edited field
        // the server did not name").
        try store.__test_executeRawSQL(
            "UPDATE visible_projection SET notes = ? WHERE task_id = ?",
            arguments: ["Untouched local notes", "t-5"]
        )

        let ack = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .conflict,
            snapshotJSON: #"{"title":"Server's title"}"#, affectedFields: ["title"]
        )
        _ = try offMain { try store.acknowledge(ack) }

        XCTAssertEqual(try store.journalOutcome(forMutationId: "m-5"), "conflict")
        XCTAssertEqual(try offMain { try store.readyMutations() }.count, 0)

        let snapshot = try offMain { try store.snapshot() }
        let row = try XCTUnwrap(snapshot.tasks.first(where: { $0.taskId == "t-5" }))
        XCTAssertEqual(row.notes, "Untouched local notes", "an unaffected field must survive a conflict settlement byte-identical")
        XCTAssertEqual(row.title, "My title", "a conflict never replays the server's shadow over the person's own edit")

        let conflictRows = try offMain { try store.__test_fetchAllRows(table: "conflicts") }
        XCTAssertEqual(conflictRows.count, 1)
        let detailsJSON: String = try XCTUnwrap(conflictRows.first?["details_json"])
        XCTAssertTrue(detailsJSON.contains("\"title\""))
        XCTAssertFalse(detailsJSON.contains("notes"), "the conflict record must never carry a field the server did not name")
    }

    // MARK: - Behavior 6: rejected terminalizes and deletes the outbox row without applying canonical state

    func testRejectedSettlementDeletesOutboxAndAppliesNoCanonicalState() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-6", taskId: "t-6", title: "Original title")
        let beforeCanonicalRows = try offMain { try store.__test_fetchAllRows(table: "canonical_shadow") }

        let ack = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .rejected,
            snapshotJSON: "null"
        )
        _ = try offMain { try store.acknowledge(ack) }

        XCTAssertEqual(try store.journalOutcome(forMutationId: "m-6"), "rejected")
        XCTAssertEqual(try store.outboxState(forMutationId: "m-6"), nil)
        let afterCanonicalRows = try offMain { try store.__test_fetchAllRows(table: "canonical_shadow") }
        XCTAssertEqual(beforeCanonicalRows.count, afterCanonicalRows.count, "a rejection must apply zero canonical state")

        let snapshot = try offMain { try store.snapshot() }
        XCTAssertEqual(snapshot.tasks.first(where: { $0.taskId == "t-6" })?.title, "Original title")
    }

    // MARK: - Behavior 7: undo availability on a successful acknowledgement is retained, not discarded

    func testUndoAvailabilityOnASuccessfulAcknowledgementIsRetained() throws {
        let store = try makeStore()
        let mutation = try accept(store, mutationId: "m-7", taskId: "t-7", title: "Undoable")
        let undo = SyncAcknowledgement.UndoAvailabilityHandle(
            handle: String(repeating: "a", count: 43), label: "Undo capture", expiresAt: "2026-01-02T00:00:00Z"
        )
        let ack = SyncAcknowledgement(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-7","revision":1,"title":"Undoable"}"#, undo: undo
        )
        _ = try offMain { try store.acknowledge(ack) }

        let retained = try offMain {
            try store.__test_fetchAllRows(table: "namespace_metadata").first { row in
                (row["key"] as String?) == "undo_handle:m-7"
            }
        }
        let retainedValue: String = try XCTUnwrap(retained?["value"])
        XCTAssertTrue(retainedValue.contains(undo.handle))
        XCTAssertTrue(retainedValue.contains("Undo capture"))
    }
}
