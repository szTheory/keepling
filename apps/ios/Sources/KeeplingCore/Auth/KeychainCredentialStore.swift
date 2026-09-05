import Foundation
import Security

/// A testable seam over the four `SecItem*` calls this store uses. The
/// Security framework's C API has no protocol to conform to, so this is
/// the one injectable point (mirrors `RefusalClassificationTests.StubTransport`'s
/// pattern for `swift-openapi-generator`'s `ClientTransport`) -- a test
/// can simulate `errSecInteractionNotAllowed` (before first device unlock)
/// deterministically, which the Simulator cannot exercise by actually
/// locking the device (`DataProtectionTests.swift` already disclosed this
/// same Simulator limitation for file-protection reads).
public protocol KeychainQuerying: Sendable {
    func add(_ query: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: CFTypeRef?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The production `KeychainQuerying` implementation -- the only file in
/// this codebase that calls `SecItemAdd`/`SecItemCopyMatching`/
/// `SecItemUpdate`/`SecItemDelete` directly.
public struct SystemKeychain: KeychainQuerying {
    public init() {}

    public func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainCredentialStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
}

/// D-08 (04-CONTEXT.md): the ONLY `CredentialPort` implementation. Sets
/// accessibility to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// explicitly and `kSecAttrSynchronizable` false, so a credential never
/// travels to another device through iCloud Keychain and never survives a
/// restore onto a device that has not yet been unlocked once.
public final class KeychainCredentialStore: CredentialPort {
    private let service: String
    private let account: String
    private let keychain: KeychainQuerying

    public init(
        service: String = "com.szTheory.keepling.native-credentials",
        account: String = "native-credentials",
        keychain: KeychainQuerying = SystemKeychain()
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func store(_ credentials: StoredNativeCredentials) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(CodableStoredCredentials(credentials))
        } catch {
            throw CredentialPortError.encodingFailed
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        // Explicit, never inherited from a system default: never
        // `.whenUnlocked`, never `.always`, and never synchronized to
        // iCloud Keychain.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = false

        let addStatus = keychain.add(addQuery)
        if addStatus == errSecDuplicateItem {
            let updateStatus = keychain.update(baseQuery, attributes: [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ])
            guard updateStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unexpectedStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    public func load() throws -> StoredNativeCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, result) = keychain.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            guard let decoded = try? JSONDecoder().decode(CodableStoredCredentials.self, from: data) else {
                throw CredentialPortError.decodingFailed
            }
            return decoded.stored
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            // The device has not been unlocked since boot -- a named,
            // distinguishable fact, never collapsed into "not found" or an
            // empty credential (D-08).
            throw CredentialPortError.unavailableBeforeFirstUnlock
        default:
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    public func clear() throws {
        let status = keychain.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }
}

/// The exact on-disk (in-Keychain) shape -- never a superset of
/// `StoredNativeCredentials`, so there is no extra field this store could
/// leak by accident.
private struct CodableStoredCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let namespace: SyncNamespace

    init(_ stored: StoredNativeCredentials) {
        accessToken = stored.accessToken
        refreshToken = stored.refreshToken
        namespace = stored.namespace
    }

    var stored: StoredNativeCredentials {
        StoredNativeCredentials(accessToken: accessToken, refreshToken: refreshToken, namespace: namespace)
    }
}
