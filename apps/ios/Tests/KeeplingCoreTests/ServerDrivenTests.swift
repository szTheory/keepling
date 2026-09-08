import XCTest
import GRDB
@testable import KeeplingCore

/// The SERVER-DRIVEN half of D-22 Criterion 2, driven through the REAL
/// Swift client (04-18-PLAN.md Task 3).
///
/// WHAT WAS ACTUALLY MISSING
/// -------------------------
/// These four scenarios -- authentication expiry, account fencing,
/// duplicate replay, structured conflict -- were already proven against
/// real Phoenix on real PostgreSQL. They were proven by a Node `fetch`
/// client written thirty lines above the assertions in
/// `tooling/verify-real-stack-ios.mjs`. Not one byte of
/// `KeeplingSyncAdapter`, `SyncReducer`, or the GRDB outbox participated.
///
/// Underneath that, `KeeplingSyncAdapter` could not authenticate AT ALL:
/// it built its generated `Client` with no middlewares and no credential,
/// while the server requires `Authorization: Bearer` for a native client.
/// That is why `SyncPassTests.testRealStackSettlesAPushedCapture` has been
/// skipping since 04-08, and why every other sync test in this repository
/// uses a stubbed `SyncPort` or a fake `ClientTransport`. The gap was never
/// really about the phone, and never really about TLS.
///
/// So this suite runs the genuine adapter -- default `URLSessionTransport`,
/// no injected transport, no trust override anywhere -- against the real
/// server behind the recording proxy, and asserts what the SERVER did.
///
/// IT MUST FAIL, NOT SKIP
/// ----------------------
/// `SyncPassTests` skips when its real-stack variable is unset, and that is
/// correct there: it is an opt-in extra inside a suite with other coverage.
/// This suite exists ONLY to prove the server-driven half. A skip here
/// would report green for a run that proved nothing -- exactly the vacuity
/// D-24 forbids, and exactly the shape that produced hollow G7 evidence
/// twice already in this phase. So a missing lane environment is a FAILURE.
final class ServerDrivenTests: XCTestCase {
    // MARK: - Lane environment

    private struct LaneEnvironment {
        /// The proxy ORIGIN (`http://host:port`). Used for harness calls --
        /// the control channel and reading the server's inbox back.
        let origin: URL
        /// What the ADAPTER is given.
        ///
        /// MEASURED, and a trap worth naming: the contract declares
        /// `servers: [{ url: /api/v1 }]` and every path is relative to it, so
        /// the generated `Client`'s `serverURL` must ALREADY include
        /// `/api/v1`. Handing it a bare origin produces a 404 on every
        /// endpoint -- which reads as "the server does not have this route"
        /// rather than "the base URL is missing its prefix".
        ///
        /// `KeeplingApp` passes `KEEPLING_SERVER_URL` straight into this
        /// constructor, so the same requirement holds for the app itself, and
        /// it is documented in no README and exercised by no other test.
        let apiURL: URL
        let bearer: String
        let revokedBearer: String
    }

    private func laneEnvironment(_ function: StaticString = #function) throws -> LaneEnvironment {
        let environment = ProcessInfo.processInfo.environment
        guard
            let raw = environment["KEEPLING_LANE_BASE_URL"], !raw.isEmpty,
            let origin = URL(string: raw),
            let bearer = environment["KEEPLING_LANE_BEARER"], !bearer.isEmpty,
            let revoked = environment["KEEPLING_LANE_REVOKED_BEARER"], !revoked.isEmpty
        else {
            XCTFail(
                "\(function) had no lane environment (KEEPLING_LANE_BASE_URL / KEEPLING_LANE_BEARER / " +
                "KEEPLING_LANE_REVOKED_BEARER). This suite proves the server-driven half of D-22 Criterion 2 " +
                "and nothing else, so it FAILS rather than skipping: a skip would publish a green run that " +
                "proved nothing."
            )
            throw LaneUnavailable()
        }
        return LaneEnvironment(
            origin: origin,
            apiURL: origin.appendingPathComponent("api/v1"),
            bearer: bearer,
            revokedBearer: revoked
        )
    }

    private struct LaneUnavailable: Error {}

