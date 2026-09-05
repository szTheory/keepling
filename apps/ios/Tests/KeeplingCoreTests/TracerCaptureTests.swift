import XCTest
@testable import KeeplingCore

/// RED-first tests for the capture command path (04-01-PLAN.md Task 3
/// `<behavior>`): command-bytes/fingerprint shape and settlement idempotence.
final class TracerCaptureTests: XCTestCase {
    func testBuildProducesDeterministicFingerprintOverExactBytes() throws {
        let built = try CaptureCommand.build(title: "Call dentist", mutationId: "m-1", taskId: "t-1")
        XCTAssertEqual(
            built.commandBytes,
            #"{"mutation_id":"m-1","task_id":"t-1","title":"Call dentist","type":"capture_task","version":1}"#
        )
        XCTAssertEqual(built.fingerprint, sha256Hex(built.commandBytes))
        XCTAssertEqual(built.fingerprint.count, 64)
    }

    func testBuildRejectsEmptyTitle() {
        XCTAssertThrowsError(try CaptureCommand.build(title: "   ", mutationId: "m", taskId: "t")) { error in
            XCTAssertEqual(error as? CaptureCommand.ValidationError, .titleOutOfBounds)
        }
    }

    func testBuildRejectsOversizedTitle() {
        let longTitle = String(repeating: "a", count: 513)
        XCTAssertThrowsError(try CaptureCommand.build(title: longTitle, mutationId: "m", taskId: "t")) { error in
            XCTAssertEqual(error as? CaptureCommand.ValidationError, .titleOutOfBounds)
        }
    }

    func testAcceptMutationRejectsFingerprintMismatch() throws {
        let store = try makeStore()
        let mutation = LocalMutation(
            mutationId: "m-1", taskId: "t-1", commandBytes: "{\"tampered\":true}",
            fingerprint: sha256Hex("not the same bytes"), acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:t-1"], title: "x"
        )
        XCTAssertThrowsError(try store.acceptMutation(mutation)) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fingerprintMismatch)
        }
    }

    func testAcceptMutationReportsLocalSavedOnlyAfterCommit() throws {
        let store = try makeStore()
        let built = try CaptureCommand.build(title: "Buy milk", mutationId: "m-2", taskId: "t-2")
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )
        let acceptance = try store.acceptMutation(mutation)
        XCTAssertEqual(acceptance.mutationId, "m-2")
        XCTAssertEqual(acceptance.title, "Buy milk")

        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks[0].syncStatus, "saved_on_this_mac")
    }

    func testAcknowledgeSettlesAndDeletesOutboxRow() throws {
        let store = try makeStore()
        let built = try CaptureCommand.build(title: "Water plants", mutationId: "m-3", taskId: "t-3")
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )
        _ = try store.acceptMutation(mutation)
        XCTAssertEqual(try store.readyMutations().count, 1)

        let ack = SyncAcknowledgement(
            mutationId: "m-3", fingerprint: built.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-3","revision":1,"title":"Water plants"}"#
        )
        _ = try store.acknowledge(ack)

        XCTAssertEqual(try store.readyMutations().count, 0)
        XCTAssertEqual(try store.outboxState(forMutationId: "m-3"), nil)
        XCTAssertEqual(try store.journalOutcome(forMutationId: "m-3"), "accepted")
    }

    func testReplayingIdenticalAcknowledgementIsANoOpNotAnError() throws {
        let store = try makeStore()
        let built = try CaptureCommand.build(title: "Feed cat", mutationId: "m-4", taskId: "t-4")
        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-01-01T00:00:00Z",
            resourceKeys: ["task:\(built.taskId)"], title: built.title
        )
        _ = try store.acceptMutation(mutation)
        let ack = SyncAcknowledgement(
            mutationId: "m-4", fingerprint: built.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"t-4","revision":1,"title":"Feed cat"}"#
        )
        _ = try store.acknowledge(ack)
        // Second application of the SAME acknowledgement: no-op success.
        XCTAssertNoThrow(try store.acknowledge(ack))
    }

    private func makeStore() throws -> GRDBLocalStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("keepling-test.sqlite").path
        return try GRDBLocalStore(path: path)
    }
}
