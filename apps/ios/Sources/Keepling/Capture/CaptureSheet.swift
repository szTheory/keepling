import SwiftUI

/// The capture sheet (D-35, 04-UI-SPEC.md Capture Contract), completed from
/// the tracer's durable-commit-only version (04-01-PLAN.md): title-first,
/// `.presentationDetents`, the destination and `Add to Today` controls,
/// `.keyboardShortcut` bindings for the hardware-keyboard case, and the
/// durable draft. The draft is durable in `WorkspaceFacade`'s backing
/// store, not in this view's `@State` -- backgrounding a SwiftUI sheet can
/// tear down its view state, and the guarantee is that a nonempty draft is
/// never silently discarded (T-04-09-04). Saved continuously (every
/// keystroke) rather than only on dismissal, so a hard interruption (a
/// crash, a jetsam kill) loses at most the last unsaved keystroke, never
/// the whole draft.
struct CaptureSheet: View {
    @ObservedObject var facade: WorkspaceFacade
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var addToToday: Bool = false
    @State private var hasLoadedDraft = false
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var isShowingDiscardDraftDialog = false
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                // D-32: platform text undo is confined to editing INSIDE
                // this field -- SwiftUI's `TextField` wires the system
                // `UndoManager` to its own editing session automatically,
                // and nothing else in this sheet touches that
                // `UndoManager` or produces a semantic command from it.
                Section {
                    TextField("What do you want to keep?", text: $title, axis: .vertical)
                        .font(TokenSemantics.Typography.body)
                        .focused($isTitleFocused)
                        .accessibilityLabel("What do you want to keep?")
                        .accessibilityIdentifier("capture-title-field")
                }
                Section {
                    Text("Destination: Inbox")
                        .font(TokenSemantics.Typography.body)
                        .foregroundStyle(TokenSemantics.mutedText)
                    Toggle("Add to Today", isOn: $addToToday)
                        .font(TokenSemantics.Typography.body)
                        .accessibilityIdentifier("add-to-today-toggle")
                }
                if !trimmedTitle.isEmpty {
                    Section {
                        Button("Discard Draft", role: .destructive) {
                            isShowingDiscardDraftDialog = true
                        }
                        .frame(minHeight: TokenSemantics.Layout.target)
                        .accessibilityIdentifier("discard-draft-button")
                    }
                }
                if let captureError {
                    Section {
                        Text(captureError)
                            .foregroundStyle(TokenSemantics.destructive)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Task") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("add-task-button")
                    .disabled(trimmedTitle.isEmpty || isCapturing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("capture-cancel-button")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard !hasLoadedDraft else { return }
            let draft = await facade.loadDraft()
            title = draft.title
            addToToday = draft.addToToday
            hasLoadedDraft = true
            isTitleFocused = true
        }
        .onChange(of: title) { _, newValue in
            Task { await facade.saveDraft(title: newValue, addToToday: addToToday) }
        }
        .onChange(of: addToToday) { _, newValue in
            Task { await facade.saveDraft(title: title, addToToday: newValue) }
        }
        .confirmationDialog(
            "Discard Quick Entry Draft?",
            isPresented: $isShowingDiscardDraftDialog,
            titleVisibility: .visible
        ) {
            Button("Discard Draft", role: .destructive) {
                Task {
                    await facade.discardDraft()
                    dismiss()
                }
            }
            .accessibilityIdentifier("confirm-discard-draft-button")
            // Default focus `Keep Draft` (04-UI-SPEC.md Destructive and
            // consequential actions).
            Button("Keep Draft", role: .cancel) {}
                .accessibilityIdentifier("keep-draft-button")
        } message: {
            Text("This draft is saved on this iPhone but hasn't been added as a task.")
        }
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        isCapturing = true
        captureError = nil
        Task {
            do {
                // The sheet shows nothing claiming durability until this
                // call returns -- `capture` resolves only after
                // `GRDBLocalStore.acceptMutation`'s transaction commits
                // (D-03), never before.
                _ = try await facade.capture(title: trimmedTitle, addToToday: addToToday)
                await facade.discardDraft() // the draft became a real task -- silently cleared, no dialog
                isCapturing = false
                dismiss()
            } catch {
                isCapturing = false
                captureError = "Couldn't save this on your iPhone. Try again."
            }
        }
    }
}
