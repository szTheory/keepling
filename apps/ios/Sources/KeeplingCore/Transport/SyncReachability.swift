import Foundation

/// The one boundary that can tell "the server did not answer" from "the
/// server answered no" (O-30/O-38, mirrored from
/// `apps/desktop/main/application/sync-reachability.ts` and
/// `apps/desktop/main/adapters/sync.ts`'s `#json`). A thrown `URLSession`
/// error -- DNS failure, connection refused, TLS failure, timeout, an
/// explicit cancellation -- is the ONLY path that produces this value.
/// Everything that runs after an HTTP response has actually arrived ran
/// because the server ANSWERED, and must never be represented as
/// `SyncUnreachable` (T-04-05-03): an unheard answer must never be treated
/// as a settled one, and a decided refusal must never be treated as
/// unreachable either.
public struct SyncUnreachable: Error, Sendable {
    /// The underlying transport failure (URLError, POSIX error, TLS
    /// failure, ...) -- carried through, never inspected or re-classified
    /// by this type. Reachability is a binary fact (did an HTTP response
    /// arrive, yes or no); the REASON a request never got one is diagnostic
    /// context only, never a branch this client's correctness depends on.
    public let underlying: any Error

    public init(underlying: any Error) {
        self.underlying = underlying
    }
}

/// Thrown by `KeeplingSyncAdapter` for an answered non-2xx response this
/// closed-set classifier (`ServerRefusal`) does not settle into an
/// acknowledgement -- 403, 5xx other than the ones a caller has already
/// handled, a malformed problem body, or any status/code combination
/// outside the closed set. T-04-05-07: anything unlisted keeps throwing
/// rather than being silently settled, so it keeps landing on the
/// retryable-failure row instead of being terminalized incorrectly.
public struct SyncPortRefused: Error, Sendable {
    public let status: Int
    public let code: String?

    public init(status: Int, code: String?) {
        self.status = status
        self.code = code
    }
}
