import XCTest

/// Structurally enforces the D-45 presentation boundary (04-09-PLAN.md
/// Task 1): no SwiftUI *view* under `Sources/Keepling` may reference a
/// storage, transport, or credential type, and no file outside
/// `DesignTokens/` may contain a hex color literal. Mirrors the desktop's
/// `client-facade-boundary` import-boundary test.
///
/// Runs against the real checked-out source tree via `#filePath` -- an
/// iOS Simulator XCTest host is an ordinary macOS process with full host
/// filesystem access (established precedent: `StorageTests/
/// SourceDisciplineTests.swift`).
final class ShellBoundaryTests: XCTestCase {
    /// `#filePath` == `.../apps/ios/Tests/KeeplingUITests/ShellBoundaryTests.swift`.
    /// Three `deletingLastPathComponent()` calls strip the filename, then
    /// `KeeplingUITests`, then `Tests`, landing on `apps/ios` -- verified
    /// defensively below rather than trusted silently (a wrong depth here
    /// would make every assertion in this file vacuously pass over zero
    /// files, exactly the false-green failure mode 04-RESEARCH.md's own
    /// Pitfall 1 warns against).
    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KeeplingUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // apps/ios
    }

    private var keeplingSourcesRoot: URL { iosRoot.appendingPathComponent("Sources/Keepling") }
    private var keeplingCoreSourcesRoot: URL { iosRoot.appendingPathComponent("Sources/KeeplingCore") }

    /// The two sanctioned exceptions to the boundary this test enforces:
    /// `KeeplingApp.swift` is an `App` conformer, not a `View`, and
    /// constructs `GRDBLocalStore`/`KeeplingSyncAdapter` exactly once;
    /// `WorkspaceFacade.swift` IS the presentation-only boundary object
    /// itself -- it is the one thing sanctioned to hold a store handle
    /// precisely so nothing else needs to (mirrors the desktop's own
    /// `main/index.ts` composition root and `ClientFacade.ts`
    /// implementation, both exempt from `apps/web`'s
    /// `client-facade-boundary` test the same way). Every OTHER file
    /// under `Sources/Keepling`, including every view this plan adds, is
    /// scanned with no exemption.
    private static let boundaryExemptions: Set<String> = ["App/KeeplingApp.swift", "Workspace/WorkspaceFacade.swift"]

    /// A THIRD exemption, distinct from the two sanctioned ones above:
    /// `SignInFlow.swift` (04-07-PLAN.md) is a genuine, PRE-EXISTING D-45
    /// violation -- a `View` holding a `DeviceGrantClient` directly -- not
    /// something this plan introduced or is authorized to fix (out of this
    /// plan's `files_modified` scope; scope-boundary deviation rule).
    /// Disclosed in 04-09-SUMMARY.md and the cross-phase defect ledger
    /// rather than silently exempted forever: a future plan wiring
    /// `SignInFlow` into root navigation must resolve this properly (route
    /// the device-grant flow through `WorkspaceFacade` or an equivalent
    /// auth-facade boundary) before this exemption can be removed.
    private static let preExistingViolationExemption = "Auth/SignInFlow.swift"

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    /// Derives forbidden storage/transport/credential type names from
    /// their OWN declaring files under `Sources/KeeplingCore` -- never a
    /// hand-maintained list -- so a type added later to one of these files
    /// is covered automatically.
    ///
    /// Only `class`/`protocol` declarations are captured (never `struct`/
    /// `enum`): these declaring files mix genuine storage/transport/
    /// credential HANDLES (`GRDBLocalStore`, `LocalStorePort`,
    /// `KeeplingSyncAdapter`, `DeviceGrantClient`, `KeychainCredentialStore`
    /// -- all classes or protocols) with plain, storage-neutral `Sendable`
    /// DTOs the facade legitimately re-exposes to presentation
    /// (`ProjectionRow`, `WorkspaceSnapshot`, `LocalMutation`,
    /// `ConflictRecord`, `CaptureDraft` -- all structs). Matching is
    /// anchored to the START of a trimmed line and requires a `public`
    /// modifier, so a doc-comment sentence using "class"/"protocol" as an
    /// ordinary English word (this codebase's declaring files are heavily
    /// commented) can never be captured as a bogus type name.
    private func declaredTypeNames(in files: [URL]) throws -> Set<String> {
        var names: Set<String> = []
        let pattern = #"^public\s+(?:final\s+)?(?:class|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let nameRange = Range(match.range(at: 1), in: line)
                else { continue }
                names.insert(String(line[nameRange]))
            }
        }
        return names
    }

    func testNoStorageTransportOrCredentialTypeAppearsUnderSourcesKeepling() throws {
        let declaringFileNames = [
            "Storage/GRDBLocalStore.swift", "Storage/LocalStorePort.swift",
            "Auth/DeviceGrantClient.swift", "Auth/KeychainCredentialStore.swift", "Auth/CredentialPort.swift",
            "Auth/NamespaceActivation.swift",
            "Transport/KeeplingSyncAdapter.swift", "Transport/SyncPort.swift",
        ]
        let declaringFiles = declaringFileNames
            .map { keeplingCoreSourcesRoot.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertFalse(declaringFiles.isEmpty, "no declaring files resolved under \(keeplingCoreSourcesRoot.path) -- iosRoot path resolution is broken")

        var forbidden = try declaredTypeNames(in: declaringFiles)
        XCTAssertTrue(forbidden.contains("GRDBLocalStore"), "derivation did not find GRDBLocalStore -- the anchor pattern is broken")
        XCTAssertTrue(forbidden.contains("LocalStorePort"), "derivation did not find LocalStorePort -- the anchor pattern is broken")
        // Two narrow, explicit exceptions to "derive, never hand-list":
        // (1) GRDB's own top-level types -- GRDB's sources are a
        // third-party package, not checked into this repository, so they
        // cannot be source-scanned by file the same way; (2) `DurableUnit`
        // -- declared as a `struct` (so the class/protocol-only derivation
        // above does not catch it) but wraps a raw database FILE PATH,
        // exactly the D-45 threat register's "no file path" boundary.
        forbidden.formUnion(["DatabasePool", "Database", "DurableUnit"])

        let presentationFiles = try swiftFiles(under: keeplingSourcesRoot)
            .filter { file in
                !Self.boundaryExemptions.contains { file.path.hasSuffix($0) } &&
                    !file.path.hasSuffix(Self.preExistingViolationExemption)
            }
        XCTAssertFalse(presentationFiles.isEmpty, "no presentation files found under \(keeplingSourcesRoot.path) -- path resolution is broken")

        for file in presentationFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            // A doc-comment PROSE mention (e.g. "resolves only after
            // `GRDBLocalStore.acceptMutation`'s transaction commits") is
            // documentation, not real code coupling -- only non-comment
            // lines are scanned for actual references, mirroring
            // `StorageTests/SourceDisciplineTests.swift`'s established
            // `nonCommentLines` convention.
            let nonCommentContents = contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(
                nonCommentContents.contains("import GRDB"),
                "\(file.lastPathComponent) imports GRDB directly -- breaks the D-45 presentation boundary"
            )
            for name in forbidden {
                let boundaryPattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
                guard let regex = try? NSRegularExpression(pattern: boundaryPattern) else { continue }
                let range = NSRange(nonCommentContents.startIndex..., in: nonCommentContents)
                XCTAssertEqual(
                    regex.numberOfMatches(in: nonCommentContents, range: range), 0,
                    "\(file.lastPathComponent) references forbidden storage/transport/credential type \(name)"
                )
            }
        }
    }

    func testNoHexColorLiteralOutsideDesignTokens() throws {
        let files = try swiftFiles(under: keeplingSourcesRoot).filter { !$0.path.contains("/DesignTokens/") }
        XCTAssertFalse(files.isEmpty, "no files found to scan -- path resolution is broken")
        let regex = try NSRegularExpression(pattern: "#[0-9A-Fa-f]{6}")
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            XCTAssertEqual(
                regex.numberOfMatches(in: contents, range: range), 0,
                "\(file.lastPathComponent) contains a hex color literal outside DesignTokens/"
            )
        }
    }

    func testRootTabViewDeclaresExactlyTwoLockedTabsWithMinimizeBehavior() throws {
        let file = keeplingSourcesRoot.appendingPathComponent("App/RootTabView.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"Today\""))
        XCTAssertTrue(contents.contains("\"Inbox\""))
        XCTAssertTrue(contents.contains(".tabBarMinimizeBehavior(.onScrollDown)"))
        let navigationStackCount = contents.components(separatedBy: "NavigationStack(path:").count - 1
        XCTAssertEqual(navigationStackCount, 2, "expected exactly two NavigationStacks (one per locked tab)")
    }

    // MARK: - Live navigation-preservation test

    func testEachTabsNavigationStackPositionIsPreservedIndependentlyAcrossATabSwitch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["KEEPLING_UITEST_RESET_STORE"] = "1"
        app.launch()

        let newTaskButton = app.buttons["new-task-button"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 5))
        newTaskButton.tap()

        let titleField = app.textFields["capture-title-field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Shell boundary task")

        let addTaskButton = app.buttons["add-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 5))
        addTaskButton.tap()

        let row = app.staticTexts["task-row-Shell boundary task"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let detailTitleField = app.textFields["detail-title-field"]
        XCTAssertTrue(detailTitleField.waitForExistence(timeout: 5))

        // Switch to Today, then back to Inbox -- the pushed detail screen
        // must still be there (D-25: each tab preserves its own
        // NavigationStack position independently across a tab switch).
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(
            detailTitleField.waitForExistence(timeout: 5),
            "Inbox's NavigationStack lost its pushed detail screen across a tab switch"
        )
    }
}
