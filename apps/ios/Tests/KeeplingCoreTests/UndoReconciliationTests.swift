import XCTest
import GRDB
import HTTPTypes
import OpenAPIRuntime
@testable import KeeplingCore

/// Proves `UndoAvailability`/`CompensatingCommands` (04-11-PLAN.md Task 1):
/// undo travels as a compensating semantic action through the server's own
/// handle, is retained/cleared as a single-level current availability on
/// every settlement, refuses loudly at the point of action when there is
/// nothing to undo, and never settles a client-uncertain outcome.
///
/// Behaviors driven from `packages/contracts/vectors/undo.json`:
/// - the closed supported/unsupported command matrix
///   (`testCompensatingCommandsCoverExactlyTheClosedSupportedMatrix`).
///
/// Behaviors this plan authored (not covered by the vector file, which has
/// no notion of settlement timing or client-side refusal semantics):
/// - retaining/clearing the single-level current availability on
///   settlement (`testAcknowledge*`)
/// - refusing undo of an unacknowledged mutation with zero store mutations
///   (`testInvokeRefusesWithZeroMutationsWhenNothingToUndo`,
///   `testUndoingBeforeAnyAcknowledgementRefusesAndTouchesNoStoreState`)
/// - an uncertain undo outcome staying uncertain, never client-settled
///   (`testAnUndoTaskUncertainOutcomeKeepsThrowingNeverSettling`)
final class UndoReconciliationTests: XCTestCase {
    // MARK: - Fixtures

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("undo-reconciliation-test.sqlite").path
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

    private func acceptedAcknowledgement(
        mutationId: String,
        fingerprint: String,
        taskId: String,
        handle: String? = nil,
        label: String = "Undo Trash"
    ) -> SyncAcknowledgement {
        SyncAcknowledgement(
            mutationId: mutationId,
            fingerprint: fingerprint,
            outcome: .accepted,
            snapshotJSON: #"{"id":"\#(taskId)","revision":2,"title":"Task"}"#,
            undo: handle.map { SyncAcknowledgement.UndoAvailabilityHandle(handle: $0, label: label, expiresAt: "2026-09-06T00:00:00Z") }
        )
    }

    // MARK: - `undo.json` golden vectors: the closed supported matrix

    private struct UndoVectors: Decodable {
        struct Supported: Decodable { let command: String; let inverse: String; let label: String }
        let supported: [Supported]
        let unsupported: [String]
    }

