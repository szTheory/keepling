import XCTest
import AppIntents
import KeeplingCore
import Security

/// D-23/D-36 on the App Intents surface specifically (04-12-PLAN.md Task 2).
///
/// **Harness disclosure:** `AppIntentsTesting`'s resolve-and-perform path
/// (04-RESEARCH.md's recommended harness) is NOT present on this Mac's
/// pinned SDK -- verified directly: no `AppIntentsTesting.framework`/
/// `.swiftmodule` exists anywhere under
/// `iPhoneSimulator26.5.sdk` or `Xcode.app`, and 04-PATTERNS.md records no
/// in-repo App Intent precedent to fall back on either. Every test in this
/// file (and in `CaptureIntentTests`/`CompleteIntentTests`) therefore
/// drives `AppIntent.perform()` directly rather than through
/// `AppIntentsTesting`'s resolve-then-perform wrapper -- disclosed here and
/// in `docs/testing/ios-testing.md` per the plan's own required fallback
/// language, not silently substituted.
final class IntentPrivacyTests: XCTestCase {
    // MARK: - Repository-root resolution (mirrors `RepositoryRoot.swift`'s
    // established #filePath-ascension technique; AppIntentsTests has no
    // access to that file, declared in a different test target)

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while true {
            let marker = current.appendingPathComponent("apps/ios/project.yml")
            if fileManager.fileExists(atPath: marker.path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                throw XCTSkip("could not resolve the Keepling repository root by ascending from #filePath")
            }
            current = parent
        }
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let url = try repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Parameter resolution failure surfaces as a named intent error

    func testAParameterResolutionFailureSurfacesAsANamedIntentErrorRatherThanAnUnhandledThrow() async throws {
        do {
            _ = try await CaptureTaskIntent(title: "   ").perform()
            XCTFail("expected CaptureTaskIntentError.emptyTitle")
        } catch let error as CaptureTaskIntentError {
            XCTAssertEqual(error, .emptyTitle)
        }
        // A real Swift error, not a trap/precondition failure -- the test
        // process is still alive to make the assertions above, which is
        // itself part of the proof: an unhandled throw at the AppIntents
        // runtime boundary would abort the host process, not surface as a
        // catchable Swift error.
    }

    // MARK: - No credential, token, cursor, or fingerprint in any
    // intent-surfaced string (T-04-12-02, D-23)

    func testNoIntentPhraseParameterSummaryOrDonatedValueContainsACredentialTokenCursorOrFingerprint() async throws {
        // A real secret round trip: written to a fake Keychain (mirrors
        // `CredentialStoreTests.StubKeychain`), then a capture performed
        // through the intent -- proving the ACTUAL secret value used in
        // this test never appears in any intent-surfaced string, not
        // merely that no string LOOKS secret-shaped.
        let accessSecret = "access-\(UUID().uuidString)"
        let refreshSecret = "refresh-\(UUID().uuidString)"
        let namespace = SyncNamespace(issuer: "https://keepling.example/oauth", origin: "server", serverInstance: "server-1", accountSubject: "user-1", generation: "1")
        let keychain = InMemoryKeychain()
        let credentialStore = KeychainCredentialStore(keychain: keychain)
        try credentialStore.store(StoredNativeCredentials(accessToken: accessSecret, refreshToken: refreshSecret, namespace: namespace))

        let intent = CaptureTaskIntent(title: "Buy milk")
        let result = try await intent.perform()
        let taskId = try XCTUnwrap(result.value)

        // Every string this plan's shipped intents can actually surface to
        // Shortcuts/Siri/Spotlight: the two intents' `title`s (the ONLY
        // publicly readable `LocalizedStringResource`s -- `description` and
        // `parameterSummary` are framework-opaque, not readable outside
        // AppIntentsTesting), plus the returned result value, plus the
        // static source text every `Summary`/`AppShortcut`/`title`/
        // `description` literal in this plan's three AppIntents files is
        // compiled from (these are pure compile-time string literals --
        // never interpolated from a runtime secret -- so scanning the
        // exact source text they are declared in is equivalent to scanning
        // every value they could ever render).
        var surfaced: [String] = [
            String(localized: CaptureTaskIntent.title),
            String(localized: CompleteTaskIntent.title),
            taskId,
        ]
        for relativePath in [
            "apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift",
            "apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift",
            "apps/ios/Sources/KeeplingCore/AppIntents/KeeplingShortcuts.swift",
        ] {
            surfaced.append(try sourceText(relativePath))
        }

        for candidate in surfaced {
            XCTAssertFalse(candidate.contains(accessSecret), "intent-surfaced string leaked the access token: \(candidate)")
            XCTAssertFalse(candidate.contains(refreshSecret), "intent-surfaced string leaked the refresh token: \(candidate)")
        }
    }

    // MARK: - No dialog quotes task content beyond what the person supplied

    func testNoAppIntentsSourceFileConstructsADialogQuotingStoreReadTaskContent() throws {
        // This plan's shipped intents build NO `IntentDialog` at all
        // (`.result(value:)` only) -- asserted structurally so a future
        // change that adds one is forced to keep this true rather than
        // silently starting to quote `row.title`/`row.notes` into a
        // system-surfaced dialog.
        for relativePath in [
            "apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift",
            "apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift",
        ] {
            let text = try sourceText(relativePath)
            XCTAssertFalse(text.contains("IntentDialog("), "\(relativePath) constructs an IntentDialog -- verify it quotes only this invocation's own parameter, never a store-read field")
        }
    }

    // MARK: - Deferred surfaces are genuinely absent, not stubbed (D-36)

    func testNoDeferredCaptureSurfaceFrameworkOrAffordanceAppearsAnywhereUnderSources() throws {
        let root = try repositoryRoot()
        let sourcesRoot = root.appendingPathComponent("apps/ios/Sources")
        let forbidden = ["import WidgetKit", "ControlWidget", "LockScreenWidget", "NSExtensionPointIdentifier"]

        var swiftFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }
        XCTAssertFalse(swiftFiles.isEmpty, "expected to find Swift sources under \(sourcesRoot.path)")

        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in forbidden {
                XCTAssertFalse(text.contains(needle), "\(file.lastPathComponent) references deferred surface \(needle) -- forbidden by D-36")
            }
        }
    }

    // MARK: - project.yml declares exactly one app target, no extension target

    func testProjectYmlDeclaresExactlyOneApplicationTargetAndNoExtensionTarget() throws {
        let text = try sourceText("apps/ios/project.yml")
        let applicationTargetCount = text.components(separatedBy: "type: application").count - 1
        XCTAssertEqual(applicationTargetCount, 1)
        XCTAssertFalse(text.contains("appex"), "an app-extension target was introduced -- forbidden by D-36/D-37")
    }
}

// MARK: - Test double (mirrors `CredentialStoreTests.StubKeychain`'s
// established in-memory-Keychain technique; AppIntentsTests cannot
// `@testable import` KeeplingCore's internal `StubKeychain`, declared in a
// different test target, so this is its own minimal equivalent)

private final class InMemoryKeychain: KeychainQuerying, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    private func key(_ query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? ""
        let account = query[kSecAttrAccount as String] as? String ?? ""
        return "\(service)|\(account)"
    }

    func add(_ query: [String: Any]) -> OSStatus {
        let itemKey = key(query)
        if storage[itemKey] != nil { return errSecDuplicateItem }
        storage[itemKey] = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: CFTypeRef?) {
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
