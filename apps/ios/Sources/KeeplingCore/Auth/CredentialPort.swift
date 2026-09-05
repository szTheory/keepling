import Foundation

/// The five-field namespace plus opaque credential pair -- the ONLY shape
/// ever written through this port. Mirrors desktop's `StoredCredentials`
/// (`apps/desktop/main/adapters/auth.ts`): the namespace is stored EXACTLY
/// as `NamespaceActivation` accepted it (D-02), never re-derived here.
public struct StoredNativeCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let namespace: SyncNamespace

    public init(accessToken: String, refreshToken: String, namespace: SyncNamespace) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.namespace = namespace
    }
}

/// D-08 (04-CONTEXT.md): credentials live ONLY behind this port -- a
/// Keychain-backed implementation today, kept replaceable so a later phase
/// can add a stronger posture without touching `DeviceGrantClient`.
///
/// Note this file's declaration landed alongside `DeviceGrantClient.swift`
/// (Task 1) rather than with `KeychainCredentialStore.swift` (Task 2, its
/// nominal plan home): `DeviceGrantClient` structurally requires this
/// protocol to compile, so the protocol boundary was authored first and
/// the concrete Keychain implementation followed in Task 2 -- disclosed in
/// 04-07-SUMMARY.md, mirroring 04-06-SUMMARY.md's own disclosed
/// intra-task code placement note.
public protocol CredentialPort: Sendable {
    /// Writes the ONLY shape this port accepts. A caller replaces the
    /// whole record on every store -- there is no partial-field update.
    func store(_ credentials: StoredNativeCredentials) throws

    /// `nil` means "no credential is stored" (never signed in, or cleared).
    /// A read attempted before first device unlock throws
    /// `CredentialPortError.unavailableBeforeFirstUnlock` rather than
    /// returning `nil` or a stale value -- those are observably different
    /// facts a caller must not confuse.
    func load() throws -> StoredNativeCredentials?

    /// Removes every item this port wrote. A subsequent `load()` returns
    /// `nil`.
    func clear() throws
}

public enum CredentialPortError: Error, Sendable, Equatable {
    /// The Keychain query answered "cannot decrypt yet" -- the device has
    /// not been unlocked since boot. A named, distinguishable fact, never
    /// collapsed into "not found" or an empty credential.
    case unavailableBeforeFirstUnlock
    case encodingFailed
    case decodingFailed
}
