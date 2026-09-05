import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import KeeplingCore

/// A `ClientTransport` test seam dedicated to this file (rather than
/// reusing `RefusalClassificationTests.StubTransport`, which has no
/// request-body-capture or per-operation queueing this plan's rotation and
/// callback-rejection proofs need). Same officially-documented pattern
/// `OpenAPIRuntime.ClientTransport`'s own doc comment describes.
final class DeviceGrantStubTransport: ClientTransport, @unchecked Sendable {
    struct Canned {
        let status: Int
        let contentType: String
        let body: Data
    }

    private var responses: [String: [Canned]] = [:]
    private(set) var callCounts: [String: Int] = [:]
    private(set) var recordedBodies: [String: [Data]] = [:]

    func enqueue<T: Encodable>(operationID: String, status: Int, value: T, contentType: String = "application/json") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(value)
        responses[operationID, default: []].append(Canned(status: status, contentType: contentType, body: data))
    }

    func enqueueProblem(operationID: String, status: Int, code: String) {
        let problem = Components.Schemas.Problem(
            _type: "about:blank", title: "refused", status: status, code: code, retryable: false, recovery_action: "none"
        )
        enqueue(operationID: operationID, status: status, value: problem, contentType: "application/problem+json")
    }

    func send(
        _ request: HTTPRequest,
        body: OpenAPIRuntime.HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, OpenAPIRuntime.HTTPBody?) {
        callCounts[operationID, default: 0] += 1
        if let body {
            var collected = Data()
            for try await chunk in body {
                collected.append(contentsOf: chunk)
            }
            recordedBodies[operationID, default: []].append(collected)
        }
        guard var queue = responses[operationID], !queue.isEmpty else {
            XCTFail("no stub registered for operation \(operationID)")
            throw URLError(.unknown)
        }
        let canned = queue.removeFirst()
        responses[operationID] = queue
        var response = HTTPResponse(status: .init(code: canned.status))
        response.headerFields[.contentType] = canned.contentType
        return (response, OpenAPIRuntime.HTTPBody(canned.body))
    }
}

/// In-memory `CredentialPort` double -- the leak-scan/before-first-unlock
/// proofs live in `CredentialStoreTests` against the real Keychain-backed
/// implementation; this double only needs to record what was stored.
final class InMemoryCredentialStore: CredentialPort, @unchecked Sendable {
    private(set) var stored: StoredNativeCredentials?
    private(set) var clearCallCount = 0

    func store(_ credentials: StoredNativeCredentials) throws {
        stored = credentials
    }

    func load() throws -> StoredNativeCredentials? { stored }

    func clear() throws {
        clearCallCount += 1
        stored = nil
    }
}

/// Records every namespace it was asked to activate and returns a fixed
/// mapped `SyncNamespace` -- the real field-by-field refusal proofs live
/// in `NamespaceFencingTests` against `NamespaceActivation` itself.
final class RecordingNamespaceActivator: NamespaceActivating, @unchecked Sendable {
    private(set) var activated: [Components.Schemas.NativeSyncNamespace] = []

    func activate(_ namespace: Components.Schemas.NativeSyncNamespace) throws -> SyncNamespace {
        activated.append(namespace)
        return SyncNamespace(
            issuer: namespace.issuer,
            origin: namespace.origin,
            serverInstance: namespace.server_instance,
            accountSubject: namespace.account_subject,
            generation: String(namespace.generation)
        )
    }
}

final class DeviceGrantTests: XCTestCase {
    private func makeNamespace(accountSubject: String = "user-1", generation: Int = 1) -> Components.Schemas.NativeSyncNamespace {
        Components.Schemas.NativeSyncNamespace(
            account_subject: accountSubject,
            generation: generation,
            issuer: "https://keepling.example/oauth",
            origin: "server",
            server_instance: "server-1"
        )
    }

    private func makeTokenResponse(accessToken: String, refreshToken: String, namespace: Components.Schemas.NativeSyncNamespace) -> Components.Schemas.NativeTokenResponse {
        Components.Schemas.NativeTokenResponse(
            access_token: accessToken, expires_in: ._900, namespace: namespace, refresh_token: refreshToken, token_type: .Bearer
        )
    }

    private func makeClient(
        transport: DeviceGrantStubTransport,
        credentialStore: InMemoryCredentialStore = InMemoryCredentialStore(),
        activator: RecordingNamespaceActivator = RecordingNamespaceActivator(),
        entropy: [Data] = []
    ) -> DeviceGrantClient {
        var remaining = entropy
        return DeviceGrantClient(
            baseURL: URL(string: "https://keepling.example.com")!,
            configuration: DeviceGrantConfiguration(installationId: "installation-1", label: "Keepling for iPhone", redirectURI: "keepling://ios/auth/callback"),
            credentialStore: credentialStore,
            namespaceActivator: activator,
            transport: transport,
            entropy: { count in
                if remaining.isEmpty { return Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }
                return remaining.removeFirst()
            }
        )
    }

