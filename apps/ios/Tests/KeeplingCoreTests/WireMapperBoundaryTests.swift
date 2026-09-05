import XCTest
@testable import KeeplingCore

/// The Swift analogue of the desktop's `client-facade-boundary` import-
/// boundary test: proves structurally, not by convention, that a generated
/// wire DTO can never reach `LocalStorePort.swift`'s or
/// `SyncReducerState.swift`'s own declarations (`docs/architecture/
/// REPOSITORY.md`'s four-deliberate-representations rule, D-30 inherited).
final class WireMapperBoundaryTests: XCTestCase {
    /// Every generated type name, derived from the generated sources
    /// THEMSELVES at test time -- never hand-listed -- so a newly
    /// generated type is covered automatically the next time the client is
    /// regenerated.
    private func generatedTypeNames() throws -> Set<String> {
        let generatedDirectory = try RepositoryRoot.resolve()
            .appendingPathComponent("apps/ios/Sources/KeeplingCore/Transport/Generated")
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: generatedDirectory.path)
            .filter { $0.hasSuffix(".swift") }

        var names = Set<String>()
        // Matches `struct Foo:` / `enum Foo:` / `typealias Foo =` at any
        // indentation -- the generator's own declaration shapes for every
        // schema-derived type.
        let pattern = #"(?:struct|enum|typealias)\s+([A-Z][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern)

        for file in files {
            let contents = try String(contentsOf: generatedDirectory.appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            for match in regex.matches(in: contents, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: contents) else { continue }
                names.insert(String(contents[nameRange]))
            }
        }

