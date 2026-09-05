import Foundation

/// The exact copy vocabulary this app renders for every synchronization
/// state, inherited **verbatim** from `03-UI-SPEC.md`'s "Exact state
/// language" table with exactly one device-specific substitution -- the
/// Mac's device noun swapped for the iPhone's -- applied everywhere it
/// appears, including the compound `Sync when you're back online` /
/// `Your changes stay on this iPhone` forms (04-UI-SPEC.md "Exact state
/// language", D-43).
///
/// This is the ONE place these strings are declared. `SyncPresentation.swift`
/// reads from here rather than inlining copy, so a future device
/// substitution or wording change is one edit, not a search-and-replace
/// across every derived case. Never paraphrased -- a paraphrase is copy
/// drift across two clients at once, which D-43 rates one-way.
public enum SyncCopy {
    public static let opening = "Opening your tasks…"
    public static let preparing = "Preparing your tasks for offline use…"
    public static let updating = "Updating…"
    public static let offline = "Offline — showing tasks saved on this iPhone"

    /// The "Local acceptance" row. `Saved on this iPhone` is the primary
    /// clause; `Sync when you're back online` is appended only "when
    /// useful" by the caller (mirrors the Mac's own conditional compound).
    public static let localAcceptance = "Saved on this iPhone"
    public static let localAcceptanceSyncHint = "Sync when you’re back online"

    public static let retryableFailure = "Couldn’t reach the server. Your changes stay on this iPhone."
    public static let uncertain = "Checking whether this change was accepted…"
    public static let rejected = "The server didn’t accept this change. Your version is still on this iPhone."

    /// The conflict row's two-sentence compound, concatenated with a
    /// space exactly as the Mac's own inline resolver copy does.
    public static let conflictPrimary = "This task changed somewhere else. Choose what to keep."
    public static let conflictSecondary = "Other tasks can continue."
    public static var conflict: String { "\(conflictPrimary) \(conflictSecondary)" }

    public static let authenticationFence = "Sign in to continue syncing. Changes remain safe on this iPhone."

    public static let localSaveFailure = "Couldn’t save this change on this iPhone. Nothing was added to your task list."

    public static let unrecoverable = "Keepling can’t open the tasks saved on this iPhone. Your data was not replaced or removed."

    // MARK: - Sync & Recovery sheet (04-UI-SPEC.md § Synchronization and Recovery Presentation, § Empty states)

    public static let recoveryTitle = "Sync & Recovery"
    public static let noChangesHeading = "No Changes Need Your Attention"
    public static func lastSuccessfulContact(_ coarseDescription: String) -> String {
        "Last successful contact: \(coarseDescription)"
    }

    // MARK: - Recovery action labels

    public static let actionInspect = "Inspect"
    public static let actionRetry = "Retry"
    public static let actionCheckAgain = "Check Again"
    public static let actionReview = "Review"
    public static let actionReviewConflict = "Review Conflict"
    public static let actionSignIn = "Sign In"
    public static let actionExport = "Export"
    public static let actionRemoveLocalData = "Remove data from this iPhone…"
    public static let actionRetrySave = "Try Again"
    public static let actionRetryOpening = "Retry Opening"
    public static let actionShowRecoveryOptions = "Show Recovery Options"

    // MARK: - Batched announcement (D-42)

    public static func batchedAcceptanceAnnouncement(count: Int) -> String {
        "\(count) change\(count == 1 ? "" : "s") saved on this iPhone"
    }
}
