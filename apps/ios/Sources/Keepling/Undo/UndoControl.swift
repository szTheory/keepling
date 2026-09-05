import KeeplingCore
import SwiftUI

/// The named, persistent `Undo {Action}` control (D-30, D-33,
/// 04-UI-SPEC.md Undo Contract): ONE view definition shared by the bottom
/// accessory's undo row and the named row in both tabs' nav-bar overflow
/// menus, so the exact label reads identically in every place it appears.
///
/// Contains no `Timer`, no delayed dispatch, and no auto-dismiss path of
/// any kind (asserted independently by this plan's own source-scan
/// `<verify>` check): it renders exactly what `WorkspaceFacade
/// .undoAvailability` currently holds and disappears only when that
/// becomes `nil` -- superseded by the next undoable semantic action, or an
/// explicit dismissal -- never on its own clock. The label is always the
/// exact server-authored `Undo {Action}` string (e.g. `Undo Complete`,
/// `Undo Trash`), never a bare `Undo`.
struct UndoControl: View {
    let availability: UndoAvailabilityPresentation
    let onUndo: () -> Void

    /// Trash is the one action in this phase whose accessory copy carries
    /// an explicit confirmation sentence ahead of the undo label (04-11-
    /// PLAN.md Task 2's own required exact copy: `Task moved to Trash.
    /// Undo Trash`) -- Complete/Reopen and the others are self-evident
    /// from the row itself changing, so they keep the bare `Undo {Action}`
    /// label the UI-SPEC's Copywriting Contract table already specifies.
    /// The BUTTON's own label always stays the bare action label (never
    /// this compound sentence), matching `04-10-PLAN.md`'s already-shipped
    /// `sync-accessory-undo` button contract unchanged.
    private var accessoryText: String {
        availability.actionLabel == "Undo Trash" ? "Task moved to Trash. \(availability.actionLabel)" : availability.actionLabel
    }

    /// The accessory's row rendering: label + a same-labeled tappable
    /// button, matching `BottomAccessoryView`'s existing exception-row
    /// layout so the accessory reads consistently regardless of what
    /// currently occupies the slot.
    var accessoryRow: some View {
        HStack(spacing: TokenSemantics.Space.sm) {
            Text(accessoryText)
                .font(TokenSemantics.Typography.label)
                .foregroundStyle(TokenSemantics.accent)
                .accessibilityIdentifier("sync-accessory-undo-label")
            Spacer(minLength: 0)
            Button(availability.actionLabel, action: onUndo)
                .font(TokenSemantics.Typography.label)
                .foregroundStyle(TokenSemantics.accent)
                .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
                .accessibilityLabel(availability.actionLabel)
                .accessibilityIdentifier("sync-accessory-undo")
        }
        .padding(.horizontal, TokenSemantics.Space.md)
    }

    /// The overflow-menu row rendering: a named `Button` reading exactly
    /// `Undo {Action}`, present on BOTH tabs whenever `WorkspaceFacade
    /// .undoAvailability` is non-`nil` -- reachable here even while an
    /// actionable synchronization exception occupies the accessory slot
    /// (04-UI-SPEC.md: "the undo remains reachable in the overflow menu").
    var menuRow: some View {
        Button(availability.actionLabel, systemImage: "arrow.uturn.backward", action: onUndo)
            .accessibilityIdentifier("overflow-undo")
    }

    var body: some View { accessoryRow }
}
