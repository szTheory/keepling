import Foundation

/// The single seam through which an App Intent (Capture, Complete --
/// reachable from Shortcuts, Siri, the Action Button, and Spotlight
/// actions) reaches this process's ONE `GRDBLocalStore` handle (D-37,
/// 04-12-PLAN.md).
///
/// No member here accepts a store path or URL: the storage location is
/// resolved internally, at the SAME path `KeeplingApp.init()` resolves
/// (`storePath()` below is the single source of truth both call sites
/// share), so an intent has no way to open a second connection even by
/// mistake -- a second handle would reintroduce exactly the multi-writer
/// hazard D-07/D-36 exist to avoid. Whichever entry point runs first in
/// this process (the app's own `KeeplingApp.init()`, or an intent's
/// `perform()` when the OS launches the process to satisfy a
/// Shortcuts/Siri/Action-Button/Spotlight invocation while the app is not
/// already running) opens the store and caches it; every subsequent call
/// -- from either entry point -- returns the identical instance.
public enum IntentStoreAccess {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedStore: GRDBLocalStore?

    /// Returns this process's one store handle, opening it on first access
    /// and returning the SAME instance on every call after.
    public static func sharedStore() throws -> GRDBLocalStore {
        lock.lock()
        defer { lock.unlock() }
        if let cachedStore { return cachedStore }
        let opened = try GRDBLocalStore(path: storePath())
        cachedStore = opened
        return opened
    }

    /// The on-disk location of this process's one store, identical to what
    /// `KeeplingApp.init()` resolves -- kept here as the single source of
    /// truth so the app and every intent agree on exactly one file.
    public static func storePath() -> String {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keepling", isDirectory: true)
        return directory.appendingPathComponent("keepling.sqlite").path
    }

    /// Runs a throwing store call off the main actor -- `GRDBLocalStore`
    /// traps (via `preconditionFailure`) in Debug builds if entered from
    /// the main thread (D-04 G5/D-34). Mirrors `WorkspaceFacade`'s own
    /// `Task.detached` pattern (04-09-PLAN.md) so an intent's perform path
    /// obeys the identical main-thread discipline every other store caller
    /// already does.
    public static func performOffMain<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    /// Test-only: substitutes an already-open, isolated store for this
    /// process's cached handle, so `AppIntentsTests` can drive real
    /// `AppIntent.perform()` calls against a disposable database instead of
    /// the real on-device one -- mirrors `GRDBLocalStore.__test_setFence`'s
    /// established test-only-method convention (never a path-taking
    /// initializer: a caller must already hold a `GRDBLocalStore` it opened
    /// itself). Passing `nil` clears the cache so the next `sharedStore()`
    /// call opens fresh again.
    public static func __test_overrideSharedStore(_ store: GRDBLocalStore?) {
        lock.lock()
        defer { lock.unlock() }
        cachedStore = store
    }
}
