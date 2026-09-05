import KeeplingCore
import SwiftUI

/// Minimal single-screen root (Plan 04-09 builds the two-tab TabView shell;
/// this plan's tracer only needs one screen to host the capture sheet).
@main
struct KeeplingApp: App {
    private let store: GRDBLocalStore

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keepling", isDirectory: true)
        let path = directory.appendingPathComponent("keepling.sqlite").path
        // UI-test-only reset hook: XCUITest launches a fresh app process
        // each run but the simulator's Application Support directory
        // persists across launches, so without this a UI test would
        // accumulate rows from every prior run.
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_RESET_STORE"] == "1" {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        // A store that fails to open is a launch-time fatal condition in
        // this tracer -- D-22's "never present a false empty workspace"
        // rule means the app must not silently start with no store at all.
        // swiftlint:disable:next force_try
        store = try! GRDBLocalStore(path: path)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
