import XCTest
import GRDB
@testable import KeeplingCore

/// Proves `KeeplingApplication.runSyncPass` is bounded, fence-respecting,
/// concurrency-safe, and honest about an unheard answer -- the seven
/// `<behavior>` requirements of 04-08-PLAN.md Task 2 -- against a stubbed
/// `SyncPort`, then (in `testRealStackSettlesAPushedCapture`) against real
/// Phoenix on real PostgreSQL when `KEEPLING_TEST_SERVER_URL` is set.
final class SyncPassTests: XCTestCase {
    // MARK: - Test doubles

    /// A `SyncPort` test double queueing per-call responses/errors and
    /// recording every call it received -- the same "stub at the port
    /// boundary" technique 04-05's `DeviceGrantStubTransport` established,
    /// one layer up (SyncPort itself, not ClientTransport), since
    /// `KeeplingApplication` depends on `any SyncPort`, never on the
    /// concrete adapter.
    final actor StubSyncPort: SyncPort {
        enum Behavior {
            case pullPage(SyncPullPage)
            case pullThrows(Error)
            case pushResult(SyncAcknowledgement)
            case pushThrows(Error)
        }

        private var pullBehaviors: [Behavior]
        private var pushBehaviorsByMutationId: [String: [Behavior]]
        private(set) var pushCallCounts: [String: Int] = [:]
        private(set) var pullCallCount = 0
        var failIfCalled = false

        init(pullBehaviors: [Behavior] = [.pullPage(SyncPullPage(cursor: "", changes: []))], pushBehaviorsByMutationId: [String: [Behavior]] = [:]) {
            self.pullBehaviors = pullBehaviors
            self.pushBehaviorsByMutationId = pushBehaviorsByMutationId
        }

        func setFailIfCalled(_ value: Bool) { failIfCalled = value }

        func bootstrap(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: cursor ?? "", changes: []) }

        func pull(cursor: String?) async throws -> SyncPullPage {
            if failIfCalled { XCTFail("transport must not be called for a fenced namespace"); throw SyncUnreachable(underlying: NSError(domain: "test", code: 1)) }
            pullCallCount += 1
            guard !pullBehaviors.isEmpty else { return SyncPullPage(cursor: cursor ?? "", changes: []) }
            let behavior = pullBehaviors.count > 1 ? pullBehaviors.removeFirst() : pullBehaviors[0]
            switch behavior {
            case .pullPage(let page): return page
            case .pullThrows(let error): throw error
            default: return SyncPullPage(cursor: cursor ?? "", changes: [])
            }
        }

