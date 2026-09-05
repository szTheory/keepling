import Foundation

/// The Swift reimplementation of `apps/desktop/main/adapters/sync.ts`'s
/// method surface (04-PATTERNS.md "exact"). `KeeplingSyncAdapter.swift`
/// implements this over the committed generated client;
/// `ServerRefusal.swift`/`SyncReachability.swift` supply the
/// unreachable-vs-refused classification every method here relies on.
///
/// DISCLOSED NAMING NOTE (04-05-SUMMARY.md): the plan's own artifact list
/// names six capabilities -- `bootstrap`, `pull`, `push`, `acknowledge`,
/// `lookup`, `revoke`. Desktop's `KeeplingSyncAdapter` class (`sync.ts`)
/// has no separate `acknowledge` method; the `acknowledge` capability named
/// in `DesktopApplication.ts`'s `SyncPort` INTERFACE is the operation this
/// adapter's own `lookup` method implements (`GET /mutations/{id}`,
/// re-checking an uncertain outbox row against the server's own record).
/// This protocol therefore exposes five methods, not six -- `lookup` IS
/// the transport-level acknowledge/re-check capability, named to match
/// desktop's own class rather than duplicating one operation under two
/// names.
public protocol SyncPort: Sendable {
    /// Full historical replay from the beginning of the account's canonical
    /// state, bounded per page. Used only for a first sync or a full
    /// rebuild -- `pull` is the steady-state incremental path.
    func bootstrap(cursor: String?) async throws -> SyncPullPage

    /// One bounded page of canonical changes since `cursor`.
    func pull(cursor: String?) async throws -> SyncPullPage

    /// Pushes one durable local mutation's exact bytes and returns the
    /// settled acknowledgement, or throws `SyncUnreachable` when the
    /// transport itself could not be reached (never thrown as an ordinary
    /// error -- callers distinguish "unreachable, retry later" from "the
    /// server decided" the same way the desktop adapter does).
    func push(_ mutation: LocalMutation) async throws -> SyncAcknowledgement

    /// Asks the server whether it already decided on a mutation this
    /// client is uncertain about -- a push whose answer was never heard
    /// (an `uncertain` outbox row). Settles through the SAME closed
    /// classification table `push` uses.
    func lookup(mutationId: String, fingerprint: String) async throws -> SyncAcknowledgement

    /// Revokes this installation's device-grant credential.
    func revoke(installationId: String) async throws
}
