import Foundation

public enum NamespaceActivationError: Error, Sendable, Equatable {
    /// A missing OR empty field in the decoded token response, named
    /// exactly so a caller can surface which of the five fields was
    /// absent, rather than a generic "activation failed".
    case missingField(String)
}

/// D-02/D-03 (04-CONTEXT.md): server-only namespace activation. This
/// type's `activate(_:)` is the ONLY namespace-activation entry point in
/// this codebase, and its ONLY parameter is the decoded, authenticated
/// token response's namespace field -- there is no second overload
/// through which a client-derived, request-data-derived, or
/// configured-base-URL-derived namespace could arrive (T-04-07-02). A
/// missing or empty field refuses activation, naming the field, rather
/// than defaulting or partially binding.
public final class NamespaceActivation: NamespaceActivating {
    private let store: GRDBLocalStore

    public init(store: GRDBLocalStore) {
        self.store = store
    }

    @discardableResult
    public func activate(_ namespace: Components.Schemas.NativeSyncNamespace) throws -> SyncNamespace {
        try Self.requireNonEmpty(namespace.issuer, field: "issuer")
        try Self.requireNonEmpty(namespace.origin, field: "origin")
        try Self.requireNonEmpty(namespace.server_instance, field: "server_instance")
        try Self.requireNonEmpty(namespace.account_subject, field: "account_subject")
        guard namespace.generation >= 0 else { throw NamespaceActivationError.missingField("generation") }

        let mapped = SyncNamespace(
            issuer: namespace.issuer,
            origin: namespace.origin,
            serverInstance: namespace.server_instance,
            accountSubject: namespace.account_subject,
            generation: String(namespace.generation)
        )
        _ = try store.bindNamespace(mapped)
        return mapped
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.isEmpty else { throw NamespaceActivationError.missingField(field) }
    }
}

/// Sign-out order IS the safety property (T-04-07-06): write the local
/// fence, clear the Keychain, THEN attempt remote revocation best-effort.
/// A throwing or unreachable revocation still leaves the fence written and
/// the credentials gone -- it is never allowed to undo either of the first
/// two steps.
public final class SignOutCoordinator {
    /// Named so a test can assert on the exact reason string recorded, and
    /// so a UI layer can recognize "signed out" distinctly from a
    /// namespace-mismatch fence.
    public static let fenceReason = "signed_out"

    private let store: GRDBLocalStore
    private let credentials: CredentialPort
    private let revoking: any SyncPort

    public init(store: GRDBLocalStore, credentials: CredentialPort, revoking: any SyncPort) {
        self.store = store
        self.credentials = credentials
        self.revoking = revoking
    }

    /// Writes the fence, clears the Keychain, then attempts revocation
    /// best-effort. A thrown or unreachable revocation is swallowed here
    /// -- by the time it can fail, the two safety-critical local steps
    /// have ALREADY succeeded, and this function's own contract is that it
    /// never propagates a revocation failure back as if sign-out itself
    /// failed.
    public func signOut(installationId: String) async throws {
        try store.setSyncFence(reason: Self.fenceReason)
        try credentials.clear()
        do {
            try await revoking.revoke(installationId: installationId)
        } catch {
            // Best-effort: the fence is written and the credentials are
            // already gone, which is the whole safety property.
        }
    }
}

/// D-set (04-CONTEXT.md removeLocalNamespaceData analog): wipes this
/// device's local intent for the CURRENT namespace entirely. This
/// function's signature carries NO sync or transport parameter anywhere
/// -- `store` is the only parameter -- so a server deletion is
/// structurally UNREACHABLE from this call site, not merely uncalled
/// (T-04-07-08).
public enum LocalNamespaceDataRemoval {
    public static func removeAll(from store: GRDBLocalStore) throws {
        try store.wipeAllLocalData()
    }
}
