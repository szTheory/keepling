import XCTest
import KeeplingCore

/// Proves `CompleteTaskIntent` (04-12-PLAN.md Task 1) completes an existing
/// open task durably, no-ops against an already-completed task with zero
/// mutations, and refuses against an unknown task with a named error --
/// through the SAME `IntentStoreAccess`-owned store handle
/// `CaptureIntentTests` exercises.
final class CompleteIntentTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("complete-intent-test.sqlite").path
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

    @discardableResult
    private func captureTask(title: String) throws -> String {
        let taskId = UUID().uuidString
        let built = try OutboundCommands.capture(title: title, mutationId: UUID().uuidString, taskId: taskId)
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z",
            resourceKeys: built.resourceKeys, title: built.effect.title
        )
        _ = try offMain { try self.store.acceptMutation(mutation) }
        return taskId
    }

    // MARK: - Completing an existing open task

    func testCompleteIntentAgainstAnExistingOpenTaskCompletesItDurably() async throws {
        let taskId = try captureTask(title: "Call dentist")

        let intent = CompleteTaskIntent(taskID: taskId)
        let result = try await intent.perform()
        XCTAssertEqual(try XCTUnwrap(result.value), .completed)

        let snapshot = try offMain { try self.store.snapshot() }
        let row = try XCTUnwrap(snapshot.tasks.first { $0.taskId == taskId })
        XCTAssertNotNil(row.completedAt)
    }

    // MARK: - Already-completed task is a no-op success

    func testCompleteIntentAgainstAnAlreadyCompletedTaskIsANoOpSuccess() async throws {
        let taskId = try captureTask(title: "Water plants")
        _ = try await CompleteTaskIntent(taskID: taskId).perform()
        let before = try offMain { try self.store.snapshot() }

        let secondResult = try await CompleteTaskIntent(taskID: taskId).perform()
        XCTAssertEqual(try XCTUnwrap(secondResult.value), .alreadyCompleted)

        let after = try offMain { try self.store.snapshot() }
        XCTAssertEqual(before, after)
    }

    // MARK: - Unknown task refuses with a named error

    func testCompleteIntentAgainstAnUnknownTaskReturnsANamedErrorAndCommitsNothing() async throws {
        let before = try offMain { try self.store.snapshot() }
        do {
            _ = try await CompleteTaskIntent(taskID: "does-not-exist").perform()
            XCTFail("expected CompleteTaskIntentError.unknownTask")
        } catch let error as CompleteTaskIntentError {
            XCTAssertEqual(error, .unknownTask)
        }
        let after = try offMain { try self.store.snapshot() }
        XCTAssertEqual(before, after)
    }

    // MARK: - The fence: an intent is a write path and refuses like any other (T-04-12-01)

    func testCompleteIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing() async throws {
        let taskId = try captureTask(title: "Fenced task")
        // Baseline is read BEFORE the fence is set -- `GRDBLocalStore`
        // fences reads too (T-04-07-04), so a post-fence `snapshot()` call
        // would itself throw. The fence is cleared again below to confirm,
        // from a real read, that nothing changed while it was set.
        let before = try offMain { try self.store.snapshot() }
        try offMain { try self.store.__test_setFence(reason: "namespace_mismatch") }

        do {
            _ = try await CompleteTaskIntent(taskID: taskId).perform()
            XCTFail("expected the intent to throw a fence refusal")
        } catch GRDBLocalStore.StoreError.fencedForWrites(let reason) {
            XCTAssertEqual(reason, "namespace_mismatch")
        }

        try offMain { try self.store.setSyncFence(reason: nil) }
        let after = try offMain { try self.store.snapshot() }
        XCTAssertEqual(before, after)
    }
}