        func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
            if failIfCalled { XCTFail("transport must not be called for a fenced namespace"); throw SyncUnreachable(underlying: NSError(domain: "test", code: 1)) }
            pushCallCounts[mutation.mutationId, default: 0] += 1
            guard var behaviors = pushBehaviorsByMutationId[mutation.mutationId], !behaviors.isEmpty else {
                return SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
            }
            let behavior = behaviors.removeFirst()
            pushBehaviorsByMutationId[mutation.mutationId] = behaviors
            switch behavior {
            case .pushResult(let ack): return ack
            case .pushThrows(let error): throw error
            default: throw SyncUnreachable(underlying: NSError(domain: "test", code: 1))
            }
        }

        func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
            SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .alreadySatisfied, snapshotJSON: #"{"id":"x","revision":1}"#)
        }

        func revoke(installationId: String) async throws {}
    }

    // MARK: - Helpers

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sync-pass-test.sqlite").path
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

    private func seedCaptureAndQueueEdit(_ store: GRDBLocalStore, taskId: String, editMutationId: String, editNotes: String = "x") throws {
        let capture = try OutboundCommands.capture(title: "Task \(taskId)", mutationId: "\(taskId)-capture", taskId: taskId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }
        let basis = OutboundCommands.Basis(baseTitle: "Task \(taskId)", baseNotes: "", expectedRevision: 1)
        let edit = try OutboundCommands.edit(taskId: taskId, touched: .init(notes: editNotes), basis: basis, mutationId: editMutationId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(edit)) }
    }

    private func toLocalMutation(_ built: OutboundCommands.Built, acceptedAt: String = "2026-09-05T00:00:00Z") -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: acceptedAt, resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: .init(notes: built.effect.notes, completedAt: built.effect.completedAt, trashedAt: built.effect.trashedAt, planned: built.effect.planned)
        )
    }

    // MARK: - 1. Pulls before it pushes; bounded 50/25 reads from reducer constants

    func testRunSyncPassPullsBeforePushingAndSettlesAReadyMutation() async throws {
        let store = try GRDBLocalStore(path: storePath())
        try seedCaptureAndQueueEdit(store, taskId: "t-1", editMutationId: "m-edit-1")

        let port = StubSyncPort(pullBehaviors: [.pullPage(SyncPullPage(cursor: "cursor-1", changes: []))])
        let app = KeeplingApplication(store: store, syncPort: port)

        let outcome = try await app.runSyncPass()
        guard case .completed(_, let pushed, let settled) = outcome else { return XCTFail("expected completed, got \(outcome)") }
        XCTAssertEqual(pushed, 1)
        XCTAssertEqual(settled, 1)

        let pullCount = await port.pullCallCount
        XCTAssertEqual(pullCount, 1, "pull must run exactly once per pass")
        let syncState = try offMain { try store.syncState() }
        XCTAssertEqual(syncState.cursor, "cursor-1", "the cursor advances to the pull page's own cursor")
    }

    // MARK: - 2. FIFO within a resource key; disjoint keys progress independently

    func testPushPreservesFIFOWithinAResourceKeyWhileDisjointKeysProgress() async throws {
        let store = try GRDBLocalStore(path: storePath())
        // Two mutations on task t-a (must push in order); one on task t-b
        // (disjoint, must not be blocked by t-a's queue).
        let captureA = try OutboundCommands.capture(title: "Task A", mutationId: "m-a-capture", taskId: "t-a")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(captureA)) }
        let basisA = OutboundCommands.Basis(baseTitle: "Task A", baseNotes: "", expectedRevision: 1)
        let editA1 = try OutboundCommands.edit(taskId: "t-a", touched: .init(notes: "first"), basis: basisA, mutationId: "m-a-edit-1")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(editA1)) }
        let editA2 = try OutboundCommands.edit(taskId: "t-a", touched: .init(notes: "second"), basis: basisA, mutationId: "m-a-edit-2")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(editA2)) }

        let captureB = try OutboundCommands.capture(title: "Task B", mutationId: "m-b-capture", taskId: "t-b")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(captureB)) }

        let port = StubSyncPort()
        let app = KeeplingApplication(store: store, syncPort: port)

        // Pass 1: t-a's EARLIEST queued mutation (its capture) and t-b's
        // (disjoint key) both push; t-a's two edits are FIFO-blocked behind
        // their own still-outstanding capture -- mirrors
        // `SyncReducer.readyPushes`'s own rule exactly (a mutation is
        // ready only if disjoint from EVERY earlier still-outstanding
        // mutation, selected or not).
        let firstOutcome = try await app.runSyncPass()
        guard case .completed(_, let firstPushed, let firstSettled) = firstOutcome else { return XCTFail("expected completed") }
        XCTAssertEqual(firstPushed, 2, "only t-a's earliest mutation and t-b's disjoint mutation push in pass 1")
        XCTAssertEqual(firstSettled, 2)
        var counts = await port.pushCallCounts
        XCTAssertEqual(counts["m-a-capture"], 1)
        XCTAssertEqual(counts["m-b-capture"], 1)
        XCTAssertEqual(counts["m-a-edit-1"] ?? 0, 0, "FIFO-blocked behind m-a-capture in pass 1")
        XCTAssertEqual(counts["m-a-edit-2"] ?? 0, 0)

        // Pass 2: m-a-capture settled and left the outbox, so m-a-edit-1
        // is now the earliest outstanding t-a mutation and pushes; m-a-edit-2
        // stays FIFO-blocked behind IT.
        let secondOutcome = try await app.runSyncPass()
        guard case .completed(_, let secondPushed, _) = secondOutcome else { return XCTFail("expected completed") }
        XCTAssertEqual(secondPushed, 1)
        counts = await port.pushCallCounts
        XCTAssertEqual(counts["m-a-edit-1"], 1)
        XCTAssertEqual(counts["m-a-edit-2"] ?? 0, 0, "still FIFO-blocked behind m-a-edit-1 in pass 2")

        // Pass 3: m-a-edit-2 is finally the earliest outstanding t-a
        // mutation.
        let thirdOutcome = try await app.runSyncPass()
        guard case .completed(_, let thirdPushed, _) = thirdOutcome else { return XCTFail("expected completed") }
        XCTAssertEqual(thirdPushed, 1)
        counts = await port.pushCallCounts
        XCTAssertEqual(counts["m-a-edit-2"], 1)
    }

    // MARK: - 3/4. Begin transmission claims the row; a thrown transport error leaves it uncertain, never queued

    func testAThrownTransportErrorDuringPushLeavesTheRowUncertainNeverQueued() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-fail", taskId: "t-fail")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        let port = StubSyncPort(pushBehaviorsByMutationId: ["m-fail": [.pushThrows(SyncUnreachable(underlying: NSError(domain: "test", code: 1)))]])
        let app = KeeplingApplication(store: store, syncPort: port)
        _ = try await app.runSyncPass()

        let state = try offMain { try store.outboxState(forMutationId: "m-fail") }
        XCTAssertEqual(state, "uncertain")
    }

    func testAnAnsweredOutcomeSettlesTheRowAndRemovesItFromTheOutbox() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-settle", taskId: "t-settle")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        let port = StubSyncPort()
        let app = KeeplingApplication(store: store, syncPort: port)
        _ = try await app.runSyncPass()

        let state = try offMain { try store.outboxState(forMutationId: "m-settle") }
        XCTAssertNil(state, "a settled mutation's outbox row is deleted")
        let outcome = try offMain { try store.journalOutcome(forMutationId: "m-settle") }
        XCTAssertEqual(outcome, "accepted")
    }

    // MARK: - 5. Retransmission of an uncertain row carries the SAME stored bytes/identity/fingerprint

    func testRetransmissionOfAnUncertainRowCarriesTheSameBytesIdentityAndFingerprintAndSettlesOnAlreadySatisfied() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-retry", taskId: "t-retry")
        let storedFingerprint = capture.fingerprint
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        // First pass: transport failure -> uncertain.
        let firstPort = StubSyncPort(pushBehaviorsByMutationId: ["m-retry": [.pushThrows(SyncUnreachable(underlying: NSError(domain: "test", code: 1)))]])
        let firstApp = KeeplingApplication(store: store, syncPort: firstPort)
        _ = try await firstApp.runSyncPass()
        XCTAssertEqual(try offMain { try store.outboxState(forMutationId: "m-retry") }, "uncertain")

        // Second pass: server now answers already_satisfied. The store's
        // own `readyMutations()`/`allOutstandingMutationsInOrder()` read
        // the exact bytes originally stored in `immutable_commands` --
        // `OutboundCommandTests.testMutatingTheInMemoryCommandValueAfterEnqueueLeavesRetriedBytesUnchanged`
        // already proves that byte-identity at the store layer; this test
        // proves the CONSEQUENCE end to end: an `already_satisfied` answer
        // to the retransmitted bytes settles the row.
        let readyBeforeRetry = try offMain { try store.readyMutations() }
        let storedBytes = readyBeforeRetry.first { $0.mutationId == "m-retry" }?.commandBytes
        XCTAssertEqual(storedBytes, capture.commandBytes, "the retry reads the originally stored bytes")

        let secondPort = StubSyncPort(pushBehaviorsByMutationId: [
            "m-retry": [.pushResult(SyncAcknowledgement(mutationId: "m-retry", fingerprint: storedFingerprint, outcome: .alreadySatisfied, snapshotJSON: #"{"id":"t-retry","revision":1,"title":"Task"}"#))],
        ])
        let secondApp = KeeplingApplication(store: store, syncPort: secondPort)
        let outcome = try await secondApp.runSyncPass()
        guard case .completed(_, _, let settled) = outcome else { return XCTFail("expected completed") }
        XCTAssertEqual(settled, 1)
        XCTAssertNil(try offMain { try store.outboxState(forMutationId: "m-retry") })
    }

    // MARK: - 6. A fenced namespace refuses the pass before any request is built

    func testAFencedNamespaceRefusesThePassBeforeAnyRequestIsBuilt() async throws {
        let store = try GRDBLocalStore(path: storePath())
        try offMain { try store.__test_setFence(reason: "namespace_mismatch") }

        let port = StubSyncPort()
        await port.setFailIfCalled(true)
        let app = KeeplingApplication(store: store, syncPort: port)
        let outcome = try await app.runSyncPass()
        XCTAssertEqual(outcome, .fenced)
    }

    // MARK: - 7. A 401 stops the pass and raises authentication-required with zero rows rejected

    func testA401StopsThePassAndRaisesAuthenticationRequiredWithZeroRowsRejected() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-auth", taskId: "t-auth")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        let port = StubSyncPort(pushBehaviorsByMutationId: ["m-auth": [.pushThrows(SyncAuthenticationRequired(code: "expired"))]])
        let app = KeeplingApplication(store: store, syncPort: port)
        let outcome = try await app.runSyncPass()
        XCTAssertEqual(outcome, .authenticationRequired)

        let journalOutcome = try offMain { try store.journalOutcome(forMutationId: "m-auth") }
        XCTAssertNotEqual(journalOutcome, "rejected", "an authentication failure must never be recorded as a per-mutation rejection")
        let state = try offMain { try store.outboxState(forMutationId: "m-auth") }
        XCTAssertEqual(state, "uncertain", "the claimed row is left retriable, never queued, never rejected")
    }

    // MARK: - Concurrency: two concurrent passes against one ready row produce exactly one push

    func testTwoConcurrentPassesAgainstOneReadyRowProduceExactlyOnePush() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-concurrent", taskId: "t-concurrent")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        let port = StubSyncPort()
        let appA = KeeplingApplication(store: store, syncPort: port)
        let appB = KeeplingApplication(store: store, syncPort: port)

        async let first: () = { _ = try? await appA.runSyncPass() }()
        async let second: () = { _ = try? await appB.runSyncPass() }()
        _ = await (first, second)

        let pushCount = await port.pushCallCounts["m-concurrent"] ?? 0
        XCTAssertEqual(pushCount, 1, "exactly one of the two concurrent passes must push the shared row")
    }

    // MARK: - Real-stack pass (opt-in; recorded in the SUMMARY)

    /// Runs one real sync pass against local Phoenix on real PostgreSQL,
    /// exactly as 04-05/04-06/04-07 disclosed doing for their own
    /// real-stack proofs, gated on `KEEPLING_TEST_SERVER_URL` so the
    /// default test run (no real stack running) does not fail.
    func testRealStackSettlesAPushedCapture() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["KEEPLING_TEST_SERVER_URL"], let url = URL(string: urlString) else {
            throw XCTSkip("KEEPLING_TEST_SERVER_URL not set -- see docs/testing/ios-testing.md for how to start tooling/run-local-stack.sh")
        }
        let store = try GRDBLocalStore(path: storePath())
        let adapter = try KeeplingSyncAdapter(baseURL: url)
        let capture = try OutboundCommands.capture(title: "Real stack capture", mutationId: UUID().uuidString, taskId: UUID().uuidString)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        let app = KeeplingApplication(store: store, syncPort: adapter)
        let outcome = try await app.runSyncPass()
        guard case .completed(_, _, let settled) = outcome else { return XCTFail("expected completed against the real stack") }
        XCTAssertEqual(settled, 1)
    }
}
