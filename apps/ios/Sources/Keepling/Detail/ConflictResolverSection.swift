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
                    fieldValue(label: "Your Version", value: conflict.mine[field])
                    fieldValue(label: "Current Version", value: conflict.current[field])
                }
                .padding(.vertical, TokenSemantics.Space.xs)
            }

            Button {
                onUseMine()
            } label: {
                Label("Use Mine", systemImage: "person")
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-use-mine-button")

            Button {
                onUseCurrent()
            } label: {
                Label("Use Current", systemImage: "server.rack")
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-use-current-button")

            Button {
                onKeepEditing()
            } label: {
                Text("Keep Editing")
                    .frame(minHeight: TokenSemantics.Layout.target)
            }
            .accessibilityIdentifier("conflict-keep-editing-button")
        } header: {
            Text("This task changed on the server")
                .font(TokenSemantics.Typography.heading)
        }
    }

    @ViewBuilder
    private func fieldValue(label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: TokenSemantics.Space.xs) {
            Text(label)
                .font(TokenSemantics.Typography.label)
                .foregroundStyle(TokenSemantics.accent)
            Text(value ?? "")
                .font(TokenSemantics.Typography.body)
                .foregroundStyle(TokenSemantics.primaryText)
        }
    }
}
