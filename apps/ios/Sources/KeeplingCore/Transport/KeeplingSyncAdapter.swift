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

    /// Pushes one durable mutation's EXACT stored bytes and returns the
    /// settled acknowledgement (04-08-PLAN.md Task 2 -- generalized from
    /// the tracer's `capture_task`-only push to the full ten-command set).
    /// The `type` discriminator already durable in `mutation.commandBytes`
    /// is read to route to the correct endpoint; the bytes themselves are
    /// decoded DIRECTLY (never rebuilt from `mutation`'s narrower fields)
    /// into the exact contract-published request DTO for that endpoint --
    /// this is what makes a retry byte-identical: the stored bytes are the
    /// only source of truth, never re-serialized from in-memory state.
    ///
    /// O-30/O-38: a thrown `URLSession` error (DNS/connection/TLS/timeout)
    /// is reclassified as `SyncUnreachable` and NEVER reaches a
    /// per-endpoint switch below; everything past that point ran because
    /// the server ANSWERED.
    public func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
        guard let type = Self.commandType(fromBytes: mutation.commandBytes) else {
            throw SyncPortError.mutationMismatch
        }
        let bytes = Data(mutation.commandBytes.utf8)
        let decoder = JSONDecoder()

        switch type {
        case "capture_task":
            let command = try decoder.decode(Components.Schemas.CaptureTaskCommand.self, from: bytes)
            let output: Operations.captureTask.Output
            do { output = try await client.captureTask(.init(body: .json(command))) } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .created(let created):
                guard case .json(let acknowledgement) = created.body, acknowledgement.mutation_id == mutation.mutationId else {
                    throw SyncPortError.mutationMismatch
                }
                return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unprocessableContent(let r): return try settleOrThrow(status: 422, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status, _): throw SyncPortRefused(status: status, code: nil)
            }

        case "edit_task", "clarify_task":
            let command = try decoder.decode(Components.Schemas.EditTaskCommand.self, from: bytes)
            let output: Operations.editTask.Output
            let clarify = type == "clarify_task"
            do {
                output = clarify
                    ? try await mapClarify(client.clarifyTask(.init(body: .json(command))))
                    : try await client.editTask(.init(body: .json(command)))
            } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let r):
                guard case .json(let acknowledgement) = r.body, acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r): return try settleOrThrow(status: 404, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unprocessableContent(let r): return try settleOrThrow(status: 422, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status, _): throw SyncPortRefused(status: status, code: nil)
            }

        case "return_to_inbox":
            let command = try decoder.decode(Components.Schemas.ReturnToInboxCommand.self, from: bytes)
            let output: Operations.returnToInbox.Output
            do { output = try await client.returnToInbox(.init(body: .json(command))) } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let r):
                guard case .json(let acknowledgement) = r.body, acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r): return try settleOrThrow(status: 404, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status, _): throw SyncPortRefused(status: status, code: nil)
            }

        case "plan_for_today", "unplan_task":
            let command = try decoder.decode(Components.Schemas.PlanForTodayRequest.self, from: bytes)
            let output: Operations.planForToday.Output
            do {
                output = type == "plan_for_today"
                    ? try await client.planForToday(.init(body: .json(command)))
                    : try await mapUnplan(client.unplanTask(.init(body: .json(command))))
            } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let r):
                guard case .json(let acknowledgement) = r.body, acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r): return try settleOrThrow(status: 404, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unprocessableContent(let r): return try settleOrThrow(status: 422, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status, _): throw SyncPortRefused(status: status, code: nil)
            }

        case "complete_task", "reopen_task", "trash_task":
            let command = try decoder.decode(Components.Schemas.TaskLifecycleCommand.self, from: bytes)
            let output: LifecycleOutput
            do {
                switch type {
                case "complete_task": output = try mapLifecycle(await client.completeTask(.init(body: .json(command))))
                case "reopen_task": output = try mapLifecycle(await client.reopenTask(.init(body: .json(command))))
                default: output = try mapLifecycle(await client.trashTask(.init(body: .json(command))))
                }
            } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let acknowledgement):
                guard acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r): return try settleOrThrow(status: 404, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status): throw SyncPortRefused(status: status, code: nil)
            }

        case "restore_task":
            let command = try decoder.decode(Components.Schemas.TaskLifecycleCommand.self, from: bytes)
            let output: Operations.restoreTask.Output
            do { output = try await client.restoreTask(.init(body: .json(command))) } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let r):
                guard case .json(let acknowledgement) = r.body, acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                return try WireMappers.mapRestoreAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r): return try settleOrThrow(status: 404, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .conflict(let r): return try settleOrThrow(status: 409, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .serviceUnavailable(let r): return try settleOrThrow(status: 503, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .undocumented(let status, _): throw SyncPortRefused(status: status, code: nil)
            }

        default:
            // Outside this plan's ten-command scope (organizations,
            // activity, search are not iPhone surfaces in Phase 4).
            throw SyncPortError.mutationMismatch
        }
    }

    /// Reads only the `type` discriminator out of the stored bytes -- never
    /// the full command -- so an unroutable/malformed type is detected
    /// before attempting a full per-endpoint decode.
    private static func commandType(fromBytes bytes: String) -> String? {
        guard let data = bytes.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["type"] as? String
    }

    /// A shared, endpoint-agnostic shape for the four `TaskLifecycleCommand`
    /// endpoints (complete/reopen/trash), all of which answer 200 with the
    /// SAME `CommandAcknowledgement` body -- collapsing three near-identical
    /// switches (they differ only in which client method was called, never
    /// in the response shape) into one.
    private enum LifecycleOutput {
        case ok(Components.Schemas.CommandAcknowledgement)
        case badRequest(Components.Responses.ProblemResponse)
        case unauthorized(Components.Responses.ProblemResponse)
        case forbidden(Components.Responses.ProblemResponse)
        case notFound(Components.Responses.ProblemResponse)
        case conflict(Components.Responses.ProblemResponse)
        case serviceUnavailable(Components.Responses.ProblemResponse)
        case undocumented(Int)
    }

    private func mapLifecycle(_ output: Operations.completeTask.Output) throws -> LifecycleOutput {
        switch output {
        case .ok(let r): guard case .json(let a) = r.body else { throw SyncPortError.mutationMismatch }; return .ok(a)
        case .badRequest(let r): return .badRequest(r)
        case .unauthorized(let r): return .unauthorized(r)
        case .forbidden(let r): return .forbidden(r)
        case .notFound(let r): return .notFound(r)
        case .conflict(let r): return .conflict(r)
        case .serviceUnavailable(let r): return .serviceUnavailable(r)
        case .undocumented(let status, _): return .undocumented(status)
        }
    }

    private func mapLifecycle(_ output: Operations.reopenTask.Output) throws -> LifecycleOutput {
        switch output {
        case .ok(let r): guard case .json(let a) = r.body else { throw SyncPortError.mutationMismatch }; return .ok(a)
        case .badRequest(let r): return .badRequest(r)
        case .unauthorized(let r): return .unauthorized(r)
        case .forbidden(let r): return .forbidden(r)
        case .notFound(let r): return .notFound(r)
        case .conflict(let r): return .conflict(r)
        case .serviceUnavailable(let r): return .serviceUnavailable(r)
        case .undocumented(let status, _): return .undocumented(status)
        }
    }

    private func mapLifecycle(_ output: Operations.trashTask.Output) throws -> LifecycleOutput {
        switch output {
        case .ok(let r): guard case .json(let a) = r.body else { throw SyncPortError.mutationMismatch }; return .ok(a)
        case .badRequest(let r): return .badRequest(r)
        case .unauthorized(let r): return .unauthorized(r)
        case .forbidden(let r): return .forbidden(r)
        case .notFound(let r): return .notFound(r)
        case .conflict(let r): return .conflict(r)
        case .serviceUnavailable(let r): return .serviceUnavailable(r)
        case .undocumented(let status, _): return .undocumented(status)
        }
    }

    /// `clarifyTask`'s `Output` is a structurally distinct generated type
    /// from `editTask`'s even though both share the SAME case names and
    /// payload shapes (the generator does not deduplicate operation output
    /// enums the way it does request/response schemas) -- this bridges one
    /// into the other so `push`'s edit/clarify branch has one switch, not
    /// two near-identical copies.
    private func mapClarify(_ output: Operations.clarifyTask.Output) throws -> Operations.editTask.Output {
        switch output {
        case .ok(let r):
            guard case .json(let acknowledgement) = r.body else { throw SyncPortError.mutationMismatch }
            return .ok(.init(body: .json(acknowledgement)))
        case .badRequest(let r): return .badRequest(r)
        case .unauthorized(let r): return .unauthorized(r)
        case .forbidden(let r): return .forbidden(r)
        case .notFound(let r): return .notFound(r)
        case .conflict(let r): return .conflict(r)
        case .unprocessableContent(let r): return .unprocessableContent(r)
        case .serviceUnavailable(let r): return .serviceUnavailable(r)
        case .undocumented(let status, let body): return .undocumented(statusCode: status, body)
        }
    }

    /// Same bridging rationale as `mapClarify` above, for `unplanTask` into
    /// `planForToday`'s `Output`.
    private func mapUnplan(_ output: Operations.unplanTask.Output) throws -> Operations.planForToday.Output {
        switch output {
        case .ok(let r):
            guard case .json(let acknowledgement) = r.body else { throw SyncPortError.mutationMismatch }
            return .ok(.init(body: .json(acknowledgement)))
        case .badRequest(let r): return .badRequest(r)
        case .unauthorized(let r): return .unauthorized(r)
        case .forbidden(let r): return .forbidden(r)
        case .notFound(let r): return .notFound(r)
        case .conflict(let r): return .conflict(r)
        case .unprocessableContent(let r): return .unprocessableContent(r)
        case .serviceUnavailable(let r): return .serviceUnavailable(r)
        case .undocumented(let status, let body): return .undocumented(statusCode: status, body)
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
