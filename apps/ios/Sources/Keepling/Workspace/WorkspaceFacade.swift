import Combine
import Foundation
import KeeplingCore

/// The iPhone analogue of the desktop's frozen `ClientFacade`
/// (`packages/web-ui`, 03-CONTEXT.md D-45): a presentation-only boundary
/// exposing a snapshot value, a subscription, and named task/navigation
/// operations. No view holds a store handle, a transport, a credential, a
/// cursor, or a fingerprint -- every presentation type below (`WorkspaceItem`,
/// `ConflictPresentation`, `DraftPresentation`) is a plain, `Sendable`,
/// GRDB-free value the facade derives from `KeeplingCore`'s own
/// storage-neutral `ProjectionRow`/`ConflictRecord`/`CaptureDraft` types
/// (04-09-PLAN.md Task 1, `ShellBoundaryTests` enforces this structurally).
///
/// `WorkspaceFacade` talks ONLY to `LocalStorePort` -- it never constructs a
/// `KeeplingApplication` or a `SyncPort` itself. The already-running
/// `ScenePhaseDriver`/`BackgroundRefresh` (04-08-PLAN.md Task 3, wired in
/// `KeeplingApp.swift`) push whatever this facade durably accepts into the
/// outbox; the facade's job stops at "durably accepted on this iPhone"
/// (D-03), exactly like the tracer's `RootView.capture(title:)` did before
/// this plan replaced it.
@MainActor
public final class WorkspaceFacade: ObservableObject {
    private let store: any LocalStorePort

    /// The full workspace snapshot, presentation-shaped. Every view reads
    /// this ONE published value -- never the store directly.
    @Published public private(set) var items: [WorkspaceItem] = []

    /// The ONE derived synchronization summary the accessory, every
    /// per-task inline row, and the `Sync & Recovery` sheet all read
    /// identically (04-10-PLAN.md Task 1, D-41) -- none of those three
    /// surfaces recomputes it. Defaults to silent/healthy; a driver calls
    /// `updateSyncPresentation` as `KeeplingApplication.runSyncPass`
    /// outcomes and transport errors become known. Wiring every one of
    /// those live signals through `ScenePhaseDriver`/`BackgroundRefresh`
    /// end to end is this plan's disclosed remaining gap (see
    /// 04-10-SUMMARY.md) -- the projection, its priority order, and every
    /// consuming view are complete and independently tested against this
    /// published value today.
    @Published public private(set) var syncPresentation: SyncPresentationSummary = SyncPresentation.derive(.healthy(), now: Date())

    /// Whether a named `Undo {Action}` control is currently available
    /// (D-30). `nil` when there is nothing to undo. This plan builds only
    /// the presentation-priority arbitration point the accessory needs
    /// between an available undo and an actionable exception (04-UI-SPEC.md
    /// Navigation, Tab, and Gesture Contract) -- the full semantic-undo
    /// feature (persistent until superseded, compensating server action,
    /// separate from in-field `UndoManager`) is a disclosed later plan's
    /// concern.
    @Published public private(set) var undoAvailability: UndoAvailabilityPresentation?

    public init(store: any LocalStorePort) {
        self.store = store
    }

    /// Feeds a newly observed synchronization state into the one derived
    /// summary every surface reads (04-10-PLAN.md Task 1). `now` is
    /// injected so grace-period absorption stays deterministic under test.
    public func updateSyncPresentation(_ input: SyncPresentationInput, now: Date = Date()) {
        syncPresentation = SyncPresentation.derive(input, now: now)
    }

    public func updateUndoAvailability(_ availability: UndoAvailabilityPresentation?) {
        undoAvailability = availability
    }

    // MARK: - Undo (04-11-PLAN.md Task 2, D-30/D-34)

