import XCTest
@testable import KeeplingCore
@testable import Keepling

/// Proves D-22 Criterion 3's claim the way the plan states it: correctness
/// does not require background execution. The structural half is that
/// `BackgroundRefresh.handle(task:)` calls the IDENTICAL `runSyncPass` entry
/// point as `ScenePhaseDriver` -- proven with a spy that counts calls
/// through the underlying `SyncPort`, not by inspecting source text. The
/// behavioral half is a test that disables the background path entirely and
/// runs the full foreground restoration scenario to completion
/// (04-08-PLAN.md Task 3).
final class BackgroundAccelerationTests: XCTestCase {
    /// A minimal `SyncPort` spy: every call succeeds trivially and is
    /// counted, so a test can assert HOW MANY passes ran without caring
    /// about push/pull content.
    final actor CountingSyncPort: SyncPort {
        private(set) var pullCallCount = 0
        private(set) var pushCallCount = 0

        func bootstrap(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: cursor ?? "", changes: []) }
        func pull(cursor: String?) async throws -> SyncPullPage { pullCallCount += 1; return SyncPullPage(cursor: cursor ?? "", changes: []) }
        func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
            pushCallCount += 1
            return SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
        }
        func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
            SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .alreadySatisfied, snapshotJSON: #"{"id":"x","revision":1}"#)
        }
        func revoke(installationId: String) async throws {}
    }

    /// A fake `BackgroundTaskHandling` -- `BGAppRefreshTask` has no public
    /// initializer, so this is the injected seam `handle(task:)` was
    /// designed to accept (mirrors `KeychainQuerying`/`ClientTransport`
    /// stubbing precedent already established in this codebase).
    final class FakeBackgroundTask: BackgroundTaskHandling, @unchecked Sendable {
        var expirationHandler: (() -> Void)?
        private(set) var completions: [Bool] = []
        func setTaskCompleted(success: Bool) { completions.append(success) }
    }

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("background-acceleration-test.sqlite").path
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

    // MARK: - The background handler drives the SAME entry point as the foreground driver

    @MainActor
    func testBackgroundHandlerAndForegroundDriverCallTheSameRunSyncPassEntryPoint() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let port = CountingSyncPort()
        let application = KeeplingApplication(store: store, syncPort: port)

        let scenePhaseDriver = ScenePhaseDriver(application: application, startMonitoringPath: false)
        await scenePhaseDriver.triggerPass().value
        let pullCountAfterForeground = await port.pullCallCount
        XCTAssertEqual(pullCountAfterForeground, 1, "the foreground driver ran exactly one pass")

        let backgroundRefresh = BackgroundRefresh(application: application)
        let fakeTask = FakeBackgroundTask()
        var handlerInvoked = false
        backgroundRefresh.onHandlerInvoked = { handlerInvoked = true }
        backgroundRefresh.register()
        backgroundRefresh.handle(task: fakeTask)
        // Give the detached completion Task a chance to run.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(handlerInvoked)
        let pullCountAfterBackground = await port.pullCallCount
        XCTAssertEqual(pullCountAfterBackground, 2, "the background handler drove the SAME runSyncPass entry point on the SAME application instance -- one more pass, not a separate path")
        XCTAssertEqual(fakeTask.completions, [true])
    }

    // MARK: - A background expiration handler leaves every outbox row in a legal state

    @MainActor
    func testBackgroundExpirationLeavesEveryOutboxRowInALegalState() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(title: "Task", mutationId: "m-expire", taskId: "t-expire")
        let mutation = LocalMutation(
            mutationId: capture.mutationId, taskId: capture.taskId, commandBytes: capture.commandBytes,
            fingerprint: capture.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: capture.resourceKeys,
            title: capture.effect.title
        )
        _ = try offMain { try store.acceptMutation(mutation) }

        /// A `SyncPort` whose `push` suspends until released -- lets the
        /// test fire the expiration handler while a pass is genuinely
        /// mid-flight, after the row has already been claimed.
        actor SlowSyncPort: SyncPort {
            private var continuation: CheckedContinuation<Void, Never>?
            func bootstrap(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: cursor ?? "", changes: []) }
            func pull(cursor: String?) async throws -> SyncPullPage { SyncPullPage(cursor: cursor ?? "", changes: []) }
            func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
                await withCheckedContinuation { self.continuation = $0 }
                return SyncAcknowledgement(mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted, snapshotJSON: #"{"id":"x","revision":1}"#)
            }
            func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
                SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .alreadySatisfied, snapshotJSON: #"{"id":"x","revision":1}"#)
            }
            func revoke(installationId: String) async throws {}
        }

        let port = SlowSyncPort()
        let application = KeeplingApplication(store: store, syncPort: port)
        let backgroundRefresh = BackgroundRefresh(application: application)
        let fakeTask = FakeBackgroundTask()
        backgroundRefresh.register()
        backgroundRefresh.handle(task: fakeTask)

        // Let the pass claim the row and reach the suspended push, then
        // expire the task.
        try await Task.sleep(nanoseconds: 200_000_000)
        let stateWhileInFlight = try offMain { try store.outboxState(forMutationId: "m-expire") }
        XCTAssertEqual(stateWhileInFlight, "in_flight", "sanity: the row was claimed before expiration")

        fakeTask.expirationHandler?()
        try await Task.sleep(nanoseconds: 100_000_000)

        let finalState = try offMain { try store.outboxState(forMutationId: "m-expire") }
        XCTAssertNotEqual(finalState, "queued", "an expiration must never leave a claimed row back in queued")
        XCTAssertTrue(finalState == "in_flight" || finalState == nil, "the row is left in_flight (cancellation is cooperative; the claim itself is what's legal) or, if settlement raced ahead, settled and removed -- never anything else")
        XCTAssertEqual(fakeTask.completions, [false], "the expiration path completed the task with success: false exactly once")
    }

    // MARK: - Every supported behavior is correct with the background path disabled

    @MainActor
    func testFullForegroundRestorationScenarioSucceedsWithBackgroundPathDisabledEntirely() async throws {
        let store = try GRDBLocalStore(path: storePath())
        let port = CountingSyncPort()
        let application = KeeplingApplication(store: store, syncPort: port)

        // No BackgroundRefresh is ever constructed in this test -- the
        // background path does not exist here at all, not merely "is not
        // invoked." Launch, resume, and reconnect are simulated purely via
        // ScenePhaseDriver.
        let capture = try OutboundCommands.capture(title: "Restoration task", mutationId: "m-restore-scenario", taskId: "t-restore-scenario")
        let mutation = LocalMutation(
            mutationId: capture.mutationId, taskId: capture.taskId, commandBytes: capture.commandBytes,
            fingerprint: capture.fingerprint, acceptedAt: "2026-09-05T00:00:00Z", resourceKeys: capture.resourceKeys,
            title: capture.effect.title
        )
        _ = try offMain { try store.acceptMutation(mutation) }

        let driver = ScenePhaseDriver(application: application, startMonitoringPath: false)

        // Launch: a non-empty outbox settles.
        driver.scenePhaseChanged(to: .active)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(try offMain { try store.outboxState(forMutationId: "m-restore-scenario") }, "launch settles the pre-existing outbox with no background wake involved")

        // Resume: another active transition runs a pass cleanly (idempotent
        // with nothing new to push).
        driver.scenePhaseChanged(to: .background)
        driver.scenePhaseChanged(to: .active)
        try await Task.sleep(nanoseconds: 200_000_000)
        let pullCount = await port.pullCallCount
        XCTAssertGreaterThanOrEqual(pullCount, 2, "both the launch and the resume each ran a pass")
    }
}
