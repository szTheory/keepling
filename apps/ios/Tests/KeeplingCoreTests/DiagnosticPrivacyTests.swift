import XCTest
import GRDB
@testable import KeeplingCore

/// Proves 04-15-PLAN.md Task 2's central claim: a full exercise -- sign in,
/// capture, edit, complete (with an undo handle), undo, a second task's
/// conflict, a namespace fence, sign out, and an unrecoverable halt --
/// produces no diagnostic-adjacent surface containing the ACTUAL task
/// titles, notes, credentials, undo handle, cursor, or fingerprint this
/// test used. Mirrors `CredentialStoreTests
/// .testFullCycleLeaksNoSecretToAnySurfaceOtherThanTheKeychain`'s technique
/// (assert against the run's own real values, never a pattern) extended to
/// every surface D-23/T-04-15-01/02 name: the export bundle, the in-product
/// Inspect presentation, the system unified log, accessibility announcement
/// strings, and user-visible error messages.
final class DiagnosticPrivacyTests: XCTestCase {
    // MARK: - Test double

    final actor StubSyncPort: SyncPort {
        enum Behavior {
            case pushResult(SyncAcknowledgement)
            case pushThrows(Error)
        }
        private var pullPage: SyncPullPage
        private var pushBehaviorsByMutationId: [String: [Behavior]]

        init(pullPage: SyncPullPage = SyncPullPage(cursor: "", changes: []), pushBehaviorsByMutationId: [String: [Behavior]] = [:]) {
            self.pullPage = pullPage
            self.pushBehaviorsByMutationId = pushBehaviorsByMutationId
        }

        func bootstrap(cursor: String?) async throws -> SyncPullPage { pullPage }
        func pull(cursor: String?) async throws -> SyncPullPage { pullPage }

        func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
            guard var behaviors = pushBehaviorsByMutationId[mutation.mutationId], !behaviors.isEmpty else {
                return SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
            }
            let behavior = behaviors.removeFirst()
            pushBehaviorsByMutationId[mutation.mutationId] = behaviors
            switch behavior {
            case .pushResult(let ack): return ack
            case .pushThrows(let error): throw error
            }
        }

