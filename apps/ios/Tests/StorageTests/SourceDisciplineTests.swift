import XCTest
@testable import KeeplingCore

/// A build-time source scan that keeps three permanently-rejected shapes
/// out of `apps/ios/Sources`, so they cannot silently re-enter the tree
/// between plans:
///
/// 1. GRDB's `eraseDatabaseOnSchemaChange` destructive-reset flag -- the
///    opposite of D-04 G4's "halt, never repair."
/// 2. SwiftData (`import SwiftData` or `@Model`) -- D-02 rejects it
///    outright; it is explicitly not the fallback.
/// 3. A second local-store adapter (`RawSQLite3LocalStore.swift` or a
///    `libsqlite3.tbd` linkage) -- D-05 predeclares the raw `sqlite3` C API
///    as a fallback triggered only by a G1-G6 failure or GRDB going
///    unmaintained, never built alongside GRDB.
///
/// Runs against the real checked-out source tree via `#filePath`, since an
/// iOS Simulator XCTest host is an ordinary macOS process with full host
/// filesystem access -- there is no need to bundle the sources as test
/// resources to read them.
final class SourceDisciplineTests: XCTestCase {
    private var iosRoot: URL {
        // #filePath == .../apps/ios/Tests/StorageTests/SourceDisciplineTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StorageTests
            .deletingLastPathComponent() // Tests
    }

    private var sourcesRoot: URL {
        iosRoot.appendingPathComponent("Sources")
    }

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

    /// Strips full-line `//` comments before searching -- an occurrence
    /// living only in a comment does not count as the destructive flag
    /// actually being wired up, matching the plan's own non-comment-line
    /// grep check in `<verify>`.
    private func nonCommentLines(of contents: String) -> [String] {
        contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    func testNoNonCommentOccurrenceOfTheDestructiveResetFlag() throws {
        for file in try swiftFiles(under: sourcesRoot) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let offendingLines = nonCommentLines(of: contents).filter { $0.contains("eraseDatabaseOnSchemaChange") }
            XCTAssertTrue(
                offendingLines.isEmpty,
                "\(file.lastPathComponent) contains a non-comment occurrence of eraseDatabaseOnSchemaChange: \(offendingLines)"
            )
        }
    }

    func testNoSwiftDataImportOrModelAttributeAnywhereUnderSources() throws {
        for file in try swiftFiles(under: sourcesRoot) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = nonCommentLines(of: contents)
            XCTAssertFalse(
                lines.contains { $0.contains("import SwiftData") },
                "\(file.lastPathComponent) imports SwiftData -- D-02 rejects it outright"
            )
            XCTAssertFalse(
                lines.contains { $0.contains("@Model") },
                "\(file.lastPathComponent) carries a @Model attribute -- D-02 rejects SwiftData outright"
            )
        }
    }

    func testNoSecondRawSQLite3AdapterFileOrLinkageExistsInTheTree() throws {
        for file in try swiftFiles(under: sourcesRoot) {
            XCTAssertNotEqual(
                file.lastPathComponent, "RawSQLite3LocalStore.swift",
                "D-05's raw sqlite3 adapter is a predeclared fallback, never built alongside GRDB"
            )
        }

        // project.yml and the generated .pbxproj are the only places a
        // library linkage would be declared for this XcodeGen-managed
        // project (04-01-SUMMARY.md "XcodeGen -> Keepling.xcodeproj, never
        // hand-edited").
        let candidateLinkageFiles = [
            iosRoot.appendingPathComponent("project.yml"),
            iosRoot.appendingPathComponent("Keepling.xcodeproj/project.pbxproj"),
        ]
        for file in candidateLinkageFiles {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            XCTAssertFalse(
                contents.contains("libsqlite3.tbd"),
                "\(file.lastPathComponent) links libsqlite3.tbd -- D-01's single committed adapter is GRDB"
            )
        }
    }
}
