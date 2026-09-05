import XCTest
import GRDB
@testable import KeeplingCore

/// The D-09 adversarial fixture: proves that even a hand-restored store
/// (a device-backup replay vector) cannot double-apply an accepted
/// command, and that a restore under a DIFFERENT account namespace is
/// fenced rather than silently pushing a previous account's outbox
/// (04-06-PLAN.md Task 2). Also carries the D-07 structural guard that
/// keeps the App Group storage hazard (RESEARCH.md Pitfall 4) out of
/// `apps/ios/Sources` permanently.
final class BackupReplayTests: XCTestCase {
    /// Builds a fresh path AND creates its parent directory -- `DurableUnit`
    /// (unlike `GRDBLocalStore.init`) never creates directories itself, so
    /// a `copy`/`move` destination whose parent does not yet exist must be
    /// prepared by the caller, exactly as this helper does.
    private func newStorePath(name: String = UUID().uuidString) -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name).sqlite").path
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

    private func accept(_ store: GRDBLocalStore, mutationId: String, taskId: String, title: String) throws -> LocalMutation {
        let commandBytes = #"{"mutation_id":"\#(mutationId)","task_id":"\#(taskId)","title":"\#(title)","type":"capture_task","version":1}"#
        let mutation = LocalMutation(
            mutationId: mutationId, taskId: taskId, commandBytes: commandBytes, fingerprint: sha256Hex(commandBytes),
            acceptedAt: "2026-01-01T00:00:00Z", resourceKeys: ["task:\(taskId)"], title: title
        )
        _ = try offMain { try store.acceptMutation(mutation) }
        return mutation
    }

    private func namespace(accountSubject: String) -> SyncNamespace {
        SyncNamespace(
            issuer: "https://keepling.example/oauth", origin: "server", serverInstance: "server-1",
            accountSubject: accountSubject, generation: "1"
        )
    }

    /// Drives every ready mutation on `store` through a stubbed
    /// already-satisfied settlement (the real server's honest answer for a
    /// mutation identity it already recorded before this restore): mark
    /// in_flight, then acknowledge with `.alreadySatisfied` and the same
    /// snapshot the ORIGINAL settlement produced. Returns the mutation ids
    /// actually settled.
    @discardableResult
    private func drivePushPass(_ store: GRDBLocalStore, snapshotJSON: (String) -> String) throws -> [String] {
        var settled: [String] = []
        for mutation in try offMain({ try store.readyMutations() }) {
            try offMain { try store.setOutboxState(mutationId: mutation.mutationId, to: "in_flight") }
            let ack = SyncAcknowledgement(
                mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .alreadySatisfied,
                snapshotJSON: snapshotJSON(mutation.taskId)
            )
            _ = try offMain { try store.acknowledge(ack) }
            settled.append(mutation.mutationId)
        }
        return settled
    }

    // MARK: - D-09: a store restored to the SAME namespace replays as a no-op

    func testRestoredStoreReplaysEveryOutboxRowAsAlreadySatisfiedWithNoDuplicateOrCanonicalMutation() throws {
        let livePath = newStorePath(name: "live")
        var live: GRDBLocalStore? = try GRDBLocalStore(path: livePath)
        let ns = namespace(accountSubject: "user-a")
        try offMain { try live!.bindNamespace(ns) }

        let m1 = try accept(live!, mutationId: "m-backup-1", taskId: "t-backup-1", title: "Water plants")
        let m2 = try accept(live!, mutationId: "m-backup-2", taskId: "t-backup-2", title: "Feed cat")

        // Checkpoint the WAL into the main file before snapshotting -- a
        // deterministic, self-contained "backup" fixture, sidestepping the
        // WAL-mode byte-drift-on-open characteristic 04-02-SUMMARY.md
        // already disclosed rather than re-discovering it here.
        try live!.__test_checkpointTruncate()
        let backupPath = newStorePath(name: "backup")
        try live!.durableUnit.copy(to: backupPath)

        // Continue using the live store past the snapshot point: both
        // mutations settle normally, so the LIVE store's outbox becomes
        // empty -- exactly the "restored over a store whose outbox is
        // empty" precondition the plan's own <behavior> names.
        let originalCanonicalTitle1 = #"{"id":"t-backup-1","revision":1,"title":"Water plants"}"#
        let originalCanonicalTitle2 = #"{"id":"t-backup-2","revision":1,"title":"Feed cat"}"#
        _ = try offMain {
            try live!.acknowledge(SyncAcknowledgement(
                mutationId: m1.mutationId, fingerprint: m1.fingerprint, outcome: .accepted, snapshotJSON: originalCanonicalTitle1
            ))
        }
        _ = try offMain {
            try live!.acknowledge(SyncAcknowledgement(
                mutationId: m2.mutationId, fingerprint: m2.fingerprint, outcome: .accepted, snapshotJSON: originalCanonicalTitle2
            ))
        }
        XCTAssertEqual(try offMain { try live!.readyMutations() }.count, 0)
        let liveTaskCountBeforeRestore = try live!.countRows(in: "visible_projection")

        // Release the live store's DatabasePool before overwriting its
        // file -- models the device process being relaunched after the
        // backup restore, not a live handle fighting the restore.
        live = nil

        // The restore: the current store's file is entirely replaced by
        // the OLD backup snapshot (which still carries both mutations
        // pending in its outbox, because it was taken BEFORE settlement).
        try DurableUnit(databasePath: livePath).restoreContents(of: DurableUnit(databasePath: backupPath))

        let restored = try GRDBLocalStore(path: livePath)
        // The restored file still carries the namespace bound before the
        // snapshot was taken -- binding the SAME namespace again succeeds.
        XCTAssertTrue(try offMain { try restored.bindNamespace(ns) })

        let readyBeforeReplay = try offMain { try restored.readyMutations() }
        XCTAssertEqual(Set(readyBeforeReplay.map(\.mutationId)), ["m-backup-1", "m-backup-2"])

        let settled = try drivePushPass(restored) { taskId in
            taskId == "t-backup-1" ? originalCanonicalTitle1 : originalCanonicalTitle2
        }
        XCTAssertEqual(Set(settled), ["m-backup-1", "m-backup-2"])

        XCTAssertEqual(try offMain { try restored.readyMutations() }.count, 0)
        XCTAssertEqual(try restored.journalOutcome(forMutationId: "m-backup-1"), "already_satisfied")
        XCTAssertEqual(try restored.journalOutcome(forMutationId: "m-backup-2"), "already_satisfied")

        // No duplicate task: the restored file already had both
        // visible_projection rows from the original acceptMutation calls
        // captured in the snapshot -- replay only updates them, it never
        // inserts a second row for the same task_id.
        XCTAssertEqual(try restored.countRows(in: "visible_projection"), liveTaskCountBeforeRestore)
        let finalSnapshot = try offMain { try restored.snapshot() }
        XCTAssertEqual(finalSnapshot.tasks.first(where: { $0.taskId == "t-backup-1" })?.title, "Water plants")
        XCTAssertEqual(finalSnapshot.tasks.first(where: { $0.taskId == "t-backup-2" })?.title, "Feed cat")
        XCTAssertEqual(finalSnapshot.tasks.first(where: { $0.taskId == "t-backup-1" })?.syncStatus, "synced")
        XCTAssertEqual(finalSnapshot.tasks.first(where: { $0.taskId == "t-backup-2" })?.syncStatus, "synced")

        // canonical_shadow converges to exactly one row per task -- no
        // duplicate/divergent canonical mutation was created by the replay.
        XCTAssertEqual(try restored.countRows(in: "canonical_shadow"), 2)
    }

    // MARK: - D-09/D-03: the same backup restored under a DIFFERENT account namespace is fenced

    func testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush() throws {
        let livePath = newStorePath(name: "live-fence")
        let live = try GRDBLocalStore(path: livePath)
        let originalNamespace = namespace(accountSubject: "user-a")
        try offMain { try live.bindNamespace(originalNamespace) }
        _ = try accept(live, mutationId: "m-fence-1", taskId: "t-fence-1", title: "Buy milk")
        try live.__test_checkpointTruncate()

        let backupPath = newStorePath(name: "backup-fence")
        try live.durableUnit.copy(to: backupPath)

        // Restore the SAME backup into a fresh location representing "a
        // different device/account now signing in" -- the account binding
        // a fresh sign-in performs disagrees with what this file was
        // bound to.
        let restoredPath = newStorePath(name: "restored-different-account")
        try DurableUnit(databasePath: backupPath).copy(to: restoredPath)
        let restored = try GRDBLocalStore(path: restoredPath)

        let differentNamespace = namespace(accountSubject: "user-b")
        let bindResult = try offMain { try restored.bindNamespace(differentNamespace) }
        XCTAssertFalse(bindResult, "binding a different account namespace over a restored store must refuse, not silently rebind")

        // Every restored outbox row is fenced: the very first write this
        // replay attempts (marking a row in_flight before it can be pushed)
        // refuses, and the fence reason is recorded.
        let readyRows = try offMain { try restored.readyMutations() }
        XCTAssertEqual(readyRows.map(\.mutationId), ["m-fence-1"])
        for mutation in readyRows {
            XCTAssertThrowsError(
                try offMain { try restored.setOutboxState(mutationId: mutation.mutationId, to: "in_flight") }
            ) { error in
                XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
            }
        }
        // The fence reason is durably recorded, not just returned in the
        // moment -- a relaunch (a fresh GRDBLocalStore at the same path)
        // still refuses the same way.
        let reopened = try GRDBLocalStore(path: restoredPath)
        XCTAssertThrowsError(
            try offMain { try reopened.setOutboxState(mutationId: "m-fence-1", to: "in_flight") }
        ) { error in
            XCTAssertEqual(error as? GRDBLocalStore.StoreError, .fencedForWrites("namespace_mismatch"))
        }
    }

    // MARK: - D-07 structural guard: the App Group container API never re-enters apps/ios/Sources

    func testAppGroupContainerAPINeverAppearsUnderSources() throws {
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StorageTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else {
            return XCTFail("could not enumerate \(sourcesRoot.path)")
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("forSecurityApplicationGroupIdentifier"),
                "\(url.lastPathComponent) reaches for an App Group container -- D-07 rejects this outright (RESEARCH.md Pitfall 4)"
            )
        }
    }
}
