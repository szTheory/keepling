import Foundation

/// `.high` is reserved for actionable exceptions (D-42) -- a screen
/// reader/Switch Control user hears those before, and independently of,
/// whatever else it may currently be reading.
public enum AnnouncementPriority: Sendable, Equatable {
    case normal
    case high
}

/// Emits exactly one debounced accessibility announcement per meaningful
/// synchronization-state transition, debounced at THIS projection layer
/// rather than per view (04-10-PLAN.md Task 1, D-42) -- a view calls
/// `process(_:)` with every newly derived `SyncPresentationSummary` and
/// this type decides whether, and what, to announce; no view computes its
/// own debounce window.
///
/// Routine local-acceptance transitions are never announced individually:
/// they accumulate into a bounded count and are flushed as ONE batched
/// summary (`"3 changes saved on this iPhone"`) the next time a
/// non-`.localAcceptance` transition arrives -- never one announcement per
/// acknowledgement, which on a multi-change sync pass would be an
/// announcement storm (T-04-10-06).
public final class AnnouncementDebouncer {
    private static let maximumBatchedCount = 99

    /// The closed set of kinds `.high` priority is reserved for --
    /// everything an actionable-exception accessory slot would show.
    private static let highPriorityKinds: Set<SyncPresentationKind> = [
        .localSaveFailure, .retryableFailure, .rejected, .conflict, .authenticationFence, .unrecoverable,
    ]

    private let announce: (String, AnnouncementPriority) -> Void
    private(set) var lastAnnouncedKind: SyncPresentationKind?
    private(set) var pendingAcceptanceCount = 0

    public init(announce: @escaping (String, AnnouncementPriority) -> Void) {
        self.announce = announce
    }

    /// Feeds one newly derived summary. Returns `true` if this call
    /// emitted an announcement (a test observation aid; the real signal is
    /// the `announce` closure's own invocation).
    @discardableResult
    public func process(_ summary: SyncPresentationSummary) -> Bool {
        if summary.kind == .localAcceptance {
            pendingAcceptanceCount = min(pendingAcceptanceCount + 1, Self.maximumBatchedCount)
            return false
        }

        // Debounced: the SAME kind repeating is not a meaningful
        // transition and produces no second announcement.
        guard summary.kind != lastAnnouncedKind else { return false }

        let didFlush = flushBatchedAcceptancesIfNeeded()
        lastAnnouncedKind = summary.kind

        guard let copy = summary.copy else { return didFlush }
        let priority: AnnouncementPriority = Self.highPriorityKinds.contains(summary.kind) ? .high : .normal
        announce(copy, priority)
        return true
    }

    /// Flushes any batched local-acceptance count into one bounded
    /// announcement (`"N changes saved on this iPhone"`), e.g. when a sync
    /// pass concludes with no further transition to trigger a flush via
    /// `process(_:)`.
    @discardableResult
    public func flushBatchedAcceptancesIfNeeded() -> Bool {
        guard pendingAcceptanceCount > 0 else { return false }
        let count = pendingAcceptanceCount
        pendingAcceptanceCount = 0
        announce(SyncCopy.batchedAcceptanceAnnouncement(count: count), .normal)
        return true
    }
}