    /// Invokes undo: reads the store's own current undo availability,
    /// builds the compensating command through `CompensatingCommands`
    /// (04-11-PLAN.md Task 1), and hands it to `accept` -- the SAME
    /// outbound path any other command travels. Single-level: consumed
    /// immediately, so a second tap before the compensation settles
    /// cannot mint a second `undo_task` against an already-spent handle.
    /// Refuses silently at the presentation layer when there is nothing
    /// (currently) to undo -- the control itself is only ever shown when
    /// `undoAvailability` is non-`nil`, so this branch is a defensive
    /// guard, not the primary refusal path (that path is
    /// `CompensatingCommands.invoke` returning `.refused`, which this
    /// method also respects and never silently swallows into "success").
    @discardableResult
    public func invokeUndo() async -> Bool {
        let store = self.store
        let current = await Task.detached(priority: .userInitiated) { try? store.currentUndoAvailability() }.value
        guard let current, let existingItem = item(forTaskId: current.taskId) else {
            updateUndoAvailability(nil)
            return false
        }

        let outcome = CompensatingCommands.invoke(
            current: current,
            mutationId: UUID().uuidString,
            currentTitle: existingItem.title,
            currentEffect: LocalMutation.ProjectionEffect(
                notes: existingItem.notes, completedAt: existingItem.completedAt,
                trashedAt: existingItem.trashedAt, planned: existingItem.planned
            )
        )
        guard case .compensating(let built) = outcome else {
            // A refusal here means the defensive matrix gate tripped
            // (should never happen -- see `CompensatingCommands`'s own
            // doc comment) or the availability vanished between the read
            // above and here. Either way: zero store mutations, and the
            // stale control is cleared rather than left dangling.
            updateUndoAvailability(nil)
            return false
        }

        let mutation = LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
            resourceKeys: built.resourceKeys, title: built.title, effect: built.effect
        )
        _ = await Task.detached(priority: .userInitiated) { try? store.acceptMutation(mutation) }.value
        await Task.detached(priority: .userInitiated) { try? store.clearCurrentUndoAvailability() }.value
        updateUndoAvailability(nil)
        await refresh()
        return true
    }

    // MARK: - Sync & Recovery presentation state (D-39)

    /// Whether the full-screen `Sync & Recovery` sheet is presented.
    /// Public and settable (not `private(set)`) so `RootTabView`'s
    /// `.sheet(isPresented:)` binding can flip it back to `false` on
    /// dismiss (swipe-down or the sheet's own Close button).
    @Published public var isSyncRecoveryPresented: Bool = false

    /// The task the sheet should scroll to when opened via a per-task
    /// exception's deep link -- `nil` when opened from the accessory or
    /// the overflow-menu row (no specific task to focus).
    @Published public private(set) var syncRecoveryFocusTaskId: String?

    /// Opens the `Sync & Recovery` sheet -- from the accessory's
    /// `Sync & Recovery` action, the overflow-menu row on either tab, or a
    /// per-task exception's deep link (D-39).
    public func openSyncRecovery(focusTaskId: String? = nil) {
        syncRecoveryFocusTaskId = focusTaskId
        isSyncRecoveryPresented = true
    }

    // MARK: - Snapshot

    /// Reloads `items` from the store. Runs the store call off the main
    /// actor (`Task.detached`), mirroring the tracer's own
    /// `RootView.reload()` -- `GRDBLocalStore` traps in Debug builds if
    /// entered from the main thread.
    public func refresh() async {
        let store = self.store
        let snapshot = await Task.detached(priority: .userInitiated) {
            (try? store.snapshot()) ?? WorkspaceSnapshot(tasks: [])
        }.value
        var presented: [WorkspaceItem] = []
        for row in snapshot.tasks {
            let conflict = await Task.detached(priority: .userInitiated) {
                try? store.activeConflict(forTaskId: row.taskId)
            }.value ?? nil
            presented.append(WorkspaceItem(row: row, conflict: conflict.map(ConflictPresentation.init)))
        }
        items = presented
    }

    /// Today's items: unfinished, uncompleted tasks planned onto Today.
    /// Trashed and completed tasks never appear on either tab in this
    /// phase (no "recently completed" or Trash-browsing surface exists
    /// yet -- D-49: Trash is reachable only through the context menu/
    /// detail view, never a list; a completed task's mirrored controls
    /// (Reopen, Trash/Restore) remain reachable through the task detail
    /// view, which stays pushed across the transition).
    public var todayItems: [WorkspaceItem] {
        items.filter { $0.planned && !$0.isTrashed && !$0.isCompleted }
    }

    /// Inbox items: unfinished, uncompleted, untrashed, not planned onto
    /// Today.
    public var inboxItems: [WorkspaceItem] {
        items.filter { !$0.planned && !$0.isTrashed && !$0.isCompleted }
    }

    public func item(forTaskId taskId: String) -> WorkspaceItem? {
        items.first { $0.taskId == taskId }
    }

    // MARK: - Capture (D-35)

    @discardableResult
    public func capture(title: String, addToToday: Bool) async throws -> String {
        let mutationId = UUID().uuidString
        let taskId = UUID().uuidString
        let built = try OutboundCommands.capture(title: title, mutationId: mutationId, taskId: taskId)
        try await accept(built, planned: addToToday)
        if addToToday {
            // Capture only produces `planned: false`; a second, independent
            // command expresses "also place on Today" -- the local effect
            // flips optimistically, exactly as `OutboundCommands.planForToday`
            // documents (the server resolves the actual account day).
            let planMutationId = UUID().uuidString
            let basis = try await revisionBasis(forTaskId: taskId, title: title, notes: "")
            let planned = try OutboundCommands.planForToday(true, taskId: taskId, basis: basis, mutationId: planMutationId)
            try await accept(planned, planned: true)
        }
        await refresh()
        return taskId
    }

    // MARK: - Edit / clarify

    public func saveChanges(taskId: String, title: String, notes: String) async throws {
        guard let item = item(forTaskId: taskId) else { return }
        let basis = try await revisionBasis(forTaskId: taskId, title: item.title, notes: item.notes)
        var touched = OutboundCommands.TouchedFields()
        if title != item.title { touched = OutboundCommands.TouchedFields(title: title, notes: touched.notes) }
        if notes != item.notes { touched = OutboundCommands.TouchedFields(title: touched.title, notes: notes) }
        guard touched.title != nil || touched.notes != nil else { return }
        let built = try OutboundCommands.edit(taskId: taskId, touched: touched, basis: basis, mutationId: UUID().uuidString)
        try await accept(built, planned: item.planned)
        await refresh()
    }

    /// `Save & Move Out of Inbox` -- the Inbox clarify action. Produces the
    /// identical wire shape as `saveChanges`, with the `clarify_task` type
    /// discriminator (the server moves the task out of Inbox as its own
    /// side effect; this client expresses no local Inbox-membership field).
    public func clarify(taskId: String, title: String, notes: String) async throws {
        guard let item = item(forTaskId: taskId) else { return }
        let basis = try await revisionBasis(forTaskId: taskId, title: item.title, notes: item.notes)
        let touched = OutboundCommands.TouchedFields(
            title: title == item.title ? nil : title,
            notes: notes == item.notes ? nil : notes
        )
        let built = try OutboundCommands.edit(
            taskId: taskId, touched: touched.isTouchedFieldsEmpty ? OutboundCommands.TouchedFields(title: title, notes: notes) : touched,
            basis: basis, mutationId: UUID().uuidString, asClarify: true
        )
        try await accept(built, planned: item.planned)
        await refresh()
    }

    /// Move an EXISTING task on or off Today.
    ///
    /// A task's destination has to be changeable after capture, not only at
    /// capture time -- opening a task you filed yesterday and saying "do this
    /// today" is half the daily loop, and `TaskDetailView` had no control for
    /// it (found by `DeviceCoreLoopTests
    /// .testPlanForTodayAndFindItOnTheTodayTabOnPhysicalDevice`, which failed
    /// on the phone against a detail view that offered no such affordance).
    ///
    /// The command layer already expressed both directions --
    /// `OutboundCommands.planForToday` emits `plan_for_today` or
    /// `unplan_task` -- so nothing new goes on the wire here; only the
    /// affordance was missing. The local effect flips optimistically and the
    /// server resolves the actual account day, exactly as `capture(title:
    /// addToToday:)` already does for the capture-time case.
    public func planForToday(taskId: String, planned: Bool) async throws {
        guard let item = item(forTaskId: taskId) else { return }
        // A no-op toggle must not burn a revision or enqueue a command.
        guard item.planned != planned else { return }
        let basis = try await revisionBasis(forTaskId: taskId, title: item.title, notes: item.notes)
        let built = try OutboundCommands.planForToday(
            planned, taskId: taskId, basis: basis, mutationId: UUID().uuidString
        )
        try await accept(built, planned: planned)
        await refresh()
    }

    // MARK: - Lifecycle

    public func complete(taskId: String) async throws { try await lifecycle(.complete, taskId: taskId) }
    public func reopen(taskId: String) async throws { try await lifecycle(.reopen, taskId: taskId) }
    public func trash(taskId: String) async throws { try await lifecycle(.trash, taskId: taskId) }
    public func restore(taskId: String) async throws { try await lifecycle(.restore, taskId: taskId) }

    private func lifecycle(_ transition: OutboundCommands.Lifecycle, taskId: String) async throws {
        guard let item = item(forTaskId: taskId) else { return }
        let basis = try await revisionBasis(forTaskId: taskId, title: item.title, notes: item.notes)
        let acceptedAt = ISO8601DateFormatter().string(from: Date())
        let built = try OutboundCommands.lifecycle(transition, taskId: taskId, basis: basis, mutationId: UUID().uuidString, acceptedAt: acceptedAt)
        let planned = transition == .trash ? item.planned : (built.effect.planned)
        try await accept(built, planned: planned)
        await refresh()
    }

    // MARK: - Conflict resolution

    /// `Use Mine` / `Use Current` (04-UI-SPEC.md Conflict resolver): sends a
    /// fresh `edit` command carrying the chosen field values against
    /// CURRENT server truth (a freshly read basis, revision included) --
    /// never a local merge. `Keep Editing` calls neither of these and
    /// mutates nothing.
    public func resolveConflict(taskId: String, useMine: Bool) async throws {
        guard let item = item(forTaskId: taskId), let conflict = item.conflict else { return }
        let chosen = useMine ? conflict.mine : conflict.current
        let store = self.store
        let freshBasis = try await Task.detached(priority: .userInitiated) {
            OutboundCommands.Basis(
                baseTitle: item.title,
                baseNotes: item.notes,
                baseCompletedAt: item.completedAt,
                baseTrashedAt: item.trashedAt,
                basePlanned: item.planned,
                expectedRevision: (try? store.expectedRevision(forTaskId: taskId)) ?? 1
            )
        }.value
        var touched = OutboundCommands.TouchedFields()
        if let title = chosen["title"] { touched = OutboundCommands.TouchedFields(title: title, notes: touched.notes) }
        if let notes = chosen["notes"] { touched = OutboundCommands.TouchedFields(title: touched.title, notes: notes) }
        if touched.title != nil || touched.notes != nil {
            let built = try OutboundCommands.edit(taskId: taskId, touched: touched, basis: freshBasis, mutationId: UUID().uuidString)
            try await accept(built, planned: item.planned)
        }
        try await Task.detached(priority: .userInitiated) {
            try? store.clearConflict(conflictId: conflict.conflictId)
        }.value
        await refresh()
    }

    // MARK: - Durable capture draft (D-35)

    public func loadDraft() async -> DraftPresentation {
        let store = self.store
        let draft = await Task.detached(priority: .userInitiated) {
            (try? store.loadDraft()) ?? CaptureDraft(title: "", addToToday: false)
        }.value
        return DraftPresentation(title: draft.title, addToToday: draft.addToToday)
    }

    public func saveDraft(title: String, addToToday: Bool) async {
        let store = self.store
        await Task.detached(priority: .userInitiated) {
            try? store.saveDraft(CaptureDraft(title: title, addToToday: addToToday))
        }.value
    }

    public func discardDraft() async {
        let store = self.store
        await Task.detached(priority: .userInitiated) {
            try? store.clearDraft()
        }.value
    }

    // MARK: - Private helpers

    private func revisionBasis(forTaskId taskId: String, title: String, notes: String) async throws -> OutboundCommands.Basis {
        guard let item = item(forTaskId: taskId) else {
            let store = self.store
            let revision = try await Task.detached(priority: .userInitiated) { try store.expectedRevision(forTaskId: taskId) }.value
            return OutboundCommands.Basis(baseTitle: title, baseNotes: notes, expectedRevision: revision)
        }
        let store = self.store
        let revision = try await Task.detached(priority: .userInitiated) { try store.expectedRevision(forTaskId: taskId) }.value
        return OutboundCommands.Basis(
            baseTitle: title,
            baseNotes: notes,
            baseCompletedAt: item.completedAt,
            baseTrashedAt: item.trashedAt,
            basePlanned: item.planned,
            expectedRevision: revision
        )
    }

    private func accept(_ built: OutboundCommands.Built, planned: Bool) async throws {
        let mutation = LocalMutation(
            mutationId: built.mutationId,
            taskId: built.taskId,
            commandBytes: built.commandBytes,
            fingerprint: built.fingerprint,
            acceptedAt: ISO8601DateFormatter().string(from: Date()),
            resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: LocalMutation.ProjectionEffect(
                notes: built.effect.notes,
                completedAt: built.effect.completedAt,
                trashedAt: built.effect.trashedAt,
                planned: planned
            )
        )
        let store = self.store
        try await Task.detached(priority: .userInitiated) {
            _ = try store.acceptMutation(mutation)
        }.value
    }
}

