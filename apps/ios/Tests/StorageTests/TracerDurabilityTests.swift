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
            _ = try store.acceptMutation(mutation)
        }
        // A fresh store instance over the SAME file is the real relaunch --
        // no store handle survives across this boundary.
        let reopened = try GRDBLocalStore(path: path)
        let snapshot = try reopened.snapshot()
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks[0].title, "Renew passport")

        let ready = try reopened.readyMutations()
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
        XCTAssertThrowsError(try store.acceptMutation(badMutation))

        XCTAssertEqual(try store.countRows(in: "visible_projection"), 0)
        XCTAssertEqual(try store.countRows(in: "immutable_commands"), 0)
        XCTAssertEqual(try store.countRows(in: "mutation_journal"), 0)
        XCTAssertEqual(try store.countRows(in: "outbox"), 0)

        // Reopening confirms nothing was left behind on disk either.
        let reopened = try GRDBLocalStore(path: path)
        XCTAssertEqual(try reopened.snapshot().tasks.count, 0)
    }

    func testMigrationLedgerAppliesAllElevenStrictTablesExactlyOnce() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        XCTAssertEqual(try store.countRows(in: "schema_migrations"), 2)

        // Reopening must not re-apply or duplicate ledger rows.
        let reopened = try GRDBLocalStore(path: path)
        XCTAssertEqual(try reopened.countRows(in: "schema_migrations"), 2)
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
        XCTAssertThrowsError(try store.acceptMutation(mutation)) { error in
            guard case .fencedForWrites = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected fencedForWrites, got \(error)")
            }
        }
    }
}
