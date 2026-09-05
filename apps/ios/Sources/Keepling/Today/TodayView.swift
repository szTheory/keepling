import SwiftUI

/// Today's tab root (D-25): a native `List` of tasks planned onto today,
/// pushed to `TaskDetailView` on tap. The primary visual anchor on this tab
/// is the task list itself; the secondary anchor is the `Sync & Recovery`
/// entry point in the toolbar overflow menu (04-09-PLAN.md Task 1 resolves
/// the UI-SPEC checker's non-blocking Dimension 2 flag this way).
struct TodayView: View {
    @ObservedObject var facade: WorkspaceFacade
    @Binding var path: NavigationPath
    @State private var isPresentingCapture = false
    @AccessibilityFocusState private var focusedElement: String?

    private static let headingFocusId = "today-heading"

    private var items: [WorkspaceItem] { facade.todayItems }

    var body: some View {
        Group {
            if items.isEmpty {
                TaskListEmptyState(
                    heading: "Nothing for Today",
                    bodyText: "Add a task or choose an existing task to make it part of today.",
                    action: nil
                )
                .accessibilityFocused($focusedElement, equals: Self.headingFocusId)
            } else {
                List {
                    ForEach(items) { item in
                        // A plain row with `.onTapGesture` navigating
                        // programmatically -- NOT `NavigationLink(value:)`.
                        // `NavigationLink`'s automatic accessibility
                        // grouping collapses a row's child text into one
                        // opaque Button element, which would make the
                        // title's own `task-row-<title>` identifier
                        // unreachable as an independent element for
                        // XCUITest and for a screen reader announcing just
                        // the title (04-09-PLAN.md Task 2 discovery).
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
        .navigationTitle("Today")
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
