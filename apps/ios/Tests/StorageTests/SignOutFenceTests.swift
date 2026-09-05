import XCTest
@testable import KeeplingCore

/// A `SyncPort` double whose `revoke` always throws -- proves sign-out's
/// order (fence, then clear credentials, THEN best-effort revoke) is a
/// real property, not just documented (T-04-07-06).
final class ThrowingRevokeSyncPort: SyncPort, @unchecked Sendable {
    struct RevocationFailed: Error {}
    private(set) var revokeCallCount = 0

    func bootstrap(cursor: String?) async throws -> SyncPullPage { throw RevocationFailed() }
    func pull(cursor: String?) async throws -> SyncPullPage { throw RevocationFailed() }
    func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement { throw RevocationFailed() }
    func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement { throw RevocationFailed() }
    func revoke(installationId: String) async throws {
        revokeCallCount += 1
        throw RevocationFailed()
    }
}

/// D-set/T-04-07-06/T-04-07-08: proves sign-out's order is a real,
/// asserted property (write the fence, clear the Keychain, THEN attempt
/// revocation best-effort), that every write-path store method refuses
/// with the fence reason once signed out, and that local-data removal's
/// signature carries no transport dependency.
final class SignOutFenceTests: XCTestCase {
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
        return directory.appendingPathComponent("sign-out-fence.sqlite").path
    }

    private func namespace() -> SyncNamespace {
        SyncNamespace(issuer: "https://keepling.example/oauth", origin: "server", serverInstance: "server-1", accountSubject: "user-1", generation: "1")
    }

    // MARK: - Sign-out order: fence + clear credentials survive a throwing revocation

    func testSignOutLeavesTheFenceWrittenAndCredentialsClearedEvenWhenRevocationThrows() async throws {
        let store = try GRDBLocalStore(path: newStorePath())
        try offMain { try store.bindNamespace(self.namespace()) }

        final class InMemoryCredentialStoreDouble: CredentialPort, @unchecked Sendable {
            private(set) var stored: StoredNativeCredentials?
            func store(_ credentials: StoredNativeCredentials) throws { stored = credentials }
            func load() throws -> StoredNativeCredentials? { stored }
            func clear() throws { stored = nil }
        }

        let credentialStore = InMemoryCredentialStoreDouble()
        try credentialStore.store(StoredNativeCredentials(accessToken: "access-1", refreshToken: "refresh-1", namespace: namespace()))

        let revoking = ThrowingRevokeSyncPort()
        let coordinator = SignOutCoordinator(store: store, credentials: credentialStore, revoking: revoking)

        // signOut itself must not surface the revocation failure -- it is
        // caught internally, by design (best-effort).
        try await coordinator.signOut(installationId: "installation-1")

        XCTAssertEqual(revoking.revokeCallCount, 1, "revocation must still be attempted")
        XCTAssertNil(credentialStore.stored, "credentials must be gone regardless of revocation outcome")

        let fenceRows = try store.__test_fetchAllRows(table: "namespace_metadata").filter { $0["key"] == "sync_fence" }
        XCTAssertEqual(fenceRows.first?["value"], SignOutCoordinator.fenceReason)
    }

    // MARK: - Every write-path store method refuses with the fence reason after sign-out

    func testEveryWritePathStoreMethodRefusesWithTheFenceReasonAfterSignOut() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        try offMain { try store.bindNamespace(self.namespace()) }
        try offMain { try store.setSyncFence(reason: SignOutCoordinator.fenceReason) }

        let commandBytes = #"{"mutation_id":"m-1","task_id":"t-1","title":"Call dentist","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: "m-1", taskId: "t-1", commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: ["task:t-1"], title: "Call dentist"
        )

        XCTAssertThrowsError(try offMain { try store.acceptMutation(mutation) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites(SignOutCoordinator.fenceReason))
        }
        XCTAssertThrowsError(try offMain { try store.setOutboxState(mutationId: "m-1", to: "in_flight") }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites(SignOutCoordinator.fenceReason))
        }
        let ack = SyncAcknowledgement(mutationId: "m-1", fingerprint: sha256Hex(commandBytes), outcome: .accepted, snapshotJSON: #"{"id":"t-1","revision":1,"title":"Call dentist"}"#)
        XCTAssertThrowsError(try offMain { try store.acknowledge(ack) }) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites(SignOutCoordinator.fenceReason))
        }
    }

    // MARK: - Local-data removal is structurally transport-free

    func testLocalNamespaceDataRemovalWipesEveryTableAndClearsTheNamespace() throws {
        let store = try GRDBLocalStore(path: newStorePath())
        try offMain { try store.bindNamespace(self.namespace()) }

        let commandBytes = #"{"mutation_id":"m-wipe-1","task_id":"t-wipe-1","title":"Call dentist","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: "m-wipe-1", taskId: "t-wipe-1", commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: ["task:t-wipe-1"], title: "Call dentist"
        )
        _ = try offMain { try store.acceptMutation(mutation) }
        XCTAssertEqual(try store.countRows(in: "visible_projection"), 1)

        try offMain { try LocalNamespaceDataRemoval.removeAll(from: store) }

        for table in ["visible_projection", "immutable_commands", "mutation_journal", "outbox", "namespace_metadata"] {
            XCTAssertEqual(try store.countRows(in: table), 0, "\(table) must be empty after removal")
        }

        // A fresh bind after removal starts clean -- no lingering fence.
        XCTAssertTrue(try offMain { try store.bindNamespace(self.namespace()) })
    }

    /// Source-scan proof (mirrors `WireMapperBoundaryTests`' own
    /// technique): `LocalNamespaceDataRemoval.removeAll`'s declaration
    /// line names no sync/transport type, so a server deletion is
    /// UNREACHABLE from this call site structurally, not merely uncalled.
    func testLocalNamespaceDataRemovalSignatureCarriesNoTransportParameter() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SignOutFenceTests.swift -> StorageTests
            .deletingLastPathComponent() // StorageTests -> Tests
            .deletingLastPathComponent() // Tests -> apps/ios
            .appendingPathComponent("Sources/KeeplingCore/Auth/NamespaceActivation.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let declarationLine = source.components(separatedBy: "\n").first(where: { $0.contains("static func removeAll") }) else {
            XCTFail("could not find LocalNamespaceDataRemoval.removeAll's declaration")
            return
        }
        for forbidden in ["SyncPort", "Transport", "ClientTransport", "URLSession"] {
            XCTAssertFalse(declarationLine.contains(forbidden), "removeAll's signature must never name a transport type (\(forbidden))")
        }
        XCTAssertTrue(declarationLine.contains("GRDBLocalStore"), "removeAll's only parameter must be the store")
    }
}
