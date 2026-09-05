import Foundation

/// A bounded, on-device ring of `DiagnosticEvent`s (D-23, 04-15-PLAN.md
/// Task 1). Every production emission point (`KeeplingApplication.runSyncPass`,
/// `GRDBLocalStore.bindNamespace`/`init`) writes to `DiagnosticLog.shared`
/// by default; a test injects its own instance so assertions never race
/// against events from another test's store/application pair.
///
/// **The bound: 500 events.** Reasoning (recorded here, not only in the
/// SUMMARY, so the number and its justification travel together): a
/// "bad day" this log exists to reconstruct is a burst of activity across
/// one or a few sync passes -- each pass touches at most
/// `SyncReducer.maximumReadyPushes` (25) mutations, and even a person who
/// captures, edits, and completes dozens of tasks in one sitting before
/// their next successful sync produces at most a few hundred transitions.
/// 500 comfortably covers "everything since the last time this app opened
/// and settled," while a single `DiagnosticEvent` is four small value-type
/// fields (no strings) -- 500 of them is a trivially small, bounded
/// footprint, never a risk of unbounded on-device growth (T-04-15-06).
/// Retrieval over USB (via `DiagnosticExport`) happens well before this
/// bound would roll a bad day's own events out of the window in practice.
public final class DiagnosticLog: @unchecked Sendable {
    /// The explicit bound (see the type's own doc comment for the
    /// reasoning). Oldest events are dropped first once this many are held.
    public static let defaultBound = 500

    /// The process-wide log every production emission point writes to.
    /// `KeeplingApplication`/`GRDBLocalStore` default to this instance so
    /// existing call sites gain diagnostics with no signature break; a test
    /// constructs its OWN `DiagnosticLog(bound:)` and injects it instead so
    /// assertions never observe another test's events.
    public static let shared = DiagnosticLog(bound: defaultBound)

    private let bound: Int
    private let lock = NSLock()
    private var storage: [DiagnosticEvent] = []

    public init(bound: Int = DiagnosticLog.defaultBound) {
        self.bound = bound
    }

    /// Appends one event, dropping the oldest event(s) if this would exceed
    /// the bound. Never throws -- diagnostics recording must never be the
    /// reason a real operation fails.
    public func record(_ event: DiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
        if storage.count > bound {
            storage.removeFirst(storage.count - bound)
        }
    }

    /// Every currently-retained event, oldest first -- the log's own
    /// contents, retrievable over USB and read by the in-product Inspect
    /// presentation (`SyncPresentation`'s `.unrecoverable` Inspect action)
    /// and by `DiagnosticExport`.
    public func allEvents() -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Test-only reset so independent test cases never see a prior test's
    /// events. Also used by a fresh app launch against `DiagnosticLog.shared`
    /// (mirrors the store's own `KEEPLING_UITEST_RESET_STORE` fixture
    /// convention) if a caller needs a clean slate without constructing a
    /// new instance.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
