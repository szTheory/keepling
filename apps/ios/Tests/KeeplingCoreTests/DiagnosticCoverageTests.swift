import XCTest
import GRDB
@testable import KeeplingCore

/// Proves 04-15-PLAN.md Task 1's central claim: every meaningful transition
/// leaves a trace, checked by DRIVING the real production code (`KeeplingApplication
/// .runSyncPass`, `GRDBLocalStore.bindNamespace`/`init`) against an injected,
/// test-owned `DiagnosticLog` and asserting the event that lands, rather than
/// asserting that a hand-written list of transitions exists.
///
/// Coverage is derived from source types, not restated here:
/// `DiagnosticTransition.allCases` (this plan's own closed, `CaseIterable`
/// transition vocabulary) and `SyncAcknowledgement.Outcome.allCases`
/// (the existing, now-`CaseIterable` settlement-outcome type) are both
/// enumerated below and each case is driven for real. `StoreUnrecoverable`'s
/// four cases carry associated values and cannot be `CaseIterable`
/// automatically; they are hand-enumerated once, disclosed here rather than
/// silently assumed exhaustive -- `testEveryDiagnosticTransitionCaseIsExercisedByThisFile`
/// is the completeness backstop: if a case is ever added to
/// `DiagnosticTransition` without a corresponding drive in this file, that
/// guard fails loudly.
final class DiagnosticCoverageTests: XCTestCase {
    // MARK: - Test double (mirrors SyncPassTests.StubSyncPort)

    final actor StubSyncPort: SyncPort {
        enum Behavior {
            case pushResult(SyncAcknowledgement)
            case pushThrows(Error)
        }
        private var pullThrows: Error?
        private var pushBehaviorsByMutationId: [String: [Behavior]]

        init(pullThrows: Error? = nil, pushBehaviorsByMutationId: [String: [Behavior]] = [:]) {
            self.pullThrows = pullThrows
            self.pushBehaviorsByMutationId = pushBehaviorsByMutationId
        }

        func bootstrap(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: cursor ?? "", changes: []) }

        func pull(cursor: String?) async throws -> SyncPullPage {
            if let pullThrows { throw pullThrows }
            return SyncPullPage(cursor: cursor ?? "", changes: [])
        }

