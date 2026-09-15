import XCTest
@testable import KeeplingCore

/// D-14: "a decode round-trip test over every wire payload appearing in the
/// 13 vector files, so a generator regression fails a test rather than
/// failing on a phone" -- and 04-RESEARCH.md Pitfall 2's own warning that
/// such a suite "only catches the defect if the vector files actually
/// contain a null value for every nullable field, which should be
/// spot-checked, not assumed."
///
/// EXPIRED DEVIATION -- READ THIS BEFORE RE-DERIVING THE OLD ONE.
/// 04-05-SUMMARY.md disclosed a deviation from D-14 on the ground that
/// D-14's premise was false: `packages/contracts/vectors/`'s then-13
/// files held no wire payload OBJECT decodable by the generated Swift
/// client. Every file was an ABSTRACT domain-reducer fixture -- e.g.
/// `sync.json`'s `{id, revision, title}` snapshot omits
/// `SyncTaskSnapshot`'s required `captured_at`/`inbox_state`/`notes`/
/// `tags`/`trashed_at` -- never a contract-conformant object satisfying
/// any generated DTO's `additionalProperties: false` + `required` set.
/// That deviation shipped with a TRIPWIRE rather than a comment:
/// a test that walked every object in every vector file and FAILED if the
/// decodable count ever stopped being zero.
///
/// THE TRIPWIRE FIRED, on the first CI run that ever executed this lane
/// (34897943904). `mcp-tools.json`, added by 05-11, carries 6 genuinely
/// contract-conformant objects: 2 `CaptureTaskCommand` and 4 `Problem`.
/// So D-14's premise is no longer false, and the deviation taken from it
/// no longer has a premise to stand on. The honest response is to do what
/// D-14 asked for in the first place -- "a decode round-trip test over
/// every wire payload appearing in the vector files" -- NOT to raise the
/// tripwire's threshold from 0 to 6, which would silence the one check
/// that noticed, and would leave the new payloads untested precisely
/// because they are new.
///
/// Two corpora therefore run here, and both must stay non-empty:
///   1. the literal fixtures below, built directly from
///      `packages/contracts/openapi/keepling.yaml`'s own required-field
///      sets, covering every DTO `KeeplingSyncAdapter.swift` sends or
///      receives whether or not any vector file happens to contain one;
///   2. every wire payload discovered IN the vector files, round-tripped
///      where it lies, so a generator regression fails a test rather than
///      failing on a phone.
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

    // MARK: - D-14 proper: every wire payload IN the vector files round-trips

    /// Enumerates every JSON object nested anywhere in every vector file
    /// and round-trips the ones that decode as a generated wire DTO,
    /// in place, where they lie.
    ///
    /// This replaces the tripwire described in the type doc comment above.
    /// That test asserted the decodable count was exactly ZERO and existed
    /// to fail the moment a vector file grew a real wire payload. It did
    /// exactly that on CI run 34897943904 -- 6 objects, all in
    /// `mcp-tools.json` -- so it has done its job and is now replaced by
    /// the coverage it was holding a place for.
    ///
    /// D-24: the assertions below are deliberately BOTH-SIDED. A file
    /// count that drifts fails, so new vectors force a look at this test
    /// rather than sliding in unexamined. A decodable count of zero ALSO
    /// fails, so this test can never go quiet by finding nothing to do --
    /// which is the exact shape (a check that passes without observing
    /// anything) that this phase exists to remove, and which a naive
    /// "walk the files and round-trip whatever turns up" would have.
    func testEveryWireDTOPayloadInTheVectorFilesRoundTrips() throws {
        let vectorsDirectory = try RepositoryRoot.vectorsDirectory()
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: vectorsDirectory.path)
            .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }
            .sorted()
        XCTAssertEqual(files.count, 16, "expected 16 vector files, found \(files.count): \(files)")

        var objectsInspected = 0
        var roundTrippedByDTO: [String: Int] = [:]
        var carryingFiles: Set<String> = []

        for file in files {
            let data = try Data(contentsOf: vectorsDirectory.appendingPathComponent(file))
            let root = try JSONSerialization.jsonObject(with: data)
            var objects: [[String: Any]] = []
            walk(root) { object in
                objectsInspected += 1
                objects.append(object)
            }
            for object in objects {
                if let dto = try roundTripAsWireDTO(object) {
                    roundTrippedByDTO[dto, default: 0] += 1
                    carryingFiles.insert(file)
                }
            }
        }

        let roundTripped = roundTrippedByDTO.values.reduce(0, +)
        XCTAssertGreaterThan(objectsInspected, 0, "the walk found no nested JSON objects at all -- the walker is broken")
        XCTAssertGreaterThan(
            roundTripped, 0,
            "no object in packages/contracts/vectors/ decoded as ANY generated wire DTO. Before 05-11 that was the " +
            "documented truth and this test did not exist; now it means either the vectors lost their wire payloads " +
            "or the generated DTOs stopped matching them. Both are regressions, and neither may pass silently."
        )
        print(
            "vector wire-payload round-trip corpus: \(roundTripped) payload(s) across " +
            "\(carryingFiles.sorted().joined(separator: ", ")) -- " +
            "\(roundTrippedByDTO.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
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

    /// Tries the REQUIRED-field-bearing generated DTOs this plan's scope
    /// cares about against `object` and, for the first that decodes,
    /// drives it through a full decode/encode/decode round trip. Returns
    /// the DTO's name, or nil when `object` is not a wire payload at all
    /// -- which is still true of the overwhelming majority of objects in
    /// the vector files, and was true of ALL of them before 05-11.
    ///
    /// Attempt order is load-bearing and deliberately unchanged from the
    /// version of this method that only counted: reordering it would
    /// silently re-label which DTO a structurally ambiguous object is
    /// reported as.
    private func roundTripAsWireDTO(_ object: [String: Any]) throws -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        if (try? decoder().decode(Components.Schemas.TaskSnapshot.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.TaskSnapshot.self, json: data)
            return "TaskSnapshot"
        }
        if (try? decoder().decode(Components.Schemas.SyncOrganizationSnapshot.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.SyncOrganizationSnapshot.self, json: data)
            return "SyncOrganizationSnapshot"
        }
        if (try? decoder().decode(Components.Schemas.CommandAcknowledgement.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.CommandAcknowledgement.self, json: data)
            return "CommandAcknowledgement"
        }
        if (try? decoder().decode(Components.Schemas.CaptureTaskCommand.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.CaptureTaskCommand.self, json: data)
            return "CaptureTaskCommand"
        }
        if (try? decoder().decode(Components.Schemas.SyncFeedEnvelope.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.SyncFeedEnvelope.self, json: data)
            return "SyncFeedEnvelope"
        }
        if (try? decoder().decode(Components.Schemas.Problem.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.Problem.self, json: data)
            return "Problem"
        }
        if (try? decoder().decode(Components.Schemas.PersistedConflict.self, from: data)) != nil {
            _ = try roundTrip(Components.Schemas.PersistedConflict.self, json: data)
            return "PersistedConflict"
        }
        return nil
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
