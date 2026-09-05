import KeeplingCore
import SwiftUI

/// Task 3's minimal single-screen root (Plan 04-09 replaces this with the
/// two-tab TabView/NavigationStack shell, D-25). Hosts the capture sheet
/// and the visible projection this tracer proves end to end.
struct RootView: View {
    let store: any LocalStorePort

    @State private var isPresentingCapture = false
    @State private var tasks: [ProjectionRow] = []

    var body: some View {
        NavigationStack {
            List(tasks, id: \.taskId) { task in
                Text(task.title)
                    .accessibilityIdentifier("task-row-\(task.title)")
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem {
                    Button("New Task") { isPresentingCapture = true }
                        .accessibilityIdentifier("new-task-button")
                }
            }
            .task { reload() }
            .sheet(isPresented: $isPresentingCapture) {
                CaptureSheet { title in
                    try capture(title: title)
                    reload()
                }
            }
        }
    }

    private func reload() {
        tasks = (try? store.snapshot().tasks) ?? []
    }

    private func capture(title: String) throws {
        let mutationId = UUID().uuidString
        let taskId = UUID().uuidString
        let built = try CaptureCommand.build(title: title, mutationId: mutationId, taskId: taskId)
        let mutation = LocalMutation(
            mutationId: built.mutationId,
            taskId: built.taskId,
            commandBytes: built.commandBytes,
            fingerprint: built.fingerprint,
            acceptedAt: ISO8601DateFormatter().string(from: Date()),
            resourceKeys: ["task:\(built.taskId)"],
            title: built.title
        )
        _ = try store.acceptMutation(mutation)
    }
}
