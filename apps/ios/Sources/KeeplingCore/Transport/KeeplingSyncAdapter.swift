import Foundation
import HTTPTypes
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

    /// Supplies the bearer credential this adapter authenticates with.
    ///
    /// A closure, not a stored string, and `async` on purpose. A device-grant
    /// credential EXPIRES, and `DeviceGrantClient.refresh()` already exists to
    /// replace it; a value captured once at construction would authenticate in
    /// a lane and then fail in the app at the first expiry -- exactly the shape
    /// of defect that only shows up against a real server, which is the class
    /// this seam exists to make testable. Returning `nil` means "no credential
    /// available", and the request goes out unauthenticated rather than with an
    /// empty header the server would have to interpret.
    public typealias CredentialProvider = @Sendable () async -> String?

    /// Attaches `Authorization: Bearer` when a credential is available.
    ///
    /// The server distinguishes a native client from a browser by this header
    /// alone (`apps/server/lib/keepling_web/auth.ex`, `authenticate_client`):
    /// with it, the request takes the device-grant path and is CSRF-exempt
    /// because no session is involved; without it, the request is treated as a
    /// browser request and refused for want of a session. So this middleware is
    /// not a convenience -- it is the only thing that makes this adapter
    /// addressable as a native client at all.
    private struct BearerCredentialMiddleware: ClientMiddleware {
        let provider: CredentialProvider

        func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            var request = request
            if let credential = await provider(), !credential.isEmpty {
                request.headerFields[.authorization] = "Bearer \(credential)"
            }
            return try await next(request, body, baseURL)
        }
    }

    /// - Parameter credentialProvider: supplies the bearer credential. Defaults
    ///   to `nil`, so every existing caller and every stubbed test emits a
    ///   byte-identical request to the one it emitted before this seam existed.
    public init(
        baseURL: URL,
        transport: any ClientTransport = URLSessionTransport(),
        credentialProvider: CredentialProvider? = nil
    ) throws {
        // UNCHANGED, and deliberately evaluated BEFORE anything else: holding a
        // credential must never buy a relaxation of the transport rule. A
        // reader reaching for this guard to explain why a lane cannot reach a
        // LAN host should find exactly the same three conditions as before
        // (T-04-01-03/T-04-05-04).
        guard baseURL.scheme == "https" || baseURL.host == "127.0.0.1" || baseURL.host == "localhost" else {
            throw ConfigurationError.insecureBaseURL
        }
        let middlewares: [any ClientMiddleware] =
            credentialProvider.map { [BearerCredentialMiddleware(provider: $0)] } ?? []
        client = Client(
            serverURL: baseURL,
            // The real server sends RFC 3339 with microsecond precision, which
            // the runtime's default ISO8601 transcoder rejects. See
            // `RFC3339DateTranscoder` -- without this, every response carrying
            // a timestamp fails to decode and surfaces as SyncUnreachable.
            configuration: Configuration(dateTranscoder: RFC3339DateTranscoder()),
            transport: transport,
            middlewares: middlewares
        )
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

        case "undo_task":
            let command = try decoder.decode(Components.Schemas.UndoTaskCommand.self, from: bytes)
            let output: Operations.undoTask.Output
            do { output = try await client.undoTask(.init(body: .json(command))) } catch { throw SyncUnreachable(underlying: error) }
            switch output {
            case .ok(let r):
                switch r.body {
                case .json(let undoResult):
                    switch undoResult {
                    case .CommandAcknowledgement(let acknowledgement):
                        guard acknowledgement.mutation_id == mutation.mutationId else { throw SyncPortError.mutationMismatch }
                        return try WireMappers.mapCommandAcknowledgement(acknowledgement, expectedFingerprint: mutation.fingerprint)
                    case .UndoNoChange(let noChange):
                        return try settleUndoNoChange(noChange, mutationId: mutation.mutationId, fingerprint: mutation.fingerprint)
                    }
                }
            case .badRequest(let r): return try settleOrThrow(status: 400, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .unauthorized(let r): return try settleOrThrow(status: 401, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .forbidden(let r): return try settleOrThrow(status: 403, response: r, taskId: mutation.taskId, fingerprint: mutation.fingerprint, mutationId: mutation.mutationId)
            case .notFound(let r):
                switch r.body {
                case .json(let noChange):
                    return try settleUndoNoChange(noChange, mutationId: mutation.mutationId, fingerprint: mutation.fingerprint)
                }
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
        case .Problem(let problem):
            // A lookup whose stored outcome was a REFUSAL. The server
            // recorded what it decided about this mutation, and that
            // decision is settleable in exactly the cases the shared
            // classifier already recognises -- so it is classified here by
            // the same rules a live refusal takes, never by a second
            // opinion about what a code means.
            //
            // `MutationResult` gained this variant when it was measured that
            // the sync feed carries a `Problem` in `command_outcome.result`
            // for a refused command (04-18-PLAN.md Task 3). The lookup
            // endpoint returns the same union, so the same answer can arrive
            // here.
            if case .authenticationRequired(let code)? = ServerRefusal.classify(status: Int(problem.status), problem: problem) {
                throw SyncAuthenticationRequired(code: code)
            }
            throw SyncPortRefused(status: Int(problem.status), code: problem.code)
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

    /// The `undo-task` endpoint's 200/404 "no change" answer
    /// (04-11-PLAN.md Task 1). `undo_uncertain` is the ONE code this
    /// client refuses to settle -- the server itself does not know
    /// whether the compensation applied, so treating it as either
    /// accepted or rejected would be a guess presented as a fact,
    /// mirroring the unclassified-refusal-throws pattern 04-08 already
    /// established (`SyncPortRefused` -> `runSyncPass` moves the row to
    /// `uncertain`, never `queued`, never guessed into `rejected`).
    /// Every OTHER code (already applied/expired/stale/unknown) is a
    /// genuine, terminal negative answer -- settled as `.rejected` so the
    /// compensating row leaves the outbox without `acknowledge` ever
    /// touching canonical/local state for it.
    private func settleUndoNoChange(
        _ noChange: Components.Schemas.UndoNoChange,
        mutationId: String,
        fingerprint: String
    ) throws -> SyncAcknowledgement {
        guard noChange.mutation_id == mutationId else { throw SyncPortError.mutationMismatch }
        if noChange.code == .undo_uncertain {
            throw SyncPortRefused(status: 200, code: noChange.code.rawValue)
        }
        let snapshotJSON = (try? jsonString(["code": noChange.code.rawValue])) ?? "{}"
        return SyncAcknowledgement(mutationId: mutationId, fingerprint: fingerprint, outcome: .rejected, snapshotJSON: snapshotJSON)
    }

    /// Classifies a refusal on a READ path (pull, bootstrap, lookup).
    ///
    /// MEASURED DEFECT this fixes (04-18-PLAN.md Task 3). This returned a
    /// bare `SyncPortRefused` for EVERY status, including 401 -- while
    /// `KeeplingApplication.runSyncPass` catches `SyncAuthenticationRequired`
    /// around the pull and returns `.authenticationRequired` for it. Since
    /// the real adapter could never throw that type from a read, that catch
    /// was UNREACHABLE through the real adapter, and reachable only through
    /// the test stub -- which is exactly why a test covered it and it looked
    /// correct.
    ///
    /// The consequence with a real server: a sync pass begins with the pull,
    /// so an expired or revoked credential produces a 401 THERE first. The
    /// pass then threw an opaque refusal instead of reporting that
    /// authentication was required, and the app had no way to know it should
    /// ask the person to sign in again. This is the authentication-expiry
    /// half of D-22 Criterion 2, unhandled on the leg where it actually
    /// arrives.
    ///
    /// The push path has always classified correctly via `settleOrThrow` ->
    /// `ServerRefusal.classify`. This makes reads agree with writes, using
    /// the same classifier rather than a second opinion about what a 401
    /// means.
    private func refused(status: Int, response: Components.Responses.ProblemResponse) throws -> Error {
        let problem = try self.problem(from: response)
        if case .authenticationRequired(let code)? = ServerRefusal.classify(status: status, problem: problem) {
            return SyncAuthenticationRequired(code: code)
        }
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
