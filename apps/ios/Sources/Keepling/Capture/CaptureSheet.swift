import KeeplingCore
import SwiftUI

/// The capture sheet (D-35, 04-UI-SPEC.md Capture Contract). This tracer
/// implements the durable-commit half only: capture and Inbox destination.
/// Durable draft persistence, `Discard Draft`, hardware-keyboard shortcuts,
/// and App Intents are Plan 04-09/04-13/04-14 work (flagged_assumptions in
/// 04-01-PLAN.md).
struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var isCapturing = false
    @State private var captureError: String?

    let onCapture: (String) async throws -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to keep?", text: $title, axis: .vertical)
                        .accessibilityLabel("What do you want to keep?")
                        .accessibilityIdentifier("capture-title-field")
                }
                Section {
                    Text("Destination: Inbox")
                        .foregroundStyle(.secondary)
                }
                if let captureError {
                    Section {
                        Text(captureError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Task") {
                        submit()
                    }
                    .accessibilityIdentifier("add-task-button")
                    .disabled(trimmedTitle.isEmpty || isCapturing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        isCapturing = true
        captureError = nil
        Task {
            do {
                // The sheet shows nothing claiming durability until this
                // call returns -- `onCapture` resolves only after
                // `GRDBLocalStore.acceptMutation`'s transaction commits
                // (D-03), never before.
                try await onCapture(trimmedTitle)
                isCapturing = false
                dismiss()
            } catch {
                isCapturing = false
                captureError = "Couldn't save this on your iPhone. Try again."
            }
        }
    }
}
