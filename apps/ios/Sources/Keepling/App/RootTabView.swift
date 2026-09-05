import KeeplingCore
import SwiftUI

/// The root of the app (D-25): a two-tab `TabView` -- **Today** and
/// **Inbox** only, each owning its own `NavigationStack` so switching tabs
/// preserves each stack's navigation position independently. List-to-detail
/// is always a push; capture is the only sheet-presented flow.
///
/// Exactly two locked destinations -- do not add a third, and do not build a
/// lists-home root (D-25 rejects the Things-style single stack for this
/// phase: it costs a tap on every switch between the two loops used
/// hourly).
struct RootTabView: View {
    @ObservedObject var facade: WorkspaceFacade

    @State private var selectedTab: AppTab = .inbox
    @State private var todayPath = NavigationPath()
    @State private var inboxPath = NavigationPath()

    /// Named `AppTab`, not `Tab`, to avoid shadowing `SwiftUI.Tab` (the
    /// `TabView` content-builder type used directly in `body` below).
    enum AppTab: Hashable {
        case today
        case inbox
    }

    /// Whether the accessory has anything to show right now (D-38's
    /// priority order, applied by `SyncPresentationSummary
    /// .isActionableException` -- this view computes no order of its
    /// own).
    private var accessoryHasContent: Bool {
        BottomAccessoryView.hasContent(summary: facade.syncPresentation, undoAvailability: facade.undoAvailability)
    }

    /// 04-04-PLAN.md measured that genuine `tabViewBottomAccessory`
    /// absence on this pinned SDK requires the `conditionalModifier`
    /// configuration -- attaching the modifier unconditionally, even with
    /// empty content, reproduces a 48pt reserved, hit-testable phantom
    /// region (T-04-04-01). So when absence IS achievable (the measured
    /// case today), the call site below is omitted entirely whenever there
    /// is nothing to show; only when a future SDK measurement records
    /// `.absenceNotAchievable` is the modifier attached unconditionally,
    /// with `BottomAccessoryView` rendering the disclosed empty fallback
    /// for a healthy state (D-40).
    private var shouldAttachAccessory: Bool {
        switch currentAccessoryHostability {
        case .absenceAchievable:
            return accessoryHasContent
        case .absenceNotAchievable:
            return true
        }
    }

    var body: some View {
        if shouldAttachAccessory {
            tabs.tabViewBottomAccessory {
                BottomAccessoryView(
                    summary: facade.syncPresentation,
                    undoAvailability: facade.undoAvailability,
                    hostability: currentAccessoryHostability,
                    // Task 3 (SyncRecoverySheet.swift) wires the actual
                    // full-screen sheet presentation this action opens.
                    onAction: { _ in },
                    onUndo: {}
                )
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView(facade: facade, path: $todayPath)
                        .navigationDestination(for: String.self) { taskId in
                            TaskDetailView(facade: facade, taskId: taskId)
                        }
                }
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack(path: $inboxPath) {
                    InboxView(facade: facade, path: $inboxPath)
                        .navigationDestination(for: String.self) { taskId in
                            TaskDetailView(facade: facade, taskId: taskId)
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(TokenSemantics.accent)
    }
}
