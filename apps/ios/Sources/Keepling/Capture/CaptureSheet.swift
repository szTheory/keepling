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
                    // The `TextField(_:text:)` initializer's placeholder
                    // renders in the SYSTEM default placeholder gray, which
                    // -- measured directly via `performAccessibilityAudit
                    // (for: .contrast)` while building this plan -- is
                    // roughly 1.7:1 against this app's Surface background,
                    // far below WCAG 2.2 AA's 4.5:1 minimum for normal text
                    // (T-04-13 finding, Rule 1 fix). The `prompt:`
                    // initializer accepts a styled `Text`, letting this
                    // placeholder use the same `mutedText` token proven AA
                    // elsewhere in this file instead.
                    TextField(text: $title, prompt: Text("What do you want to keep?").foregroundStyle(TokenSemantics.mutedText), axis: .vertical) {
                        Text("What do you want to keep?")
                    }
                    .font(TokenSemantics.Typography.body)
                    .focused($isTitleFocused)
                    .accessibilityLabel("What do you want to keep?")
                    .accessibilityIdentifier("capture-title-field")
                }
                Section {
                    Text("Destination: Inbox")
                        .font(TokenSemantics.Typography.body)
                        .foregroundStyle(TokenSemantics.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    // A native `Toggle` reserves a fixed-width switch
                    // control alongside its label, which -- measured
                    // directly via `performAccessibilityAudit(for:
                    // [.dynamicType, .textClipped])` while building this
                    // plan -- still clips the label at the largest
                    // accessibility Dynamic Type sizes, even with the
                    // label's own `.fixedSize(horizontal: false, vertical:
                    // true)`: the platform switch's own minimum width is
                    // the constraint, not something this app's code
                    // controls (T-04-13 finding, Rule 1 fix). Replaced with
                    // an equivalent checkmark-style row built from a plain
                    // `Button` -- the label gets the FULL row width to wrap
                    // in, with only a small fixed-size SF Symbol beside it,
                    // never a fixed-width platform switch.
                    Button {
                        addToToday.toggle()
                    } label: {
                        HStack(spacing: TokenSemantics.Space.sm) {
                            Text("Add to Today")
                                .font(TokenSemantics.Typography.body)
                                .foregroundStyle(TokenSemantics.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: addToToday ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(addToToday ? TokenSemantics.accent : TokenSemantics.mutedText)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: TokenSemantics.Layout.target)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(addToToday ? "On" : "Off")
                    .accessibilityIdentifier("add-to-today-toggle")
                }
                if !trimmedTitle.isEmpty {
                    Section {
                        // See `TaskDetailView`'s identical Trash-button
                        // comment: `role: .destructive` alone renders
                        // below WCAG 2.2 AA contrast in a Form row
                        // (T-04-13 finding, Rule 1 fix).
                        Button("Discard Draft", role: .destructive) {
                            isShowingDiscardDraftDialog = true
                        }
                        .foregroundStyle(TokenSemantics.destructive)
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
                // `Add Task`/`Cancel` render inline in the Form, not as
                // `.confirmationAction`/`.cancellationAction` navigation-bar
                // toolbar items -- measured directly via
                // `performAccessibilityAudit(for: [.dynamicType,
                // .textClipped])` while building this plan: a compact
                // NavigationBar toolbar item has a fixed-width, single-line
                // slot that clips this exact required copy (`Add Task`,
                // `Cancel`) at the largest accessibility Dynamic Type sizes
                // with no way to wrap (a genuine iOS system-chrome
                // constraint, not something `.font`/`.lineLimit` can fix
                // without violating the never-shrink prohibition). A Form
                // Section gives both buttons the full sheet width to wrap
                // in, exactly like `Discard Draft` above already does
                // (T-04-13 finding, Rule 1 fix). `.keyboardShortcut` still
                // covers the hardware-keyboard commit/dismiss case (D-35)
                // regardless of where in the view hierarchy the button
                // lives.
                Section {
                    Button {
                        submit()
                    } label: {
                        Text("Add Task")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(TokenSemantics.Typography.body)
                    .keyboardShortcut(.defaultAction)
                    .frame(minHeight: TokenSemantics.Layout.target)
                    .accessibilityIdentifier("add-task-button")
                    // `.disabled()` sets `\.isEnabled = false` in the
                    // environment, which `Text`'s OWN default rendering
                    // reads to apply a SECOND opacity reduction beyond
                    // anything a custom `.buttonStyle` controls -- measured
                    // directly via `performAccessibilityAudit(for:
                    // .contrast)` while building this plan: even an
                    // explicit `.foregroundStyle` proven WCAG AA on its own
                    // still failed once that automatic dim compounded on
                    // top of it (T-04-13 finding, Rule 1 fix).
                    // `.allowsHitTesting(false)` blocks the same taps
                    // without touching `isEnabled` at all, so no automatic
                    // dim ever applies; `submit()`'s own existing
                    // `guard !trimmedTitle.isEmpty` (below) keeps this
                    // safe even if VoiceOver's double-tap activation
                    // reaches the action through a path hit-testing does
                    // not gate.
                    .allowsHitTesting(!(trimmedTitle.isEmpty || isCapturing))
                    .foregroundStyle((trimmedTitle.isEmpty || isCapturing) ? TokenSemantics.mutedText : TokenSemantics.accent)

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(TokenSemantics.Typography.body)
                    .keyboardShortcut(.cancelAction)
                    .frame(minHeight: TokenSemantics.Layout.target)
                    .accessibilityIdentifier("capture-cancel-button")
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
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
