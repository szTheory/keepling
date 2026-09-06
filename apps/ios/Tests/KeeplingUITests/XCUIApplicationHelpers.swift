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
        // Match the overflow-menu entry by IDENTIFIER first and only then
        // by display label. A collapsed toolbar item does not reliably
        // carry its on-screen title as its accessible label once UIKit has
        // rehosted it inside the `More` menu, so a label-only lookup can
        // miss a button that is plainly present -- measured on a physical
        // iPhone, where `Save & Move Out of Inbox` (a long title sharing a
        // 440pt bar with a Back button and `Cancel Editing`) collapses and
        // the label lookup then failed. The identifier is set by this app
        // and does not change with presentation.
        for candidate in [buttons[identifier].firstMatch, buttons[label].firstMatch] {
            if candidate.waitForExistence(timeout: timeout) {
                candidate.tap()
                return true
            }
        }
        return false
    }
}
