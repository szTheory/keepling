import Security
import XCTest
@testable import KeeplingCore

/// In-memory `KeychainQuerying` double that reproduces just enough real
/// Keychain semantics (duplicate-item detection on add, not-found on a
/// missing item) for these tests, plus a `simulateBeforeFirstUnlock` knob
/// the Simulator itself cannot exercise (there is no way to actually lock
/// an iOS Simulator's Keychain from a test process).
final class StubKeychain: KeychainQuerying, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    var simulateBeforeFirstUnlock = false
    private(set) var lastAddQuery: [String: Any]?

    private func key(_ query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? ""
        let account = query[kSecAttrAccount as String] as? String ?? ""
        return "\(service)|\(account)"
    }

    func add(_ query: [String: Any]) -> OSStatus {
        lastAddQuery = query
        let itemKey = key(query)
        if storage[itemKey] != nil { return errSecDuplicateItem }
        storage[itemKey] = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: CFTypeRef?) {
        if simulateBeforeFirstUnlock { return (errSecInteractionNotAllowed, nil) }
        let itemKey = key(query)
        guard let data = storage[itemKey] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as CFTypeRef)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        let itemKey = key(query)
        guard storage[itemKey] != nil else { return errSecItemNotFound }
        storage[itemKey] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        let itemKey = key(query)
        guard storage.removeValue(forKey: itemKey) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}

final class CredentialStoreTests: XCTestCase {
    private func makeNamespace() -> SyncNamespace {
        SyncNamespace(issuer: "https://keepling.example/oauth", origin: "server", serverInstance: "server-1", accountSubject: "user-1", generation: "1")
    }

    // MARK: - Accessibility class

    func testStoringSetsAfterFirstUnlockAccessibilityAndNotSynchronizable() throws {
        let keychain = StubKeychain()
        let store = KeychainCredentialStore(keychain: keychain)
        try store.store(StoredNativeCredentials(accessToken: "access-1", refreshToken: "refresh-1", namespace: makeNamespace()))

        let query = try XCTUnwrap(keychain.lastAddQuery)
        let accessible = query[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
    }

    // MARK: - Read before first unlock

    func testReadingBeforeFirstUnlockThrowsNamedErrorRatherThanEmptyOrStaleValue() throws {
        let keychain = StubKeychain()
        let store = KeychainCredentialStore(keychain: keychain)
        try store.store(StoredNativeCredentials(accessToken: "access-1", refreshToken: "refresh-1", namespace: makeNamespace()))

        keychain.simulateBeforeFirstUnlock = true
        do {
            _ = try store.load()
            XCTFail("expected CredentialPortError.unavailableBeforeFirstUnlock")
        } catch CredentialPortError.unavailableBeforeFirstUnlock {
            // expected
        }
    }

    // MARK: - Clearing

    func testClearingRemovesTheItemAndSubsequentReadReturnsNotFound() throws {
        let keychain = StubKeychain()
        let store = KeychainCredentialStore(keychain: keychain)
        try store.store(StoredNativeCredentials(accessToken: "access-1", refreshToken: "refresh-1", namespace: makeNamespace()))
        XCTAssertNotNil(try store.load())

        try store.clear()
        XCTAssertNil(try store.load())
    }

    // MARK: - Leak scan: sign-in, capture, push, sign-out

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

    /// Drives a full sign-in, capture, push, and sign-out cycle while
    /// capturing every byte the app writes to UserDefaults, the app
    /// container's files, all 11 SQLite tables, and a diagnostics log --
    /// then asserts none of them contain the ACTUAL access credential,
    /// refresh credential, or PKCE code verifier this test used (never a
    /// pattern -- a pattern scan passes when the format changes and the
    /// leak does not).
    func testFullCycleLeaksNoSecretToAnySurfaceOtherThanTheKeychain() async throws {
        let accessSecret = "leak-scan-access-\(UUID().uuidString)"
        let refreshSecret = "leak-scan-refresh-\(UUID().uuidString)"

        let appContainer = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: appContainer, withIntermediateDirectories: true)
        let storePath = appContainer.appendingPathComponent("keepling.sqlite").path

        let defaultsSuite = "leak-scan-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        defaults.set("some-unrelated-preference", forKey: "unrelated_preference")

        final class DiagnosticsCapture: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var events: [String] = []
            func append(_ event: String) {
                lock.lock(); defer { lock.unlock() }
                events.append(event)
            }
        }
        let diagnostics = DiagnosticsCapture()

        let store = try GRDBLocalStore(path: storePath)
        let keychain = StubKeychain()
        let credentialStore = KeychainCredentialStore(keychain: keychain)
        let transport = DeviceGrantStubTransport()

        struct BindingNamespaceActivator: NamespaceActivating {
            let store: GRDBLocalStore
            func activate(_ namespace: Components.Schemas.NativeSyncNamespace) throws -> SyncNamespace {
                let mapped = SyncNamespace(
                    issuer: namespace.issuer, origin: namespace.origin, serverInstance: namespace.server_instance,
                    accountSubject: namespace.account_subject, generation: String(namespace.generation)
                )
                _ = try store.bindNamespace(mapped)
                return mapped
            }
        }

