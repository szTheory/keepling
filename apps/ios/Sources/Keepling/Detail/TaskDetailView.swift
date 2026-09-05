import SwiftUI

/// The task detail and editor (04-UI-SPEC.md § Capture Contract / §
/// Destructive and consequential actions), pushed from a `TodayView`/
/// `InboxView` row (D-25). Every gesture-bound command has a matching named
/// control here (D-27): Complete/Reopen, Trash/Restore, Save Changes/Save &
/// Move Out of Inbox, Cancel Editing. Titles and notes render as untrusted
/// plain text in the Body role -- `Text(_ content: String)` and
/// `TextField(_:text:)` bound to a `String` variable never interpret
/// markup, satisfying T-04-09-01 without any extra sanitization step.
struct TaskDetailView: View {
    @ObservedObject var facade: WorkspaceFacade
    let taskId: String

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var hasLoadedFields = false
    @State private var isShowingDiscardDialog = false
    @State private var isShowingFullNotes = false

    /// Long-notes threshold for the accessible `Show Full Value` disclosure
    /// (04-UI-SPEC.md "Long text" -- nothing shrinks below the declared
    /// type sizes to fit; a disclosure is used instead).
    private static let longNotesThreshold = 400

    private var item: WorkspaceItem? { facade.item(forTaskId: taskId) }

