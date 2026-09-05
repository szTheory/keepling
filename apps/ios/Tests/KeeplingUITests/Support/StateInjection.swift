import XCTest

/// The deterministic state-injection seam (04-14-PLAN.md Task 1). Configures
/// an `XCUIApplication`'s launch environment BEFORE `launch()` so the app
/// lands, without a server and without waiting, in any of the thirteen
/// named presentation states this app can render (`.populated`/`.empty`
/// are the two data shapes of the inherited `.healthy` state; the other
/// eleven are `SyncPresentationKind`'s own named states) plus the
/// zero/one/many/partial item-count shapes.
///
/// This is the construction site 04-13-SUMMARY.md's own inherited Phase-3
/// lesson (O-46/O-47) says was missing on the Mac for `.opening`/
/// `.preparing`: `KeeplingApp.swift`'s `#if DEBUG`-enclosed launch-
/// environment reads are the PRODUCTION seam this test-support type only
/// configures the caller side of -- it never touches app internals
/// directly, mirroring `ScreenInventory.swift`'s established
/// "configure an `XCUIApplication` before launch" convention.
@MainActor
enum StateInjection {
    /// One case per reachable presentation state. `.populated`/`.empty`
    /// are both the inherited `.healthy` `SyncPresentationKind` -- split
    /// here by their DATA shape (has tasks / has none) since that is the
    /// axis 04-UI-SPEC.md's "never substitute empty for loading" truth
    /// actually cares about, not a thirteenth `SyncPresentationKind` case.
    enum State: String, CaseIterable {
        case populated
        case empty
        case opening
        case preparing
        case updating
        case offline
        case localAcceptance
        case localSaveFailure
        case retryable
        case uncertain
        case rejection
        case conflict
        case authentication
        case unrecoverable
    }

    enum ItemShape {
        case zero
        case one
        case many(Int)
        /// A single seeded task with no notes, not completed, not
        /// trashed -- the shape `SyncStateMatrixTests` uses to assert
        /// absent optional fields stay absent and inapplicable actions
        /// (Reopen/Restore) are omitted rather than disabled-but-visible.
        case partial
    }

    /// The wire value `WorkspaceFacade.applyUITestSyncState(_:count:)`
    /// switches on -- `nil` for `.populated`/`.empty`, which carry no
    /// sync-state string at all (an ordinary launch is `.healthy` by
    /// default; nothing needs setting).
    private static func syncStateValue(for state: State) -> String? {
        switch state {
        case .populated, .empty: return nil
        case .opening: return "opening"
        case .preparing: return "preparing"
        case .updating: return "updating_past_grace"
        case .offline: return "offline"
        case .localAcceptance: return "local_acceptance"
        case .localSaveFailure: return "local_save_failure"
        case .retryable: return "retryable_failure"
        case .uncertain: return "uncertain"
        case .rejection: return "rejected"
        case .conflict: return "conflict"
        case .authentication: return "authentication_fence"
        case .unrecoverable: return "unrecoverable"
        }
    }

    /// Configures `app`'s launch environment to reach `state` (and,
    /// optionally, an item-count/partial-data shape) deterministically.
    /// MUST be called before `app.launch()`. `count`, when supplied,
    /// overrides the sync state's own bundled count (proving the "many"
    /// case is genuinely bounded, `KEEPLING_UITEST_SYNC_STATE_COUNT`).
    static func configure(_ app: XCUIApplication, state: State, itemShape: ItemShape? = nil, count: Int? = nil) {
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        if let value = syncStateValue(for: state) {
            app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE"] = value
        }
        if let count {
            app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE_COUNT"] = String(count)
        }
        switch itemShape {
        case .zero, .none:
            break // an unseeded store is already empty -- nothing to configure
        case .one, .partial:
            app.launchEnvironment["KEEPLING_UITEST_SEED_ITEM_COUNT"] = "1"
        case let .many(n):
            app.launchEnvironment["KEEPLING_UITEST_SEED_ITEM_COUNT"] = String(n)
        }
    }

    /// Pre-seeds a durable capture draft (D-35) BEFORE the app's normal
    /// launch path runs, through the real `saveDraft`/`loadDraft` round
    /// trip `CaptureDraftTests` already exercises -- never a synthesized
    /// `DraftPresentation`. Used by the failure-state draft-preservation
    /// truth: a failure state must never cause a durable draft to be lost.
    static func configureDraft(_ app: XCUIApplication, title: String) {
        app.launchEnvironment["KEEPLING_UITEST_SEED_DRAFT"] = title
    }
}
