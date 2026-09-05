import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// The Swift reimplementation of `apps/desktop/main/adapters/sync.ts`'s
/// `SyncPort` interface (04-PATTERNS.md "exact"). Only `push` for
/// `capture_task` is implemented in this tracer plan.
public protocol SyncPort: Sendable {
    /// Pushes one durable mutation's exact bytes and returns the settled
    /// acknowledgement, or `nil` when the transport could not be reached
    /// at all (never thrown as an ordinary error -- callers distinguish
    /// "unreachable, retry later" from "the server decided" the same way
    /// the desktop adapter does).
    func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement
}

/// Thrown when the transport itself could not be reached (DNS failure,
/// connection refused, TLS failure, timeout) -- as opposed to an answered
/// non-2xx response, which is a decided refusal (O-38's unreachable-vs-
/// refused classification, mirrored from `apps/desktop/main/adapters/sync.ts`).
public struct SyncUnreachableError: Error, Sendable {
    public let underlying: Error
    public init(underlying: Error) { self.underlying = underlying }
}

/// Thrown when the server ANSWERED with a non-2xx status this tracer does
/// not yet classify into a settled acknowledgement (Plan 04-06 extends the
/// classification table for conflict/rejection outcomes).
public struct SyncRefusedError: Error, Sendable {
    public let status: Int
    public init(status: Int) { self.status = status }
}

/// URLSession-backed `SyncPort` over the generated Swift client
/// (04-PATTERNS.md `KeeplingSyncAdapter` analog). Reimplements the
/// desktop's HTTPS-only guard identically: a non-HTTPS base URL is
/// rejected unless the host is `127.0.0.1` or `localhost` (T-04-01-03).
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

    public func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement {
        // The WIRE call uses a typed request built from the SAME field
        // values that produced the durable bytes -- never re-derived
        // values. Identity/fingerprint matching against the acknowledgement
        // is checked against the STORED bytes' fingerprint by the caller
        // (GRDBLocalStore.acknowledge), so a typed re-encoding here cannot
        // silently substitute a different logical command.
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
            // O-30: this is the only line that can tell "unreachable" from
            // "rejected" -- everything below ran because the server
            // ANSWERED. A thrown URLSession error (DNS/connection/TLS/
            // timeout) never reaches here as anything else.
            throw SyncUnreachableError(underlying: error)
        }

        switch output {
        case .created(let created):
            guard case .json(let acknowledgement) = created.body else { throw SyncRefusedError(status: 201) }
            guard acknowledgement.mutation_id == mutation.mutationId else {
                throw SyncPortError.mutationMismatch
            }
            let snapshotJSON = try encodeSnapshotJSON(acknowledgement.snapshot)
            let outcome: SyncAcknowledgement.Outcome = acknowledgement.outcome == .accepted ? .accepted : .alreadySatisfied
            return SyncAcknowledgement(
                mutationId: acknowledgement.mutation_id,
                fingerprint: mutation.fingerprint,
                outcome: outcome,
                snapshotJSON: snapshotJSON
            )
        case .badRequest: throw SyncRefusedError(status: 400)
        case .unauthorized: throw SyncRefusedError(status: 401)
        case .forbidden: throw SyncRefusedError(status: 403)
        case .conflict: throw SyncRefusedError(status: 409)
        case .unprocessableContent: throw SyncRefusedError(status: 422)
        case .serviceUnavailable: throw SyncRefusedError(status: 503)
        case .undocumented(let statusCode, _):
            // An answered non-2xx response is a DECIDED refusal, not a
            // transport failure (O-38). This tracer does not yet map a
            // 409/422 body into a conflict/rejection acknowledgement --
            // Plan 04-06 extends this -- but it still classifies the
            // response as "the server answered", never as unreachable.
            throw SyncRefusedError(status: statusCode)
        }
    }
}

public enum SyncPortError: Error, Equatable {
    case mutationMismatch
}

private func encodeSnapshotJSON(_ snapshot: Components.Schemas.TaskSnapshot) throws -> String {
    let encoder = JSONEncoder()
    let data = try encoder.encode(snapshot)
    return String(data: data, encoding: .utf8) ?? "{}"
}
