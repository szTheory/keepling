import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Errors specific to this adapter's own request/response construction,
/// distinct from `SyncUnreachable` (transport failure) and
/// `SyncPortRefused` (an answered refusal outside the closed settleable
/// set).
public enum SyncPortError: Error, Equatable {
    case mutationMismatch
    /// The lookup endpoint answered with an `UndoNoChange` body for a
    /// mutation this adapter did not ask an undo question about -- out of
    /// this plan's scope (undo settlement is Plan 04-06's concern).
    case unexpectedUndoNoChange
}

/// URLSession-backed `SyncPort` over the committed generated client
/// (04-PATTERNS.md `KeeplingSyncAdapter` analog,
/// `apps/desktop/main/adapters/sync.ts`). Reimplements the desktop's
/// HTTPS-only guard identically: a non-HTTPS base URL is rejected unless
/// the host is `127.0.0.1` or `localhost` (T-04-01-03/T-04-05-04).
public final class KeeplingSyncAdapter: SyncPort, @unchecked Sendable {
    private let client: Client

    public enum ConfigurationError: Error, Equatable {
        case insecureBaseURL
    }

    public init(baseURL: URL, transport: any ClientTransport = URLSessionTransport()) throws {
        guard baseURL.scheme == "https" || baseURL.host == "127.0.0.1" || baseURL.host == "localhost" else {
            throw ConfigurationError.insecureBaseURL
        }
        client = Client(serverURL: baseURL, transport: transport)
    }

    // MARK: - push

    /// Pushes one durable `capture_task` mutation's exact bytes and returns
    /// the settled acknowledgement. O-30/O-38: a thrown `URLSession` error
    /// (DNS/connection/TLS/timeout) is reclassified as `SyncUnreachable`
    /// and NEVER reaches the switch below; everything below ran because
    /// the server ANSWERED.
    public func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
        let command = Components.Schemas.CaptureTaskCommand(
            mutation_id: mutation.mutationId,
            task_id: mutation.taskId,
            title: mutation.title,
            _type: .capture_task,
            version: ._1
        )