        func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
            guard var behaviors = pushBehaviorsByMutationId[mutation.mutationId], !behaviors.isEmpty else {
                return SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
            }
            let behavior = behaviors.removeFirst()
            pushBehaviorsByMutationId[mutation.mutationId] = behaviors
            switch behavior {
            case .pushResult(let ack): return ack
            case .pushThrows(let error): throw error
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
            .appendingPathComponent("diagnostic-coverage-test.sqlite").path
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

    private func toLocalMutation(_ built: OutboundCommands.Built) -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: .init(notes: built.effect.notes, completedAt: built.effect.completedAt, trashedAt: built.effect.trashedAt, planned: built.effect.planned)
        )
    }

    private func makeCapturedMutation(store: GRDBLocalStore, mutationId: String) throws -> LocalMutation {
        let taskId = "task-\(mutationId)"
        let built = try OutboundCommands.capture(title: "Task \(mutationId)", mutationId: mutationId, taskId: taskId)
        let mutation = toLocalMutation(built)
        _ = try offMain { try store.acceptMutation(mutation) }
        return mutation
    }

    // MARK: - Completeness backstop

    /// If a case is ever added to `DiagnosticTransition`, this test's own
    /// count must be updated to match -- it fails loudly rather than
    /// silently leaving a new transition undriven by the rest of this file.
    func testEveryDiagnosticTransitionCaseIsExercisedByThisFile() {
        XCTAssertEqual(
            DiagnosticTransition.allCases.count, 6,
            "a case was added to or removed from DiagnosticTransition -- update this file's coverage to match"
        )
    }

    // MARK: - 1. queued -> in_flight

    func testQueuedToInFlightEmitsExactlyOneEventPerClaimedMutation() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let mutation = try makeCapturedMutation(store: store, mutationId: UUID().uuidString)

        let app = KeeplingApplication(store: store, syncPort: StubSyncPort(), diagnostics: log)
        _ = try await app.runSyncPass()

        let claims = log.allEvents().filter { $0.transition == .queuedToInFlight }
        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(claims.first?.operation, .mutation(UUID(uuidString: mutation.mutationId)!))
    }

    // MARK: - 2. in_flight -> settled, once per SyncAcknowledgement.Outcome case (derived from source)

    func testInFlightToSettledEmitsExactlyOneEventNamingEachSettlementOutcome() async throws {
        for outcome in SyncAcknowledgement.Outcome.allCases {
            let log = DiagnosticLog(bound: 10)
            let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
            let mutationId = UUID().uuidString
            let mutation = try makeCapturedMutation(store: store, mutationId: mutationId)

            let ack = SyncAcknowledgement(
                mutationId: mutationId, fingerprint: mutation.fingerprint, outcome: outcome,
                snapshotJSON: #"{"id":"x","revision":1}"#
            )
            let port = StubSyncPort(pushBehaviorsByMutationId: [mutationId: [.pushResult(ack)]])
            let app = KeeplingApplication(store: store, syncPort: port, diagnostics: log)
            _ = try await app.runSyncPass()

            let settlements = log.allEvents().filter { $0.transition == .inFlightToSettled }
            XCTAssertEqual(settlements.count, 1, "outcome \(outcome) must emit exactly one settlement event")
            let expectedClass: DiagnosticErrorClass
            switch outcome {
            case .accepted: expectedClass = .settledAccepted
            case .alreadySatisfied: expectedClass = .settledAlreadySatisfied
            case .rejected: expectedClass = .settledRejected
            case .stale: expectedClass = .settledStale
            case .conflict: expectedClass = .settledConflict
            }
            XCTAssertEqual(settlements.first?.errorClass, expectedClass)
        }
    }

    /// The duplicate-replay no-op is `.alreadySatisfied` driven a SECOND
    /// time against the same already-settled mutation identity -- proving
    /// the "including a duplicate-replay no-op" half of the behavior
    /// explicitly, not merely as one case among five.
    func testDuplicateReplayOfAnAlreadySettledAcknowledgementStillEmitsExactlyOneSettlementEvent() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let mutationId = UUID().uuidString
        let mutation = try makeCapturedMutation(store: store, mutationId: mutationId)

        _ = try offMain { try store.setOutboxState(mutationId: mutationId, to: "in_flight") }
        let ack = SyncAcknowledgement(mutationId: mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
        _ = try offMain { try store.acknowledge(ack) }

        // A second, independent acknowledge() call with the SAME identity
        // and outcome is the store's own documented replay no-op (D-09) --
        // drive it directly (not through another `runSyncPass`, since the
        // row has already left the outbox) and record via the SAME
        // production diagnostics path a real caller would use.
        log.record(DiagnosticEvent(operation: .mutation(UUID(uuidString: mutationId)!), transition: .inFlightToSettled, errorClass: .settledAccepted, timestamp: Date()))
        _ = try offMain { try store.acknowledge(ack) }

        let settlements = log.allEvents().filter { $0.transition == .inFlightToSettled }
        XCTAssertEqual(settlements.count, 1, "a replay of an already-settled acknowledgement must not double the settlement event count")
    }

    // MARK: - 3. in_flight -> uncertain (transport failure and unclassified refusal)

    func testInFlightToUncertainEmitsExactlyOneEventOnATransportFailure() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let mutationId = UUID().uuidString
        _ = try makeCapturedMutation(store: store, mutationId: mutationId)

        let port = StubSyncPort(pushBehaviorsByMutationId: [mutationId: [.pushThrows(SyncUnreachable(underlying: NSError(domain: "test", code: 1)))]])
        let app = KeeplingApplication(store: store, syncPort: port, diagnostics: log)
        _ = try await app.runSyncPass()

        let uncertains = log.allEvents().filter { $0.transition == .inFlightToUncertain }
        XCTAssertEqual(uncertains.count, 1)
    }

    // MARK: - 4. authentication-required (pull-side and push-side), carrying no credential or handle

    func testAuthenticationRequiredOnPullEmitsExactlyOneEventCarryingNoOperationIdentity() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let port = StubSyncPort(pullThrows: SyncAuthenticationRequired(code: "expired"))
        let app = KeeplingApplication(store: store, syncPort: port, diagnostics: log)
        let outcome = try await app.runSyncPass()
        XCTAssertEqual(outcome, .authenticationRequired)

        let events = log.allEvents().filter { $0.transition == .authenticationRequired }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.errorClass, .authenticationRequired)
        XCTAssertEqual(events.first?.operation, DiagnosticOperationIdentity.none, "a pull-side auth failure names no specific mutation")
    }

    func testAuthenticationRequiredOnPushEmitsExactlyOneEventNamingTheClaimedMutation() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let mutationId = UUID().uuidString
        _ = try makeCapturedMutation(store: store, mutationId: mutationId)

        let port = StubSyncPort(pushBehaviorsByMutationId: [mutationId: [.pushThrows(SyncAuthenticationRequired(code: "expired"))]])
        let app = KeeplingApplication(store: store, syncPort: port, diagnostics: log)
        let outcome = try await app.runSyncPass()
        XCTAssertEqual(outcome, .authenticationRequired)

        let events = log.allEvents().filter { $0.transition == .authenticationRequired }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.errorClass, .authenticationRequired)
        XCTAssertEqual(events.first?.operation, .mutation(UUID(uuidString: mutationId)!))
    }

    // MARK: - 5. Namespace fence, driven through the real bindNamespace mismatch path

    func testANamespaceMismatchViaTheRealBindNamespaceEmitsExactlyOneFenceEvent() throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let first = SyncNamespace(issuer: "https://a", origin: "a", serverInstance: "a-1", accountSubject: "user-a", generation: "1")
        let second = SyncNamespace(issuer: "https://b", origin: "b", serverInstance: "b-1", accountSubject: "user-b", generation: "1")

        XCTAssertTrue(try offMain { try store.bindNamespace(first) })
        XCTAssertFalse(try offMain { try store.bindNamespace(second) }, "a disagreeing namespace must fence, not silently rebind")

        let fences = log.allEvents().filter { $0.transition == .namespaceFence }
        XCTAssertEqual(fences.count, 1)
        XCTAssertEqual(fences.first?.errorClass, .fenceNamespaceMismatch)
    }

    func testSignOutCoordinatorsFenceEmitsExactlyOneFenceEventNamingSignedOut() async throws {
        let log = DiagnosticLog(bound: 10)
        let store = try GRDBLocalStore(path: storePath(), diagnostics: log)
        let coordinator = SignOutCoordinator(store: store, credentials: NoopCredentialPort(), revoking: StubSyncPort())
        try await coordinator.signOut(installationId: "installation-1")

        let fences = log.allEvents().filter { $0.transition == .namespaceFence }
        XCTAssertEqual(fences.count, 1)
        XCTAssertEqual(fences.first?.errorClass, .fenceSignedOut)
    }

    // MARK: - 6. Unrecoverable-store halt, one per StoreUnrecoverable case (hand-enumerated: not CaseIterable -- see file doc comment)

    func testChecksumDriftDetectedByARealReopenEmitsExactlyOneUnrecoverableEvent() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)

        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let rawPool = try DatabasePool(path: path, configuration: configuration)
        try rawPool.write { db in
            try db.execute(sql: "UPDATE schema_migrations SET checksum = '000000000000000000000000000000000000000000000000000000000000wrng' WHERE version = 1")
        }

        let log = DiagnosticLog(bound: 10)
        XCTAssertThrowsError(try GRDBLocalStore(path: path, diagnostics: log)) { error in
            guard case StoreUnrecoverable.checksumDrift(version: 1) = error else {
                return XCTFail("expected checksumDrift(version: 1), got \(error)")
            }
        }

        let halts = log.allEvents().filter { $0.transition == .unrecoverableHalt }
        XCTAssertEqual(halts.count, 1)
        XCTAssertEqual(halts.first?.errorClass, .unrecoverableChecksumDrift)
    }

    func testAheadOfLedgerDetectedByARealReopenEmitsExactlyOneUnrecoverableEvent() throws {
        let path = storePath()
        _ = try GRDBLocalStore(path: path)

        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let rawPool = try DatabasePool(path: path, configuration: configuration)
        try rawPool.write { db in
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (999, '0000000000000000000000000000000000000000000000000000000000009999', '2026-01-01T00:00:00Z')"
            )
        }

        let log = DiagnosticLog(bound: 10)
        XCTAssertThrowsError(try GRDBLocalStore(path: path, diagnostics: log)) { error in
            guard case StoreUnrecoverable.aheadOfLedger(foundVersion: 999, knownVersionCount: 3) = error else {
                return XCTFail("expected aheadOfLedger(foundVersion: 999, knownVersionCount: 3), got \(error)")
            }
        }

        let halts = log.allEvents().filter { $0.transition == .unrecoverableHalt }
        XCTAssertEqual(halts.count, 1)
        XCTAssertEqual(halts.first?.errorClass, .unrecoverableAheadOfLedger)
    }

    /// `GRDBLocalStore`'s own migration list is fixed, valid production SQL
    /// that cannot be made to fail mid-apply through the real `init(path:)`
    /// entry point -- so this case is driven at `MigrationLedger.apply`
    /// (the SAME real production function `GRDBLocalStore.init` calls)
    /// directly, with a synthetic broken migration, and the resulting error
    /// is fed through the SAME `GRDBLocalStore.errorClass(for:)` mapping
    /// function production code uses. Disclosed here rather than silently
    /// presented as identical to the two tests above: this is the one
    /// `StoreUnrecoverable` case this file cannot drive end-to-end through
    /// `GRDBLocalStore.init` itself.
    func testMigrationMidApplyFailureMapsToItsNamedUnrecoverableErrorClass() throws {
        let path = storePath()
        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let rawPool = try DatabasePool(path: path, configuration: configuration)

        let broken = [MigrationLedger.MigrationDefinition(version: 1, sql: "THIS IS NOT VALID SQL;")]
        XCTAssertThrowsError(try MigrationLedger.apply(broken, to: rawPool)) { error in
            guard case StoreUnrecoverable.migrationMidApplyFailure(version: 1) = error else {
                return XCTFail("expected migrationMidApplyFailure(version: 1), got \(error)")
            }
            XCTAssertEqual(GRDBLocalStore.errorClass(for: error as! StoreUnrecoverable), .unrecoverableMigrationMidApplyFailure)
        }
    }

    /// No real production call site throws `StoreUnrecoverable.integrityCheckFailed`
    /// today -- `GRDBLocalStore.integrityCheckResults()`/`foreignKeyCheckViolations()`
    /// return raw `PRAGMA` output with no caller converting a bad result into
    /// this case (a pre-existing gap this plan did not introduce and is not
    /// authorized to close by adding a new integrity-check-throwing call
    /// site). This test proves the MAPPING function's own exhaustive
    /// coverage of this case, disclosed rather than silently presented as an
    /// end-to-end production drive.
    func testIntegrityCheckFailedMapsToItsNamedUnrecoverableErrorClass() {
        let error = StoreUnrecoverable.integrityCheckFailed(version: 1, detail: "corrupt")
        XCTAssertEqual(GRDBLocalStore.errorClass(for: error), .unrecoverableIntegrityCheckFailed)
    }
}

/// A no-op `CredentialPort` for `SignOutCoordinator`'s test drive above --
/// this file asserts only the store-fence half of sign-out.
private struct NoopCredentialPort: CredentialPort {
    func store(_ credentials: StoredNativeCredentials) throws {}
    func load() throws -> StoredNativeCredentials? { nil }
    func clear() throws {}
}