    // MARK: - Task 1 acceptance: closed client_id, no secret, no namespace assertion

    func testAuthorizationURLDeclaresClientIdIphoneWithNoSecretOrNamespaceAssertion() {
        let client = makeClient(transport: DeviceGrantStubTransport())
        let url = client.beginAuthorization(serverBaseURL: URL(string: "https://keepling.example.com")!)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let byName = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(byName["client_id"], "iphone")
        XCTAssertNil(byName["client_secret"])
        XCTAssertNil(byName["namespace"])
        XCTAssertNil(byName["account_subject"])
        XCTAssertEqual(byName["code_challenge_method"], "S256")
    }

    // MARK: - Extra authority field rejected before dispatch

    func testCallbackWithExtraAuthorityFieldIsRejectedBeforeDispatch() async throws {
        let transport = DeviceGrantStubTransport()
        let client = makeClient(transport: transport)
        _ = client.beginAuthorization(serverBaseURL: URL(string: "https://keepling.example.com")!)

        // An attacker/malformed redirect attempting to smuggle namespace
        // authority through the one untrusted input this flow accepts.
        var components = URLComponents(url: URL(string: "keepling://ios/auth/callback")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "some-code"),
            URLQueryItem(name: "state", value: "some-state"),
            URLQueryItem(name: "account_subject", value: "attacker-controlled"),
        ]

        do {
            _ = try await client.completeAuthorization(callbackURL: components.url!)
            XCTFail("expected unexpectedCallbackField to be thrown")
        } catch DeviceGrantError.unexpectedCallbackField(let field) {
            XCTAssertEqual(field, "account_subject")
        }

