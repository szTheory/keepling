import Foundation

/// The third independent implementation of Keepling's synchronization
/// reducer (SRV-02, D-10), reproducing
/// `apps/server/lib/keepling/application/sync/reference_model.ex` state
/// field-for-field. Every entry point is a pure function over
/// `SyncReducerState` -- this type imports nothing from `Storage`,
/// `Transport`, GRDB, or the UI frameworks (04-03-PLAN.md Task 2
/// acceptance criteria).
///
/// Per D-11 there is no shared FFI core in this phase: this is a native
/// Swift reimplementation, not a binding to a cross-compiled artifact.
///
/// The reducer reproduces the reference model's outcomes; it never becomes
/// an independent source of acceptance, revision, or conflict authority --
/// the Phoenix server owns those decisions, this type only replays them.
public enum SyncReducer {
    /// Contract bound from Phase 2: a pull page carries at most this many
    /// changes. Not a tuning knob -- carried across at its exact value.
    public static let maximumPullChanges = 50

    /// Contract bound from Phase 2: at most this many mutations are
    /// reported ready to push at once.
    public static let maximumReadyPushes = 25

    // MARK: - local_accept

    /// Accepts one local mutation: rejects a reused mutation identity or an
    /// orphan dependency without mutating `state`; otherwise records the
    /// journal entry, the dependency edges, and the outbox row, and replays
    /// the visible projection -- all in the SAME returned state value (this
    /// is a pure function; there is no partial application to roll back).
    public static func localAccept(
        _ state: SyncReducerState,
        mutation: SyncMutation
    ) -> Result<(outcome: String, state: SyncReducerState), SyncReducerError> {
        if state.journal[mutation.mutationId] != nil {
            return .failure(.mutationIdentityReused)
        }
        guard mutation.dependencies.allSatisfy({ state.journal[$0] != nil }) else {
            return .failure(.orphanDependency)
        }

        var next = state
        next.journal[mutation.mutationId] = SyncJournalEntry(
            acceptedAt: mutation.acceptedAt,
            commandBytes: mutation.commandBytes,
            fingerprint: mutation.fingerprint,
            outcome: "pending",
            resourceKeys: mutation.resourceKeys
        )
        next.dependencies[mutation.mutationId] = mutation.dependencies
        next.outbox.append(mutation)
        next = replayVisible(next)
        return .success((outcome: "local_saved", state: next))
    }

    // MARK: - pull

    /// Applies a bounded pull page into the canonical shadow. A page over
    /// `maximumPullChanges` is rejected without mutating `state`. Only a
    /// change whose revision is `>=` the entity's existing shadow revision
    /// replaces it (mirrors `apply_changes/2`'s last-writer-by-revision
    /// rule, never "last pull wins" by arrival order alone).
    public static func pull(
        _ state: SyncReducerState,
        page: SyncPullPage
    ) -> Result<SyncReducerState, SyncReducerError> {
        guard page.changes.count <= maximumPullChanges else {
            return .failure(.pullPageTooLarge)
        }

        var shadow = state.canonicalShadow
        for change in page.changes {
            let existingRevision = shadow[change.entityId]?.revision ?? -1
            if change.snapshot.revision >= existingRevision {
                shadow[change.entityId] = change.snapshot
            }
        }

        var next = state
        next.canonicalShadow = shadow
        next.cursor = page.cursor
        next = replayVisible(next)
        return .success(next)
    }

    // MARK: - ready_pushes

    /// Mutations eligible to push right now, bounded at `maximumReadyPushes`,
    /// preserving FIFO within a resource key while letting disjoint
    /// resource keys progress independently -- ordering is by resource key
    /// (outbox position + shared-key lane blocking), never by the
    /// `dependencies` journal edge ([Phase 03] decision: a dependency only
    /// clears on an accepted outcome, so keying order on dependencies would
    /// strand a task's whole chain once conflicts became reachable).
    ///
    /// Returns an empty array (never an error) while `state.fence` is set --
    /// a fenced state simply reports nothing ready, exactly as
    /// `reference_model.ex`'s `ready_pushes/1` clause does.
    public static func readyPushes(_ state: SyncReducerState) -> Result<[SyncMutation], SyncReducerError> {
        if state.fence != nil { return .success([]) }

        if let error = validateDependencyGraph(state) { return .failure(error) }

        var ready: [SyncMutation] = []
        for (index, mutation) in state.outbox.enumerated() {
            guard dependenciesSatisfied(mutation, in: state) else { continue }
            let resourceKeys = Set(mutation.resourceKeys)
            let earlier = state.outbox[0..<index]
            let laneUnblocked = earlier.allSatisfy { Set($0.resourceKeys).isDisjoint(with: resourceKeys) }
            guard laneUnblocked else { continue }
            ready.append(mutation)
            if ready.count == maximumReadyPushes { break }
        }
        return .success(ready)
    }

