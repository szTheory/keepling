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

    var body: some View {
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
        // No `.tabViewBottomAccessory` call site exists here at all (not an
        // always-applied modifier with empty content). 04-04-PLAN.md
        // measured that genuine absence on this SDK requires the
        // `conditionalModifier` configuration (`AccessoryHostability
        // .currentAccessoryHostability`) -- attaching the modifier
        // unconditionally, even with empty content, reproduces a 48pt
        // reserved, hit-testable phantom region (T-04-04-01). This plan
        // builds no accessory content (Plan 04-10's concern); the correct
        // way to honor `conditionalModifier` with nothing to show is to
        // omit the call site entirely, not to apply it with `EmptyView()`.
        .tint(TokenSemantics.accent)
    }
}
