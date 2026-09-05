import XCTest
@testable import KeeplingCore

/// RED-first tests for interrupted-write and relaunch durability
/// (04-01-PLAN.md Task 3 `<behavior>`). Interruption is driven by
/// reopening the store file (a real relaunch) and by forcing an error
/// mid-acceptance via a deliberately invalid mutation (a real rejected
/// write, never a mocked one) -- not by killing the test runner process,
/// exactly as the plan specifies.
final class TracerDurabilityTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("keepling-durability-test.sqlite").path
    }

    /// 04-02-PLAN.md Task 3 (G5) added a debug main-thread precondition to
    /// every `LocalStorePort` entry point. XCTest runs test methods on the
    /// main thread by default, so this file's pre-existing synchronous
    /// calls now need to run off it -- exactly the discipline G5 exists to
    /// enforce, so this strengthens these tests rather than working around
    /// the guard.
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

    func testCommittedCaptureSurvivesReopenWithExactlyOneQueuedOutboxRow() throws {
        let path = storePath()
        let built = try CaptureCommand.build(title: "Renew passport", mutationId: "m-durable-1", taskId: "t-durable-1")
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )

        do {
            let store = try GRDBLocalStore(path: path)
            _ = try offMain { try store.acceptMutation(mutation) }
        }
        // A fresh store instance over the SAME file is the real relaunch --
        // no store handle survives across this boundary.
        let reopened = try GRDBLocalStore(path: path)
        let snapshot = try offMain { try reopened.snapshot() }
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks[0].title, "Renew passport")

        let ready = try offMain { try reopened.readyMutations() }
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready[0].mutationId, "m-durable-1")
        XCTAssertEqual(try reopened.outboxState(forMutationId: "m-durable-1"), "queued")
    }

    func testRejectedWriteBeforeCommitLeavesNoPartialStateAcrossAllFourTables() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)

        // A fingerprint mismatch is rejected BEFORE the transaction opens
        // (GRDBLocalStore.acceptMutation validates before `dbPool.write`),
        // so this proves the "before COMMIT" half of the behavior using a
        // real, reproducible rejection rather than an injected crash.
        let badMutation = LocalMutation(
            mutationId: "m-bad", taskId: "t-bad", commandBytes: "{\"tampered\":true}",
            fingerprint: sha256Hex("different bytes"), acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:t-bad"], title: "should never land"
        )
        XCTAssertThrowsError(try offMain { try store.acceptMutation(badMutation) })

        XCTAssertEqual(try store.countRows(in: "visible_projection"), 0)
        XCTAssertEqual(try store.countRows(in: "immutable_commands"), 0)
        XCTAssertEqual(try store.countRows(in: "mutation_journal"), 0)
        XCTAssertEqual(try store.countRows(in: "outbox"), 0)

        // Reopening confirms nothing was left behind on disk either.
        let reopened = try GRDBLocalStore(path: path)
        XCTAssertEqual(try offMain { try reopened.snapshot() }.tasks.count, 0)
    }

    func testFailureInsideTheWriteClosureLeavesNoPartialStateAcrossAllFourTables() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        let built = try CaptureCommand.build(title: "First capture", mutationId: "m-dup", taskId: "t-dup-1")
        let first = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )
        _ = try offMain { try store.acceptMutation(first) }
        XCTAssertEqual(try store.countRows(in: "visible_projection"), 1)

        // A SECOND mutation reusing the SAME mutation_id violates
        // immutable_commands' PRIMARY KEY on the very first statement
        // INSIDE this call's own `dbPool.write` closure -- a real failure
        // mid-transaction, not a pre-transaction validation rejection like
        // the fingerprint-mismatch test above. GRDB rolls the whole
        // closure back on any thrown error.
        let built2 = try CaptureCommand.build(title: "Second capture, same identity", mutationId: "m-dup", taskId: "t-dup-2")
        let duplicate = LocalMutation(
            mutationId: built2.mutationId, taskId: built2.taskId, commandBytes: built2.commandBytes,
            fingerprint: built2.fingerprint, acceptedAt: "2026-01-01T00:00:01Z",
            resourceKeys: ["task:\(built2.taskId)"], title: built2.title
        )
        XCTAssertThrowsError(try offMain { try store.acceptMutation(duplicate) })

        // The FIRST capture's rows still stand; the second's contributed
        // NOTHING -- no orphan visible_projection row for t-dup-2, no
        // partial outbox/journal entry for the failed attempt.
        XCTAssertEqual(try store.countRows(in: "visible_projection"), 1)
        XCTAssertEqual(try store.countRows(in: "immutable_commands"), 1)
        XCTAssertEqual(try store.countRows(in: "mutation_journal"), 1)
        XCTAssertEqual(try store.countRows(in: "outbox"), 1)
        XCTAssertEqual(try offMain { try store.snapshot() }.tasks.first?.title, "First capture")
    }

    func testMigrationLedgerAppliesAllElevenStrictTablesExactlyOnce() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        XCTAssertEqual(try store.countRows(in: "schema_migrations"), 3) // 04-09-PLAN.md Task 3 added Migration0003CaptureDraft

        // Reopening must not re-apply or duplicate ledger rows.
        let reopened = try GRDBLocalStore(path: path)
        XCTAssertEqual(try reopened.countRows(in: "schema_migrations"), 3)
    }

    func testDurabilityPostureIsSetBeforeAnyMigrationRuns() throws {
        let store = try GRDBLocalStore(path: storePath())
        let posture = try store.readDurabilityPosture()
        XCTAssertTrue(posture.foreignKeys)
        XCTAssertEqual(posture.journalMode.lowercased(), "wal")
        // SQLite reports `synchronous` as an integer; FULL = 2.
        XCTAssertEqual(posture.synchronous, 2)
    }

    func testAcceptMutationIsRejectedWhileFenced() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        try store.__test_setFence(reason: "device revoked")

        let built = try CaptureCommand.build(title: "Should be refused", mutationId: "m-fenced", taskId: "t-fenced")
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )
        XCTAssertThrowsError(try offMain { try store.acceptMutation(mutation) }) { error in
            guard case .fencedForWrites = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected fencedForWrites, got \(error)")
            }
        }
    }
}
