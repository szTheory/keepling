import Foundation

/// The identity of the operation a `DiagnosticEvent` names, closed to two
/// forms: a specific durable mutation (by its own UUID, never by its
/// human-typed title or task content) or "no specific operation" (a
/// namespace-wide fence, an unrecoverable-store halt, or a pull-side
/// authentication failure, none of which are scoped to one mutation).
///
/// Deliberately `UUID`, never `String` -- a mutation's own identity in this
/// codebase is always minted as `UUID().uuidString` (see
/// `WorkspaceFacade.capture`, `OutboundCommands`), so no information is lost
/// by storing the parsed value, and doing so keeps this whole file free of
/// any `String`-typed stored property (D-23's structural guarantee, this
/// plan's own `<verify>` node script).
public enum DiagnosticOperationIdentity: Sendable, Equatable, Hashable {
    case mutation(UUID)
    case none
}

/// The closed set of meaningful transitions a diagnostic event can name
/// (04-15-PLAN.md Task 1 `<behavior>`). `CaseIterable` so
/// `DiagnosticCoverageTests` can derive "every transition this type knows
/// about" from the type itself rather than a hand-written list living only
/// in the test file.
///
/// `.inFlightToSettled` is deliberately the SAME transition for every
/// settlement outcome -- `accepted`, `already_satisfied` (the duplicate-
/// replay no-op), `rejected`, `conflict`, `stale` -- because a settlement is
/// a single transmission-machine event; which outcome it was is the
/// `errorClass` field's job to name, not a proliferation of transitions.
public enum DiagnosticTransition: String, Sendable, Equatable, Hashable, CaseIterable {
    case queuedToInFlight = "queued_to_in_flight"
    case inFlightToSettled = "in_flight_to_settled"
    case inFlightToUncertain = "in_flight_to_uncertain"
    case namespaceFence = "namespace_fence"
    case unrecoverableHalt = "unrecoverable_halt"
    case authenticationRequired = "authentication_required"
}

/// The closed set of error/reason classes a diagnostic event can name --
/// never free text, always one of these named cases (04-15-PLAN.md Task 1
/// `<behavior>`: "an event naming the reason class"). `.none` is the
/// correct value for a transition (like `.queuedToInFlight`) that carries
/// no error/outcome distinction of its own.
public enum DiagnosticErrorClass: String, Sendable, Equatable, Hashable, CaseIterable {
    case none

    // Settlement outcomes (mirrors `SyncAcknowledgement.Outcome`, named
    // here rather than reusing that type directly -- `Diagnostics` must
    // never import `Storage`'s wire-adjacent types, only name outcomes by
    // their own closed vocabulary, per 04-PATTERNS.md's layering).
    case settledAccepted = "settled_accepted"
    case settledAlreadySatisfied = "settled_already_satisfied"
    case settledRejected = "settled_rejected"
    case settledConflict = "settled_conflict"
    case settledStale = "settled_stale"

    // Namespace fence reasons (mirrors the fence reasons this codebase
    // already writes: `NamespaceActivation`'s "namespace_mismatch",
    // `SignOutCoordinator.fenceReason`'s "signed_out").
    case fenceNamespaceMismatch = "fence_namespace_mismatch"
    case fenceSignedOut = "fence_signed_out"
    /// Any fence reason string outside the two named above. Named rather
    /// than silently dropped -- the store's fence reason is a free-form
    /// `String` at its own storage layer (`GRDBLocalStore.setSyncFence`),
    /// so a future third reason must still surface here as SOME closed
    /// case, never as free text.
    case fenceOther = "fence_other"

    // Unrecoverable-store halt reasons (one per `StoreUnrecoverable` case).
    case unrecoverableChecksumDrift = "unrecoverable_checksum_drift"
    case unrecoverableAheadOfLedger = "unrecoverable_ahead_of_ledger"
    case unrecoverableMigrationMidApplyFailure = "unrecoverable_migration_mid_apply_failure"
    case unrecoverableIntegrityCheckFailed = "unrecoverable_integrity_check_failed"

    // Authentication-required (both the pull-side and push-side stop the
    // pass for the identical reason; the transition's operation identity,
    // not this field, distinguishes which).
    case authenticationRequired = "authentication_required"
}

/// One on-device diagnostic event (D-23, 04-15-PLAN.md Task 1). Carries
/// ONLY an operation identity, a state-transition case, an error-class
/// case, and a timestamp -- structurally incapable of holding a task title,
/// note, draft, credential, token, cursor, or fingerprint, because none of
/// its four fields is a free-text `String`. A well-meaning future change
/// cannot add "just a quick title field for context" without changing this
/// type -- and this plan's own `<verify>` node script scans this exact file
/// for any `String`-typed stored property and fails the build if one
/// appears.
public struct DiagnosticEvent: Sendable, Equatable {
    public let operation: DiagnosticOperationIdentity
    public let transition: DiagnosticTransition
    public let errorClass: DiagnosticErrorClass
    public let timestamp: Date

    public init(
        operation: DiagnosticOperationIdentity,
        transition: DiagnosticTransition,
        errorClass: DiagnosticErrorClass,
        timestamp: Date
    ) {
        self.operation = operation
        self.transition = transition
        self.errorClass = errorClass
        self.timestamp = timestamp
    }
}
