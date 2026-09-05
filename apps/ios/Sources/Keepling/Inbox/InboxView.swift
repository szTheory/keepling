import SwiftUI

/// Inbox's tab root (D-25): a native `List` of captured, unplanned tasks,
/// pushed to `TaskDetailView` on tap.
struct InboxView: View {
    @ObservedObject var facade: WorkspaceFacade
    @Binding var path: NavigationPath
    @State private var isPresentingCapture = false
    @AccessibilityFocusState private var focusedElement: String?

    private static let headingFocusId = "inbox-heading"

    private var items: [WorkspaceItem] { facade.inboxItems }

    var body: some View {
        Group {
            if items.isEmpty {
                TaskListEmptyState(
                    heading: "Inbox Is Clear",
                    bodyText: "Captured tasks appear here until you move them out.",
                    action: (label: "New Task", perform: { isPresentingCapture = true })
                )
                .accessibilityFocused($focusedElement, equals: Self.headingFocusId)
            } else {
                List {
                    ForEach(items) { item in
                        // A plain row with `.onTapGesture` navigating
                        // programmatically -- see `TodayView`'s identical
                        // comment for why `NavigationLink(value:)` is
                        // avoided here.
                        TaskRow(
                            item: item,
                            onComplete: { Task { try? await facade.complete(taskId: item.taskId) } },
                            onReopen: { Task { try? await facade.reopen(taskId: item.taskId) } },
                            onTrash: { Task { try? await facade.trash(taskId: item.taskId) } }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(item.taskId) }
                        .accessibilityFocused($focusedElement, equals: item.taskId)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(TokenSemantics.canvas)
        .navigationTitle("Inbox")
        .accessibilityFocused($focusedElement, equals: Self.headingFocusId)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingCapture = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .accessibilityIdentifier("new-task-button")
                .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
            }
        }
        .task { await facade.refresh() }
        .onChange(of: items.map(\.taskId)) { old, new in
            if let target = RowFocusSafety.focusTarget(old: old, new: new, headingId: Self.headingFocusId) {
                focusedElement = target
            }
        }
        .sheet(isPresented: $isPresentingCapture) {
            CaptureSheet(facade: facade)
        }
    }
}
