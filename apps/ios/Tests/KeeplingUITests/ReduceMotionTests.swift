import XCTest

/// 04-UI-SPEC.md Motion, D-47, D-48; T-04-13-05. `Motion.swift` is a
/// SwiftUI-side gate that lives inside the `Keepling` app target, which
/// `KeeplingUITests` cannot `import` (it is an `.application`, not a
/// framework -- the same constraint `ShellBoundaryTests`' own doc comment
/// records for the storage/transport boundary). So this file proves the
/// gate two ways: a structural source scan (the SAME anchored `#filePath`
/// technique `ShellBoundaryTests` established) proving no animation call
/// site can escape the gate, plus a live, out-of-process functional pass
/// under the `-UIAccessibilityReduceMotionEnabled` environment override
/// proving every screen still renders and every state's meaning still
/// carries in text -- never only in motion.
@MainActor
final class ReduceMotionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Structural: no animation call site can escape the single gate

    private var keeplingSourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KeeplingUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // apps/ios
            .appendingPathComponent("Sources/Keepling")
    }

    func testNoAnimationCallSiteExistsOutsideTheSingleMotionGate() throws {
        guard let enumerator = FileManager.default.enumerator(
            at: keeplingSourcesRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else {
            XCTFail("could not enumerate \(keeplingSourcesRoot.path) -- path resolution is broken")
            return
        }
        var offendingFiles: [String] = []
        var scannedAnyFile = false
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if url.path.hasSuffix("Shared/Motion.swift") { continue }
            scannedAnyFile = true
            let contents = try String(contentsOf: url, encoding: .utf8)
            let nonCommentContents = contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if nonCommentContents.contains("withAnimation") || nonCommentContents.contains(".animation(") {
                offendingFiles.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(scannedAnyFile, "no files scanned -- path resolution is broken")
        XCTAssertTrue(offendingFiles.isEmpty, "the following file(s) declare an animation call site outside Shared/Motion.swift: \(offendingFiles.sorted())")
    }

    func testMotionGateDeclaresTheUISpecDurationsAndAReduceMotionBranch() throws {
        let contents = try String(contentsOf: keeplingSourcesRoot.appendingPathComponent("Shared/Motion.swift"), encoding: .utf8)
        XCTAssertTrue(contents.contains("TokenSemantics.Motion.direct"), "Motion.swift does not read the shared 160ms direct-interaction duration")
        XCTAssertTrue(contents.contains("TokenSemantics.Motion.overlay"), "Motion.swift does not read the shared 180ms overlay duration")
        XCTAssertTrue(contents.contains("TokenSemantics.Motion.reduced"), "Motion.swift does not read the shared ~100ms Reduce Motion duration")
        XCTAssertTrue(contents.contains("UIAccessibility.isReduceMotionEnabled"), "Motion.swift does not branch on the Reduce Motion environment override")
    }

    // MARK: - Functional: every screen still renders under Reduce Motion

    func testEveryInventoryScreenRendersUnderReduceMotion() throws {
        for screen in SupportedScreen.all {
            let app = XCUIApplication()
            app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
            for (key, value) in screen.launchEnvironment { app.launchEnvironment[key] = value }
            app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "1"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "\(screen.name) under Reduce Motion: tab bar never appeared")
            try screen.navigate(app)
        }
    }

    // MARK: - No state's meaning depends only on animation (D-48)

    func testEveryActionableStateStillCarriesTextUnderReduceMotion() throws {
        let actionableStates = [
            "updating_past_grace", "local_save_failure",
            "retryable_failure", "uncertain", "rejected", "conflict", "authentication_fence", "unrecoverable",
        ]
        for state in actionableStates {
            let app = XCUIApplication()
            app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
            app.launchEnvironment["KEEPLING_UITEST_SYNC_STATE"] = state
            app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "1"]
            app.launch()
            defer { app.terminate() }
            let text = app.staticTexts["sync-accessory-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 10), "state '\(state)' under Reduce Motion rendered no text cue")
            XCTAssertFalse(text.label.isEmpty, "state '\(state)' under Reduce Motion rendered empty text")
        }
    }

    func testTrashAndUndoStillCarryTextUnderReduceMotion() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launchEnvironment["KEEPLING_UITEST_SEED_UNDO"] = "trash"
        app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "1"]
        app.launch()
        defer { app.terminate() }
        let undoLabel = app.staticTexts["sync-accessory-undo-label"]
        XCTAssertTrue(undoLabel.waitForExistence(timeout: 10))
        XCTAssertEqual(undoLabel.label, "Task moved to Trash. Undo Trash")
    }
}
