import CryptoKit
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// The closed native `client_id` value for this platform (Phase 2 D-set:
/// "Native `client_id` is closed to `electron` or `iphone` and maps only
/// to the application-owned client kind, with no secret and no namespace
/// assertion entering issuance"). Declared as a bare constant, never an
/// enum with a second case reachable from this target, so there is no
/// path through which this build could assert `electron`.
public enum NativeClientIdentity {
    public static let iphone = "iphone"
}

/// The exact bytes this app needs to start and finish one authorization
/// round trip -- never a secret, never a namespace assertion.
public struct DeviceGrantConfiguration: Sendable {
    public let installationId: String
    public let label: String
    public let redirectURI: String

    public init(installationId: String, label: String, redirectURI: String) {
        self.installationId = installationId
        self.label = label
        self.redirectURI = redirectURI
    }
}

/// The credential pair plus the server-activated namespace this device
/// operates under, returned by both authorization and refresh.
public struct NativeCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let namespace: SyncNamespace
}

/// `NamespaceActivation.swift` (Task 3) implements this. Declared here
/// because `DeviceGrantClient` structurally requires it: activation's ONLY
/// input is the decoded, authenticated token response's namespace field --
/// there is no overload accepting anything else (T-04-07-02).
public protocol NamespaceActivating: Sendable {
    @discardableResult
    func activate(_ namespace: Components.Schemas.NativeSyncNamespace) throws -> SyncNamespace
}

public enum DeviceGrantError: Error, Sendable, Equatable {
    /// A callback URL carried a query parameter outside the closed
    /// `{code, state}` set -- e.g. an attacker- or malformed-redirect
    /// attempt to smuggle additional authority through the one untrusted
    /// input this flow accepts. Rejected before any exchange request is
    /// built or sent (T-04-07-01).
    case unexpectedCallbackField(String)
    case missingCallbackCode
    case missingCallbackState
    case stateMismatch
    case noAuthorizationInFlight
    case invalidTokenResponse
}

/// Native authorization-code-with-PKCE flow against the existing
/// `/oauth/token` operation and its documented `/oauth/token/refresh`
/// alias (02-11-SUMMARY.md), over the committed generated Swift client.
/// The actual RFC 8252 system-browser presentation
/// (`ASWebAuthenticationSession`) is injected via `beginAuthorization`'s
/// caller -- this type owns PKCE generation, the closed request shape,
/// rotation, and replay/authentication-required classification, and never
/// itself imports `AuthenticationServices`/UIKit, keeping `KeeplingCore`
/// pure Swift (`Package.swift`'s own stated constraint).
public final class DeviceGrantClient: @unchecked Sendable {
    private let client: Client
    private let configuration: DeviceGrantConfiguration
    private let credentialStore: CredentialPort
    private let namespaceActivator: NamespaceActivating
    private let entropy: (Int) -> Data
    private let diagnostics: @Sendable (String) -> Void

    private struct InFlightAuthorization {
        let verifier: String
        let state: String
    }

    private var inFlight: InFlightAuthorization?

    public init(
        baseURL: URL,
        configuration: DeviceGrantConfiguration,
        credentialStore: CredentialPort,
        namespaceActivator: NamespaceActivating,
        transport: any ClientTransport = URLSessionTransport(),
        entropy: @escaping (Int) -> Data = { count in Data((0..<count).map { _ in UInt8.random(in: 0...255) }) },
        diagnostics: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        client = Client(serverURL: baseURL, transport: transport)
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.namespaceActivator = namespaceActivator
        self.entropy = entropy
        self.diagnostics = diagnostics
    }

    // MARK: - Authorization URL (RFC 8252 external user agent)

