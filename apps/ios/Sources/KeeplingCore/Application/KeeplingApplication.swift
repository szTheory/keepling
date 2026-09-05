import Foundation

/// The application orchestrator: `runSyncPass` sequences a bounded pull
/// then a bounded push then settlement over one `LocalStorePort` and one
/// `SyncPort`, mirroring `apps/desktop/main/application/DesktopApplication.ts`'s
/// shape (04-08-PLAN.md Task 2). This is the ONE entry point the scene-phase
/// driver and the background-refresh handler both call (Task 3) -- there is
/// no separate reconciliation path for either trigger to drift from.
public final class KeeplingApplication: @unchecked Sendable {
    private let store: GRDBLocalStore
    private let syncPort: any SyncPort

    /// The observable result of one pass, for a driver/test to inspect.
    public enum SyncPassOutcome: Sendable, Equatable {
        /// The pass ran to completion (which may mean nothing was pulled or
        /// pushed -- an empty outbox and an unchanged cursor is success,
        /// not a distinct case).
        case completed(pulled: Int, pushed: Int, settled: Int)
        /// The namespace was fenced; the pass refused before any request
        /// was built.
        case fenced
        /// An authentication-required answer stopped the pass. No row was
        /// marked rejected; any row this pass had already claimed for
        /// transmission is left `uncertain`, never `queued`, and never
        /// `rejected`.
        case authenticationRequired
    }

    /// Thrown when the pull page itself violates the contract bound this
    /// client trusts (`SyncReducer.maximumPullChanges`) -- a defensive
    /// check on the ADAPTER's own output, since a malformed/oversized page
    /// must never be silently applied.
    public enum SyncPassError: Error, Sendable, Equatable {
        case pullPageTooLarge
    }

    public init(store: GRDBLocalStore, syncPort: any SyncPort) {
        self.store = store
        self.syncPort = syncPort
    }

    /// Pulls before it pushes, applies at most `SyncReducer.maximumPullChanges`
    /// changes, pushes at most `SyncReducer.maximumReadyPushes` mutations
    /// (both bounds read from the reducer's own named constants, never
    /// re-declared here), and never attempts a push under a fenced
    /// namespace.
    @discardableResult
    public func runSyncPass() async throws -> SyncPassOutcome {
        // The fence check runs BEFORE any request is built -- `syncState()`
        // is the fence-gated read 04-07 established; a fenced namespace
        // throws here and this returns `.fenced` without the transport
        // ever being touched (asserted in tests via a transport stub that
        // fails if called).
        let cursorBefore: String?
        do {
            cursorBefore = try store.syncState().cursor
        } catch let error as GRDBLocalStore.StoreError {
            if case .fencedForWrites = error { return .fenced }
            throw error
        }

        // MARK: - Pull (bounded)

        let pulledCount: Int
        do {
            let page = try await syncPort.pull(cursor: cursorBefore)
            guard page.changes.count <= SyncReducer.maximumPullChanges else { throw SyncPassError.pullPageTooLarge }
            pulledCount = page.changes.count
            let localPage = PullPage(
                cursor: page.cursor.isEmpty ? nil : page.cursor,
                changes: page.changes.map { change in
                    PullPage.Change(entityId: change.entityId, snapshotJSON: Self.encodeSnapshot(change.snapshot))
                }
            )
            try store.applyPull(localPage)
        } catch is SyncAuthenticationRequired {
            return .authenticationRequired
        }
        // `SyncUnreachable`/`SyncPortRefused` and any other pull failure
        // propagate to the caller uncaught -- a pull failure means this
        // pass cannot coherently proceed to push (pull-before-push is not
        // optional), and the caller (the scheduler/driver) is what decides
        // backoff, never this orchestrator.

        // MARK: - Push (bounded, lane-ordered, concurrency-safe)

        let outstanding = try store.allOutstandingMutationsInOrder()
        var blockedResourceKeys = Set<String>()
        var candidates: [LocalMutation] = []
        for (mutation, state) in outstanding {
            let keys = Set(mutation.resourceKeys)
            let laneBlocked = !keys.isDisjoint(with: blockedResourceKeys)
            if laneBlocked || state == "in_flight" {
                blockedResourceKeys.formUnion(keys)
                continue
            }
            candidates.append(mutation)
            blockedResourceKeys.formUnion(keys)
            if candidates.count == SyncReducer.maximumReadyPushes { break }
        }

        var pushedCount = 0
        var settledCount = 0
        for mutation in candidates {
            // The claim IS the concurrency guard: a second concurrent pass
            // racing for the SAME row finds it already `in_flight` and
            // claims zero rows here, so it is never pushed twice.
            guard try store.claimForTransmission(mutationId: mutation.mutationId) else { continue }
            pushedCount += 1

            do {
                let acknowledgement = try await syncPort.push(mutation)
                try store.acknowledge(acknowledgement)
                settledCount += 1
            } catch is SyncAuthenticationRequired {
                // The row this pass just claimed is left `uncertain` --
                // NEVER `queued` (D-52 monotonicity) and NEVER `rejected`
                // (an auth failure is not a per-mutation decision the
                // server made about THIS command).
                try store.setOutboxState(mutationId: mutation.mutationId, to: "uncertain")
                return .authenticationRequired
            } catch is SyncUnreachable {
                // A thrown transport error cannot say whether the bytes
                // left -- `uncertain` is the only honest destination.
                try store.setOutboxState(mutationId: mutation.mutationId, to: "uncertain")
            } catch is SyncPortRefused {
                // An answered refusal outside the closed settleable set is
                // ALSO treated conservatively as `uncertain`, never
                // `rejected`: this client cannot locally decide the
                // command was rejected when the classifier itself declined
                // to settle it -- a real decision requires a `lookup`
                // (Plan 04-09's retry/reconciliation concern), not a guess
                // made here.
                try store.setOutboxState(mutationId: mutation.mutationId, to: "uncertain")
            }
        }

        return .completed(pulled: pulledCount, pushed: pushedCount, settled: settledCount)
    }

    /// Builds `LocalStorePort.PullPage.Change`'s `snapshotJSON` from a
    /// `SyncSnapshot` -- the ONE place `SyncReducerState.swift`'s pull-side
    /// shape is translated into `LocalStorePort.swift`'s persisted-JSON
    /// shape, since `KeeplingSyncAdapter.pull` returns the former and
    /// `GRDBLocalStore.applyPull` consumes the latter.
    private static func encodeSnapshot(_ snapshot: SyncSnapshot) -> String {
        var object: [String: Any] = ["id": snapshot.id, "revision": snapshot.revision]
        for (key, value) in snapshot.extra {
            object[key] = jsonAny(value)
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func jsonAny(_ value: SyncJSON) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        case .array(let array): return array.map(jsonAny)
        case .object(let object): return object.mapValues(jsonAny)
        }
    }
}
