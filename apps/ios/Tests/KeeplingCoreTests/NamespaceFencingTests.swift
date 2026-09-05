import XCTest
@testable import KeeplingCore

/// T-04-07-02/T-04-07-04: proves `NamespaceActivation.activate(_:)` is the
/// ONLY namespace-activation entry point (its one parameter is the
/// decoded, authenticated token response), that a missing or empty field
/// refuses activation naming the field, and that a second account signing
/// in on a phone that already holds the first account's local intent
/// fences the first namespace -- rather than deleting it -- and can
/// neither read nor push through it.
final class NamespaceFencingTests: XCTestCase {
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

    private func newStorePath() -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("namespace-fencing.sqlite").path
    }

    private func completeNamespace(accountSubject: String = "user-a", generation: Int = 1) -> Components.Schemas.NativeSyncNamespace {
        Components.Schemas.NativeSyncNamespace(
            account_subject: accountSubject, generation: generation,
            issuer: "https://keepling.example/oauth", origin: "server", server_instance: "server-1"
        )
    }

    // MARK: - Task 3 acceptance: a missing/empty field refuses activation, naming it

    func testEachEmptyStringFieldRefusesActivationNamingTheField() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        let activation = NamespaceActivation(store: store)

        let fieldsToEmpty: [(String, (Components.Schemas.NativeSyncNamespace) -> Components.Schemas.NativeSyncNamespace)] = [
            ("issuer", { var n = $0; n.issuer = ""; return n }),
            ("origin", { var n = $0; n.origin = ""; return n }),
            ("server_instance", { var n = $0; n.server_instance = ""; return n }),
            ("account_subject", { var n = $0; n.account_subject = ""; return n }),
        ]

        for (fieldName, mutate) in fieldsToEmpty {
            let namespace = mutate(completeNamespace())
            XCTAssertThrowsError(try activation.activate(namespace)) { error in
                XCTAssertEqual(error as? NamespaceActivationError, .missingField(fieldName), "expected the empty \(fieldName) field to be named")
            }
        }
    }

    func testANegativeGenerationRefusesActivation() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        let activation = NamespaceActivation(store: store)
        let namespace = completeNamespace(generation: -1)
        XCTAssertThrowsError(try activation.activate(namespace)) { error in
            XCTAssertEqual(error as? NamespaceActivationError, .missingField("generation"))
        }
    }

    func testACompleteNamespaceActivatesAndBindsTheStore() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        let activation = NamespaceActivation(store: store)
        let mapped = try offMain { try activation.activate(self.completeNamespace()) }
        XCTAssertEqual(mapped.accountSubject, "user-a")
        XCTAssertEqual(mapped.generation, "1")

        // A second activation with the SAME tuple must not fence (it is
        // literally the same account/generation binding again).
        XCTAssertNoThrow(try offMain { try activation.activate(self.completeNamespace()) })
    }

    // MARK: - Account-switch fencing: fenced, not deleted; unreadable, unpushable

    private func accept(_ store: GRDBLocalStore, mutationId: String, taskId: String, title: String) throws {
        let commandBytes = #"{"mutation_id":"\#(mutationId)","task_id":"\#(taskId)","title":"\#(title)","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: mutationId, taskId: taskId, commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: ["task:\(taskId)"], title: title
        )
        _ = try offMain { try store.acceptMutation(mutation) }
    }

    func testSecondAccountFencesTheFirstNamespaceRatherThanDeletingItAndCannotReadOrPush() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        let activation = NamespaceActivation(store: store)

        _ = try offMain { try activation.activate(self.completeNamespace(accountSubject: "user-a")) }
        try accept(store, mutationId: "m-a-1", taskId: "t-a-1", title: "Account A's task")

        // Account B signs in on the SAME phone.
        let bindResult = try offMain { try activation.activate(self.completeNamespace(accountSubject: "user-b")) }
        _ = bindResult // activation itself never throws on a mismatch -- it fences (bindNamespace's own contract)

        // Cannot READ account A's rows through the normal surfaces.
        XCTAssertThrowsError(try offMain { try store.snapshot() }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
        }
        XCTAssertThrowsError(try offMain { try store.syncState() }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
        }

        // Cannot PUSH as account B either -- the whole store is fenced for
        // writes, not just account A's rows.
        XCTAssertThrowsError(try accept(store, mutationId: "m-b-1", taskId: "t-b-1", title: "Account B's task")) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
        }

        // Cannot SETTLE account A's row either.
        let ack = SyncAcknowledgement(mutationId: "m-a-1", fingerprint: sha256Hex(#"{"mutation_id":"m-a-1","task_id":"t-a-1","title":"Account A's task","type":"capture_task","version":1}"#), outcome: .accepted, snapshotJSON: #"{"id":"t-a-1","revision":1,"title":"Account A's task"}"#)
        XCTAssertThrowsError(try offMain { try store.acknowledge(ack) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
        }

        // Account A's row is FENCED, not deleted -- the test-only direct
        // read (which deliberately bypasses the fence, the same escape
        // hatch `SettlementTests`/`BackupReplayTests` use) still finds it.
        let projectionRows = try store.__test_fetchAllRows(table: "visible_projection")
        XCTAssertEqual(projectionRows.count, 1)
        XCTAssertEqual(projectionRows.first?["task_id"], "t-a-1")
    }
}