public extension WorkspaceFacade {
    /// UI-test-only fixture hook (mirrors `KEEPLING_UITEST_RESET_STORE`'s
    /// launch-environment pattern): maps a fixed string to a
    /// `SyncPresentationInput` so `SyncRecoveryTests` can launch the app
    /// deterministically into any state in the closed set without a real
    /// `KeeplingApplication`/`SyncPort` round trip. `KeeplingApp.swift`
    /// reads `KEEPLING_UITEST_SYNC_STATE` and calls this once at launch.
    /// `count`, when supplied (04-14-PLAN.md Task 1: `KEEPLING_UITEST_SYNC_STATE_COUNT`),
    /// overrides the hardcoded `1` this hook previously always passed for
    /// every count-carrying state -- letting `SyncStateMatrixTests` prove
    /// the "many" case is genuinely BOUNDED (`SyncPresentation
    /// .boundedCount`'s existing 99 ceiling, 04-10-PLAN.md Task 1) rather
    /// than only ever exercising the trivial `count == 1` case.
    func applyUITestSyncState(_ raw: String, now: Date = Date(), count: Int? = nil) {
        let c = count ?? 1
        let input: SyncPresentationInput
        switch raw {
        case "healthy": input = .healthy()
        case "opening": input = .opening
        case "preparing": input = .preparing
        case "updating_past_grace": input = .updating(startedAt: now.addingTimeInterval(-(SyncPassScheduler.activeGracePeriod + 1)))
        case "offline": input = .offline()
        case "local_acceptance": input = .localAcceptance(pendingCount: c)
        case "local_save_failure": input = .localSaveFailure
        case "retryable_failure": input = .retryableFailure(pendingCount: c)
        case "uncertain": input = .uncertain(pendingCount: c)
        case "rejected": input = .rejected(affectedCount: c)
        case "conflict": input = .conflict(affectedCount: c)
        case "authentication_fence": input = .authenticationFence(pendingCount: c)
        case "unrecoverable": input = .unrecoverable(.integrityCheckFailed(version: 1, detail: "uitest"))
        default: return
        }
        updateSyncPresentation(input, now: now)
    }
}

