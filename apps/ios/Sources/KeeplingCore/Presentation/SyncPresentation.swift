import Foundation

/// A named, labeled recovery action a `SyncPresentationSummary` may offer.
/// Mirrors `apps/desktop/main/application/presentation.ts`'s
/// `RecoveryAction`/`RecoveryActionCode`.
public enum SyncRecoveryActionCode: String, Sendable, Equatable {
    case inspect
    case retry
    case checkAgain = "check_again"
    case review
    case reviewConflict = "review_conflict"
    case signIn = "sign_in"
    case export
    case removeLocalData = "remove_local_data"
    case retrySave = "retry_save"
    case retryOpening = "retry_opening"
    case showRecoveryOptions = "show_recovery_options"
}

public struct SyncRecoveryAction: Sendable, Equatable {
    public let code: SyncRecoveryActionCode
    public let label: String
    public init(code: SyncRecoveryActionCode, label: String) {
        self.code = code
        self.label = label
    }
}

/// One case per inherited synchronization state this app can present
/// (04-10-PLAN.md Task 1). `.healthy` is silent -- no copy, no count, no
/// action -- exactly the state the `tabViewBottomAccessory` renders as
/// absent (D-38).
public enum SyncPresentationKind: String, Sendable, Equatable, CaseIterable {
    case healthy
    case opening
    case preparing
    case updating
    case offline
    case localAcceptance = "local_acceptance"
    case localSaveFailure = "local_save_failure"
    case retryableFailure = "retryable_failure"
    case uncertain
    case rejected
    case conflict
    case authenticationFence = "authentication_fence"
    case unrecoverable
}

/// The closed input union `SyncPresentation.derive` accepts -- one case per
/// inherited state (mirrors `DesktopPresentationInput`). Deriving takes an
/// injected `now: Date` so grace-period absorption is deterministic under
/// test, never `Date()` read internally.
public enum SyncPresentationInput: Sendable, Equatable {
    case healthy(lastSuccessfulContact: String? = nil)
    case opening
    case preparing
    case updating(startedAt: Date)
    case offline(lastSuccessfulContact: String? = nil)
    /// The routine "local acceptance" state -- a change is durably saved
    /// on this iPhone and has not yet been (or does not need to be) sent.
    case localAcceptance(pendingCount: Int? = nil)
    case localSaveFailure
    case retryableFailure(pendingCount: Int? = nil)
    /// A server answer this device cannot yet interpret as accepted or
    /// refused -- its own named state, never healthy and never a
    /// rejection (04-10-PLAN.md Task 1 acceptance criterion).
    case uncertain(pendingCount: Int? = nil)
    case rejected(affectedCount: Int? = nil)
    case conflict(affectedCount: Int? = nil)
    case authenticationFence(pendingCount: Int? = nil)
    /// Maps from `StoreUnrecoverable` -- every case of that closed error
    /// type derives this same presentation state, with the Inspect,
    /// Export, and separately-confirmed-removal actions.
    case unrecoverable(StoreUnrecoverable)
}

/// The one derived value every consuming surface (accessory, per-task
/// inline row, `Sync & Recovery` sheet) reads identically -- none
/// recomputes (D-41). Mirrors `DesktopPresentationSummary`.
public struct SyncPresentationSummary: Sendable, Equatable {
    public let kind: SyncPresentationKind
    /// `nil` for `.healthy` -- rendering that as visible text is exactly
    /// the "healthy status badge" the accessory-space prohibition rejects.
    public let copy: String?
    public let count: Int?
    public let actions: [SyncRecoveryAction]
    public let lastSuccessfulContact: String?

    public init(kind: SyncPresentationKind, copy: String?, count: Int?, actions: [SyncRecoveryAction], lastSuccessfulContact: String?) {
        self.kind = kind
        self.copy = copy
        self.count = count
        self.actions = actions
        self.lastSuccessfulContact = lastSuccessfulContact
    }

    /// `true` for the closed set of actionable-exception kinds this app's
    /// accessory priority order (D-38) places above an undoable action --
    /// every kind except `.healthy`, `.opening`, `.preparing`, and the
    /// silent-when-under-grace `.updating`/`.localAcceptance` routine
    /// states.
    public var isActionableException: Bool {
        switch kind {
        case .localSaveFailure, .retryableFailure, .uncertain, .rejected, .conflict, .authenticationFence, .unrecoverable:
            return true
        case .healthy, .opening, .preparing, .updating, .offline, .localAcceptance:
            return false
        }
    }
}

/// The one authoritative presentation projection (04-10-PLAN.md Task 1,
/// D-41). Every renderer-visible synchronization summary this app shows
/// derives from `derive(_:now:)` -- a pure function over a closed input, an
/// injected clock, and the copy vocabulary in `SyncCopy.swift`. No view may
/// infer synchronization truth from connectivity, a timer, or the absence
/// of an error; every view instead reads this ONE derived summary object.
public enum SyncPresentation {
    /// Presented counts are bounded (mirrors desktop's own
    /// `MAXIMUM_PRESENTED_COUNT`) -- never an unbounded number rendered to
    /// the person.
    public static let maximumPresentedCount = 99

    public static func boundedCount(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(0, min(value, maximumPresentedCount))
    }

    private static func action(_ code: SyncRecoveryActionCode, _ label: String) -> SyncRecoveryAction {
        SyncRecoveryAction(code: code, label: label)
    }