        // Exclude generic/umbrella container names that are never
        // themselves the crossing DTO (the boundary test cares about the
        // SCHEMA types nested inside these namespaces, not the namespaces),
        // and `Foundation` -- matched only via `import struct Foundation.X`
        // re-export lines, never an actual generated schema declaration.
        names.subtract(["Components", "Operations", "Schemas", "Parameters", "Headers", "RequestBodies", "Responses", "Client", "Input", "Output", "Body", "Path", "Query", "Foundation"])
        // Every real generated schema type name is at least 3 characters
        // and capitalized -- filters stray single-letter generic params a
        // naive regex over `struct`/`enum` bodies can pick up.
        names = Set(names.filter { $0.count >= 3 })
        XCTAssertGreaterThan(names.count, 10, "expected to discover many generated type names; the scan may be broken")
        return names
    }

    /// Returns `true` when `name` appears as a real Swift identifier (not a
    /// substring of a longer identifier or inside a comment/string) in
    /// `source`.
    private func containsIdentifier(_ name: String, in source: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(source.startIndex..., in: source)
        return regex.firstMatch(in: source, range: range) != nil
    }

    /// Type names the target file declares FOR ITSELF (its own client-model
    /// types). A bare identifier that resolves to a locally-declared type
    /// is never a reference to the generated namespace's type of the same
    /// name -- Swift's name lookup always prefers the local/module
    /// declaration over `Components.Schemas.X`, so a coincidental name
    /// collision (e.g. this file's own `UndoResult` vs. the generated
    /// `Components.Schemas.UndoResult`) is not a boundary violation.
    private func locallyDeclaredNames(in source: String) throws -> Set<String> {
        let pattern = #"(?:struct|enum|class)\s+([A-Z][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        var names = Set<String>()
        for match in regex.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
            names.insert(String(source[nameRange]))
        }
        return names
    }

    private func assertNoGeneratedTypeLeak(relativePath: String) throws {
        let generatedNames = try generatedTypeNames()
        let path = try RepositoryRoot.resolve().appendingPathComponent(relativePath)
        let source = try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        let ownDeclarations = try locallyDeclaredNames(in: source)
        let leaked = generatedNames.filter { containsIdentifier($0, in: source) }.subtracting(ownDeclarations)
        XCTAssertTrue(leaked.isEmpty, "\(relativePath) names generated type(s): \(leaked.sorted())")
    }

    func testLocalStorePortNeverNamesAGeneratedType() throws {
        try assertNoGeneratedTypeLeak(relativePath: "apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift")
    }

    func testSyncReducerStateNeverNamesAGeneratedType() throws {
        try assertNoGeneratedTypeLeak(relativePath: "apps/ios/Sources/KeeplingCore/Sync/SyncReducerState.swift")
    }

    // MARK: - Explicit-failure-naming-the-field (never a default/zero value)

    func testMapUndoAvailabilityThrowsNamingTheFieldForAnUnrepresentableHandle() {
        let undo = Components.Schemas.UndoAvailability(expires_at: Date(), handle: "too-short", label: "Undo complete")
        XCTAssertThrowsError(try WireMappers.mapUndoAvailability(undo)) { error in
            XCTAssertEqual(error as? WireMapperError, .invalidField("handle"))
        }
    }

    func testMapUndoAvailabilityNeverSubstitutesADefaultForAnInvalidHandle() {
        let undo = Components.Schemas.UndoAvailability(expires_at: Date(), handle: "too-short", label: "Undo complete")
        do {
            _ = try WireMappers.mapUndoAvailability(undo)
            XCTFail("expected mapUndoAvailability to throw rather than substitute a default")
        } catch {
            // expected -- no SyncUndoAvailability value was ever produced
        }
    }

    // MARK: - Acknowledgement mapping preserves identity/fingerprint byte-for-byte

    func testMapCommandAcknowledgementPreservesMutationIdentityAndFingerprintExactly() throws {
        let generatedAcknowledgement = Components.Schemas.CommandAcknowledgement(
            mutation_id: "mutation-exact-123",
            outcome: .accepted,
            revision: 9,
            snapshot: TaskSnapshotFixture.make(),
            task_id: "task-1",
            warnings: []
        )
        let mapped = try WireMappers.mapCommandAcknowledgement(generatedAcknowledgement, expectedFingerprint: "fingerprint-exact-456")
        XCTAssertEqual(mapped.mutationId, "mutation-exact-123")
        XCTAssertEqual(mapped.fingerprint, "fingerprint-exact-456")
        XCTAssertEqual(mapped.outcome, .accepted)
    }

    func testMapCommandAcknowledgementNeverRederivesTheFingerprintFromTheWireResponse() throws {
        // The generated schema carries no fingerprint field at all -- this
        // test documents that the caller's own stored value is the ONLY
        // source, never something computed from the response body.
        let generatedAcknowledgement = Components.Schemas.CommandAcknowledgement(
            mutation_id: "mutation-1",
            outcome: .already_satisfied,
            revision: 2,
            snapshot: TaskSnapshotFixture.make(),
            task_id: "task-1",
            warnings: []
        )
        let mapped = try WireMappers.mapCommandAcknowledgement(generatedAcknowledgement, expectedFingerprint: "caller-fingerprint")
        XCTAssertEqual(mapped.fingerprint, "caller-fingerprint")
        XCTAssertEqual(mapped.outcome, .alreadySatisfied)
    }

    // MARK: - Pull/bootstrap mapping discards non-snapshot envelope kinds

    func testMapSyncFeedEnvelopeDiscardsACommandOutcomeEnvelope() {
        let envelope = Components.Schemas.SyncFeedEnvelope(
            entity_id: nil,
            inserted_at: Date(),
            kind: .command_outcome,
            mutation_id: "mutation-1",
            ordinal: 0,
            payload: .SyncCommandOutcomePayload(.init(
                result: .CommandAcknowledgement(.init(
                    mutation_id: "mutation-1", outcome: .accepted, revision: 1, snapshot: TaskSnapshotFixture.make(), task_id: "task-1", warnings: []
                )),
                status: 201
            )),
            sequence: 1
        )
        XCTAssertNil(WireMappers.mapSyncFeedEnvelope(envelope))
    }

    func testMapSyncFeedEnvelopeMapsATaskSnapshot() {
        let snapshot = Components.Schemas.SyncTaskSnapshot(
            captured_at: Date(), completed_at: nil, id: "task-9", inbox_state: .inbox,
            notes: "", planned_on: nil, project_id: nil, revision: 4, tag_ids: [], title: "Buy milk", trashed_at: nil
        )
        let envelope = Components.Schemas.SyncFeedEnvelope(
            entity_id: "task-9", inserted_at: Date(), kind: .task_snapshot, mutation_id: "mutation-1",
            ordinal: 0, payload: .SyncTaskSnapshot(snapshot), sequence: 1
        )
        let mapped = WireMappers.mapSyncFeedEnvelope(envelope)
        XCTAssertEqual(mapped?.entityId, "task-9")
        XCTAssertEqual(mapped?.snapshot.revision, 4)
        if case .string(let title) = mapped?.snapshot.extra["title"] {
            XCTAssertEqual(title, "Buy milk")
        } else {
            XCTFail("expected a title in extra")
        }
    }
}
