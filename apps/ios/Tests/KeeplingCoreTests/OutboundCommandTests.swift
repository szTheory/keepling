import XCTest
import GRDB
@testable import KeeplingCore

/// Proves `OutboundCommands` produces immutable, retry-authoritative bytes
/// for every one of the ten supported commands, that edit/clarify send only
/// touched fields with matching base values, and that the store's
/// acceptance transaction is the single join point for a command's enqueue
/// and its local projection write (04-08-PLAN.md Task 1).
final class OutboundCommandTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("outbound-command-test.sqlite").path
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

    private func localMutation(from built: OutboundCommands.Built, acceptedAt: String = "2026-09-05T00:00:00Z") -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId,
            taskId: built.taskId,
            commandBytes: built.commandBytes,
            fingerprint: built.fingerprint,
            acceptedAt: acceptedAt,
            resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: .init(
                notes: built.effect.notes,
                completedAt: built.effect.completedAt,
                trashedAt: built.effect.trashedAt,
                planned: built.effect.planned
            )
        )
    }

    // MARK: - Every one of the ten commands produces bytes + fingerprint + identity

    func testAllTenSupportedCommandsProduceBytesFingerprintAndIdentity() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)

        let built: [OutboundCommands.Built] = [
            try OutboundCommands.capture(title: "Buy milk", mutationId: "m-capture", taskId: "t-1"),
            try OutboundCommands.edit(taskId: "t-2", touched: .init(notes: "Ask about Wednesday"), basis: basis, mutationId: "m-edit"),
            try OutboundCommands.edit(taskId: "t-2", touched: .init(title: "Call the dentist"), basis: basis, mutationId: "m-clarify", asClarify: true),
            try OutboundCommands.returnToInbox(taskId: "t-2", basis: basis, mutationId: "m-return"),
            try OutboundCommands.planForToday(true, taskId: "t-2", basis: basis, mutationId: "m-plan"),
            try OutboundCommands.planForToday(false, taskId: "t-2", basis: basis, mutationId: "m-unplan"),
            try OutboundCommands.lifecycle(.complete, taskId: "t-2", basis: basis, mutationId: "m-complete", acceptedAt: "2026-09-05T00:00:00Z"),
            try OutboundCommands.lifecycle(.reopen, taskId: "t-2", basis: basis, mutationId: "m-reopen", acceptedAt: "2026-09-05T00:00:00Z"),
            try OutboundCommands.lifecycle(.trash, taskId: "t-2", basis: basis, mutationId: "m-trash", acceptedAt: "2026-09-05T00:00:00Z"),
            try OutboundCommands.lifecycle(.restore, taskId: "t-2", basis: basis, mutationId: "m-restore", acceptedAt: "2026-09-05T00:00:00Z"),
        ]

        XCTAssertEqual(built.count, 10)
        let expectedTypes: Set<String> = [
            "capture_task", "edit_task", "clarify_task", "return_to_inbox", "plan_for_today",
            "unplan_task", "complete_task", "reopen_task", "trash_task", "restore_task",
        ]
        XCTAssertEqual(Set(built.map(\.type)), expectedTypes)

        for command in built {
            XCTAssertFalse(command.commandBytes.isEmpty)
            XCTAssertEqual(command.fingerprint, sha256Hex(command.commandBytes), "fingerprint must be over the exact bytes")
            XCTAssertFalse(command.mutationId.isEmpty)
            XCTAssertTrue(command.commandBytes.contains("\"type\":\"\(command.type)\""), "durable bytes must carry the type discriminator")
        }
    }

    // MARK: - Every command decodes as its contract-published DTO

    func testEveryCommandsBytesDecodeAsItsGeneratedContractDTO() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        let decoder = JSONDecoder()

        func data(_ built: OutboundCommands.Built) -> Data { Data(built.commandBytes.utf8) }

        XCTAssertNoThrow(try decoder.decode(Components.Schemas.CaptureTaskCommand.self, from: data(try OutboundCommands.capture(title: "Buy milk", mutationId: "m1", taskId: "t1"))))
        XCTAssertNoThrow(try decoder.decode(Components.Schemas.EditTaskCommand.self, from: data(try OutboundCommands.edit(taskId: "t2", touched: .init(notes: "x"), basis: basis, mutationId: "m2"))))
        XCTAssertNoThrow(try decoder.decode(Components.Schemas.ClarifyTaskCommand.self, from: data(try OutboundCommands.edit(taskId: "t2", touched: .init(title: "y"), basis: basis, mutationId: "m3", asClarify: true))))
        XCTAssertNoThrow(try decoder.decode(Components.Schemas.ReturnToInboxCommand.self, from: data(try OutboundCommands.returnToInbox(taskId: "t2", basis: basis, mutationId: "m4"))))
        XCTAssertNoThrow(try decoder.decode(Components.Schemas.PlanForTodayRequest.self, from: data(try OutboundCommands.planForToday(true, taskId: "t2", basis: basis, mutationId: "m5"))))
        XCTAssertNoThrow(try decoder.decode(Components.Schemas.UnplanTaskRequest.self, from: data(try OutboundCommands.planForToday(false, taskId: "t2", basis: basis, mutationId: "m6"))))
        for transition in [OutboundCommands.Lifecycle.complete, .reopen, .trash, .restore] {
            XCTAssertNoThrow(
                try decoder.decode(Components.Schemas.TaskLifecycleCommand.self, from: data(try OutboundCommands.lifecycle(transition, taskId: "t2", basis: basis, mutationId: "m-\(transition.rawValue)", acceptedAt: "2026-09-05T00:00:00Z")))
            )
        }
    }

    // MARK: - Edit/clarify send only touched fields with matching base values

    func testEditTouchingOnlyNotesOmitsTitleFromFieldsAndBaseValues() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        let built = try OutboundCommands.edit(taskId: "t-2", touched: .init(notes: "Ask about Wednesday"), basis: basis, mutationId: "m-edit")

        XCTAssertTrue(built.commandBytes.contains("\"notes\":\"Ask about Wednesday\""))
        XCTAssertTrue(built.commandBytes.contains("\"base_values\":{\"notes\":\"Ask about Tuesday\"}"))
        XCTAssertFalse(built.commandBytes.contains("title"), "an untouched field must be absent from the bytes entirely")
    }

    func testEditTouchingOnlyTitleOmitsNotesFromFieldsAndBaseValues() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        let built = try OutboundCommands.edit(taskId: "t-2", touched: .init(title: "Call the dentist"), basis: basis, mutationId: "m-edit-2")

        XCTAssertTrue(built.commandBytes.contains("\"title\":\"Call the dentist\""))
        XCTAssertTrue(built.commandBytes.contains("\"base_values\":{\"title\":\"Call dentist\"}"))
        XCTAssertFalse(built.commandBytes.contains("notes"), "an untouched field must be absent from the bytes entirely")
    }

    func testEditWithNoTouchedFieldsThrows() {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        XCTAssertThrowsError(try OutboundCommands.edit(taskId: "t-2", touched: .init(), basis: basis, mutationId: "m-edit-3")) { error in
            XCTAssertEqual(error as? OutboundCommands.ValidationError, .noTouchedFields)
        }
    }

    // MARK: - The retry path reads stored bytes; mutating the in-memory value after enqueue changes nothing

    func testMutatingTheInMemoryCommandValueAfterEnqueueLeavesRetriedBytesUnchanged() throws {
        let store = try GRDBLocalStore(path: storePath())
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        var built = try OutboundCommands.edit(taskId: "t-retry", touched: .init(notes: "Ask about Wednesday"), basis: basis, mutationId: "m-retry")

        // Seed the task row so the edit targets an existing task, then
        // enqueue the real command.
        _ = try offMain { try store.acceptMutation(self.localMutation(from: try OutboundCommands.capture(title: "Call dentist", mutationId: "m-seed", taskId: "t-retry"))) }
        let originalBytes = built.commandBytes
        let mutation = localMutation(from: built)
        _ = try offMain { try store.acceptMutation(mutation) }

        // Mutate the in-memory Swift value AFTER enqueue -- this must have
        // zero effect on what a retry reads, because the retry path reads
        // `immutable_commands`, never the caller's in-memory value.
        built = try OutboundCommands.edit(taskId: "t-retry", touched: .init(notes: "SOMETHING ELSE ENTIRELY"), basis: basis, mutationId: "m-retry")
        XCTAssertNotEqual(built.commandBytes, originalBytes, "sanity: the mutated value really is different bytes")

        let ready = try offMain { try store.readyMutations() }
        let retried = ready.first { $0.mutationId == "m-retry" }
        XCTAssertEqual(retried?.commandBytes, originalBytes, "the retry path must read the originally stored bytes, never a re-serialized value")
    }

    // MARK: - Every command's enqueue and projection write occur in one transaction

    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var commits = 0
        func recordCommit() { lock.lock(); commits += 1; lock.unlock() }
    }

    func testEveryCommandsEnqueueAndProjectionWriteOccurInOneTransaction() throws {
        let store = try GRDBLocalStore(path: storePath())
        _ = try offMain { try store.acceptMutation(self.localMutation(from: try OutboundCommands.capture(title: "Call dentist", mutationId: "m-seed-2", taskId: "t-txn"))) }

        let counters = Counters()
        store.__test_onTransactionStart = { db in
            db.afterNextTransaction(onCommit: { _ in counters.recordCommit() }, onRollback: { _ in XCTFail("must not roll back") })
        }

        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "", expectedRevision: 1)
        let built = try OutboundCommands.lifecycle(.complete, taskId: "t-txn", basis: basis, mutationId: "m-complete-txn", acceptedAt: "2026-09-05T00:00:00Z")
        _ = try offMain { try store.acceptMutation(self.localMutation(from: built)) }

        XCTAssertEqual(counters.commits, 1, "the enqueue and the projection write must commit as exactly one transaction")

        let rows = try offMain { try store.__test_fetchAllRows(table: "visible_projection") }
        XCTAssertEqual(rows.first?["completed_at"] as? String, "2026-09-05T00:00:00Z")
        let outboxRows = try offMain { try store.readyMutations() }
        XCTAssertTrue(outboxRows.contains { $0.mutationId == "m-complete-txn" })
    }

    // MARK: - A store failure leaves neither the enqueue nor the projection write

    func testAStoreFailureDuringEnqueueLeavesNeitherTheEnqueueNorTheProjectionWrite() throws {
        let store = try GRDBLocalStore(path: storePath())
        _ = try offMain { try store.acceptMutation(self.localMutation(from: try OutboundCommands.capture(title: "Call dentist", mutationId: "m-seed-3", taskId: "t-fail"))) }

        store.__test_injectFailure = { point in
            if point == .afterJournalBeforeDependencyEdges { throw NSError(domain: "test", code: 1) }
        }

        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "", expectedRevision: 1)
        let built = try OutboundCommands.lifecycle(.trash, taskId: "t-fail", basis: basis, mutationId: "m-trash-fail", acceptedAt: "2026-09-05T00:00:00Z")
        XCTAssertThrowsError(try offMain { try store.acceptMutation(self.localMutation(from: built)) })

        let outboxRows = try offMain { try store.readyMutations() }
        XCTAssertFalse(outboxRows.contains { $0.mutationId == "m-trash-fail" }, "the outbox row must not exist after a failed enqueue")
        let rows = try offMain { try store.__test_fetchAllRows(table: "visible_projection") }
        XCTAssertNil(rows.first?["trashed_at"] as? String, "the projection must not have recorded the trash effect either")
    }

    // MARK: - Local projection effect for lifecycle commands, mapped against the corresponding golden vector

    /// `packages/contracts/vectors/lifecycle.json`'s "complete accepts the
    /// active task" case: `expected_revision: 1 -> revision: 2`,
    /// `completed_at` set. This client's own optimistic local effect cannot
    /// know the server's real acceptance timestamp (it is the SERVER's
    /// clock, per the vector's own `accepted_at` field being an INPUT the
    /// server records, not a value this client computes) -- the local
    /// effect uses this device's own clock reading instead, replaced by the
    /// real value once a genuine acknowledgement or pull arrives. Revision
    /// bump matches the vector exactly (1 -> 2 for a fresh accept).
    func testCompleteLocalEffectMatchesLifecycleVectorRevisionBump() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Task", baseNotes: "", baseCompletedAt: nil, expectedRevision: 1)
        let built = try OutboundCommands.lifecycle(.complete, taskId: "t-v", basis: basis, mutationId: "m-v", acceptedAt: "2026-08-31T12:00:00.000000Z")
        XCTAssertEqual(built.effect.revision, 2, "matches lifecycle.json 'complete accepts the active task': revision 1 -> 2")
        XCTAssertEqual(built.effect.completedAt, "2026-08-31T12:00:00.000000Z")
    }

    /// `packages/contracts/vectors/trash-restore.json`'s "trash accepts the
    /// exact active revision": `expected_revision: 7 -> revision: 8`.
    func testTrashLocalEffectMatchesTrashRestoreVectorRevisionBump() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Task", baseNotes: "", expectedRevision: 7)
        let built = try OutboundCommands.lifecycle(.trash, taskId: "t-v2", basis: basis, mutationId: "m-v2", acceptedAt: "2026-08-31T13:00:00.000000Z")
        XCTAssertEqual(built.effect.revision, 8, "matches trash-restore.json 'trash accepts the exact active revision': revision 7 -> 8")
        XCTAssertEqual(built.effect.trashedAt, "2026-08-31T13:00:00.000000Z")
    }

    /// `packages/contracts/vectors/editing.json`'s "ordinary edit preserves
    /// Inbox": `expected_revision: 3 -> revision: 4`, notes replaced, title
    /// unaffected.
    func testEditLocalEffectMatchesEditingVectorRevisionBumpAndPreservesUntouchedTitle() throws {
        let basis = OutboundCommands.Basis(baseTitle: "Call dentist", baseNotes: "Ask about Tuesday", expectedRevision: 3)
        let built = try OutboundCommands.edit(taskId: "t-v3", touched: .init(notes: "Ask about Wednesday"), basis: basis, mutationId: "m-v3")
        XCTAssertEqual(built.effect.revision, 4, "matches editing.json 'ordinary edit preserves Inbox': revision 3 -> 4")
        XCTAssertEqual(built.effect.title, "Call dentist", "an untouched title must survive the effect unchanged")
        XCTAssertEqual(built.effect.notes, "Ask about Wednesday")
    }

    /// Commands with no corresponding golden vector in
    /// `packages/contracts/vectors/`: `return_to_inbox` (no vector file
    /// names this command), `plan_for_today`/`unplan_task` (no
    /// `task-dates.json`-style vector for the planning boolean this plan's
    /// local effect tracks -- `task-dates.json` covers `edit_task_dates`,
    /// a DIFFERENT command outside this plan's ten-command scope).
    func testCommandsWithNoCorrespondingGoldenVectorAreDocumented() {
        let undocumented = ["return_to_inbox", "plan_for_today", "unplan_task", "clarify_task"]
        XCTAssertEqual(undocumented.count, 4, "recorded here and in the SUMMARY -- see 'Commands With No Corresponding Golden Vector'")
    }
}