    /// Derives the ONE summary this app's every surface reads. `now` is
    /// injected (never `Date()` read internally) so the grace-period
    /// absorption below is deterministic under test.
    ///
    /// An `.updating` input younger than
    /// `SyncPassScheduler.activeGracePeriod` -- the SAME named constant
    /// Plan 04-08's driver uses, read here rather than redeclared, so the
    /// two clients cannot drift apart on how long "still settling" stays
    /// silent -- derives as `.healthy`; at or past the grace period it
    /// derives as `.updating` with the `Sync & Recovery` action.
    public static func derive(_ input: SyncPresentationInput, now: Date) -> SyncPresentationSummary {
        switch input {
        case let .healthy(lastSuccessfulContact):
            return SyncPresentationSummary(kind: .healthy, copy: nil, count: nil, actions: [], lastSuccessfulContact: lastSuccessfulContact)

        case .opening:
            return SyncPresentationSummary(kind: .opening, copy: SyncCopy.opening, count: nil, actions: [], lastSuccessfulContact: nil)

        case .preparing:
            return SyncPresentationSummary(kind: .preparing, copy: SyncCopy.preparing, count: nil, actions: [], lastSuccessfulContact: nil)

        case let .updating(startedAt):
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed < SyncPassScheduler.activeGracePeriod {
                return SyncPresentationSummary(kind: .healthy, copy: nil, count: nil, actions: [], lastSuccessfulContact: nil)
            }
            return SyncPresentationSummary(
                kind: .updating, copy: SyncCopy.updating, count: nil,
                actions: [action(.inspect, SyncCopy.recoveryTitle)], lastSuccessfulContact: nil
            )

        case let .offline(lastSuccessfulContact):
            return SyncPresentationSummary(kind: .offline, copy: SyncCopy.offline, count: nil, actions: [], lastSuccessfulContact: lastSuccessfulContact)

        case let .localAcceptance(pendingCount):
            return SyncPresentationSummary(kind: .localAcceptance, copy: SyncCopy.localAcceptance, count: boundedCount(pendingCount), actions: [], lastSuccessfulContact: nil)

        case .localSaveFailure:
            return SyncPresentationSummary(
                kind: .localSaveFailure, copy: SyncCopy.localSaveFailure, count: nil,
                actions: [action(.retrySave, SyncCopy.actionRetrySave)], lastSuccessfulContact: nil
            )

        case let .retryableFailure(pendingCount):
            return SyncPresentationSummary(
                kind: .retryableFailure, copy: SyncCopy.retryableFailure, count: boundedCount(pendingCount),
                actions: [action(.retry, SyncCopy.actionRetry)], lastSuccessfulContact: nil
            )

        case let .uncertain(pendingCount):
            return SyncPresentationSummary(
                kind: .uncertain, copy: SyncCopy.uncertain, count: boundedCount(pendingCount),
                actions: [action(.checkAgain, SyncCopy.actionCheckAgain)], lastSuccessfulContact: nil
            )

        case let .rejected(affectedCount):
            return SyncPresentationSummary(
                kind: .rejected, copy: SyncCopy.rejected, count: boundedCount(affectedCount),
                actions: [action(.review, SyncCopy.actionReview)], lastSuccessfulContact: nil
            )

        case let .conflict(affectedCount):
            return SyncPresentationSummary(
                kind: .conflict, copy: SyncCopy.conflict, count: boundedCount(affectedCount),
                actions: [action(.reviewConflict, SyncCopy.actionReviewConflict)], lastSuccessfulContact: nil
            )

        case let .authenticationFence(pendingCount):
            return SyncPresentationSummary(
                kind: .authenticationFence, copy: SyncCopy.authenticationFence, count: boundedCount(pendingCount),
                actions: [action(.signIn, SyncCopy.actionSignIn)], lastSuccessfulContact: nil
            )

        case .unrecoverable:
            return SyncPresentationSummary(
                kind: .unrecoverable, copy: SyncCopy.unrecoverable, count: nil,
                actions: [
                    action(.inspect, SyncCopy.actionInspect),
                    action(.export, SyncCopy.actionExport),
                    action(.removeLocalData, SyncCopy.actionRemoveLocalData),
                ],
                lastSuccessfulContact: nil
            )
        }
    }

    /// Every derived copy string across the full closed input set, for a
    /// test to scan for forbidden vocabulary (backend words, `this Mac`,
    /// `Everything synced`) without hand-enumerating cases at the call
    /// site. Uses one representative, non-nil-triggering input per kind.
    public static func allDerivedCopyStrings(now: Date = Date(timeIntervalSince1970: 0)) -> [String] {
        let representativeInputs: [SyncPresentationInput] = [
            .healthy(lastSuccessfulContact: "8 minutes ago"),
            .opening,
            .preparing,
            .updating(startedAt: now.addingTimeInterval(-SyncPassScheduler.activeGracePeriod - 1)),
            .offline(lastSuccessfulContact: "8 minutes ago"),
            .localAcceptance(pendingCount: 3),
            .localSaveFailure,
            .retryableFailure(pendingCount: 1),
            .uncertain(pendingCount: 1),
            .rejected(affectedCount: 1),
            .conflict(affectedCount: 1),
            .authenticationFence(pendingCount: 1),
            .unrecoverable(.integrityCheckFailed(version: 1, detail: "test")),
        ]
        return representativeInputs.compactMap { derive($0, now: now).copy }
            + [SyncCopy.localAcceptanceSyncHint, SyncCopy.noChangesHeading, SyncCopy.lastSuccessfulContact("8 minutes ago"), SyncCopy.recoveryTitle]
    }
}
