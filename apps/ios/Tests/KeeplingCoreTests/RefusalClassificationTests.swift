import XCTest
import HTTPTypes
import OpenAPIRuntime
@testable import KeeplingCore

/// A test seam for `ClientTransport` (the officially documented mechanism
/// for driving a generated `swift-openapi-generator` client without a real
/// network -- see `OpenAPIRuntime.ClientTransport`'s own doc comment for a
/// `TestTransport` example this mirrors). Keyed by `operationID` rather
/// than URL matching, since every operation in this plan's scope has
/// exactly one canned response per test.
final class StubTransport: ClientTransport, @unchecked Sendable {
    struct Canned {
        let status: Int
        let contentType: String
        let body: Data
    }

    var responses: [String: Canned] = [:]
    var thrownErrors: [String: any Error] = [:]

    func stubJSON<T: Encodable>(operationID: String, status: Int, value: T, contentType: String = "application/json") {
        // The generated client's own `Converter` decodes dates via
        // `DateTranscoder.iso8601` by default -- match it here so a stub
        // fixture round-trips the same way a real server response would.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(value)
        responses[operationID] = Canned(status: status, contentType: contentType, body: data)
    }

    func stubProblem(operationID: String, status: Int, code: String, conflict: Components.Schemas.PersistedConflict? = nil) {
        let problem = Components.Schemas.Problem(
            _type: "about:blank",
            title: "refused",
            status: status,
            code: code,
            retryable: false,
            recovery_action: "none",
            conflict: conflict
        )
        stubJSON(operationID: operationID, status: status, value: problem, contentType: "application/problem+json")
    }

    func send(
        _ request: HTTPRequest,
        body: OpenAPIRuntime.HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, OpenAPIRuntime.HTTPBody?) {
        if let error = thrownErrors[operationID] { throw error }
        guard let canned = responses[operationID] else {
            XCTFail("no stub registered for operation \(operationID)")
            throw URLError(.unknown)
        }
        var response = HTTPResponse(status: .init(code: canned.status))
        response.headerFields[.contentType] = canned.contentType
        return (response, OpenAPIRuntime.HTTPBody(canned.body))
    }
}