    /// Builds one authorization URL against `serverBaseURL`, generating a
    /// FRESH 32-byte verifier and unpredictable 32-byte state that REPLACE
    /// any previous in-flight request -- a verifier is never reused, and a
    /// superseded state stops being accepted the moment this returns
    /// (mirrors desktop's `BrowserDelegatedAuthorization.begin`).
    public func beginAuthorization(serverBaseURL: URL) -> URL {
        let verifier = base64url(entropy(32))
        let state = base64url(entropy(32))
        inFlight = InFlightAuthorization(verifier: verifier, state: state)
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        diagnostics("device_grant_authorization_begin")

        var components = URLComponents(
            url: serverBaseURL.appendingPathComponent("oauth/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: NativeClientIdentity.iphone),
            URLQueryItem(name: "installation_id", value: configuration.installationId),
            URLQueryItem(name: "label", value: configuration.label),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    struct ParsedCallback {
        let code: String
        let state: String
    }

    /// Parses one untrusted callback URL. The closed field set is exactly
    /// `{code, state}` -- ANY other query parameter (an extra authority
    /// field) is rejected here, before an exchange request is ever built.
    func parseCallback(_ url: URL) throws -> ParsedCallback {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let allowedKeys: Set<String> = ["code", "state"]
        for item in items where !allowedKeys.contains(item.name) {
            throw DeviceGrantError.unexpectedCallbackField(item.name)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw DeviceGrantError.missingCallbackCode
        }
        guard let state = items.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw DeviceGrantError.missingCallbackState
        }
        return ParsedCallback(code: code, state: state)
    }

    // MARK: - Exchange

    /// Completes one authorization: validates the closed callback field
    /// set, matches state against the in-flight request, exchanges the
    /// code for credentials, and stores the credentials plus the
    /// server-activated namespace as one step. The in-flight request ends
    /// here whether the exchange succeeds or fails (mirrors desktop's
    /// single-use-in-flight-state discipline).
    @discardableResult
    public func completeAuthorization(callbackURL: URL) async throws -> NativeCredentials {
        guard let authorization = inFlight else { throw DeviceGrantError.noAuthorizationInFlight }
        let parsed = try parseCallback(callbackURL)
        guard parsed.state == authorization.state else { throw DeviceGrantError.stateMismatch }
        inFlight = nil

        let request = Components.Schemas.NativeAuthorizationCodeExchangeRequest(
            code: parsed.code,
            code_verifier: authorization.verifier,
            grant_type: .authorization_code,
            redirect_uri: configuration.redirectURI,
            state: parsed.state
        )

        let output: Operations.exchangeNativeAuthorizationCode.Output
        do {
            output = try await client.exchangeNativeAuthorizationCode(.init(body: .json(request)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }

        switch output {
        case .ok(let ok):
            guard case .json(let token) = ok.body else { throw DeviceGrantError.invalidTokenResponse }
            diagnostics("device_grant_exchange_succeeded")
            return try persist(token)
        case .unauthorized(let response):
            diagnostics("device_grant_exchange_unauthorized")
            throw SyncAuthenticationRequired(code: try problemCode(from: response))
        case .badRequest(let response):
            throw SyncPortRefused(status: 400, code: try? problemCode(from: response))
        case .serviceUnavailable(let response):
            throw SyncPortRefused(status: 503, code: try? problemCode(from: response))
        case .undocumented(let statusCode, _):
            throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - Refresh (rotation)

    /// Rotates the currently-stored refresh credential. A server-detected
    /// replay or revocation (T-04-07-07) -- answered as a 401 -- is
    /// TERMINAL: this clears the stored credential and raises
    /// `SyncAuthenticationRequired` rather than retrying. The prior
    /// refresh handle is never reused after a successful rotation because
    /// `persist` immediately overwrites it via `credentialStore.store`.
    @discardableResult
    public func refresh() async throws -> NativeCredentials {
        guard let stored = try credentialStore.load() else { throw DeviceGrantError.noAuthorizationInFlight }

        let request = Components.Schemas.NativeRefreshRequest(
            grant_type: .refresh_token,
            refresh_token: stored.refreshToken
        )

        let output: Operations.refreshNativeGrant.Output
        do {
            output = try await client.refreshNativeGrant(.init(body: .json(request)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }

        switch output {
        case .ok(let ok):
            guard case .json(let token) = ok.body else { throw DeviceGrantError.invalidTokenResponse }
            diagnostics("device_grant_refresh_succeeded")
            return try persist(token)
        case .unauthorized(let response):
            // Replay or revocation: never retryable. Clear first so a
            // caller that ignores the thrown error still cannot push a
            // dead credential family (T-04-07-06/T-04-07-07).
            let code = (try? problemCode(from: response)) ?? "invalid_refresh_token"
            try? credentialStore.clear()
            diagnostics("device_grant_refresh_terminal_\(code)")
            throw SyncAuthenticationRequired(code: code)
        case .badRequest(let response):
            let code = (try? problemCode(from: response)) ?? "invalid_refresh_token"
            try? credentialStore.clear()
            diagnostics("device_grant_refresh_terminal_\(code)")
            throw SyncAuthenticationRequired(code: code)
        case .serviceUnavailable(let response):
            throw SyncPortRefused(status: 503, code: try? problemCode(from: response))
        case .undocumented(let statusCode, _):
            throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - Internals

    private func persist(_ token: Components.Schemas.NativeTokenResponse) throws -> NativeCredentials {
        let namespace = try namespaceActivator.activate(token.namespace)
        let credentials = NativeCredentials(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            namespace: namespace
        )
        try credentialStore.store(StoredNativeCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            namespace: namespace
        ))
        return credentials
    }

    private func problemCode(from response: Components.Responses.ProblemResponse) throws -> String {
        switch response.body {
        case .application_problem_plus_json(let problem):
            return problem.code
        }
    }
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
