import AppIntents

/// Declares Capture and Complete as app shortcuts so they surface in
/// Shortcuts, Siri, the Action Button, and Spotlight actions (D-35,
/// IOS-01) -- with no additional entitlement, no App Group, and no second
/// target: `AppShortcutsProvider` conformance alone, on a type compiled
/// into the main app's own executable (KeeplingCore is a local Swift
/// package statically linked into the `Keepling` target -- 04-RESEARCH.md
/// § Architecture Patterns, Pattern 3), is what makes an app's intents
/// discoverable by the system.
public struct KeeplingShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTaskIntent(),
            phrases: [
                "Capture a task in \(.applicationName)",
                "Add a task to \(.applicationName)"
            ],
            shortTitle: "Capture Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
    }
}
