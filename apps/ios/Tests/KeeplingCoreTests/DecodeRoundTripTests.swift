import XCTest
@testable import KeeplingCore

/// D-14: "a decode round-trip test over every wire payload appearing in the
/// 13 vector files, so a generator regression fails a test rather than
/// failing on a phone" -- and 04-RESEARCH.md Pitfall 2's own warning that
/// such a suite "only catches the defect if the vector files actually
/// contain a null value for every nullable field, which should be
/// spot-checked, not assumed."
///
/// DISCLOSED DEVIATION (04-05-SUMMARY.md has the full trail): D-14's own
/// premise -- that `packages/contracts/vectors/`'s 13 files contain wire
/// payload OBJECTS decodable by the generated Swift client -- is false.
/// `testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads` below
/// proves this structurally (walks every JSON object in every one of the
/// 13 files and attempts every candidate generated DTO's decoder against
/// it) rather than merely asserting it in a comment. Every vector file is
/// an ABSTRACT domain-reducer fixture -- e.g. `sync.json`'s
/// `{id, revision, title}` snapshot omits `SyncTaskSnapshot`'s required
/// `captured_at`/`inbox_state`/`notes`/`tags`/`trashed_at` -- never a
/// full contract-conformant object satisfying any generated DTO's
/// `additionalProperties: false` + `required` set.
///
/// The corpus that actually closes Pitfall 2's gate is therefore built
/// directly from `packages/contracts/openapi/keepling.yaml`'s own
/// required-field sets: every generated DTO `KeeplingSyncAdapter.swift`
/// sends or receives, decoded from a literal, committed wire-shaped
/// fixture, re-encoded, and decoded again for equality -- the only corpus
/// that CAN decode as a generated DTO, since the vector files provably
/// cannot.
final class DecodeRoundTripTests: XCTestCase {
    // MARK: - Shared decode/encode configuration matching the generated client's own Converter

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func roundTrip<T: Codable & Equatable>(_ type: T.Type, json: Data) throws -> T {
        let first = try decoder().decode(type, from: json)
        let reencoded = try encoder().encode(first)
        let second = try decoder().decode(type, from: reencoded)
        XCTAssertEqual(first, second, "\(type) did not round-trip to an equal value")
        return first
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - D-14's literal premise, verified false by direct structural inspection

    /// Enumerates every JSON object nested anywhere in all 13 vector files
    /// and attempts every candidate wire DTO's decoder against it. Fails
    /// LOUDLY (rather than silently passing on zero cases) if the count of
    /// generated-DTO-decodable objects found ever becomes nonzero without
    /// this test being updated -- that would mean a vector file grew a
    /// real wire payload this suite should start round-tripping directly.
    func testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads() throws {
        let vectorsDirectory = try RepositoryRoot.vectorsDirectory()
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: vectorsDirectory.path)
            .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }
            .sorted()
        XCTAssertEqual(files.count, 13, "expected 13 vector files, found \(files.count): \(files)")

        var objectsInspected = 0
        var decodableAsAWireDTO = 0

        for file in files {
            let data = try Data(contentsOf: vectorsDirectory.appendingPathComponent(file))
            let root = try JSONSerialization.jsonObject(with: data)
            walk(root) { object in
                objectsInspected += 1
                if self.decodesAsAnyWireDTO(object) {
                    decodableAsAWireDTO += 1
                }
            }
        }

