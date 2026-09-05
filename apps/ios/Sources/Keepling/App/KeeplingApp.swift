import SwiftUI

/// Minimal single-screen root (Plan 04-09 builds the two-tab TabView shell;
/// this plan's tracer only needs one screen to host the capture sheet).
@main
struct KeeplingApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