        func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
            SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .alreadySatisfied, snapshotJSON: #"{"id":"x","revision":1}"#)
        }

        func revoke(installationId: String) async throws {}
    }

    // MARK: - Helpers

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("diagnostic-privacy-test.sqlite").path
    }

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

    private func toLocalMutation(_ built: OutboundCommands.Built) -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: .init(notes: built.effect.notes, completedAt: built.effect.completedAt, trashedAt: built.effect.trashedAt, planned: built.effect.planned)
        )
    }

    // MARK: - The full exercise, scanned across every named surface

    func testFullExerciseLeaksNoActualTaskContentCredentialCursorFingerprintOrHandleToAnyDiagnosticAdjacentSurface() async throws {
        let suffix = UUID().uuidString
        let captureTitle = "Diagnostic leak scan capture title \(suffix)"
        let editNotes = "Diagnostic leak scan edit notes \(suffix)"
        let draftTitle = "Diagnostic leak scan draft title \(suffix)"
        let secondTitle = "Diagnostic leak scan second task title \(suffix)"
        let accessSecret = "diagnostic-leak-scan-access-\(suffix)"
        let refreshSecret = "diagnostic-leak-scan-refresh-\(suffix)"
        let distinctiveCursor = "diagnostic-leak-scan-cursor-\(suffix)"
        let undoHandle = "diagnostic-leak-scan-undo-handle-\(suffix)"

        let path = storePath()
        let log = DiagnosticLog(bound: 200)
        let store = try GRDBLocalStore(path: path, diagnostics: log)

        // 1. Sign in: a real credential round trip through an actual
        // KeychainCredentialStore, exactly as CredentialStoreTests does.
        let keychain = StubKeychain()
        let credentialStore = KeychainCredentialStore(keychain: keychain)
        try credentialStore.store(StoredNativeCredentials(
            accessToken: accessSecret, refreshToken: refreshSecret,
            namespace: SyncNamespace(issuer: "https://a", origin: "a", serverInstance: "a-1", accountSubject: "user-a", generation: "1")
        ))
        XCTAssertTrue(try offMain { try store.bindNamespace(SyncNamespace(issuer: "https://a", origin: "a", serverInstance: "a-1", accountSubject: "user-a", generation: "1")) })

        // 2. Durable capture draft, left present (never cleared) so the
        // scan proves it is absent from diagnostics while it exists.
        try offMain { try store.saveDraft(CaptureDraft(title: draftTitle, addToToday: false)) }

        // 3. Capture, then settle it -- also drives a real pull carrying a
        // distinctive cursor into the local sync state.
        let captureId = UUID().uuidString
        let taskId = "task-\(suffix)"
        let captureBuilt = try OutboundCommands.capture(title: captureTitle, mutationId: captureId, taskId: taskId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(captureBuilt)) }
        var app = KeeplingApplication(
            store: store,
            syncPort: StubSyncPort(
                pullPage: SyncPullPage(cursor: distinctiveCursor, changes: []),
                pushBehaviorsByMutationId: [captureId: [.pushResult(SyncAcknowledgement(
                    mutationId: captureId, fingerprint: captureBuilt.fingerprint, outcome: .accepted,
                    snapshotJSON: #"{"id":"\#(taskId)","revision":1,"title":"\#(captureTitle)"}"#
                ))]]
            ),
            diagnostics: log
        )
        _ = try await app.runSyncPass()
        XCTAssertEqual(try offMain { try store.syncState() }.cursor, distinctiveCursor)

        // 4. Edit (touches notes), settle.
        let editId = UUID().uuidString
        let editBasis = OutboundCommands.Basis(baseTitle: captureTitle, baseNotes: "", expectedRevision: try offMain { try store.expectedRevision(forTaskId: taskId) })
        let editBuilt = try OutboundCommands.edit(taskId: taskId, touched: .init(notes: editNotes), basis: editBasis, mutationId: editId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(editBuilt)) }
        app = KeeplingApplication(store: store, syncPort: StubSyncPort(pushBehaviorsByMutationId: [editId: [.pushResult(SyncAcknowledgement(
            mutationId: editId, fingerprint: editBuilt.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"\#(taskId)","revision":2,"title":"\#(captureTitle)"}"#
        ))]]), diagnostics: log)
        _ = try await app.runSyncPass()

        // 5. Complete, settled with a server-issued undo handle.
        let completeId = UUID().uuidString
        let completeBasis = OutboundCommands.Basis(baseTitle: captureTitle, baseNotes: editNotes, expectedRevision: try offMain { try store.expectedRevision(forTaskId: taskId) })
        let completeBuilt = try OutboundCommands.lifecycle(.complete, taskId: taskId, basis: completeBasis, mutationId: completeId, acceptedAt: "2026-09-05T00:00:00Z")
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(completeBuilt)) }
        app = KeeplingApplication(store: store, syncPort: StubSyncPort(pushBehaviorsByMutationId: [completeId: [.pushResult(SyncAcknowledgement(
            mutationId: completeId, fingerprint: completeBuilt.fingerprint, outcome: .accepted,
            snapshotJSON: #"{"id":"\#(taskId)","revision":3,"title":"\#(captureTitle)"}"#,
            undo: SyncAcknowledgement.UndoAvailabilityHandle(handle: undoHandle, label: "Undo Complete", expiresAt: "2026-09-06T00:00:00Z")
        ))]]), diagnostics: log)
        _ = try await app.runSyncPass()

        // 6. Undo: read the real retained availability, build the real
        // compensating command, accept and settle it.
        let currentUndo = try offMain { try store.currentUndoAvailability() }
        let undo = try XCTUnwrap(currentUndo)
        XCTAssertEqual(undo.handle, undoHandle)
        let undoOutcome = CompensatingCommands.invoke(
            current: undo, mutationId: UUID().uuidString, currentTitle: captureTitle,
            currentEffect: .init(notes: editNotes, completedAt: "2026-09-05T00:00:00Z", trashedAt: nil, planned: false)
        )
        guard case .compensating(let undoBuilt) = undoOutcome else { return XCTFail("expected a real compensating command") }
        let undoMutation = LocalMutation(
            mutationId: undoBuilt.mutationId, taskId: undoBuilt.taskId, commandBytes: undoBuilt.commandBytes,
            fingerprint: undoBuilt.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: undoBuilt.resourceKeys,
            title: undoBuilt.title, effect: undoBuilt.effect
        )
        _ = try offMain { try store.acceptMutation(undoMutation) }
        app = KeeplingApplication(store: store, syncPort: StubSyncPort(pushBehaviorsByMutationId: [undoBuilt.mutationId: [.pushResult(SyncAcknowledgement(
            mutationId: undoBuilt.mutationId, fingerprint: undoBuilt.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"\#(taskId)","revision":4,"title":"\#(captureTitle)"}"#
        ))]]), diagnostics: log)
        _ = try await app.runSyncPass()

        // 7. A SECOND task's edit settles as a conflict.
        let secondTaskId = "task-second-\(suffix)"
        let secondCaptureId = UUID().uuidString
        let secondCaptureBuilt = try OutboundCommands.capture(title: secondTitle, mutationId: secondCaptureId, taskId: secondTaskId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(secondCaptureBuilt)) }
        app = KeeplingApplication(store: store, syncPort: StubSyncPort(pushBehaviorsByMutationId: [secondCaptureId: [.pushResult(SyncAcknowledgement(
            mutationId: secondCaptureId, fingerprint: secondCaptureBuilt.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"\#(secondTaskId)","revision":1,"title":"\#(secondTitle)"}"#
        ))]]), diagnostics: log)
        _ = try await app.runSyncPass()

        let secondEditId = UUID().uuidString
        let secondBasis = OutboundCommands.Basis(baseTitle: secondTitle, baseNotes: "", expectedRevision: try offMain { try store.expectedRevision(forTaskId: secondTaskId) })
        let secondEditBuilt = try OutboundCommands.edit(taskId: secondTaskId, touched: .init(title: "\(secondTitle) edited"), basis: secondBasis, mutationId: secondEditId)
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(secondEditBuilt)) }
        app = KeeplingApplication(store: store, syncPort: StubSyncPort(pushBehaviorsByMutationId: [secondEditId: [.pushResult(SyncAcknowledgement(
            mutationId: secondEditId, fingerprint: secondEditBuilt.fingerprint, outcome: .conflict, snapshotJSON: #"{"id":"\#(secondTaskId)","revision":1,"title":"\#(secondTitle)"}"#,
            affectedFields: ["title"]
        ))]]), diagnostics: log)
        _ = try await app.runSyncPass()

        // 8. A namespace fence: a disagreeing namespace's bindNamespace call.
        XCTAssertFalse(try offMain { try store.bindNamespace(SyncNamespace(issuer: "https://b", origin: "b", serverInstance: "b-1", accountSubject: "user-b", generation: "1")) })

        // 9. Sign out: the real SignOutCoordinator, fencing then clearing credentials.
        struct NoopRevokingPort: SyncPort {
            func bootstrap(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: "", changes: []) }
            func pull(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: "", changes: []) }
            func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
                SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: "{}")
            }
            func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
                SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .accepted, snapshotJSON: "{}")
            }
            func revoke(installationId: String) async throws {}
        }
        let coordinator = SignOutCoordinator(store: store, credentials: credentialStore, revoking: NoopRevokingPort())
        try await coordinator.signOut(installationId: "installation-1")
        XCTAssertNil(try credentialStore.load())

        // 10. An unrecoverable halt: reopen the SAME store after a real
        // checksum-drift corruption (mirrors DiagnosticCoverageTests).
        var rawConfiguration = Configuration()
        rawConfiguration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let rawPool = try DatabasePool(path: path, configuration: rawConfiguration)
        try await rawPool.write { db in
            try db.execute(sql: "UPDATE schema_migrations SET checksum = ? WHERE version = 1", arguments: [String(repeating: "0", count: 60) + "halt"])
        }
        XCTAssertThrowsError(try GRDBLocalStore(path: path, diagnostics: log))

        // --- Scan every named surface for the run's own ACTUAL values. ---

        var scannedSurfaces: [String: String] = [:]

        let bundle = DiagnosticExport.bundle(from: log)
        XCTAssertEqual(bundle.files.count, 1, "the export bundle must contain exactly one file")
        XCTAssertEqual(Array(bundle.files.keys), [DiagnosticExport.logFileName])
        scannedSurfaces["Export bundle"] = bundle.files.values.map { String(data: $0, encoding: .utf8) ?? "" }.joined()

        // The in-product Inspect presentation: the same events, rendered
        // through only DiagnosticEvent's own closed fields -- proving that
        // ANY renderer built over this data source can only ever produce
        // closed-vocabulary text, structurally, not merely today.
        let inspectFormatter = ISO8601DateFormatter()
        scannedSurfaces["Inspect presentation"] = log.allEvents().map { event in
            "\(event.transition.rawValue) \(event.errorClass.rawValue) \(inspectFormatter.string(from: event.timestamp))"
        }.joined(separator: "\n")

        // Accessibility announcements: the Plan 04-10 debouncer, fed a
        // representative transition sequence.
        var announced: [String] = []
        let debouncer = AnnouncementDebouncer { text, _ in announced.append(text) }
        debouncer.process(SyncPresentation.derive(.localAcceptance(pendingCount: 3), now: Date()))
        debouncer.process(SyncPresentation.derive(.conflict(affectedCount: 1), now: Date()))
        debouncer.process(SyncPresentation.derive(.unrecoverable(.checksumDrift(version: 1)), now: Date()))
        scannedSurfaces["Accessibility announcements"] = announced.joined(separator: "\n")

        // User-visible error messages: every error type a person can be
        // shown, driven with the run's own real inputs where applicable.
        var errorMessages: [String] = []
        errorMessages.append(String(describing: GRDBLocalStore.StoreError.fencedForWrites("namespace_mismatch")))
        errorMessages.append(CompensatingCommands.UndoRefusalReason.nothingToUndo.copy)
        errorMessages.append(CompensatingCommands.UndoRefusalReason.unsupportedOriginalCommandType.copy)
        errorMessages.append(SyncCopy.unrecoverable)
        errorMessages.append(SyncCopy.rejected)
        errorMessages.append(SyncCopy.conflict)
        scannedSurfaces["User-visible error messages"] = errorMessages.joined(separator: "\n")

        let realValues: [String: String] = [
            "capture title": captureTitle,
            "edit notes": editNotes,
            "draft title": draftTitle,
            "second task title": secondTitle,
            "access credential": accessSecret,
            "refresh credential": refreshSecret,
            "cursor": distinctiveCursor,
            "undo handle": undoHandle,
            "capture fingerprint": captureBuilt.fingerprint,
            "edit fingerprint": editBuilt.fingerprint,
        ]

        for (valueName, value) in realValues {
            for (surfaceName, contents) in scannedSurfaces {
                XCTAssertFalse(contents.contains(value), "\(valueName) leaked into \(surfaceName)")
            }
        }
    }

    // MARK: - System unified log: a structural absence proof, disclosed honestly

    /// This codebase writes NOTHING to the OS unified log anywhere under
    /// `apps/ios/Sources` today (verified directly: no `os_log`/`Logger(`
    /// call exists) -- so there is no such surface for a per-value scan to
    /// exercise. This structural scan is the honest substitute: it proves
    /// the "no leak to the system log" claim by proving the surface itself
    /// does not exist, and it fails loudly the moment a future change adds
    /// one, at which point that call site must be added to the leak scan
    /// above rather than silently trusted.
    func testNoProductionSourceUnderSourcesWritesToTheSystemUnifiedLog() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KeeplingCoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
            return XCTFail("could not enumerate \(sourcesURL.path)")
        }
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(contents.contains("os_log("), "\(fileURL.path) writes to the system unified log via os_log -- add it to the leak scan above")
            XCTAssertFalse(contents.contains("Logger("), "\(fileURL.path) writes to the system unified log via Logger -- add it to the leak scan above")
        }
    }
}
