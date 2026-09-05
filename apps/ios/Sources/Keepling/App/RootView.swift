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
            .task { await reload() }
            .sheet(isPresented: $isPresentingCapture) {
                CaptureSheet { title in
                    try await capture(title: title)
                    await reload()
                }
            }
        }
    }

    /// Both store calls below run off the main actor via `Task.detached`
    /// (D-04 G5): `GRDBLocalStore` traps in Debug builds if entered from
    /// the main thread, and a SwiftUI view's own action closures and
    /// `.task` modifier run on the main actor by default.
    private func reload() async {
        let store = self.store
        tasks = await Task.detached(priority: .userInitiated) {
            (try? store.snapshot().tasks) ?? []
        }.value
    }

    private func capture(title: String) async throws {
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
        let store = self.store
        try await Task.detached(priority: .userInitiated) {
            _ = try store.acceptMutation(mutation)
        }.value
    }
}
