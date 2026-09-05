import KeeplingCore
import SwiftUI

/// Inbox's tab root (D-25): a native `List` of captured, unplanned tasks,
/// pushed to `TaskDetailView` on tap.
struct InboxView: View {
    @ObservedObject var facade: WorkspaceFacade
    @Binding var path: NavigationPath
    @State private var isPresentingCapture = false
    @AccessibilityFocusState private var focusedElement: String?
    /// The last focus target this view's OWN logic computed and
    /// requested, mirrored into a plain `@State` alongside every
    /// `focusedElement =` assignment below -- measured directly while
    /// building this plan (T-04-13-06): `@AccessibilityFocusState`'s
    /// stored value round-trips through the REAL accessibility focus
    /// system, and reverts to `nil` when no assistive-technology client
    /// (VoiceOver) is running to confirm the requested move, which is not
    /// achievable in this automated harness (the same constraint already
    /// disclosed for VoiceOver speech synthesis). This plain `@State`
    /// mirror has no such round-trip -- it reflects exactly what THIS
    /// APP'S OWN LOGIC decided and requested, which is what
    /// `FocusSafetyTests` verifies; whether the OS actually LANDS
    /// VoiceOver focus there is the disclosed, unprovable remainder.
    @State private var lastRequestedFocusTarget: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let headingFocusId = "inbox-heading"
    /// See `TodayView`'s identical comment: focus safety after sheet
    /// dismissal (T-04-13-06) returns to the always-present control that
    /// presented the sheet.
    private static let newTaskButtonFocusId = "new-task-button-focus"
    private static let overflowMenuFocusId = "overflow-menu-focus"

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
        // See `TodayView`'s identical comment: hides this presenting
        // content from the accessibility tree while the capture sheet is
        // up (T-04-13 finding, Rule 1 fix).
        .accessibilityHidden(isPresentingCapture)
        .background(TokenSemantics.canvas)
        // See `TodayView`'s identical comment: a near-invisible marker
        // exposing `lastRequestedFocusTarget` for `FocusSafetyTests`
        // (T-04-13-06).
        .background(
            Text(lastRequestedFocusTarget ?? "")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("debug-focused-element")
        )
        .navigationTitle("Inbox")
        .accessibilityFocused($focusedElement, equals: Self.headingFocusId)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingCapture = true
                } label: {
                    // See `TodayView`'s identical comment: icon-only at an
                    // accessibility Dynamic Type size keeps this button at
                    // its full 44pt hit target rather than being squeezed
                    // below it alongside the overflow-menu button.
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
            // BOTH tabs, present even when everything is quiet -- that is
            // precisely when a person doubts whether anything is working.
            // D-30's Undo mirror lives in the same menu when an undo is
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
