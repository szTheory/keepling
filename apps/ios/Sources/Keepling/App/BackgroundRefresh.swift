import BackgroundTasks
import Foundation
import KeeplingCore

/// The `BGAppRefreshTask` identifier this app registers (mirrored in
/// `apps/ios/project.yml`'s `BGTaskSchedulerPermittedIdentifiers`).
public enum BackgroundRefreshIdentifier {
    public static let syncRefresh = "com.szTheory.keepling.sync-refresh"
}

/// The seam over `BGAppRefreshTask` (04-08-PLAN.md Task 3): `BGAppRefreshTask`
/// has no public initializer, so a test cannot construct a real one to
/// inject. This protocol names only what `handle(task:)` actually uses,
/// mirroring this codebase's own established pattern for a system API a
/// test cannot otherwise reach (`KeychainQuerying` in 04-07,
/// `ClientTransport` stubbing in 04-05) -- never a special-cased "if
/// testing" branch in production code.
public protocol BackgroundTaskHandling: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: BackgroundTaskHandling {}

/// Registers and handles the background refresh task. `handle(task:)` is
/// the SAME entry point (`KeeplingApplication.runSyncPass`, via the same
/// `application` instance) `ScenePhaseDriver` calls in the foreground --
/// there is no separate background-only reconciliation path for the two
/// triggers to drift from, which is the structural half of D-22
/// Criterion 3's claim that background execution is an accelerator, never
/// a correctness dependency.
///
/// No push entitlement, no local/scheduled notification, and no
/// user-facing permission-prompting notification framework of any kind is
/// introduced anywhere in this type -- D-44 keeps all of that out of this
/// phase.
@MainActor
public final class BackgroundRefresh {
    private let application: KeeplingApplication

    /// Test seam: records that the handler ran, WITHOUT itself calling
    /// `runSyncPass` a second time -- the handler is exercised directly by
    /// invoking `handle(task:)` with an injected `BackgroundTaskHandling`,
    /// never by waiting for real `BGTaskScheduler` wake scheduling (not
    /// assertable; see `docs/testing/ios-testing.md`).
    public var onHandlerInvoked: (() -> Void)?

    public init(application: KeeplingApplication) {
        self.application = application
    }

    /// Guards against registering the SAME identifier twice in one process
    /// -- `BGTaskScheduler` traps (a hard assertion, not a thrown error) on
    /// a duplicate registration. Production only ever calls `register()`
    /// once (at app launch), but the test suite constructs multiple
    /// `BackgroundRefresh` instances within one process, and each needs the
    /// SAME identifier registered before `handle(task:)`'s own
    /// `scheduleNextRefresh()` call can submit a request without ALSO
    /// trapping (`BGTaskScheduler` traps on submitting an unregistered
    /// identifier too) -- this guard makes `register()` safe to call from
    /// as many call sites as need it.
    nonisolated(unsafe) private static var hasRegistered = false

    /// Registers the handler with the real system scheduler. Called once
    /// at app launch; safe to call more than once (a no-op after the
    /// first call).
    public func register() {
        guard !Self.hasRegistered else { return }
        Self.hasRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefreshIdentifier.syncRefresh, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handle(task: refreshTask)
        }
    }

    /// Submits the next opportunistic wake request. Called after every
    /// successful or failed background invocation so the system continues
    /// to consider scheduling another one -- iOS decides if/when it
    /// actually runs; this call is a request, never a guarantee (D-22
    /// Criterion 3).
    public func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshIdentifier.syncRefresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: SyncPassScheduler.baseRetryBackoff)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The handler entry point, taking the seam protocol rather than the
    /// concrete `BGAppRefreshTask` so a test can inject a fake conforming
    /// value directly -- this IS the technique `docs/testing/ios-testing.md`
    /// documents for driving the background path without real
    /// `BGTaskScheduler` wake scheduling.
    public func handle(task: any BackgroundTaskHandling) {
        onHandlerInvoked?()
        scheduleNextRefresh()

        // `setTaskCompleted` may be called at most once (a documented
        // BGTaskScheduler requirement) -- both the expiration path and the
        // normal-completion path race to call it, so a one-shot guard
        // decides which one wins rather than risking a double call.
        let completionGuard = CompletionGuard()

        let passTask = Task { [application] in
            _ = try? await application.runSyncPass()
        }
        task.expirationHandler = {
            passTask.cancel()
            completionGuard.completeOnce { task.setTaskCompleted(success: false) }
        }
        Task {
            _ = await passTask.result
            completionGuard.completeOnce { task.setTaskCompleted(success: true) }
        }
    }
}

/// A one-shot, thread-safe "run this at most once" latch.
private final class CompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func completeOnce(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        body()
    }
}
