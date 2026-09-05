import KeeplingCore
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
    /// See `InboxView`'s identical comment: `@AccessibilityFocusState`
    /// round-trips through the real accessibility focus system and
    /// reverts to `nil` without an active assistive-technology client
    /// (T-04-13-06) -- this plain `@State` mirror reflects exactly what
    /// this view's OWN logic decided and requested instead.
    @State private var lastRequestedFocusTarget: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let headingFocusId = "today-heading"
    /// Focus-safety-after-sheet-dismissal targets (04-UI-SPEC.md
    /// Accessibility and Platform Contract, T-04-13-06): focus returns to
    /// the control that presented the dismissed sheet. `new-task-button`
    /// presents the capture sheet; `overflow-menu` (the "More" button) is
    /// the always-present, persistent control a person actually taps to
    /// reach the `Sync & Recovery` full-screen cover (D-39) -- the
    /// specific menu ROW selected to open it closes with the menu itself
    /// and is not a stable return target.
    private static let newTaskButtonFocusId = "new-task-button-focus"
    private static let overflowMenuFocusId = "overflow-menu-focus"

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
                            onTrash: { Task { try? await facade.trash(taskId: item.taskId) } },
                            onOpenSyncRecovery: { facade.openSyncRecovery(focusTaskId: item.taskId) },
                            focusBinding: $focusedElement,
                            focusValue: item.taskId
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(item.taskId) }
                    }
                }
                .listStyle(.plain)
            }
        }
        // SwiftUI's `.sheet` does NOT automatically remove the presenting
        // content from the accessibility tree while the sheet is up --
        // measured directly via `performAccessibilityAudit(for: [.contrast,
        // .textClipped])` while building this plan: the audit flagged
        // Today's own row/button text (visible only as a dimmed backdrop
        // behind the capture sheet) as insufficient contrast and possibly
        // clipped, findings that don't apply to genuinely visible,
        // interactive content (T-04-13 finding, Rule 1 fix). Hiding this
        // content from the accessibility tree while a sheet is presented
        // also stops a Switch Control/VoiceOver user from navigating into
        // a dimmed, non-interactive background.
        .accessibilityHidden(isPresentingCapture)
        .background(TokenSemantics.canvas)
        // A near-invisible, always-present marker exposing
        // `lastRequestedFocusTarget` (see its own doc comment above) for
        // `FocusSafetyTests` to read directly (T-04-13-06).
        .background(
            Text(lastRequestedFocusTarget ?? "")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("debug-focused-element")
        )
        .navigationTitle("Today")
        .accessibilityFocused($focusedElement, equals: Self.headingFocusId)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingCapture = true
                } label: {
                    // At an accessibility Dynamic Type size the "New Task"
                    // text label competing with the overflow-menu button
                    // for the nav bar's fixed toolbar width measurably
                    // shrinks this button below the 44pt minimum hit
                    // target (measured directly while building this plan,
                    // T-04-13-02: 42.67pt at
                    // `UICTContentSizeCategoryAccessibilityXXXL`) --
                    // dropping to an icon-only label frees enough width for
                    // the requested `.frame` minimum to actually be
                    // honored. The accessible name is unaffected: `Label`
                    // and `Image(systemName:)` both expose "New Task" via
                    // this button's own accessibility label either way.
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "plus")
                    } else {
                        Label("New Task", systemImage: "plus")
                    }
                }
                .accessibilityLabel("New Task")
                .accessibilityIdentifier("new-task-button")
                .accessibilityFocused($focusedElement, equals: Self.newTaskButtonFocusId)
                .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
            }
            // D-39: a persistent `Sync & Recovery` overflow-menu row on
            // BOTH tabs, present even when everything is quiet. D-30's
            // Undo mirror lives in the same menu when an undo is
            // available.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let undo = facade.undoAvailability {
                        UndoControl(availability: undo, onUndo: { Task { await facade.invokeUndo() } }).menuRow
                    }
                    Button(SyncCopy.recoveryTitle) {
                        facade.openSyncRecovery()
                    }
                    .accessibilityLabel("Open Sync & Recovery")
                    .accessibilityIdentifier("overflow-sync-recovery")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("overflow-menu")
                .accessibilityFocused($focusedElement, equals: Self.overflowMenuFocusId)
                .frame(minWidth: TokenSemantics.Layout.target, minHeight: TokenSemantics.Layout.target)
            }
        }
        .task { await facade.refresh() }
        .onChange(of: items.map(\.taskId)) { old, new in
            if let target = RowFocusSafety.focusTarget(old: old, new: new, headingId: Self.headingFocusId) {
                focusedElement = target
                lastRequestedFocusTarget = target
            }
        }
        .onChange(of: isPresentingCapture) { wasPresented, isPresented in
            // T-04-13-06: focus returns to the presenting control after
            // the capture sheet dismisses (Add Task, Cancel, or a
            // confirmed Discard Draft all route through this same
            // `isPresented` flip).
            if wasPresented, !isPresented {
                focusedElement = Self.newTaskButtonFocusId
                lastRequestedFocusTarget = Self.newTaskButtonFocusId
            }
        }
        .onChange(of: facade.isSyncRecoveryPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                focusedElement = Self.overflowMenuFocusId
                lastRequestedFocusTarget = Self.overflowMenuFocusId
            }
        }
        .sheet(isPresented: $isPresentingCapture) {
            CaptureSheet(facade: facade)
        }
    }
}