        XCTAssertEqual(transport.callCounts["exchangeNativeAuthorizationCode"] ?? 0, 0, "the exchange must never be dispatched for a rejected callback")
    }

    // MARK: - Successful exchange stores credentials and activates namespace as one step

    func testSuccessfulExchangeStoresCredentialsAndActivatesNamespaceAsOneStep() async throws {
        let transport = DeviceGrantStubTransport()
        let credentialStore = InMemoryCredentialStore()
        let activator = RecordingNamespaceActivator()
        let client = makeClient(transport: transport, credentialStore: credentialStore, activator: activator)

        let authorizationURL = client.beginAuthorization(serverBaseURL: URL(string: "https://keepling.example.com")!)
        let state = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!

        let namespace = makeNamespace()
        transport.enqueue(operationID: "exchangeNativeAuthorizationCode", status: 200, value: makeTokenResponse(accessToken: "access-1", refreshToken: "refresh-1", namespace: namespace))

        var callback = URLComponents(url: URL(string: "keepling://ios/auth/callback")!, resolvingAgainstBaseURL: false)!
        callback.queryItems = [URLQueryItem(name: "code", value: "auth-code-1"), URLQueryItem(name: "state", value: state)]

        let credentials = try await client.completeAuthorization(callbackURL: callback.url!)

        XCTAssertEqual(credentials.accessToken, "access-1")
        XCTAssertEqual(credentials.refreshToken, "refresh-1")
        XCTAssertEqual(activator.activated.count, 1, "namespace activation must happen exactly once, in the same step as credential storage")
        XCTAssertEqual(credentialStore.stored?.accessToken, "access-1")
        XCTAssertEqual(credentialStore.stored?.refreshToken, "refresh-1")
        XCTAssertEqual(credentialStore.stored?.namespace, credentials.namespace)
    }

    // MARK: - Refresh rotates both credentials; prior handle never reused

    func testRefreshRotatesBothCredentialsAndNeverReusesThePriorRefreshHandle() async throws {
        let transport = DeviceGrantStubTransport()
        let credentialStore = InMemoryCredentialStore()
        let namespace = makeNamespace()
        try credentialStore.store(StoredNativeCredentials(
            accessToken: "access-old", refreshToken: "refresh-old",
            namespace: SyncNamespace(issuer: namespace.issuer, origin: namespace.origin, serverInstance: namespace.server_instance, accountSubject: namespace.account_subject, generation: "1")
        ))
        let client = makeClient(transport: transport, credentialStore: credentialStore)

        transport.enqueue(operationID: "refreshNativeGrant", status: 200, value: makeTokenResponse(accessToken: "access-new-1", refreshToken: "refresh-new-1", namespace: namespace))
        _ = try await client.refresh()

        XCTAssertEqual(credentialStore.stored?.refreshToken, "refresh-new-1")

        // Rotate again: the SECOND refresh must send the NEW handle, never
        // the one this test started with.
        transport.enqueue(operationID: "refreshNativeGrant", status: 200, value: makeTokenResponse(accessToken: "access-new-2", refreshToken: "refresh-new-2", namespace: namespace))
        _ = try await client.refresh()

        let bodies = transport.recordedBodies["refreshNativeGrant"] ?? []
        XCTAssertEqual(bodies.count, 2)
        let secondRequest = try JSONDecoder().decode(Components.Schemas.NativeRefreshRequest.self, from: bodies[1])
        XCTAssertEqual(secondRequest.refresh_token, "refresh-new-1")
        XCTAssertNotEqual(secondRequest.refresh_token, "refresh-old")
        XCTAssertEqual(credentialStore.stored?.refreshToken, "refresh-new-2")
    }

    // MARK: - Replay/revocation is terminal: clears credentials, never retries

    func testRefreshReplayOrRevocationClearsCredentialsAndRaisesAuthenticationRequiredWithoutRetrying() async throws {
        let transport = DeviceGrantStubTransport()
        let credentialStore = InMemoryCredentialStore()
        let namespace = makeNamespace()
        try credentialStore.store(StoredNativeCredentials(
            accessToken: "access-old", refreshToken: "refresh-old",
            namespace: SyncNamespace(issuer: namespace.issuer, origin: namespace.origin, serverInstance: namespace.server_instance, accountSubject: namespace.account_subject, generation: "1")
        ))
        let client = makeClient(transport: transport, credentialStore: credentialStore)

        transport.enqueueProblem(operationID: "refreshNativeGrant", status: 401, code: "refresh_replay_detected")

        do {
            _ = try await client.refresh()
            XCTFail("expected SyncAuthenticationRequired to be thrown")
        } catch let error as SyncAuthenticationRequired {
            XCTAssertEqual(error.code, "refresh_replay_detected")
        }

        XCTAssertNil(credentialStore.stored, "a replay/revocation answer must clear stored credentials")
        XCTAssertEqual(transport.callCounts["refreshNativeGrant"], 1, "a terminal replay/revocation answer must never be retried")
    }

    // MARK: - A 401 during push raises authentication-required, never an acknowledgement

    func testA401DuringPushRaisesAuthenticationRequiredNeverAnAcknowledgement() async throws {
        let transport = DeviceGrantStubTransport()
        let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)
        transport.enqueueProblem(operationID: "captureTask", status: 401, code: "authentication_required")

        let mutation = LocalMutation(
            mutationId: "mutation-auth-1", taskId: "task-1",
            commandBytes: #"{"mutation_id":"mutation-auth-1","task_id":"task-1","title":"Call dentist","type":"capture_task","version":1}"#,
            fingerprint: "fingerprint-1", acceptedAt: "2026-09-01T00:00:00.000000Z", resourceKeys: ["task:task-1"], title: "Call dentist"
        )

        do {
            _ = try await adapter.push(mutation)
            XCTFail("expected SyncAuthenticationRequired")
        } catch let error as SyncAuthenticationRequired {
            XCTAssertEqual(error.code, "authentication_required")
        }
    }

    // MARK: - A mutation interrupted by authentication expiry resumes with its original identity

    func testMutationInterruptedByAuthenticationExpiryResumesWithOriginalMutationIdentity() async throws {
        let transport = DeviceGrantStubTransport()
        let adapter = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)

        let mutation = LocalMutation(
            mutationId: "mutation-resume-1", taskId: "task-1",
            commandBytes: #"{"mutation_id":"mutation-resume-1","task_id":"task-1","title":"Call dentist","type":"capture_task","version":1}"#,
            fingerprint: "fingerprint-1", acceptedAt: "2026-09-01T00:00:00.000000Z", resourceKeys: ["task:task-1"], title: "Call dentist"
        )

        transport.enqueueProblem(operationID: "captureTask", status: 401, code: "authentication_required")
        do {
            _ = try await adapter.push(mutation)
            XCTFail("expected SyncAuthenticationRequired")
        } catch is SyncAuthenticationRequired {
            // expected: authentication expired mid-push
        }

        // Retry after re-authentication uses the EXACT SAME LocalMutation
        // value -- never a re-minted mutation identity.
        let ack = Components.Schemas.CommandAcknowledgement(
            mutation_id: mutation.mutationId,
            outcome: .accepted,
            revision: 1,
            snapshot: TaskSnapshotFixture.make(title: mutation.title),
            task_id: mutation.taskId,
            warnings: []
        )
        transport.enqueue(operationID: "captureTask", status: 201, value: ack)
        let acknowledgement = try await adapter.push(mutation)

        XCTAssertEqual(acknowledgement.mutationId, mutation.mutationId)
        let bodies = transport.recordedBodies["captureTask"] ?? []
        XCTAssertEqual(bodies.count, 2)
        let firstRequest = try JSONDecoder().decode(Components.Schemas.CaptureTaskCommand.self, from: bodies[0])
        let secondRequest = try JSONDecoder().decode(Components.Schemas.CaptureTaskCommand.self, from: bodies[1])
        XCTAssertEqual(firstRequest.mutation_id, secondRequest.mutation_id, "the retried request must carry the exact original mutation identity")
        XCTAssertEqual(secondRequest.mutation_id, mutation.mutationId)
    }
}
