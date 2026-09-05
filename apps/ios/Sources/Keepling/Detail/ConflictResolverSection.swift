import SwiftUI

/// The native detail-view conflict resolver (04-UI-SPEC.md "Conflict
/// resolver" -- same meaning as Mac's inline resolver, re-expressed for
/// touch). Rendered ONLY when a conflict exists; absent entirely otherwise,
/// with no residual `Use Mine`/`Use Current` control (T-04-09 threat
/// register, E7 "Empty / no data"). Resolution sends a fresh semantic
/// command against current server truth with a fresh mutation identity --
/// the client never merges locally (T-04-09-06). `Keep Editing` returns
/// without mutating anything.
struct ConflictResolverSection: View {
    let conflict: ConflictPresentation
    let onUseMine: () -> Void
    let onUseCurrent: () -> Void
    let onKeepEditing: () -> Void

    var body: some View {
        Section {
            ForEach(conflict.affectedFields, id: \.self) { field in
                VStack(alignment: .leading, spacing: TokenSemantics.Space.sm) {
                    Text(field.capitalized)
                        .font(TokenSemantics.Typography.label)
                        .foregroundStyle(TokenSemantics.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    fieldValue(label: "Your Version", value: conflict.mine[field])
                    fieldValue(label: "Current Version", value: conflict.current[field])
                }
                .padding(.vertical, TokenSemantics.Space.xs)
            }

            Button {
                onUseMine()
            } label: {
                Label("Use Mine", systemImage: "person")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-use-mine-button")

            Button {
                onUseCurrent()
            } label: {
                Label("Use Current", systemImage: "server.rack")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-use-current-button")

            Button {
                onKeepEditing()
            } label: {
                Text("Keep Editing")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-keep-editing-button")
        } header: {
            // See `TaskDetailView`'s identical "Notes" header comment: an
            // explicit color (not the system default a bare `Text` can
            // still inherit inside a Section header context) keeps this
            // WCAG 2.2 AA-proven, and `.fixedSize` keeps it from clipping
            // at the largest accessibility Dynamic Type sizes (T-04-13
            // finding, Rule 1 fix).
            Text("This task changed on the server")
                .font(TokenSemantics.Typography.heading)
                .foregroundStyle(TokenSemantics.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func fieldValue(label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: TokenSemantics.Space.xs) {
            Text(label)
                .font(TokenSemantics.Typography.label)
                .foregroundStyle(TokenSemantics.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(value ?? "")
                .font(TokenSemantics.Typography.body)
                .foregroundStyle(TokenSemantics.primaryText)
                // 04-14-PLAN.md Task 2 finding: `.fixedSize(vertical: true)`
                // with NO `.lineLimit` forces this `Text` to its FULL
                // intrinsic height regardless of content length --
                // measured directly at the 512-scalar maximum title
                // length, this rendered a single value block ~2300pt
                // tall (over two and a half screen-heights), making the
                // entire section unnavigable within any reasonable
                // scroll budget. A title diff does not need the Notes
                // section's own `Show Full Value` disclosure (titles are
                // capped at 512 scalars, an order of magnitude shorter
                // than notes' 50000) -- a bounded `.lineLimit` gives
                // `Text`'s own truncation (an ellipsis, never a hard
                // clip) something to truncate WITHIN, restoring this
                // section to a normal, scrollable size.
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