        XCTAssertGreaterThan(objectsInspected, 0, "the walk found no nested JSON objects at all -- the walker is broken")
        XCTAssertEqual(
            decodableAsAWireDTO, 0,
            "found \(decodableAsAWireDTO) object(s) in packages/contracts/vectors/ that decode as a generated wire DTO -- " +
            "if this is no longer zero, the vector files have grown real wire payloads and " +
            "testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads's own premise (04-05-SUMMARY.md) needs updating, " +
            "and those payloads should be added to this suite's round-trip corpus"
        )
    }

    /// Recursively visits every `[String: Any]` object in a decoded JSON
    /// value (dictionaries and arrays), invoking `visit` on each.
    private func walk(_ value: Any, visit: ([String: Any]) -> Void) {
        if let object = value as? [String: Any] {
            visit(object)
            for nested in object.values { walk(nested, visit: visit) }
        } else if let array = value as? [Any] {
            for nested in array { walk(nested, visit: visit) }
        }
    }

    /// Tries the handful of REQUIRED-field-bearing generated DTOs this
    /// plan's scope cares about. A vector fixture object satisfying none
    /// of these required-field sets is exactly what direct inspection
    /// (04-05-SUMMARY.md) found for every one of the 13 files.
    private func decodesAsAnyWireDTO(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        let attempts: [(Data) -> Bool] = [
            { (try? self.decoder().decode(Components.Schemas.TaskSnapshot.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.SyncOrganizationSnapshot.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.CommandAcknowledgement.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.CaptureTaskCommand.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.SyncFeedEnvelope.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.Problem.self, from: $0)) != nil },
            { (try? self.decoder().decode(Components.Schemas.PersistedConflict.self, from: $0)) != nil },
        ]
        return attempts.contains { $0(data) }
    }

    // MARK: - The real corpus: literal wire-shaped fixtures round-trip

    func testCaptureTaskCommandRoundTrips() throws {
        let json = try jsonData([
            "mutation_id": "mutation-1", "task_id": "task-1", "title": "Call dentist", "type": "capture_task", "version": 1,
        ])
        let command = try roundTrip(Components.Schemas.CaptureTaskCommand.self, json: json)
        XCTAssertEqual(command.title, "Call dentist")
    }

    func testCommandAcknowledgementRoundTripsWithEveryOptionalFieldPresent() throws {
        let json = try jsonData([
            "mutation_id": "mutation-1",
            "outcome": "accepted",
            "revision": 3,
            "resolved_conflict_id": "conflict-1",
            "undo": ["expires_at": "2026-09-01T12:05:00Z", "handle": String(repeating: "a", count: 43), "label": "Undo capture"],
            "snapshot": [
                "captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "",
                "revision": 3, "tags": [], "title": "Call dentist",
            ],
            "task_id": "task-1",
            "warnings": [],
        ])
        let acknowledgement = try roundTrip(Components.Schemas.CommandAcknowledgement.self, json: json)
        XCTAssertEqual(acknowledgement.undo?.label, "Undo capture")
        XCTAssertEqual(acknowledgement.resolved_conflict_id, "conflict-1")
    }

    func testProblemRoundTripsForEveryRefusalShape() throws {
        let conflictProblem = try jsonData([
            "type": "about:blank", "title": "Conflict", "status": 409, "code": "task_edit_conflict",
            "retryable": false, "recovery_action": "reconcile",
            "conflict": ["fields": [["current": "Server title", "field": "title"]], "id": "conflict-1", "latest_revision": 5],
        ])
        _ = try roundTrip(Components.Schemas.Problem.self, json: conflictProblem)

        let rejectedProblem = try jsonData([
            "type": "about:blank", "title": "Rejected", "status": 422, "code": "title_required",
            "retryable": false, "recovery_action": "fix_and_resubmit",
        ])
        _ = try roundTrip(Components.Schemas.Problem.self, json: rejectedProblem)

        let authProblem = try jsonData([
            "type": "about:blank", "title": "Unauthorized", "status": 401, "code": "authentication_required",
            "retryable": false, "recovery_action": "sign_in_again",
        ])
        _ = try roundTrip(Components.Schemas.Problem.self, json: authProblem)
    }

    func testSyncFeedEnvelopeRoundTripsForEveryPayloadKind() throws {
        let taskSnapshot: [String: Any] = [
            "captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "",
            "revision": 1, "tags": [], "title": "Call dentist",
            "completed_at": NSNull(), "deadline_on": NSNull(), "planned_on": NSNull(),
            "project": NSNull(), "trashed_at": NSNull(),
        ]
        let organizationSnapshot: [String: Any] = ["id": "org-1", "kind": "project", "name": "Errands", "revision": 1]
        let acknowledgement: [String: Any] = [
            "mutation_id": "mutation-1", "outcome": "accepted", "revision": 1,
            "snapshot": ["captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "", "revision": 1, "tags": [], "title": "t"],
            "task_id": "task-1", "warnings": [],
        ]

        let cases: [(String, [String: Any])] = [
            ("command_outcome", ["result": acknowledgement, "status": 201]),
            ("task_snapshot", taskSnapshot),
            ("organization_snapshot", organizationSnapshot),
            ("conflict_snapshot", ["fields": [["current": "x", "field": "title"]], "id": "conflict-1", "latest_revision": 1]),
            ("collection_tombstone", ["collection": "task_project", "organization_id": "org-1", "task_id": "task-1"]),
            ("undo_metadata", ["expires_at": "2026-09-01T12:05:00Z", "label": "Undo capture"]),
        ]

        for (kind, payload) in cases {
            let envelope: [String: Any] = [
                "entity_id": "entity-1", "entity_revision": 1, "entity_type": "task",
                "inserted_at": "2026-09-01T12:00:00Z", "kind": kind, "mutation_id": "mutation-1",
                "ordinal": 0, "payload": payload, "sequence": 1,
            ]
            let decoded = try roundTrip(Components.Schemas.SyncFeedEnvelope.self, json: try jsonData(envelope))
            XCTAssertEqual(decoded.kind.rawValue, kind)
        }
    }

    /// D-13/T-04-05-01: a payload whose tag names `task_snapshot` decodes
    /// into the task variant and never falls through to a structurally
    /// overlapping sibling.
    ///
    /// The fixtures here mirror what the REAL server sends, field for
    /// field. They used to spell `tag_ids` and omit five required fields,
    /// which matched a `SyncTaskSnapshot` schema the server never produced
    /// -- so this test passed while the client could not decode a single
    /// real sync page (04-18-PLAN.md Task 3). A fixture that matches the
    /// schema rather than the server proves only that the schema is
    /// self-consistent.
    func testSyncFeedEnvelopeDiscriminatesTaskSnapshotIntoTheCorrectVariant() throws {
        let taskSnapshot: [String: Any] = [
            "captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "",
            "revision": 1, "tags": [], "title": "Call dentist",
            "completed_at": NSNull(), "deadline_on": NSNull(), "planned_on": NSNull(),
            "project": NSNull(), "trashed_at": NSNull(),
        ]
        let envelope: [String: Any] = [
            "entity_id": "task-1", "entity_revision": 1, "entity_type": "task",
            "inserted_at": "2026-09-01T12:00:00Z", "kind": "task_snapshot", "mutation_id": "mutation-1",
            "ordinal": 0, "payload": taskSnapshot, "sequence": 1,
        ]
        let decoded = try decoder().decode(Components.Schemas.SyncFeedEnvelope.self, from: try jsonData(envelope))
        guard case .TaskSnapshot = decoded.payload else {
            return XCTFail("expected .TaskSnapshot, got \(decoded.payload)")
        }
    }

    /// A payload tagged `task_snapshot` whose body is malformed -- missing
    /// EVERY variant's required fields -- must fail to decode rather than
    /// silently falling through to a structurally overlapping sibling
    /// (T-04-05-01).
    func testSyncFeedEnvelopeRejectsAMalformedTaskSnapshotBodyRatherThanFallingThrough() throws {
        let malformedBody: [String: Any] = ["not_a_real_field": true]
        let envelope: [String: Any] = [
            "entity_id": "task-1", "entity_revision": 1, "entity_type": "task",
            "inserted_at": "2026-09-01T12:00:00Z", "kind": "task_snapshot", "mutation_id": "mutation-1",
            "ordinal": 0, "payload": malformedBody, "sequence": 1,
        ]
        XCTAssertThrowsError(try decoder().decode(Components.Schemas.SyncFeedEnvelope.self, from: try jsonData(envelope)))
    }

    func testSyncBootstrapPageRoundTrips() throws {
        let entity: [String: Any] = [
            "entity_id": "task-1", "entity_type": "task", "kind": "task_snapshot",
            "snapshot": [
                "captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "",
                "revision": 1, "tags": [], "title": "Call dentist",
                "completed_at": NSNull(), "deadline_on": NSNull(), "planned_on": NSNull(),
                "project": NSNull(), "trashed_at": NSNull(),
            ],
        ]
        let page: [String: Any] = ["entities": [entity], "high_water": ["ordinal": 0, "sequence": 1], "next_cursor": "cursor-1"]
        _ = try roundTrip(Components.Schemas.SyncBootstrapPage.self, json: try jsonData(page))
    }

    func testUndoResultRoundTripsForBothOneOfCases() throws {
        let acknowledgementBody = try jsonData([
            "mutation_id": "mutation-1", "outcome": "accepted", "revision": 1,
            "snapshot": ["captured_at": "2026-09-01T12:00:00Z", "id": "task-1", "inbox_state": "inbox", "notes": "", "revision": 1, "tags": [], "title": "t"],
            "task_id": "task-1", "warnings": [],
        ])
        let decodedAcknowledgement = try decoder().decode(Components.Schemas.UndoResult.self, from: acknowledgementBody)
        guard case .CommandAcknowledgement = decodedAcknowledgement else { return XCTFail("expected .CommandAcknowledgement") }

        let noChangeBody = try jsonData([
            "code": "undo_expired", "mutation_id": "mutation-1", "outcome": "expired", "retryable": false, "title": "Undo expired",
        ])
        let decodedNoChange = try decoder().decode(Components.Schemas.UndoResult.self, from: noChangeBody)
        guard case .UndoNoChange = decodedNoChange else { return XCTFail("expected .UndoNoChange") }
    }

    // MARK: - Nullable-field coverage (Pitfall 2)

    /// Decodes every fixture in the committed `Fixtures/nullable-coverage.json`,
    /// each carrying an EXPLICIT JSON `null` for the field(s) its own
    /// `nullFields` entry names -- proving the generator's nullable-decode
    /// path (upstream issue #286, closed by D-13's `Nullable<Base>`
    /// pattern) actually works for every field this plan's scope reaches,
    /// rather than assuming it from a passing round-trip suite that never
    /// happened to exercise a null.
    func testEveryNullableFieldFixtureDecodesItsExplicitNull() throws {
        let fixturesURL = try RepositoryRoot.resolve()
            .appendingPathComponent("apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json")
        let data = try Data(contentsOf: fixturesURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let fixtures = root?["fixtures"] as? [[String: Any]] else {
            return XCTFail("nullable-coverage.json has no fixtures array")
        }
        XCTAssertGreaterThan(fixtures.count, 0, "nullable-coverage.json declares zero fixtures")

        for fixture in fixtures {
            guard let name = fixture["name"] as? String,
                  let decodesAs = fixture["decodesAs"] as? String,
                  let json = fixture["json"] as? [String: Any]
            else {
                XCTFail("malformed fixture entry: \(fixture)")
                continue
            }
            let data = try jsonData(json)
            switch decodesAs {
            case "TaskSnapshot": _ = try attemptDecode(Components.Schemas.TaskSnapshot.self, data, name)
            case "SyncFeedEnvelope": _ = try attemptDecode(Components.Schemas.SyncFeedEnvelope.self, data, name)
            case "SyncFeedPage": _ = try attemptDecode(Components.Schemas.SyncFeedPage.self, data, name)
            case "SyncBootstrapPage": _ = try attemptDecode(Components.Schemas.SyncBootstrapPage.self, data, name)
            case "Problem": _ = try attemptDecode(Components.Schemas.Problem.self, data, name)
            case "ConflictField": _ = try attemptDecode(Components.Schemas.ConflictField.self, data, name)
            case "CommandAcknowledgement": _ = try attemptDecode(Components.Schemas.CommandAcknowledgement.self, data, name)
            default: XCTFail("fixture \(name) names an unknown decodesAs: \(decodesAs)")
            }
        }
    }

    @discardableResult
    private func attemptDecode<T: Decodable>(_ type: T.Type, _ data: Data, _ fixtureName: String) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            XCTFail("fixture '\(fixtureName)' failed to decode as \(type): \(error)")
            throw error
        }
    }
}