    // MARK: - acknowledge

    /// Settles a terminal server acknowledgement: verifies mutation
    /// identity + fingerprint, applies the canonical snapshot, records the
    /// journal outcome, and removes the exact outbox row.
    ///
    /// Applying the SAME terminal acknowledgement a second time (the
    /// mutation is no longer in the outbox because the first application
    /// already removed it) is a no-op that returns the state unchanged --
    /// this is a strengthening `SyncReducer` adds beyond
    /// `reference_model.ex` itself (whose `acknowledge/2` returns
    /// `:unknown_mutation` on a replay), per this plan's own explicit
    /// behavior requirement and consistent with the store layer's D-09
    /// replay-no-op decision. A replay whose outcome DISAGREES with the
    /// already-recorded terminal outcome is `.acknowledgementMismatch`,
    /// never silently accepted.
    public static func acknowledge(
        _ state: SyncReducerState,
        acknowledgement: SyncAcknowledgementInput
    ) -> Result<SyncReducerState, SyncReducerError> {
        guard let mutation = state.outbox.first(where: { $0.mutationId == acknowledgement.mutationId }) else {
            if let entry = state.journal[acknowledgement.mutationId], entry.outcome == acknowledgement.outcome.rawValue {
                return .success(state)
            }
            return .failure(.unknownMutation)
        }
        guard mutation.fingerprint == acknowledgement.fingerprint else {
            return .failure(.acknowledgementMismatch)
        }

        var shadow = state.canonicalShadow
        let existingRevision = shadow[mutation.effectEntityId]?.revision ?? -1
        if acknowledgement.snapshot.revision >= existingRevision {
            shadow[mutation.effectEntityId] = acknowledgement.snapshot
        }

        var next = state
        next.canonicalShadow = shadow
        var entry = next.journal[mutation.mutationId] ?? SyncJournalEntry(
            acceptedAt: mutation.acceptedAt,
            commandBytes: mutation.commandBytes,
            fingerprint: mutation.fingerprint,
            outcome: "pending",
            resourceKeys: mutation.resourceKeys
        )
        entry.outcome = acknowledgement.outcome.rawValue
        entry.terminalSnapshot = acknowledgement.snapshot
        next.journal[mutation.mutationId] = entry
        next.outbox.removeAll { $0.mutationId == mutation.mutationId }
        next = replayVisible(next)
        return .success(next)
    }

    // MARK: - fence

    /// Sets (or clears, when `reason` is `nil`) the synchronization fence.
    /// Never fails -- mirrors `reference_model.ex`'s `fence/2`, which
    /// always succeeds.
    public static func fence(_ state: SyncReducerState, reason: String?) -> SyncReducerState {
        var next = state
        next.fence = reason
        return next
    }

    // MARK: - Internals

    private static func dependenciesSatisfied(_ mutation: SyncMutation, in state: SyncReducerState) -> Bool {
        mutation.dependencies.allSatisfy { dependencyId in
            guard let outcome = state.journal[dependencyId]?.outcome,
                  let terminal = SyncTerminalOutcome(rawValue: outcome)
            else { return false }
            return SyncTerminalOutcome.successful.contains(terminal)
        }
    }

    private static func validateDependencyGraph(_ state: SyncReducerState) -> SyncReducerError? {
        let nodes = Set(state.journal.keys)
        guard Set(state.dependencies.keys) == nodes else { return .invalidDependencyGraph }
        for dependencyList in state.dependencies.values {
            if dependencyList.contains(where: { !nodes.contains($0) }) { return .orphanDependency }
        }
        if hasDependencyCycle(state.dependencies) { return .dependencyCycle }
        return nil
    }

    /// Repeatedly removes graph roots (nodes with no remaining
    /// dependencies); any node still present once no root remains is part
    /// of a cycle. Mirrors `reference_model.ex`'s
    /// `remove_dependency_roots/1`.
    private static func hasDependencyCycle(_ graph: [String: [String]]) -> Bool {
        var remaining = graph
        while true {
            let roots = remaining.filter { $0.value.isEmpty }.map(\.key)
            if roots.isEmpty { break }
            let rootSet = Set(roots)
            for root in roots { remaining.removeValue(forKey: root) }
            for key in remaining.keys {
                remaining[key] = remaining[key]?.filter { !rootSet.contains($0) }
            }
        }
        return !remaining.isEmpty
    }

    /// The visible projection is a replay of (canonical shadow + outbox):
    /// every still-outstanding mutation's effect overlays the canonical
    /// shadow, exactly as `reference_model.ex`'s `replay_visible/1` does.
    private static func replayVisible(_ state: SyncReducerState) -> SyncReducerState {
        var visible = state.canonicalShadow
        for mutation in state.outbox {
            visible[mutation.effectEntityId] = mutation.effectSnapshot
        }
        var next = state
        next.visible = visible
        return next
    }
}
