import XCTest
import KeeplingCore

/// Proves `CaptureTaskIntent` (04-12-PLAN.md Task 1) drives the SAME
/// `OutboundCommands.capture` producer and the SAME fence-checked
/// `acceptMutation` path the capture sheet uses, against the ONE store
/// handle `IntentStoreAccess` owns -- no second store, no dropped fence,
/// no stranded draft.
final class CaptureIntentTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("capture-intent-test.sqlite").path
    }

    private var store: GRDBLocalStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try GRDBLocalStore(path: storePath())
        IntentStoreAccess.__test_overrideSharedStore(store)
    }

    override func tearDownWithError() throws {
        IntentStoreAccess.__test_overrideSharedStore(nil)
        store = nil
        try super.tearDownWithError()
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

    // MARK: - Capture through the intent produces the real, byte-identical command

    func testCaptureIntentProducesTheSameCommandBytesFingerprintAndDurableCommitAsOutboundCommandsCapture() async throws {
        let intent = CaptureTaskIntent(title: "Buy milk")
        let result = try await intent.perform()
        let taskId = try XCTUnwrap(result.value)

        let ready = try offMain { try self.store.readyMutations() }
        let mutation = try XCTUnwrap(ready.first { $0.taskId == taskId })

        // Rebuild the SAME wire shape from the exact mutation_id/task_id the
        // intent used (read back from the durably stored mutation, not
        // fabricated) -- this proves the intent invokes the IDENTICAL
        // `OutboundCommands.capture` producer the capture sheet's
        // `WorkspaceFacade.capture` calls, not a divergent encoder.
        let rebuilt = try OutboundCommands.capture(title: "Buy milk", mutationId: mutation.mutationId, taskId: taskId)
        XCTAssertEqual(mutation.commandBytes, rebuilt.commandBytes)
        XCTAssertEqual(mutation.fingerprint, rebuilt.fingerprint)

        let snapshot = try offMain { try self.store.snapshot() }
        XCTAssertTrue(snapshot.tasks.contains { $0.taskId == taskId && $0.title == "Buy milk" })
    }

    func testEmptyTitleCaptureIntentReturnsANamedErrorAndCommitsNothing() async throws {
        let before = try offMain { try self.store.snapshot() }
        let intent = CaptureTaskIntent(title: "   ")
        do {
            _ = try await intent.perform()
            XCTFail("expected CaptureTaskIntentError.emptyTitle")
        } catch let error as CaptureTaskIntentError {
            XCTAssertEqual(error, .emptyTitle)
        }
        let after = try offMain { try self.store.snapshot() }
        XCTAssertEqual(before, after)
        let ready = try offMain { try self.store.readyMutations() }
        XCTAssertTrue(ready.isEmpty)
    }

    // MARK: - The durable capture draft survives an intent (D-37)

    func testAnIntentPerformedWithANonemptyDraftPresentLeavesTheDraftIntact() async throws {
        try offMain { try self.store.saveDraft(CaptureDraft(title: "unsent draft text", addToToday: false)) }

        let intent = CaptureTaskIntent(title: "A completely different capture")
        _ = try await intent.perform()

        let draft = try offMain { try self.store.loadDraft() }
        XCTAssertEqual(draft.title, "unsent draft text")
        XCTAssertFalse(draft.addToToday)
    }

    // MARK: - The fence: an intent is a write path and refuses like any other (T-04-12-01)

    func testCaptureIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing() async throws {
        // Baseline is read BEFORE the fence is set -- `GRDBLocalStore`
        // fences reads too (T-04-07-04), so a post-fence `snapshot()` call
        // would itself throw. The fence is cleared again below to confirm,
        // from a real read, that nothing landed while it was set.
        let before = try offMain { try self.store.snapshot() }
        try offMain { try self.store.__test_setFence(reason: "namespace_mismatch") }

        let intent = CaptureTaskIntent(title: "Should never land")
        do {
            _ = try await intent.perform()
            XCTFail("expected the intent to throw a fence refusal")
        } catch GRDBLocalStore.StoreError.fencedForWrites(let reason) {
            XCTAssertEqual(reason, "namespace_mismatch")
        }

        try offMain { try self.store.setSyncFence(reason: nil) }
        let after = try offMain { try self.store.snapshot() }
        XCTAssertEqual(before, after)
    }

    // MARK: - One process-wide store handle, no second one (D-37)

    func testTheIntentReachesTheStoreThroughIntentStoreAccessNeverConstructingASecondHandle() async throws {
        // `IntentStoreAccess.sharedStore()` called twice in this process
        // returns the identical instance -- proven directly, since a
        // second, distinct `GRDBLocalStore` opened against the SAME sqlite
        // file from the SAME process would itself be the multi-writer
        // hazard D-37 exists to prevent.
        let first = try IntentStoreAccess.sharedStore()
        let second = try IntentStoreAccess.sharedStore()
        XCTAssertTrue(first === second)

        let intent = CaptureTaskIntent(title: "Reaches the shared handle")
        let result = try await intent.perform()
        let taskId = try XCTUnwrap(result.value)
        let snapshot = try offMain { try first.snapshot() }
        XCTAssertTrue(snapshot.tasks.contains { $0.taskId == taskId })
    }
}
