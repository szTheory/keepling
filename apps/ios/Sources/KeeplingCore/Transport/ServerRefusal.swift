import Foundation

/// A 401's distinct tagged state (T-04-05-06). Never an acknowledgement
/// outcome -- a 401 must not be collapsed into a per-mutation rejection,
/// because every authentication problem carries `retryable: false`, and a
/// rule keyed on that field alone would quietly discard a whole outbox as
/// "the server didn't accept these changes" when the truth is "sign in
/// again".
public struct SyncAuthenticationRequired: Error, Sendable, Equatable {
    public let code: String
    public init(code: String) {
        self.code = code
    }
}

/// O-38: hearing what the server actually says when it does not accept a
/// command -- the closed classification table, reproduced from
/// `apps/desktop/main/adapters/server-refusal.ts`'s `classifyServerRefusal`.
///
/// Turning every refusal into a settled outcome is the failure this phase
/// keeps finding: it converts a loud failure into a silent one. A 401 must
/// NOT become a per-mutation rejection -- every authentication problem
/// carries `retryable: false`, so a rule keyed on that field alone would
/// quietly discard a whole outbox as "the server didn't accept these
/// changes" when the truth is "sign in again" (T-04-05-06). Anything not
/// named here -- 403, 5xx, a malformed body, a status/code combination
/// outside this table -- keeps throwing and keeps landing on the
/// retryable-failure row (T-04-05-07).
public enum ServerRefusal: Sendable, Equatable {
    case conflict(affectedFields: [String], conflictId: String?, currentTitle: String?, latestRevision: Int64?)
    case authenticationRequired(code: String)
    case rejected(code: String)

    /// 409 codes the server emits for a genuine divergence, all of which it
    /// persists. Quoted VERBATIM from
    /// `apps/desktop/main/adapters/server-refusal.ts`'s `CONFLICT_CODES`
    /// (see 04-05-SUMMARY.md for the side-by-side citation).
    public static let conflictCodes: Set<String> = [
        "task_assignment_conflict",
        "task_edit_conflict",
        "task_lifecycle_conflict",
        "task_trash_conflict",
    ]

    /// Refusals about THIS command's content that will never succeed on
    /// retry, so the mutation is terminal and the person must be told
    /// rather than have it retried forever. Quoted verbatim from the same
    /// desktop source's `REJECTION_CODES`.
    public static let rejectionCodes: Set<String> = [
        "invalid_command",
        "task_not_found",
    ]

    /// Classifies one non-OK answer from the server. `nil` means "this is
    /// not a decision about the mutation" -- the caller MUST keep throwing
    /// (`SyncPortRefused`), never settle it.
    public static func classify(status: Int, problem: Components.Schemas.Problem?) -> ServerRefusal? {
        guard let problem, !problem.code.isEmpty else { return nil }
        let code = problem.code

        if status == 401 { return .authenticationRequired(code: code) }
        if status == 409, conflictCodes.contains(code) { return readConflict(problem.conflict) }
        // Every 422 from the command surface is a semantic refusal of this
        // exact body (title_required, notes_too_long, no_fields_touched,
        // base_values_mismatch, invalid_task_details, invalid_timezone...).
        // None of them can succeed on a retry of the same immutable bytes.
        if status == 422 { return .rejected(code: code) }
        if (status == 400 || status == 404), rejectionCodes.contains(code) { return .rejected(code: code) }
        return nil
    }

    /// Reads the server's own conflict extension
    /// (`PersistedConflict.fields[].{base, current, field, mine}`). Only
    /// the SERVER may say what diverged and what it currently holds;
    /// nothing here derives or defaults a value the server did not send --
    /// a conflict with no `conflict` extension body still classifies as a
    /// conflict (the status/code said so), just with every server-derived
    /// field absent rather than defaulted to something invented locally.
    private static func readConflict(_ conflict: Components.Schemas.PersistedConflict?) -> ServerRefusal {
        guard let conflict else {
            return .conflict(affectedFields: [], conflictId: nil, currentTitle: nil, latestRevision: nil)
        }
        let affectedFields = conflict.fields.map(\.field.rawValue)
        let currentTitle = conflict.fields.first { $0.field == .title }?.current
        return .conflict(
            affectedFields: affectedFields,
            conflictId: conflict.id,
            currentTitle: currentTitle,
            latestRevision: conflict.latest_revision
        )
    }
}