    private var isDirty: Bool {
        guard let item else { return false }
        return title != item.title || notes != item.notes
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTitleValid: Bool { !trimmedTitle.isEmpty }

    var body: some View {
        Group {
            if let item {
                detailForm(for: item)
            } else {
                ProgressView()
            }
        }
        .task {
            guard !hasLoadedFields, let item else { return }
            title = item.title
            notes = item.notes
            hasLoadedFields = true
        }
    }

    @ViewBuilder
    private func detailForm(for item: WorkspaceItem) -> some View {
        Form {
            // D-32: platform text undo is confined to editing INSIDE this
            // field (SwiftUI's `TextField` wires the system `UndoManager`
            // to its own editing session automatically -- no additional
            // code needed to enable it, and none of this view's other
            // controls ever touch that `UndoManager` or produce a semantic
            // command from it). `UndoPersistenceTests
            // .testAPlatformTextUndoInAFieldProducesNoSemanticCommand`
            // proves a text-field undo gesture never mutates the store.
            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .font(TokenSemantics.Typography.body)
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("detail-title-field")
            }

            Section {
                if notes.unicodeScalars.count > Self.longNotesThreshold && !isShowingFullNotes {
                    Text(String(notes.prefix(Self.longNotesThreshold)) + "…")
                        .font(TokenSemantics.Typography.body)
                    Button("Show Full Value") { isShowingFullNotes = true }
                        .frame(minHeight: TokenSemantics.Layout.target)
                        .accessibilityIdentifier("show-full-notes-button")
                } else {
                    // Absent optional fields stay absent rather than being
                    // synthesized (04-UI-SPEC.md E3 "Empty / no data"): the
                    // field is simply empty text, its label ("Notes",
                    // above) retained.
                    TextField("Notes", text: $notes, axis: .vertical)
                        .font(TokenSemantics.Typography.body)
                        .accessibilityLabel("Notes")
                        .accessibilityIdentifier("detail-notes-field")
                }
            } header: {
                // The string-literal `Section("Notes")` initializer
                // renders in the system's default secondary section-header
                // color, which -- measured directly via
                // `performAccessibilityAudit(for: .contrast)` while
                // building this plan -- is only ~3.29:1 against this
                // Form's section background, below WCAG 2.2 AA's 4.5:1
                // minimum for its footnote-weight text (T-04-13 finding,
                // Rule 1 fix). An explicit `Text` with a token color
                // (already proven AA elsewhere in this app) replaces it.
                Text("Notes")
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(TokenSemantics.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let conflict = item.conflict {
                ConflictResolverSection(
                    conflict: conflict,
                    onUseMine: { Task { try? await facade.resolveConflict(taskId: taskId, useMine: true) } },
                    onUseCurrent: { Task { try? await facade.resolveConflict(taskId: taskId, useMine: false) } },
                    onKeepEditing: {}
                )
            }

            Section {
                if item.isCompleted {
                    Button {
                        Task { try? await facade.reopen(taskId: taskId) }
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: TokenSemantics.Layout.target)
                    }
                    .accessibilityLabel("Reopen \"\(item.title)\"")
                    .accessibilityIdentifier("detail-reopen-button")
                } else {
                    Button {
                        Task { try? await facade.complete(taskId: taskId) }
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: TokenSemantics.Layout.target)
                    }
                    .accessibilityLabel("Complete \"\(item.title)\"")
                    .accessibilityIdentifier("detail-complete-button")
                }

                if item.isTrashed {
                    Button {
                        Task { try? await facade.restore(taskId: taskId) }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.up")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: TokenSemantics.Layout.target)
                    }
                    .accessibilityLabel("Restore \"\(item.title)\"")
                    .accessibilityIdentifier("detail-restore-button")
                } else {
                    // `role: .destructive` alone renders in the SYSTEM
                    // default destructive red, which -- measured directly
                    // via `performAccessibilityAudit(for: .contrast)`
                    // while building this plan -- is only ~3.57:1 against
                    // this Form's background, below WCAG 2.2 AA's 4.5:1
                    // minimum for normal-weight text (T-04-13 finding,
                    // Rule 1 fix). An explicit `.foregroundStyle` with the
                    // token `destructive` color (already proven AA
                    // elsewhere in this app) overrides it; the role itself
                    // is kept for the semantic destructive-action trait.
                    Button(role: .destructive) {
                        Task { try? await facade.trash(taskId: taskId) }
                    } label: {
                        Label("Trash", systemImage: "trash")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: TokenSemantics.Layout.target)
                    }
                    .foregroundStyle(TokenSemantics.destructive)
                    .accessibilityLabel("Trash \"\(item.title)\"")
                    .accessibilityIdentifier("detail-trash-button")
                }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // Same T-04-13 contrast/dynamicType fix as `CaptureSheet`'s
                // Add Task button: an explicit font plus a token-driven
                // disabled foreground color, rather than relying on the
                // system's automatic dimming/font resolution for a
                // `.disabled()` toolbar button.
                Button(item.planned ? "Save Changes" : "Save & Move Out of Inbox") {
                    Task { await save(item: item) }
                }
                .font(TokenSemantics.Typography.body)
                // See `CaptureSheet`'s identical `add-task-button` comment:
                // `.allowsHitTesting` (not `.disabled`) avoids the
                // automatic `Text`-level opacity dim that compounds with
                // an already-AA-proven `.foregroundStyle` and fails
                // contrast (T-04-13 finding, Rule 1 fix). `save(item:)`'s
                // own `guard isTitleValid` keeps this safe regardless.
                .allowsHitTesting(isTitleValid)
                .foregroundStyle(isTitleValid ? TokenSemantics.accent : TokenSemantics.mutedText)
                .accessibilityIdentifier(item.planned ? "save-changes-button" : "save-and-move-button")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel Editing") {
                    if isDirty {
                        isShowingDiscardDialog = true
                    } else {
                        dismiss()
                    }
                }
                .font(TokenSemantics.Typography.body)
                .accessibilityIdentifier("cancel-editing-button")
            }
        }
        .confirmationDialog(
            "Discard Unsaved Changes?",
            isPresented: $isShowingDiscardDialog,
            titleVisibility: .visible
        ) {
            Button("Save Changes") {
                Task { await save(item: item); dismiss() }
            }
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            // Default focus `Keep Editing` (04-UI-SPEC.md Destructive and
            // consequential actions): `.cancel` is the platform-idiomatic
            // way to mark the safe default action in a confirmation
            // dialog, rendered in its own separated, emphasized slot.
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("keep-editing-button")
        } message: {
            Text("These edits haven't been saved.")
        }
    }

    private func save(item: WorkspaceItem) async {
        guard isTitleValid else { return }
        if item.planned {
            try? await facade.saveChanges(taskId: taskId, title: title, notes: notes)
        } else {
            try? await facade.clarify(taskId: taskId, title: title, notes: notes)
        }
    }
}