    private func loadVectors() throws -> UndoVectors {
        let url = try RepositoryRoot.vectorsDirectory().appendingPathComponent("undo.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UndoVectors.self, from: data)
    }

    private func availability(originalCommandType: String) -> UndoAvailability {
        UndoAvailability(
            mutationId: "m-original", taskId: "task-1", handle: String(repeating: "h", count: 43),
            label: "Undo Something", expiresAt: "2026-09-06T00:00:00Z", originalCommandType: originalCommandType
        )
    }

    /// Vector-derived: `CompensatingCommands` covers EXACTLY the closed
    /// supported matrix `undo.json` names, and mints nothing for a command
    /// in its `unsupported` list.
    func testCompensatingCommandsCoverExactlyTheClosedSupportedMatrix() throws {
        let vectors = try loadVectors()

        for supported in vectors.supported {
            let outcome = CompensatingCommands.invoke(
                current: availability(originalCommandType: supported.command),
                mutationId: "m-undo",
                currentTitle: "Task",
                currentEffect: LocalMutation.ProjectionEffect()
            )
            guard case .compensating(let built) = outcome else {
                XCTFail("expected a compensating command for supported original command \(supported.command)")
                continue
            }
            XCTAssertEqual(built.type, "undo_task")
        }

        for unsupported in vectors.unsupported {
            let outcome = CompensatingCommands.invoke(
                current: availability(originalCommandType: unsupported),
                mutationId: "m-undo",
                currentTitle: "Task",
                currentEffect: LocalMutation.ProjectionEffect()
            )
            guard case .refused(let reason) = outcome else {
                XCTFail("expected a refusal for unsupported original command \(unsupported)")
                continue
            }
            XCTAssertEqual(reason, .unsupportedOriginalCommandType)
        }

        XCTAssertEqual(Set(vectors.supported.map(\.command)), CompensatingCommands.supportedOriginalCommandTypes)
    }

    // MARK: - The compensating command itself

    func testCompensatingCommandCarriesAFreshMutationIdentityAndTheServerIssuedHandle() {
        let current = availability(originalCommandType: "trash_task")
        let outcome = CompensatingCommands.invoke(
            current: current, mutationId: "m-fresh-undo", currentTitle: "Buy milk",
            currentEffect: LocalMutation.ProjectionEffect(notes: "n", completedAt: nil, trashedAt: "2026-09-05T00:00:00Z", planned: false)
        )
        guard case .compensating(let built) = outcome else { return XCTFail("expected a compensating command") }

        XCTAssertEqual(built.mutationId, "m-fresh-undo")
        XCTAssertNotEqual(built.mutationId, current.mutationId, "the compensating command's identity must be FRESH, never the original mutation's")
        XCTAssertTrue(built.commandBytes.contains("\"handle\":\"\(current.handle)\""), "the compensating bytes must carry the server-issued handle")
        XCTAssertTrue(built.commandBytes.contains("\"type\":\"undo_task\""))
        XCTAssertEqual(built.taskId, current.taskId)
        XCTAssertEqual(built.resourceKeys, ["task:\(current.taskId)"])
        XCTAssertEqual(built.fingerprint, sha256Hex(built.commandBytes))
        // Carried through unchanged -- never blanked to a fresh-capture default.
        XCTAssertEqual(built.effect.trashedAt, "2026-09-05T00:00:00Z")
        XCTAssertEqual(built.effect.notes, "n")
    }

    // MARK: - Refusal: nothing to undo (zero store mutations)

    func testInvokeRefusesWithZeroMutationsWhenNothingToUndo() {
        let outcome = CompensatingCommands.invoke(
            current: nil, mutationId: "m-undo", currentTitle: "Task", currentEffect: LocalMutation.ProjectionEffect()
        )
        guard case .refused(let reason) = outcome else { return XCTFail("expected a refusal") }
        XCTAssertEqual(reason, .nothingToUndo)
        XCTAssertFalse(reason.copy.isEmpty, "a refusal must carry authored copy, never a bare failure")
    }

    /// Undoing an unacknowledged mutation is refused at the point of
    /// action with authored copy and produces ZERO store mutations,
    /// proven by comparing full store snapshots before and after --
    /// `UndoAvailability` structurally cannot exist until a settlement
    /// carries a handle, so an unacknowledged mutation's `currentUndoAvailability()`
    /// is `nil`, and refusing on `nil` never touches the store at all.
    func testUndoingBeforeAnyAcknowledgementRefusesAndTouchesNoStoreState() throws {
        let store = try GRDBLocalStore(path: storePath())
        let built = try OutboundCommands.capture(title: "Call dentist", mutationId: "m-unacked", taskId: "t-unacked")
        _ = try offMain {
            try store.acceptMutation(LocalMutation(
                mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
                fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: built.resourceKeys,
                title: built.effect.title
            ))
        }
        // No acknowledge() call -- the mutation is still outstanding.

        let before = try offMain { try store.snapshot() }
        let current = try offMain { try store.currentUndoAvailability() }
        XCTAssertNil(current, "an unacknowledged mutation must never produce an undo availability")

        let outcome = CompensatingCommands.invoke(current: current, mutationId: "m-undo-attempt", currentTitle: "Call dentist", currentEffect: LocalMutation.ProjectionEffect())
        guard case .refused(let reason) = outcome else { return XCTFail("expected a refusal") }
        XCTAssertEqual(reason, .nothingToUndo)

        let after = try offMain { try store.snapshot() }
        XCTAssertEqual(before, after, "refusing undo must produce zero store mutations")
    }

    // MARK: - `GRDBLocalStore.acknowledge` retains/clears the single-level current availability

    func testAcknowledgeRetainsCurrentUndoAvailabilityWhenTheAcknowledgementCarriesAHandle() throws {
        let store = try GRDBLocalStore(path: storePath())
        let built = try OutboundCommands.lifecycle(
            .trash, taskId: "t-1", basis: .init(baseTitle: "Buy milk", baseNotes: "", expectedRevision: 1),
            mutationId: "m-trash", acceptedAt: "2026-09-05T00:00:00Z"
        )
        _ = try offMain {
            try store.acceptMutation(self.localMutation(from: built, title: "Buy milk"))
        }
        XCTAssertNil(try offMain { try store.currentUndoAvailability() }, "no availability exists before settlement")

        _ = try offMain {
            try store.acknowledge(self.acceptedAcknowledgement(mutationId: "m-trash", fingerprint: built.fingerprint, taskId: "t-1", handle: String(repeating: "h", count: 43), label: "Undo Trash"))
        }

        let current = try offMain { try store.currentUndoAvailability() }
        XCTAssertEqual(current?.mutationId, "m-trash")
        XCTAssertEqual(current?.taskId, "t-1")
        XCTAssertEqual(current?.label, "Undo Trash")
        XCTAssertEqual(current?.originalCommandType, "trash_task")
    }

    func testAcknowledgeClearsCurrentUndoAvailabilityWhenTheAcknowledgementCarriesNoHandle() throws {
        let store = try GRDBLocalStore(path: storePath())

        // First: a trash command settles WITH a handle.
        let trashBuilt = try OutboundCommands.lifecycle(
            .trash, taskId: "t-1", basis: .init(baseTitle: "Buy milk", baseNotes: "", expectedRevision: 1),
            mutationId: "m-trash-2", acceptedAt: "2026-09-05T00:00:00Z"
        )
        _ = try offMain { try store.acceptMutation(self.localMutation(from: trashBuilt, title: "Buy milk")) }
        _ = try offMain {
            try store.acknowledge(self.acceptedAcknowledgement(mutationId: "m-trash-2", fingerprint: trashBuilt.fingerprint, taskId: "t-1", handle: String(repeating: "h", count: 43)))
        }
        XCTAssertNotNil(try offMain { try store.currentUndoAvailability() })

        // Second: a fresh capture settles WITHOUT a handle (unsupported
        // command) -- this must CLEAR the prior availability rather than
        // leaving it stale.
        let captureBuilt = try OutboundCommands.capture(title: "Second task", mutationId: "m-capture-2", taskId: "t-2")
        _ = try offMain {
            try store.acceptMutation(LocalMutation(
                mutationId: captureBuilt.mutationId, taskId: captureBuilt.taskId, commandBytes: captureBuilt.commandBytes,
                fingerprint: captureBuilt.fingerprint, acceptedAt: "2026-09-05T00:00:01Z", resourceKeys: captureBuilt.resourceKeys,
                title: captureBuilt.effect.title
            ))
        }
        _ = try offMain {
            try store.acknowledge(SyncAcknowledgement(
                mutationId: "m-capture-2", fingerprint: captureBuilt.fingerprint, outcome: .accepted,
                snapshotJSON: #"{"id":"t-2","revision":1,"title":"Second task"}"#
                // no `undo:` -- capture_task never mints one.
            ))
        }

        XCTAssertNil(try offMain { try store.currentUndoAvailability() }, "settling an acknowledgement with no handle must clear the prior availability")
    }

    func testAcknowledgeClearsCurrentUndoAvailabilityOnAConflictOutcomeToo() throws {
        let store = try GRDBLocalStore(path: storePath())

        let trashBuilt = try OutboundCommands.lifecycle(
            .trash, taskId: "t-1", basis: .init(baseTitle: "Buy milk", baseNotes: "", expectedRevision: 1),
            mutationId: "m-trash-3", acceptedAt: "2026-09-05T00:00:00Z"
        )
        _ = try offMain { try store.acceptMutation(self.localMutation(from: trashBuilt, title: "Buy milk")) }
        _ = try offMain {
            try store.acknowledge(self.acceptedAcknowledgement(mutationId: "m-trash-3", fingerprint: trashBuilt.fingerprint, taskId: "t-1", handle: String(repeating: "h", count: 43)))
        }
        XCTAssertNotNil(try offMain { try store.currentUndoAvailability() })

        let editBuilt = try OutboundCommands.edit(
            taskId: "t-1", touched: .init(notes: "Ask about Wednesday"),
            basis: .init(baseTitle: "Buy milk", baseNotes: "", expectedRevision: 2), mutationId: "m-edit-conflict"
        )
        _ = try offMain {
            try store.acceptMutation(LocalMutation(
                mutationId: editBuilt.mutationId, taskId: editBuilt.taskId, commandBytes: editBuilt.commandBytes,
                fingerprint: editBuilt.fingerprint, acceptedAt: "2026-09-05T00:00:02Z", resourceKeys: editBuilt.resourceKeys,
                title: editBuilt.effect.title,
                effect: .init(notes: editBuilt.effect.notes, completedAt: editBuilt.effect.completedAt, trashedAt: editBuilt.effect.trashedAt, planned: editBuilt.effect.planned)
            ))
        }
        _ = try offMain {
            try store.acknowledge(SyncAcknowledgement(
                mutationId: "m-edit-conflict", fingerprint: editBuilt.fingerprint, outcome: .conflict,
                snapshotJSON: #"{"id":"t-1","notes":"Someone else's notes"}"#, affectedFields: ["notes"]
            ))
        }

        XCTAssertNil(try offMain { try store.currentUndoAvailability() }, "a conflict outcome never carries a handle -- it must clear too")
    }

    private func localMutation(from built: OutboundCommands.Built, title: String) -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: built.resourceKeys,
            title: title, effect: .init(
                notes: built.effect.notes, completedAt: built.effect.completedAt,
                trashedAt: built.effect.trashedAt, planned: built.effect.planned
            )
        )
    }

    // MARK: - `KeeplingSyncAdapter.push` routes `undo_task` through the same outbound path

    private final class UndoStubTransport: ClientTransport, @unchecked Sendable {
        struct Canned { let status: Int; let contentType: String; let body: Data }
        var responses: [String: Canned] = [:]

        func stubJSON<T: Encodable>(operationID: String, status: Int, value: T) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            responses[operationID] = Canned(status: status, contentType: "application/json", body: try! encoder.encode(value))
        }

        func send(
            _ request: HTTPRequest,
            body: OpenAPIRuntime.HTTPBody?,
            baseURL: URL,
            operationID: String
        ) async throws -> (HTTPResponse, OpenAPIRuntime.HTTPBody?) {
            guard let canned = responses[operationID] else {
                XCTFail("no stub registered for operation \(operationID)")
                throw URLError(.unknown)
            }
            var response = HTTPResponse(status: .init(code: canned.status))
            response.headerFields[.contentType] = canned.contentType
            return (response, OpenAPIRuntime.HTTPBody(canned.body))
        }
    }

    private func undoMutation(handle: String = String(repeating: "h", count: 43), mutationId: String = "m-undo-push") -> LocalMutation {
        let outcome = CompensatingCommands.invoke(
            current: availability(originalCommandType: "trash_task"), mutationId: mutationId,
            currentTitle: "Buy milk", currentEffect: LocalMutation.ProjectionEffect()
        )
        guard case .compensating(let built) = outcome else { fatalError("expected a compensating command") }
        return LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: built.resourceKeys,
            title: built.title, effect: built.effect
        )
    }

    func testUndoTaskAcceptedResponseSettlesThroughTheSameOutboundPath() async throws {
        let transport = UndoStubTransport()
        let ack = Components.Schemas.CommandAcknowledgement(
            mutation_id: "m-undo-push", outcome: .accepted, revision: 3, snapshot: TaskSnapshotFixture.make(), task_id: "task-1", warnings: []
        )
        transport.stubJSON(operationID: "undoTask", status: 200, value: ack)
        let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)

        let result = try await adapter.push(undoMutation())
        XCTAssertEqual(result.outcome, .accepted)
        XCTAssertEqual(result.mutationId, "m-undo-push")
    }

    /// An undo whose own outcome is UNCERTAIN stays in the uncertain
    /// state and is never settled by the client -- mirrors the
    /// unclassified-refusal-throws pattern `runSyncPass` already treats
    /// as `uncertain`, never `queued`, never guessed into `rejected`.
    func testAnUndoTaskUncertainOutcomeKeepsThrowingNeverSettling() async throws {
        let transport = UndoStubTransport()
        let noChange = Components.Schemas.UndoNoChange(
            code: .undo_uncertain, mutation_id: "m-undo-push", outcome: .uncertain,
            recovery_action: .check_mutation_result, retryable: true, title: "This change's outcome is unclear."
        )
        transport.stubJSON(operationID: "undoTask", status: 200, value: noChange)
        let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)

        do {
            _ = try await adapter.push(undoMutation())
            XCTFail("expected SyncPortRefused -- an uncertain undo outcome must never be settled")
        } catch let error as SyncPortRefused {
            XCTAssertEqual(error.code, "undo_uncertain")
        } catch {
            XCTFail("expected SyncPortRefused, got \(error)")
        }
    }

    func testEveryOtherUndoNoChangeCodeSettlesAsRejected() async throws {
        for code in [Components.Schemas.UndoNoChange.codePayload.undo_already_applied, .undo_expired, .undo_stale, .undo_unknown] {
            let transport = UndoStubTransport()
            let noChange = Components.Schemas.UndoNoChange(
                code: code, mutation_id: "m-undo-push", outcome: .expired,
                recovery_action: nil, retryable: false, title: "This change can no longer be undone."
            )
            transport.stubJSON(operationID: "undoTask", status: 200, value: noChange)
            let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)

            let result = try await adapter.push(undoMutation())
            XCTAssertEqual(result.outcome, .rejected, "code \(code) must settle as .rejected, terminal, never queued again")
        }
    }
}
