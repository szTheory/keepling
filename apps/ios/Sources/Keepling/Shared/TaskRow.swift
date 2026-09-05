import KeeplingCore
import SwiftUI

/// Focus safety after a row is removed by completion or trashing
/// (04-UI-SPEC.md Accessibility and Platform Contract): focus moves to the
/// next row, then the previous row, then the screen heading, mirroring the
/// Mac contract. Shared by `TodayView`/`InboxView` rather than duplicated,
/// since both lists apply the identical rule.
/// The authoritative empty state for Today/Inbox (04-UI-SPEC.md Empty
/// states) -- never reused for opening/preparing/updating/failed-loading
/// states, which render their own distinct content (Plan 04-14's own
/// matrix).
struct TaskListEmptyState: View {
    let heading: String
    let bodyText: String
    let action: (label: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: TokenSemantics.Space.md) {
            Text(heading)
                .font(TokenSemantics.Typography.heading)
                .foregroundStyle(TokenSemantics.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(bodyText)
                .font(TokenSemantics.Typography.body)
                .foregroundStyle(TokenSemantics.mutedText)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.borderedProminent)
                    .tint(TokenSemantics.accent)
                    .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
            }
        }
        .padding(TokenSemantics.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum RowFocusSafety {
    /// Returns the accessibility-focus target (a row id from `new`, or
    /// `headingId` as the final fallback) after `old` shrank to `new` by
    /// exactly one removed row. Returns `nil` when no row was removed (no
    /// focus change needed).
    static func focusTarget(old: [String], new: [String], headingId: String) -> String? {
        guard old.count > new.count, let removedIndex = old.firstIndex(where: { !new.contains($0) }) else { return nil }
        if removedIndex < new.count { return new[removedIndex] } // the next row shifted into this position
        if removedIndex > 0 { return new[removedIndex - 1] } // the previous row
        return headingId // the list is now empty -- fall back to the screen heading
    }
}

/// One task row on Today or Inbox (D-26, D-49, 04-UI-SPEC.md Navigation, Tab,
/// and Gesture Contract). Native `List` row semantics only -- never a custom
/// grid.
///
/// The locked gesture contract, structurally enforced here (verified again
/// by a source scan in the plan's own `<verify>` block):
/// - Trailing swipe (`allowsFullSwipe: true`) offers **Complete** on an open
///   task and **Reopen** on a completed one. Nothing else is ever bound to a
///   swipe.
/// - **Trash never gets a swipe action of any kind.** It is reachable only
///   through this row's long-press `.contextMenu` and the task detail view.
/// - Every gesture-bound command is mirrored as an `.accessibilityActions`
///   entry with an action-and-object accessible name (`Complete "Call
///   dentist"`), so Switch Control, Voice Control, and Full Keyboard Access
///   reach every command with no gesture-only path (D-27).
struct TaskRow: View {
    let item: WorkspaceItem
    let onComplete: () -> Void
    let onReopen: () -> Void
    let onTrash: () -> Void
    /// Opens the `Sync & Recovery` sheet deep-linked to this task (D-39).
    /// `nil` in call sites that have not yet wired the sheet -- the
    /// exception indicator simply does not render tappable in that case
    /// (defensive default, never a crash).
    var onOpenSyncRecovery: (() -> Void)?
    /// The caller's `@AccessibilityFocusState` binding and this row's own
    /// comparison value, applied directly to the title `Text` below --
    /// NOT to this whole row (T-04-13-06 finding, Rule 1 fix). Applying
    /// `.accessibilityFocused` to a multi-element container that is not
    /// itself merged into one accessibility element (this row is
    /// deliberately NOT merged -- 04-09-PLAN.md Task 2's own finding that
    /// merging collapses the title out of independent VoiceOver/XCUITest
    /// reach) does not reliably attach focus to any single queryable leaf.
    var focusBinding: AccessibilityFocusState<String?>.Binding
    var focusValue: String

    /// This row's own exception summary -- derived from the SAME
    /// authoritative projection every surface reads (D-41). Today the
    /// only per-task exception this codebase models is an active conflict
    /// (`WorkspaceItem.conflict`, 04-09-PLAN.md Task 1); a disclosed gap
    /// this SUMMARY records is that per-task rejected/uncertain modeling
    /// awaits a later plan's data wiring.
    private var exceptionSummary: SyncPresentationSummary? {
        guard item.conflict != nil else { return nil }
        return SyncPresentation.derive(.conflict(affectedCount: 1), now: Date())
    }

    var body: some View {
        HStack(spacing: TokenSemantics.Space.sm) {
            VStack(alignment: .leading, spacing: TokenSemantics.Space.xs) {
                Text(item.title)
                    .font(TokenSemantics.Typography.body)
                    .foregroundStyle(TokenSemantics.primaryText)
                    .strikethrough(item.isCompleted)
                    .lineLimit(2)
                    // 04-14-PLAN.md Task 2 finding: without an explicit
                    // max-width, an EXTREMELY long, contiguous title (the
                    // 512-scalar overflow fixture) measured directly via
                    // `performAccessibilityAudit(.textClipped)` as
                    // genuinely CLIPPED rather than ellipsis-truncated at
                    // the largest accessibility Dynamic Type category --
                    // this row's intrinsic content width was not properly
                    // constrained by the List cell alone at that extreme.
                    // An explicit leading-aligned max-width frame gives
                    // `.lineLimit(2)`'s own truncation a bounded box to
                    // truncate within, confirmed fixed by re-running the
                    // same audit.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("task-row-\(item.title)")
                    .accessibilityFocused(focusBinding, equals: focusValue)
                // A zero-size marker exposing this row's OWN focus value
                // (its opaque `taskId`) -- see `TodayView`'s identical
                // comment on `debug-focused-element`: `hasFocus` cannot
                // observe `@AccessibilityFocusState` in this harness, so
                // `FocusSafetyTests` reads this row's true focus value and
                // compares it directly against `debug-focused-element`'s
                // current value, rather than a human-readable title this
                // app's real focus contract never keys on (D-49: task
                // titles are not guaranteed unique).
                Text(focusValue)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("task-row-focus-value-\(item.title)")
                if let exceptionSummary {
                    TaskExceptionRow(summary: exceptionSummary, taskTitle: item.title, onTap: { onOpenSyncRecovery?() })
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, TokenSemantics.Space.xs)
        .frame(minHeight: TokenSemantics.Layout.taskRowMin)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if item.isCompleted {
                Button {
                    onReopen()
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .tint(TokenSemantics.accent)
                .accessibilityLabel("Reopen \"\(item.title)\"")
                .accessibilityIdentifier("row-reopen-\(item.title)")
            } else {
                Button {
                    onComplete()
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .tint(TokenSemantics.accent)
                .accessibilityLabel("Complete \"\(item.title)\"")
                .accessibilityIdentifier("row-complete-\(item.title)")
            }
        }
        .contextMenu {
            if item.isCompleted {
                Button {
                    onReopen()
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    onComplete()
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                onTrash()
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .accessibilityLabel("Trash \"\(item.title)\"")
            .accessibilityIdentifier("row-trash-\(item.title)")
        }
        .accessibilityActions {
            if item.isCompleted {
                Button("Reopen \"\(item.title)\"") { onReopen() }
            } else {
                Button("Complete \"\(item.title)\"") { onComplete() }
            }
            Button("Trash \"\(item.title)\"") { onTrash() }
        }
    }
}
