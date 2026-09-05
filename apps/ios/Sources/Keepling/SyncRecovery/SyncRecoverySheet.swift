import KeeplingCore
import SwiftUI

/// The full-screen `Sync & Recovery` sheet (D-39): deliberate inspection,
/// reachable from the accessory's action, the persistent overflow-menu row
/// on both tabs (present even when everything is quiet -- that is
/// precisely when a person doubts whether anything is working), and by
/// deep link from any per-task exception. Lists ONLY changes that need
/// attention, bounded, each deep-linking to its task -- never mirroring
/// healthy per-task state into a second global inventory (04-UI-SPEC.md
/// Synchronization and Recovery Presentation, point 3/4).
///
/// Renders the exact inherited copy from `SyncCopy.swift` rather than
/// inlining it a second time (Task 1's "one place" centralization
/// principle carries into this view too): `"Sync & Recovery"` (the
/// navigation title), `"No Changes Need Your Attention"` (the
/// no-exceptions heading), and `"Last successful contact"` (the coarse
/// last-contact prefix) -- see `SyncCopy.recoveryTitle`,
/// `SyncCopy.noChangesHeading`, `SyncCopy.lastSuccessfulContact(_:)`.
struct SyncRecoverySheet: View {
    @ObservedObject var facade: WorkspaceFacade
    @Environment(\.dismiss) private var dismiss

    /// Items carrying an active exception. Today the only per-task
    /// exception this codebase models is an active conflict
    /// (`WorkspaceItem.conflict`, 04-09-PLAN.md Task 1) -- per-task
    /// rejected/uncertain modeling is a disclosed later-plan gap recorded
    /// in 04-10-SUMMARY.md; this sheet reads the same derived summary
    /// vocabulary `TaskExceptionRow`/`BottomAccessoryView` read, so it
    /// scales to more exception kinds without a structural change once
    /// that data exists.
    private var exceptionItems: [WorkspaceItem] {
        facade.items.filter { $0.conflict != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exceptionItems.isEmpty {
                    noExceptionsState
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(exceptionItems) { item in
                                // NOTE: no `.accessibilityIdentifier` on
                                // this `NavigationLink` container -- see
                                // `BottomAccessoryView`'s identical note;
                                // a container identifier overrides the
                                // leaf `sync-recovery-row-title-<title>`
                                // identifier `exceptionRow` sets below
                                // rather than coexisting with it.
                                NavigationLink(value: item.taskId) {
                                    exceptionRow(for: item)
                                }
                                .id(item.taskId)
                            }
                        }
                        .listStyle(.plain)
                        .onAppear {
                            if let focusTaskId = facade.syncRecoveryFocusTaskId {
                                proxy.scrollTo(focusTaskId, anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(TokenSemantics.surface)
            .navigationTitle(SyncCopy.recoveryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { taskId in
                TaskDetailView(facade: facade, taskId: taskId)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sync-recovery-close")
                }
            }
        }
        // D-40: a navigation bar carries no persistent synchronization
        // status glyph, in this sheet or anywhere else in the app --
        // nothing is ever added to this toolbar beyond the explicit Close
        // action above.
    }

    private var noExceptionsState: some View {
        VStack(spacing: TokenSemantics.Space.md) {
            Text(SyncCopy.noChangesHeading)
                .font(TokenSemantics.Typography.heading)
                .foregroundStyle(TokenSemantics.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sync-recovery-no-changes-heading")
            // No global-completeness claim of any kind here -- coarse
            // last-contact copy only (04-UI-SPEC.md Synchronization and
            // Recovery Presentation; the forbidden phrase this guards
            // against is asserted absent by this plan's own `<verify>`
            // node check and by SyncPresentationTests).
            Text(SyncCopy.lastSuccessfulContact(facade.syncPresentation.lastSuccessfulContact ?? "just now"))
                .font(TokenSemantics.Typography.body)
                .foregroundStyle(TokenSemantics.mutedText)
                .accessibilityIdentifier("sync-recovery-last-contact")
        }
        .padding(TokenSemantics.Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NOTE: no `.accessibilityIdentifier` on this container -- see
        // `BottomAccessoryView`'s identical note; a container identifier
        // overrides its children's own identifiers rather than coexisting
        // with them.
    }

    private func exceptionRow(for item: WorkspaceItem) -> some View {
        let summary = SyncPresentation.derive(.conflict(affectedCount: 1), now: Date())
        return VStack(alignment: .leading, spacing: TokenSemantics.Space.xs) {
            Text(item.title)
                .font(TokenSemantics.Typography.body)
                .foregroundStyle(TokenSemantics.primaryText)
                .accessibilityIdentifier("sync-recovery-row-title-\(item.title)")
            if let copy = summary.copy {
                Text(copy)
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(TokenSemantics.accent)
                    .lineLimit(2)
            }
        }
    }
}
