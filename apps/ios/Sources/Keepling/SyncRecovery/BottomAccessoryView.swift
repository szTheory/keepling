import KeeplingCore
import SwiftUI

/// The conditional `tabViewBottomAccessory` content (D-29, D-38, D-40).
///
/// A dumb consumer of `SyncPresentationSummary`/`UndoAvailabilityPresentation`
/// -- priority ordering lives ENTIRELY in `SyncPresentation.swift`
/// (`SyncPresentationSummary.isActionableException`); this view renders
/// exactly what it is handed and re-derives no priority order of its own
/// (independently verified by this plan's own source-scan `<verify>`
/// check).
///
/// Healthy rendering follows the `AccessoryHostability` capability the
/// Plan 04-04 measurement produced: where absence is achievable
/// (`.conditionalModifier` on this pinned SDK), `RootTabView` omits the
/// `.tabViewBottomAccessory` call site entirely and this view is never
/// instantiated for a healthy state at all. Where it is NOT achievable
/// (measured differently on a future SDK), `RootTabView` still attaches
/// the modifier and this view renders the disclosed fallback below --
/// never a repurposed healthy status badge occupying the reserved space
/// (T-04-10-07).
struct BottomAccessoryView: View {
    let summary: SyncPresentationSummary
    let undoAvailability: UndoAvailabilityPresentation?
    /// The Plan 04-04 measurement this view's healthy-case rendering
    /// decision reads. `RootTabView` uses the SAME value to decide
    /// whether to attach the `.tabViewBottomAccessory` call site at all;
    /// this view uses it to pick between literal absence (omitted by the
    /// caller, so this branch is unreachable today on the measured
    /// `.absenceAchievable` SDK) and the disclosed empty fallback.
    let hostability: AccessoryHostability
    let onAction: (SyncRecoveryActionCode) -> Void
    let onUndo: () -> Void

    /// Whether this render has anything to show -- `RootTabView` reads
    /// this (not `summary.kind == .healthy` directly) to decide whether to
    /// omit the accessory call site entirely.
    static func hasContent(summary: SyncPresentationSummary, undoAvailability: UndoAvailabilityPresentation?) -> Bool {
        summary.isActionableException || undoAvailability != nil
            || summary.kind == .updating || summary.kind == .offline || summary.kind == .localAcceptance
    }

    /// 04-14-PLAN.md Task 1: `.offline` and `.localAcceptance` are two more
    /// of this plan's own twelve-state matrix that previously had NO
    /// construction site at all -- `SyncCopy.offline`/`SyncCopy
    /// .localAcceptance` existed and were fully unit-tested at the
    /// `SyncPresentation.derive` layer (04-10-PLAN.md Task 1), but nothing
    /// under `Sources/Keepling` ever read `summary.copy` for either kind.
    /// Both are routine, non-actionable states (`isActionableException` is
    /// `false` for both, by design -- D-38 "healthy is silent" extends to
    /// "routine is quiet, not silent": muted styling, no recovery action),
    /// so they render through this SAME `row(text:...)` helper `.updating`
    /// already used, with the identical muted color.
    var body: some View {
        Group {
            if summary.isActionableException {
                row(text: summary.copy, textColor: TokenSemantics.primaryText, actions: summary.actions)
            } else if let undoAvailability {
                undoRow(undoAvailability)
            } else if summary.kind == .updating || summary.kind == .offline || summary.kind == .localAcceptance {
                row(text: summary.copy, textColor: TokenSemantics.mutedText, actions: summary.actions)
            } else {
                healthyFallback
            }
        }
        .frame(minHeight: TokenSemantics.Layout.target)
    }

    /// The healthy-case rendering, read from `hostability` (D-40's own
    /// prohibition against a repurposed healthy status badge, T-04-10-07):
    /// on the measured `.absenceAchievable` SDK this branch is normally
    /// unreached because `RootTabView` omits the call site entirely; on a
    /// future `.absenceNotAchievable` measurement this is what actually
    /// renders -- no text, no glyph, no count, hidden from accessibility
    /// either way.
    @ViewBuilder
    private var healthyFallback: some View {
        switch hostability {
        case .absenceAchievable, .absenceNotAchievable:
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .accessibilityIdentifier("sync-accessory-empty")
        }
    }

    // NOTE: no `.accessibilityIdentifier` is applied to any CONTAINER here
    // (Group/HStack) -- only to the leaf text/button elements below.
    // Setting an identifier on a container that wraps elements which
    // already carry their own identifiers overrides those children's
    // identifiers with the container's, collapsing every leaf to the SAME
    // identifier (observed directly via `XCUIApplication.debugDescription`
    // while developing this view) -- a real SwiftUI/XCUITest interaction,
    // not a hypothetical, so this constraint is enforced structurally by
    // omission rather than left to be rediscovered.
    @ViewBuilder
    private func row(text: String?, textColor: Color, actions: [SyncRecoveryAction]) -> some View {
        HStack(spacing: TokenSemantics.Space.sm) {
            if let text {
                Text(text)
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .accessibilityIdentifier("sync-accessory-text")
            }
            // 04-14-PLAN.md Task 1: `summary.count` was already derived and
            // unit-tested at `SyncPresentation.derive`'s `boundedCount`
            // ceiling (04-10-PLAN.md Task 1, max 99) but never actually
            // RENDERED anywhere -- so "many" affected items could never
            // visibly prove the bounded-count truth this plan's own state
            // matrix asserts. A `nil`/`0` count renders nothing (no bare
            // "(0)"); any positive count renders the ALREADY-bounded
            // value verbatim, never re-clamped or reformatted here.
            if let count = summary.count, count > 0 {
                Text("(\(count))")
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(textColor)
                    .accessibilityIdentifier("sync-accessory-count")
            }
            Spacer(minLength: 0)
            ForEach(actions, id: \.code) { recoveryAction in
                // A `.frame(minWidth:minHeight:)` on a Button's label
                // visually resizes it but does NOT expand the button's
                // actual TAPPABLE hit region to match -- measured directly
                // via `performAccessibilityAudit(for: .hitRegion)` while
                // building this plan (T-04-13 finding, Rule 1 fix).
                // `.contentShape(Rectangle())` makes the whole frame the
                // real hit-testing area.
                Button(recoveryAction.label) { onAction(recoveryAction.code) }
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(TokenSemantics.accent)
                    .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("sync-accessory-action-\(recoveryAction.code.rawValue)")
            }
        }
        .padding(.horizontal, TokenSemantics.Space.md)
    }

    // 04-11-PLAN.md Task 2: the row layout itself lives in `UndoControl`
    // (`Sources/Keepling/Undo/UndoControl.swift`) -- ONE definition shared
    // with the overflow-menu row, so the exact label and identifiers match
    // in both places this control appears.
    @ViewBuilder
    private func undoRow(_ undo: UndoAvailabilityPresentation) -> some View {
        UndoControl(availability: undo, onUndo: onUndo).accessoryRow
    }
}
