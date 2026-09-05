import XCTest
import GRDB
@testable import KeeplingCore

/// Adversarial proof of D-04 G2 (single transaction, proven structurally)
/// and G3 (five enumerated interruption points inside the acceptance write
/// each leave complete accepted state or none).
///
/// A hard kill of the XCTest host process itself would take these
/// assertions down with it, so interruption is modeled two ways, both
/// disclosed rather than presented as a real signal kill: (1) throwing out
/// of the write closure via a test-only fault seam (`GRDBLocalStore`'s
/// `#if DEBUG`-only `__test_injectFailure`), which is compiled into the
/// test target's Debug configuration only and never into the shipped app;
/// and (2) closing the store without a clean shutdown and reopening the
/// file. Plan 04-16 supplies the real on-device `devicectl device process
/// terminate` kill.
final class CrashRecoveryTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("crash-recovery-test.sqlite").path
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

    private func mutation(id: String, task: String, resourceKeys: [String]? = nil) -> LocalMutation {
        let commandBytes = #"{"mutation_id":"\#(id)","task_id":"\#(task)","title":"x","type":"capture_task","version":1}"#
        return LocalMutation(
            mutationId: id, taskId: task, commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: resourceKeys ?? ["task:\(task)"], title: "x"
        )
    }

    /// Thread-safe counters for `afterNextTransaction`'s `@Sendable`
    /// callbacks -- both fire synchronously on GRDB's writer queue before
    /// `dbPool.write` returns, but the closures themselves must still be
    /// `Sendable`.
    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var commits = 0
        private(set) var rollbacks = 0
        func recordCommit() { lock.lock(); commits += 1; lock.unlock() }
        func recordRollback() { lock.lock(); rollbacks += 1; lock.unlock() }
    }

    private func rowCounts(atPath path: String) throws -> [String: Int] {
        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let pool = try DatabasePool(path: path, configuration: configuration)
        return try pool.read { db in
            var counts: [String: Int] = [:]
            for table in ["visible_projection", "immutable_commands", "mutation_journal", "mutation_dependencies", "outbox"] {
                counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            return counts
        }
    }

    // MARK: G2 -- acceptance is one transaction, proven through a commit/rollback hook

    func testSuccessfulAcceptanceRecordsExactlyOneCommitAndZeroRollbacksViaTransactionHook() throws {
        let store = try GRDBLocalStore(path: storePath())
        let counters = Counters()
        store.__test_onTransactionStart = { db in
            db.afterNextTransaction(onCommit: { _ in counters.recordCommit() }, onRollback: { _ in counters.recordRollback() })
        }
        _ = try offMain { try store.acceptMutation(self.mutation(id: "m-commit", task: "t-commit")) }
        XCTAssertEqual(counters.commits, 1)
        XCTAssertEqual(counters.rollbacks, 0)
    }

    // MARK: G3 -- five enumerated injection points each roll back completely

    private struct InjectedFailure: Error {}

    /// Arms `store`'s test-only fault seam to throw exactly at `point`.
    /// Named `injectFailure` (not merely "sets a closure") because five
    /// literal call sites below are this plan's own `<verify>` proof that
    /// at least five distinct injection points are actually driven, not an
    /// incidental naming choice.
    private func injectFailure(_ point: GRDBLocalStore.FaultInjectionPoint, on store: GRDBLocalStore) {
        store.__test_injectFailure = { candidate in
            if candidate == point { throw InjectedFailure() }
        }
    }

    private func assertInjectionRollsBackCompletely(
        at point: GRDBLocalStore.FaultInjectionPoint, store: GRDBLocalStore, path: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let counters = Counters()
        store.__test_onTransactionStart = { db in
            db.afterNextTransaction(onCommit: { _ in counters.recordCommit() }, onRollback: { _ in counters.recordRollback() })
        }

        let victim = mutation(id: "m-\(point.rawValue)", task: "t-\(point.rawValue)")
        XCTAssertThrowsError(try offMain { try store.acceptMutation(victim) }, "expected injection at \(point) to throw", file: file, line: line)

        XCTAssertEqual(counters.commits, 0, "injection at \(point) must not commit", file: file, line: line)
        XCTAssertEqual(counters.rollbacks, 1, "injection at \(point) must roll back exactly once", file: file, line: line)

        let counts = try rowCounts(atPath: path)
        for (table, count) in counts {
            XCTAssertEqual(count, 0, "injection at \(point) left \(count) row(s) in \(table)", file: file, line: line)
        }
    }

    func testInjectingFailureBeforeProjectionRollsBackCompletely() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        injectFailure(.beforeProjection, on: store)
        try assertInjectionRollsBackCompletely(at: .beforeProjection, store: store, path: path)
    }

    func testInjectingFailureAfterProjectionBeforeCommandBytesRollsBackCompletely() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        injectFailure(.afterProjectionBeforeCommandBytes, on: store)
        try assertInjectionRollsBackCompletely(at: .afterProjectionBeforeCommandBytes, store: store, path: path)
    }

    func testInjectingFailureAfterCommandBytesBeforeJournalRollsBackCompletely() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        injectFailure(.afterCommandBytesBeforeJournal, on: store)
        try assertInjectionRollsBackCompletely(at: .afterCommandBytesBeforeJournal, store: store, path: path)
    }

    func testInjectingFailureAfterJournalBeforeDependencyEdgesRollsBackCompletely() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        injectFailure(.afterJournalBeforeDependencyEdges, on: store)
        try assertInjectionRollsBackCompletely(at: .afterJournalBeforeDependencyEdges, store: store, path: path)
    }

    func testInjectingFailureAfterDependencyEdgesBeforeOutboxRollsBackCompletely() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        injectFailure(.afterDependencyEdgesBeforeOutbox, on: store)
        try assertInjectionRollsBackCompletely(at: .afterDependencyEdgesBeforeOutbox, store: store, path: path)
    }

    // MARK: A successful acceptance survives an abrupt close (no clean shutdown) and reopen

    func testSuccessfulAcceptanceSurvivesAbruptCloseAndReopenWithAllFiveWritesPresentExactlyOnce() throws {
        let path = storePath()
        let victim = mutation(id: "m-abrupt", task: "t-abrupt")
        do {
            let store = try GRDBLocalStore(path: path)
            _ = try offMain { try store.acceptMutation(victim) }
            // `store` goes out of scope here with no explicit close call --
            // the abrupt-shutdown half of the model (see file header).
        }

        let counts = try rowCounts(atPath: path)
        XCTAssertEqual(counts["visible_projection"], 1)
        XCTAssertEqual(counts["immutable_commands"], 1)
        XCTAssertEqual(counts["mutation_journal"], 1)
        XCTAssertEqual(counts["outbox"], 1)
        // No other outstanding mutation shared this resource key, so zero
        // dependency edges is the CORRECT steady state here, not a gap.
        XCTAssertEqual(counts["mutation_dependencies"], 0)
    }

    // MARK: Outbox state machine monotonicity

    func testInFlightToQueuedAndUncertainToQueuedAreBothRejected() throws {
        let path = storePath()
        let store = try GRDBLocalStore(path: path)
        let victim = mutation(id: "m-mono-1", task: "t-mono-1")
        _ = try offMain { try store.acceptMutation(victim) }

        XCTAssertTrue(try offMain { try store.setOutboxState(mutationId: victim.mutationId, to: "in_flight") })
        XCTAssertThrowsError(try offMain { try store.setOutboxState(mutationId: victim.mutationId, to: "queued") }) { error in
            guard case .outboxTransitionRejected(from: "in_flight", to: "queued") = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected .outboxTransitionRejected(from: in_flight, to: queued), got \(error)")
            }
        }

        let victim2 = mutation(id: "m-mono-2", task: "t-mono-2")
        _ = try offMain { try store.acceptMutation(victim2) }
        XCTAssertTrue(try offMain { try store.setOutboxState(mutationId: victim2.mutationId, to: "uncertain") })
        XCTAssertThrowsError(try offMain { try store.setOutboxState(mutationId: victim2.mutationId, to: "queued") }) { error in
            guard case .outboxTransitionRejected(from: "uncertain", to: "queued") = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected .outboxTransitionRejected(from: uncertain, to: queued), got \(error)")
            }
        }
    }

    // MARK: Fence-check ordering -- every implemented write-path method refuses BEFORE opening a transaction

    func testEveryImplementedWritePathMethodRefusesWhileFencedBeforeOpeningATransaction() throws {
        let store = try GRDBLocalStore(path: storePath())
        try store.__test_setFence(reason: "device revoked")

        let counters = Counters()
        store.__test_onTransactionStart = { db in
            db.afterNextTransaction(onCommit: { _ in counters.recordCommit() }, onRollback: { _ in counters.recordRollback() })
        }

        // acceptMutation: implemented.
        XCTAssertThrowsError(try offMain { try store.acceptMutation(self.mutation(id: "m-fenced-1", task: "t-fenced-1")) }) { error in
            guard case .fencedForWrites = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected fencedForWrites, got \(error)")
            }
        }

        // acknowledge: implemented.
        let ack = SyncAcknowledgement(
            mutationId: "does-not-matter", fingerprint: "does-not-matter", outcome: .accepted,
            snapshotJSON: "{}"
        )
        XCTAssertThrowsError(try offMain { try store.acknowledge(ack) }) { error in
            guard case .fencedForWrites = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected fencedForWrites, got \(error)")
            }
        }

        // setOutboxState: implemented.
        XCTAssertThrowsError(try offMain { try store.setOutboxState(mutationId: "does-not-matter", to: "in_flight") }) { error in
            guard case .fencedForWrites = error as? GRDBLocalStore.StoreError else {
                return XCTFail("expected fencedForWrites, got \(error)")
            }
        }

        // Every refusal above happened on the fence pre-check (a `dbPool.read`)
        // BEFORE `dbPool.write` was ever entered -- the transaction-start hook
        // (which only fires from inside a write transaction) never fired.
        XCTAssertEqual(counters.commits, 0)
        XCTAssertEqual(counters.rollbacks, 0)

        // `applyPull`, `undoLastLocalAction`, and `resolveConflict` are NOT
        // implemented in this plan (04-01-PLAN.md Task 3's deferred trio) --
        // they throw `UnimplementedInTracerError` unconditionally, before any
        // fence check could run. Plans 04-08 and 04-11 inherit the obligation
        // to add fence checks to those methods when they implement them.
    }
}
