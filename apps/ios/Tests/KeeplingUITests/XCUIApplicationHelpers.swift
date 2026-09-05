import XCTest

/// Shared XCUITest helpers for this plan's suite (`CoreLoopTests`,
/// `GestureMirrorTests`, `CaptureDraftTests`, `ShellBoundaryTests`).
extension XCUIApplication {
    /// Finds and taps a toolbar button, first checking whether iOS
    /// collapsed it into the navigation bar's automatic overflow ("More")
    /// menu -- a real, correct system layout decision `TaskDetailView`'s
    /// two long exact-copy button labels (`Cancel Editing`, `Save & Move
    /// Out of Inbox`) can trigger on a compact nav bar, not a bug in the
    /// view itself. A button inside the overflow menu loses its own
    /// `.accessibilityIdentifier` (measured: the collapsed representation
    /// carries only `label`), so the fallback matches by `label` rather
    /// than `identifier`.
    func tapToolbarButton(identifier: String, label: String, timeout: TimeInterval = 5) -> Bool {
        let direct = buttons[identifier]
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return true
        }
        let overflow = buttons["OverflowBarButtonItem"]
        guard overflow.waitForExistence(timeout: 2) else { return false }
        overflow.tap()
        let inMenu = buttons[label].firstMatch
        guard inMenu.waitForExistence(timeout: timeout) else { return false }
        inMenu.tap()
        return true
    }
}