    /// Arms one server-side fault for the NEXT matching request.
    ///
    /// This is the test coordinating the harness, not manufacturing the
    /// evidence. The proxy adds the fault header to the FORWARDED request
    /// and real Phoenix produces the real refusal; nothing here answers on
    /// the server's behalf. Control paths are reserved under `/__lane/`,
    /// are never forwarded upstream, and are never recorded as arrivals.
    private func arm(_ fault: String, path: String, on lane: LaneEnvironment) async throws {
        var components = URLComponents(url: lane.origin.appendingPathComponent("__lane/arm"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fault", value: fault),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "times", value: "1"),
        ]
        let (_, response) = try await URLSession.shared.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(status, 200, "the lane control channel refused to arm \(fault)")
    }

    // MARK: - Helpers

    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("server-driven-test.sqlite").path
    }

    private func offMain<T>(_ work: @escaping () throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        DispatchQueue.global().async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    private func toLocalMutation(_ built: OutboundCommands.Built, acceptedAt: String = "2026-09-08T00:00:00Z") -> LocalMutation {
        LocalMutation(
            mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
            fingerprint: built.fingerprint, acceptedAt: acceptedAt, resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: .init(notes: built.effect.notes, completedAt: built.effect.completedAt, trashedAt: built.effect.trashedAt, planned: built.effect.planned)
        )
    }

    /// The genuine adapter: default `URLSessionTransport`, no injected
    /// transport, only the credential seam the app itself uses.
    private func adapter(for lane: LaneEnvironment, credential: String) throws -> KeeplingSyncAdapter {
        try KeeplingSyncAdapter(baseURL: lane.apiURL, credentialProvider: { credential })
    }

    // MARK: - 1. Authentication expiry

    func testAuthenticationExpiryIsSettledAndNotReturnedToQueued() async throws {
        let lane = try laneEnvironment()
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(
            title: "Captured while authentication expired", mutationId: UUID().uuidString, taskId: UUID().uuidString
        )
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        try await arm("authentication_before_acceptance", path: "/api/v1/commands/", on: lane)

        let application = KeeplingApplication(store: store, syncPort: try adapter(for: lane, credential: lane.bearer))
        let outcome = try await application.runSyncPass()

        XCTAssertEqual(
            outcome, .authenticationRequired,
            "a real 401 from the real server must surface as authenticationRequired, not as a generic failure"
        )
        // D-52's rule is `queued -> in_flight -> settled/uncertain`, never
        // BACK to queued. A mutation still sitting in `queued` is correct
        // here and must not be asserted against: a sync pass pulls before it
        // pushes, so a 401 on the pull leg ends the pass before this
        // mutation is ever claimed. What would be wrong is leaving it
        // stranded `in_flight` -- claimed, unsettled, and unclaimable by any
        // later pass, which is how an outbox silently stops draining.
        let state = try offMain { try store.outboxState(forMutationId: capture.mutationId) }
        XCTAssertNotEqual(state, "in_flight", "an authentication refusal stranded the mutation in `in_flight`")
    }

    // MARK: - 2. Account fencing

    func testAFencedCredentialBuysNothingFromTheRealServer() async throws {
        let lane = try laneEnvironment()
        let store = try GRDBLocalStore(path: storePath())
        let capture = try OutboundCommands.capture(
            title: "Captured behind the fence", mutationId: UUID().uuidString, taskId: UUID().uuidString
        )
        _ = try offMain { try store.acceptMutation(self.toLocalMutation(capture)) }

        // A REVOKED device grant, revoked by the real server through its own
        // revocation endpoint before this test ran. Not a malformed token,
        // not an empty header: the exact credential a signed-out or remotely
        // revoked phone still holds on disk.
        let application = KeeplingApplication(
            store: store, syncPort: try adapter(for: lane, credential: lane.revokedBearer)
        )
        let outcome = try await application.runSyncPass()

        XCTAssertEqual(
            outcome, .authenticationRequired,
            "a revoked device grant was not refused -- a fenced credential bought a real push"
        )
        let state = try offMain { try store.outboxState(forMutationId: capture.mutationId) }
        XCTAssertNotEqual(state, "in_flight", "a fenced refusal stranded the mutation in `in_flight`")
    }

    // MARK: - 3. Duplicate replay

    func testAByteIdenticalReplayIsAcceptedOnceByTheRealServer() async throws {
        let lane = try laneEnvironment()
        let taskId = UUID().uuidString
        let capture = try OutboundCommands.capture(
            title: "Replayed capture \(taskId)", mutationId: UUID().uuidString, taskId: taskId
        )
        let port = try adapter(for: lane, credential: lane.bearer)

        // The EXACT stored bytes, pushed twice. This is what a restored
        // device backup does, and the bug worth catching is a duplicate the
        // client believes it suppressed but the server accepted twice --
        // which is why the second assertion reads the SERVER's inbox rather
        // than either acknowledgement.
        let mutation = toLocalMutation(capture)
        let first = try await port.push(mutation)
        let second = try await port.push(mutation)

        XCTAssertEqual(first.fingerprint, second.fingerprint, "the replay was fingerprinted differently")
        // Compare the REVISION, not the raw snapshot text. `snapshotJSON` is
        // serialized from a dictionary, so its key order is not stable across
        // two encodes of identical content, and asserting on the string
        // compares the encoder's whim rather than the server's behaviour.
        // The claim being made is "the second delivery performed no work",
        // and the revision is what carries that claim.
        XCTAssertEqual(
            revision(of: first.snapshotJSON), revision(of: second.snapshotJSON),
            "the replay advanced the revision -- it was accepted twice"
        )

        // Read back through the SYNC FEED, using the same adapter and the
        // same device-grant credential the app uses.
        //
        // Not `/api/v1/inbox`: that route is session-authenticated
        // (`load_session`/`require_authenticated`/`protect_from_forgery`),
        // so a bearer credential is correctly refused there. Only
        // `/sync`, `/sync/bootstrap` and `/device-grants` accept a device
        // grant. Reading through the feed is also the better evidence --
        // it is the surface the client actually consumes.
        //
        // A byte-identical replay returns the original receipt verbatim and
        // performs no work, so it must add NO second snapshot for this task.
        let page = try await port.pull(cursor: nil)
        // Case-insensitive on purpose: Swift's `UUID().uuidString` is
        // UPPERCASE and the server echoes identifiers lowercased, so an
        // `==` comparison between a locally generated id and one read back
        // from the server never matches. Worth knowing beyond this test --
        // any reconciliation that compares the two forms directly has the
        // same trap waiting in it.
        let snapshots = page.changes.filter { $0.entityId.caseInsensitiveCompare(taskId) == .orderedSame }.count
        XCTAssertEqual(
            snapshots, 1,
            "the real server's feed holds \(snapshots) snapshots for the replayed task -- exactly one was required"
        )
    }

    // MARK: - 4. Structured conflict

    func testAStaleExpectedRevisionIsAnsweredAsAStructuredConflict() async throws {
        let lane = try laneEnvironment()
        let taskId = UUID().uuidString
        let port = try adapter(for: lane, credential: lane.bearer)

        let capture = try OutboundCommands.capture(title: "Conflict subject", mutationId: UUID().uuidString, taskId: taskId)
        _ = try await port.push(toLocalMutation(capture))

        // Advance the task once so revision 1 is genuinely stale.
        let basis = OutboundCommands.Basis(baseTitle: "Conflict subject", baseNotes: "", expectedRevision: 1)
        let advance = try OutboundCommands.edit(taskId: taskId, touched: .init(notes: "advanced"), basis: basis, mutationId: UUID().uuidString)
        _ = try await port.push(toLocalMutation(advance))

        // A SECOND writer still holding revision 1 -- exactly the divergence
        // a phone that was offline produces. The 409 comes from the server's
        // own concurrency check, not from anything this test arranged.
        let stale = try OutboundCommands.edit(
            taskId: taskId, touched: .init(notes: "written from a stale basis"), basis: basis, mutationId: UUID().uuidString
        )
        let acknowledgement = try await port.push(toLocalMutation(stale))

        XCTAssertEqual(
            acknowledgement.outcome, .conflict,
            "a stale expected_revision settled \(acknowledgement.outcome), not conflict"
        )
    }

    /// Reads `revision` out of a settled acknowledgement's snapshot.
    private func revision(of snapshotJSON: String) -> Int? {
        guard
            let data = snapshotJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["revision"] as? Int
    }

}