private extension OutboundCommands.TouchedFields {
    var isTouchedFieldsEmpty: Bool { title == nil && notes == nil }
}

// MARK: - Presentation types (no store, transport, credential, cursor, or fingerprint)

public struct WorkspaceItem: Sendable, Equatable, Identifiable {
    public var id: String { taskId }
    public let taskId: String
    public let title: String
    public let notes: String
    public let syncStatus: String
    public let completedAt: String?
    public let trashedAt: String?
    public let planned: Bool
    public let conflict: ConflictPresentation?

    public var isCompleted: Bool { completedAt != nil }
    public var isTrashed: Bool { trashedAt != nil }

    init(row: ProjectionRow, conflict: ConflictPresentation?) {
        taskId = row.taskId
        title = row.title
        notes = row.notes
        syncStatus = row.syncStatus
        completedAt = row.completedAt
        trashedAt = row.trashedAt
        planned = row.planned
        self.conflict = conflict
    }
}

public struct ConflictPresentation: Sendable, Equatable {
    public let conflictId: String
    public let affectedFields: [String]
    public let mine: [String: String]
    public let current: [String: String]

    init(_ record: ConflictRecord) {
        conflictId = record.conflictId
        affectedFields = record.affectedFields
        mine = record.mine
        current = record.current
    }
}

public struct DraftPresentation: Sendable, Equatable {
    public let title: String
    public let addToToday: Bool
    public var isEmpty: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