/// T-04-05-03/T-04-05-06/T-04-05-07: proves the ONE boundary that tells an
/// unheard answer from a decided one, and that the closed settleable-
/// refusal set is exactly the set 04-05-PLAN.md names -- reproduced from
/// `apps/desktop/main/adapters/server-refusal.ts`.
final class RefusalClassificationTests: XCTestCase {
    private func makeAdapter(_ transport: StubTransport) throws -> KeeplingSyncAdapter {
        try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!, transport: transport)
    }

    private func mutation() -> LocalMutation {
        LocalMutation(
            mutationId: "mutation-1",
            taskId: "task-1",
            commandBytes: #"{"mutation_id":"mutation-1","task_id":"task-1","title":"Call dentist","type":"capture_task","version":1}"#,
            fingerprint: "fingerprint-1",
            acceptedAt: "2026-09-01T00:00:00.000000Z",
            resourceKeys: ["task:task-1"],
            title: "Call dentist"
        )
    }

    // MARK: - Unreachable vs refused (T-04-05-03)

    func testAThrownURLSessionErrorProducesUnreachableNeverARefusal() async throws {
        let transport = StubTransport()
        transport.thrownErrors["captureTask"] = URLError(.notConnectedToInternet)
        let adapter = try makeAdapter(transport)

        do {
            _ = try await adapter.push(mutation())
            XCTFail("expected SyncUnreachable")
        } catch is SyncUnreachable {
            // expected
        } catch {
            XCTFail("expected SyncUnreachable, got \(error)")
        }
    }

    func testAnAnsweredNonOKResponseIsNeverUnreachable() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 422, code: "title_required")
        let adapter = try makeAdapter(transport)

        do {
            let acknowledgement = try await adapter.push(mutation())
            XCTAssertEqual(acknowledgement.outcome, .rejected)
        } catch is SyncUnreachable {
            XCTFail("an answered 422 must never classify as unreachable")
        }
    }

    // MARK: - Closed conflict set (409)

    func testEachOfTheFourConflictCodesSettlesAsAConflictAcknowledgement() async throws {
        for code in ServerRefusal.conflictCodes {
            let transport = StubTransport()
            let conflict = Components.Schemas.PersistedConflict(
                fields: [.init(current: "Current title", field: .title)],
                id: "conflict-1",
                latest_revision: 5
            )
            transport.stubProblem(operationID: "captureTask", status: 409, code: code, conflict: conflict)
            let adapter = try makeAdapter(transport)

            let acknowledgement = try await adapter.push(mutation())
            XCTAssertEqual(acknowledgement.outcome, .conflict, "code \(code) did not settle as .conflict")
            XCTAssertEqual(acknowledgement.mutationId, "mutation-1")
            XCTAssertEqual(acknowledgement.fingerprint, "fingerprint-1", "fingerprint must be the CALLER's stored value, never re-derived")

            let snapshot = try JSONSerialization.jsonObject(with: Data(acknowledgement.snapshotJSON.utf8)) as? [String: Any]
            XCTAssertEqual(snapshot?["title"] as? String, "Current title")
            XCTAssertEqual(snapshot?["conflict_id"] as? String, "conflict-1")
            // T-04-05-05: a 409 settlement carries ONLY the server's own
            // affected-field values -- never local fields the server did
            // not return (e.g. `notes`), which would silently replay the
            // canonical shadow over a person's unsent edit.
            XCTAssertNil(snapshot?["notes"], "conflict snapshot must never carry a field the server did not return")
        }
    }

    func testA409WithACodeOutsideTheConflictSetKeepsThrowing() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 409, code: "some_unrelated_409_code")
        let adapter = try makeAdapter(transport)

        do {
            _ = try await adapter.push(mutation())
            XCTFail("expected SyncPortRefused")
        } catch let error as SyncPortRefused {
            XCTAssertEqual(error.status, 409)
        } catch {
            XCTFail("expected SyncPortRefused, got \(error)")
        }
    }

    // MARK: - Every 422 is rejected

    func testEvery422SettlesAsRejected() async throws {
        for code in ["title_required", "notes_too_long", "no_fields_touched", "base_values_mismatch", "invalid_task_details", "invalid_timezone"] {
            let transport = StubTransport()
            transport.stubProblem(operationID: "captureTask", status: 422, code: code)
            let adapter = try makeAdapter(transport)

            let acknowledgement = try await adapter.push(mutation())
            XCTAssertEqual(acknowledgement.outcome, .rejected, "422 code \(code) did not settle as .rejected")
            let snapshot = try JSONSerialization.jsonObject(with: Data(acknowledgement.snapshotJSON.utf8)) as? [String: Any]
            XCTAssertEqual(snapshot?["rejection_code"] as? String, code)
        }
    }

    // MARK: - invalid_command / task_not_found

    func testInvalidCommandAt400SettlesAsRejected() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 400, code: "invalid_command")
        let adapter = try makeAdapter(transport)

        let acknowledgement = try await adapter.push(mutation())
        XCTAssertEqual(acknowledgement.outcome, .rejected)
    }

    func testTaskNotFoundAt404SettlesAsRejected() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 400, code: "task_not_found")
        let adapter = try makeAdapter(transport)

        let acknowledgement = try await adapter.push(mutation())
        XCTAssertEqual(acknowledgement.outcome, .rejected)
    }

    // MARK: - 401 is its own tagged state (T-04-05-06)

    func testA401ProducesADistinctAuthenticationRequiredStateNeverAnAcknowledgement() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 401, code: "authentication_required")
        let adapter = try makeAdapter(transport)

        do {
            _ = try await adapter.push(mutation())
            XCTFail("expected SyncAuthenticationRequired")
        } catch let error as SyncAuthenticationRequired {
            XCTAssertEqual(error.code, "authentication_required")
        } catch {
            XCTFail("expected SyncAuthenticationRequired, got \(error) -- a 401 must never become a per-mutation rejection")
        }
    }

    // MARK: - Anything unlisted keeps throwing (T-04-05-07)

    func testA403KeepsThrowingRatherThanBeingSettled() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 403, code: "forbidden")
        let adapter = try makeAdapter(transport)

        do {
            _ = try await adapter.push(mutation())
            XCTFail("expected SyncPortRefused")
        } catch let error as SyncPortRefused {
            XCTAssertEqual(error.status, 403)
        } catch {
            XCTFail("expected SyncPortRefused, got \(error)")
        }
    }

    func testA503KeepsThrowingRatherThanBeingSettled() async throws {
        let transport = StubTransport()
        transport.stubProblem(operationID: "captureTask", status: 503, code: "service_unavailable")
        let adapter = try makeAdapter(transport)

        do {
            _ = try await adapter.push(mutation())
            XCTFail("expected SyncPortRefused")
        } catch let error as SyncPortRefused {
            XCTAssertEqual(error.status, 503)
        } catch {
            XCTFail("expected SyncPortRefused, got \(error)")
        }
    }

    // MARK: - The accepted path (sanity: still routes through the mapper)

    func testAcceptedResponseSettlesWithTheCallersFingerprintNotAWireValue() async throws {
        let transport = StubTransport()
        let acknowledgement = Components.Schemas.CommandAcknowledgement(
            mutation_id: "mutation-1",
            outcome: .accepted,
            revision: 1,
            snapshot: TaskSnapshotFixture.make(),
            task_id: "task-1",
            warnings: []
        )
        transport.stubJSON(operationID: "captureTask", status: 201, value: acknowledgement)
        let adapter = try makeAdapter(transport)

        let result = try await adapter.push(mutation())
        XCTAssertEqual(result.outcome, .accepted)
        XCTAssertEqual(result.fingerprint, "fingerprint-1")
    }
}

/// Shared minimal `TaskSnapshot` fixture builder -- every field the schema
/// requires, with every optional left absent so callers can override only
/// what a given test cares about.
enum TaskSnapshotFixture {
    static func make(
        title: String = "Call dentist",
        completedAt: Date? = nil,
        trashedAt: Date? = nil
    ) -> Components.Schemas.TaskSnapshot {
        Components.Schemas.TaskSnapshot(
            captured_at: Date(timeIntervalSince1970: 0),
            completed_at: completedAt,
            id: "task-1",
            inbox_state: .inbox,
            notes: "",
            revision: 1,
            tags: [],
            title: title,
            trashed_at: trashedAt
        )
    }
}