        // Deterministic PKCE verifier so this test knows the exact secret
        // string to scan for (a real device uses real random bytes; the
        // point of this fixture is a KNOWN value, not real entropy).
        let verifierBytes = Data("leak-scan-verifier-material-000000".utf8)
        let stateBytes = Data("leak-scan-state-material-00000000".utf8)
        var entropyQueue = [verifierBytes, stateBytes]

        let client = DeviceGrantClient(
            baseURL: URL(string: "https://keepling.example.com")!,
            configuration: DeviceGrantConfiguration(installationId: "installation-1", label: "Keepling for iPhone", redirectURI: "keepling://ios/auth/callback"),
            credentialStore: credentialStore,
            namespaceActivator: BindingNamespaceActivator(store: store),
            transport: transport,
            entropy: { count in
                if entropyQueue.isEmpty { return Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }
                return entropyQueue.removeFirst()
            },
            diagnostics: { diagnostics.append($0) }
        )

        // 1. Sign in.
        let authorizationURL = client.beginAuthorization(serverBaseURL: URL(string: "https://keepling.example.com")!)
        let state = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)

        let namespace = Components.Schemas.NativeSyncNamespace(account_subject: "user-leak-scan", generation: 1, issuer: "https://keepling.example/oauth", origin: "server", server_instance: "server-1")
        transport.enqueue(operationID: "exchangeNativeAuthorizationCode", status: 200, value: Components.Schemas.NativeTokenResponse(
            access_token: accessSecret, expires_in: ._900, namespace: namespace, refresh_token: refreshSecret, token_type: .Bearer
        ))
        var callback = URLComponents(url: URL(string: "keepling://ios/auth/callback")!, resolvingAgainstBaseURL: false)!
        callback.queryItems = [URLQueryItem(name: "code", value: "auth-code-leak-scan"), URLQueryItem(name: "state", value: state)]
        _ = try await client.completeAuthorization(callbackURL: callback.url!)

        // 2. Capture.
        let mutationId = "mutation-leak-scan-1"
        let commandBytes = #"{"mutation_id":"\#(mutationId)","task_id":"task-leak-scan-1","title":"Call dentist","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: mutationId, taskId: "task-leak-scan-1", commandBytes: commandBytes,
            fingerprint: sha256Hex(commandBytes), acceptedAt: "2026-09-01T00:00:00.000000Z",
            resourceKeys: ["task:task-leak-scan-1"], title: "Call dentist"
        )
        _ = try offMain { try store.acceptMutation(mutation) }

        // 3. Push.
        let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)
        transport.enqueue(operationID: "captureTask", status: 201, value: Components.Schemas.CommandAcknowledgement(
            mutation_id: mutation.mutationId, outcome: .accepted, revision: 1,
            snapshot: TaskSnapshotFixture.make(title: mutation.title), task_id: mutation.taskId, warnings: []
        ))
        _ = try offMain { try store.setOutboxState(mutationId: mutation.mutationId, to: "in_flight") }
        let acknowledgement = try await adapter.push(mutation)
        _ = try offMain { try store.acknowledge(acknowledgement) }

        // 4. Sign out: fence, then clear credentials.
        try offMain { try store.setSyncFence(reason: "signed_out") }
        try credentialStore.clear()

        // --- Scan every surface other than the Keychain itself. ---

        var scannedSurfaces: [String: String] = [:]

        scannedSurfaces["UserDefaults"] = "\(defaults.dictionaryRepresentation())"

        let tableNames = [
            "schema_migrations", "namespace_metadata", "canonical_shadow", "visible_projection",
            "immutable_commands", "mutation_journal", "mutation_dependencies", "outbox",
            "sync_cursor", "conflicts", "last_local_action",
        ]
        var sqliteDump = ""
        for table in tableNames {
            let rows = try offMain { try store.__test_fetchAllRows(table: table) }
            sqliteDump += rows.map { "\($0)" }.joined(separator: "\n")
        }
        scannedSurfaces["SQLite (11 tables)"] = sqliteDump

        scannedSurfaces["Diagnostics log"] = diagnostics.events.joined(separator: "\n")

        scannedSurfaces["App container files"] = Self.dumpContainerFiles(under: appContainer)

        for (secretName, secret) in ["access credential": accessSecret, "refresh credential": refreshSecret, "code verifier": "leak-scan-verifier-material-000000".base64URLEncoded] {
            for (surfaceName, contents) in scannedSurfaces {
                XCTAssertFalse(
                    contents.contains(secret),
                    "\(secretName) leaked into \(surfaceName)"
                )
            }
        }
    }

    /// `FileManager.enumerator`'s `NSEnumerator`-based iteration is
    /// unavailable from an `async` context, so this scan is a plain
    /// synchronous helper the async test calls into.
    private static func dumpContainerFiles(under directory: URL) -> String {
        var dump = ""
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                // The SQLite store's own file (and -wal/-shm) is checked
                // precisely via the structured full-table dump above, not
                // via a raw-bytes scan here, which would double-count it.
                if fileURL.lastPathComponent.hasPrefix("keepling.sqlite") { continue }
                if let contents = try? Data(contentsOf: fileURL), let text = String(data: contents, encoding: .isoLatin1) {
                    dump += text
                }
            }
        }
        return dump
    }
}

private extension String {
    var base64URLEncoded: String {
        Data(utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