        let output: Operations.captureTask.Output
        do {
            output = try await client.captureTask(.init(body: .json(command)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }

        switch output {
        case .created(let created):
            guard case .json(let acknowledgement) = created.body else {
                throw SyncPortError.mutationMismatch
            }
            guard acknowledgement.mutation_id == mutation.mutationId else {
                throw SyncPortError.mutationMismatch
            }
            return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
        case .badRequest(let response):
            return try settleOrThrow(status: 400, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .unauthorized(let response):
            return try settleOrThrow(status: 401, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .forbidden(let response):
            return try settleOrThrow(status: 403, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .conflict(let response):
            return try settleOrThrow(status: 409, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .unprocessableContent(let response):
            return try settleOrThrow(status: 422, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .serviceUnavailable(let response):
            return try settleOrThrow(status: 503, response: response, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
        case .undocumented(let statusCode, _):
            throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - pull

    public func pull(cursor: String?) async throws -> SyncPullPage {
        let output: Operations.pullSyncPage.Output
        do {
            output = try await client.pullSyncPage(.init(query: .init(cursor: cursor, limit: 50)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }
        switch output {
        case .ok(let ok):
            guard case .json(let page) = ok.body else { throw SyncPortError.mutationMismatch }
            return WireMappers.mapSyncFeedPage(page, cursorFallback: cursor)
        case .badRequest(let response): throw try refused(status: 400, response: response)
        case .unauthorized(let response): throw try refused(status: 401, response: response)
        case .conflict(let response): throw try refused(status: 409, response: response)
        case .serviceUnavailable(let response): throw try refused(status: 503, response: response)
        case .undocumented(let statusCode, _): throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - bootstrap

    public func bootstrap(cursor: String?) async throws -> SyncPullPage {
        let output: Operations.bootstrapSync.Output
        do {
            output = try await client.bootstrapSync(.init(query: .init(cursor: cursor, limit: 50)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }
        switch output {
        case .ok(let ok):
            guard case .json(let page) = ok.body else { throw SyncPortError.mutationMismatch }
            let changes = WireMappers.mapSyncBootstrapPage(page)
            return SyncPullPage(cursor: page.next_cursor ?? cursor ?? "", changes: changes)
        case .badRequest(let response): throw try refused(status: 400, response: response)
        case .unauthorized(let response): throw try refused(status: 401, response: response)
        case .conflict(let response): throw try refused(status: 409, response: response)
        case .serviceUnavailable(let response): throw try refused(status: 503, response: response)
        case .undocumented(let statusCode, _): throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - lookup

    /// Asks the server whether it already decided on a mutation this client
    /// is uncertain about (a push whose answer was never heard). This is
    /// the SAME closed classification table `push` uses -- a decided
    /// refusal is settled identically whichever call surfaced it.
    public func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement {
        let output: Operations.getMutation.Output
        do {
            output = try await client.getMutation(.init(path: .init(mutation_id: mutationId)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }
        switch output {
        case .created(let created):
            return try mapMutationResult(created.body, mutationId: mutationId, fingerprint: fingerprint)
        case .ok(let ok):
            return try mapMutationResult(ok.body, mutationId: mutationId, fingerprint: fingerprint)
        case .unauthorized(let response): throw try refused(status: 401, response: response)
        case .conflict(let response): throw try refused(status: 409, response: response)
        case .unprocessableContent(let response): throw try refused(status: 422, response: response)
        case .notFound(let response): throw try refused(status: 404, response: response)
        case .serviceUnavailable(let response): throw try refused(status: 503, response: response)
        case .undocumented(let statusCode, _): throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - revoke

    public func revoke(installationId: String) async throws {
        let output: Operations.revokeDeviceGrant.Output
        do {
            output = try await client.revokeDeviceGrant(.init(path: .init(installation_id: installationId)))
        } catch {
            throw SyncUnreachable(underlying: error)
        }
        switch output {
        case .ok: return
        case .unauthorized(let response): throw try refused(status: 401, response: response)
        case .notFound(let response): throw try refused(status: 404, response: response)
        case .serviceUnavailable(let response): throw try refused(status: 503, response: response)
        case .undocumented(let statusCode, _): throw SyncPortRefused(status: statusCode, code: nil)
        }
    }

    // MARK: - Internals

    private func mapMutationResult(
        _ body: Operations.getMutation.Output.Created.Body,
        mutationId: String,
        fingerprint: String
    ) throws -> SyncAcknowledgement {
        guard case .json(let result) = body else { throw SyncPortError.mutationMismatch }
        return try mapMutationResult(result, mutationId: mutationId, fingerprint: fingerprint)
    }

    private func mapMutationResult(
        _ body: Operations.getMutation.Output.Ok.Body,
        mutationId: String,
        fingerprint: String
    ) throws -> SyncAcknowledgement {
        guard case .json(let result) = body else { throw SyncPortError.mutationMismatch }
        return try mapMutationResult(result, mutationId: mutationId, fingerprint: fingerprint)
    }

    private func mapMutationResult(
        _ result: Components.Schemas.MutationResult,
        mutationId: String,
        fingerprint: String
    ) throws -> SyncAcknowledgement {
        switch result {
        case .CommandAcknowledgement(let acknowledgement):
            guard acknowledgement.mutation_id == mutationId else { throw SyncPortError.mutationMismatch }
            return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: fingerprint)
        case .UndoNoChange:
            throw SyncPortError.unexpectedUndoNoChange
        case .OrganizationAcknowledgement:
            // Out of this plan's scope -- only `capture_task` mutations are
            // pushed/looked-up today (see `push`'s own doc comment).
            throw SyncPortError.mutationMismatch
        }
    }

    /// Classifies an answered non-2xx response into a settled
    /// acknowledgement, or throws `SyncPortRefused`/`SyncAuthenticationRequired`
    /// when the status/code combination is outside the closed set (T-04-05-07).
    private func settleOrThrow(
        status: Int,
        response: Components.Responses.ProblemResponse,
        taskId: String,
        fingerprint: String,
        mutationId: String
    ) throws -> SyncAcknowledgement {
        let problem = try self.problem(from: response)
        guard let refusal = ServerRefusal.classify(status: status, problem: problem) else {
            throw SyncPortRefused(status: status, code: problem.code)
        }
        switch refusal {
        case .authenticationRequired(let code):
            throw SyncAuthenticationRequired(code: code)
        case .rejected(let code):
            let snapshotJSON = try jsonString(["id": taskId, "rejection_code": code])
            return SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .rejected, snapshotJSON: snapshotJSON)
        case .conflict(let affectedFields, let conflictId, let currentTitle, let latestRevision):
            // Only the server's own affected-field values are carried
            // through -- never the caller's local notes/title/other
            // fields, which would silently replay the canonical shadow
            // over a person's unsent edit (T-04-05-05).
            var payload: [String: Any] = ["id": taskId, "affected_fields": affectedFields]
            if let conflictId { payload["conflict_id"] = conflictId }
            if let latestRevision { payload["revision"] = latestRevision }
            if let currentTitle { payload["title"] = currentTitle }
            let snapshotJSON = try jsonString(payload)
            return SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .conflict, snapshotJSON: snapshotJSON)
        }
    }

    private func refused(status: Int, response: Components.Responses.ProblemResponse) throws -> Error {
        let problem = try self.problem(from: response)
        return SyncPortRefused(status: status, code: problem.code)
    }

    private func problem(from response: Components.Responses.ProblemResponse) throws -> Components.Schemas.Problem {
        switch response.body {
        case .application_problem_plus_json(let problem):
            return problem
        }
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw WireMapperError.invalidField("snapshot")
        }
        return string
    }
}
