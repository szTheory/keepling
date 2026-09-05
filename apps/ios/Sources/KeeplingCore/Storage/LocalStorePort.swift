import Foundation

/// Thrown by a `LocalStorePort` method this tracer plan deliberately does
/// not implement. The full method surface mirrors
/// `apps/desktop/store-worker/local-store.ts`'s public API (04-01-PLAN.md
/// Task 3) so later plans (04-02, 04-09) extend this port rather than
/// replace it; only `acceptMutation`, `acknowledge`, `readyMutations`, and
/// `snapshot` are implemented here.
public struct UnimplementedInTracerError: Error, Sendable, Equatable {
    public let member: String
    public init(_ member: String) { self.member = member }
}

/// One durable local mutation, ready to be persisted atomically alongside
/// its projection effect (mirrors `SyncMutation` in
/// `apps/desktop/main/application/DesktopApplication.ts`).
public struct LocalMutation: Sendable, Equatable {
    /// The full local-projection effect a mutation applies (04-08-PLAN.md
    /// Task 1). Defaulted to a fresh-capture shape (`notes: ""`,
    /// `completedAt`/`trashedAt: nil`, `planned: false`) so every caller
    /// that pre-dates this plan (the capture tracer, its tests) is
    /// unaffected -- additive, not a breaking signature change, mirroring
    /// 04-06/04-07's own `SyncAcknowledgement` extension pattern.
    public struct ProjectionEffect: Sendable, Equatable {
        public let notes: String
        public let completedAt: String?
        public let trashedAt: String?
        public let planned: Bool

        public init(notes: String = "", completedAt: String? = nil, trashedAt: String? = nil, planned: Bool = false) {
            self.notes = notes
            self.completedAt = completedAt
            self.trashedAt = trashedAt
            self.planned = planned
        }
    }

    public let mutationId: String
    public let taskId: String
    public let commandBytes: String
    public let fingerprint: String
    public let acceptedAt: String
    public let resourceKeys: [String]
    public let title: String
    public let effect: ProjectionEffect

    public init(
        mutationId: String,
        taskId: String,
        commandBytes: String,
        fingerprint: String,
        acceptedAt: String,
        resourceKeys: [String],
        title: String,
        effect: ProjectionEffect = ProjectionEffect()
    ) {
        self.mutationId = mutationId
        self.taskId = taskId
        self.commandBytes = commandBytes
        self.fingerprint = fingerprint
        self.acceptedAt = acceptedAt
        self.resourceKeys = resourceKeys
        self.title = title
        self.effect = effect
    }
}

/// The local result of a capture, reported only after the durable
/// transaction committed (D-03 -- never before).
public struct LocalAcceptance: Sendable, Equatable {
    public let mutationId: String
    public let fingerprint: String
    public let taskId: String
    public let title: String
}

/// A page of changes pulled from the server (mirrors `PullPage`).
public struct PullPage: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public let entityId: String
        public let snapshotJSON: String
        public init(entityId: String, snapshotJSON: String) {
            self.entityId = entityId
            self.snapshotJSON = snapshotJSON
        }
    }
    public let cursor: String?
    public let changes: [Change]
    public init(cursor: String?, changes: [Change]) {
        self.cursor = cursor
        self.changes = changes
    }
}

/// A terminal server answer to one durable mutation (mirrors
/// `SyncAcknowledgement`). `snapshotJSON` is the canonical task snapshot on
/// `accepted`/`already_satisfied`; on `conflict` it carries ONLY the
/// server's own affected-field values (04-06-PLAN.md Task 1) -- never a
/// caller-synthesized full snapshot, because settlement must not be able
/// to blank a field the server did not name.
public struct SyncAcknowledgement: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case accepted
        case alreadySatisfied = "already_satisfied"
        case rejected
        case stale
        case conflict
    }

    /// The server-issued compensation capability, retained against the
    /// mutation it undoes (mirrors desktop's `RetainedUndo` / O-45). Named
    /// as a plain value here rather than importing `Transport`'s
    /// `SyncUndoAvailability` -- `Storage` must not depend on `Transport`
    /// (04-PATTERNS.md layering), so the two types are structurally
    /// identical but independently declared at their own layer boundary.
    public struct UndoAvailabilityHandle: Sendable, Equatable {
        public let handle: String
        public let label: String
        public let expiresAt: String
        public init(handle: String, label: String, expiresAt: String) {
            self.handle = handle
            self.label = label
            self.expiresAt = expiresAt
        }
    }

    public let mutationId: String
    public let fingerprint: String
    public let outcome: Outcome
    public let snapshotJSON: String
    /// The exact field names the server named as diverged on a `conflict`
    /// outcome (04-06-PLAN.md Task 1). Empty for every other outcome.
    public let affectedFields: [String]
    /// Present only when the accepted command was one the server can
    /// compensate. `nil` is an honest "this cannot be undone" -- never a
    /// reason to synthesize one (04-06-PLAN.md Task 1 behavior).
    public let undo: UndoAvailabilityHandle?

    public init(
        mutationId: String,
        fingerprint: String,
        outcome: Outcome,
        snapshotJSON: String,
        affectedFields: [String] = [],
        undo: UndoAvailabilityHandle? = nil
    ) {
        self.mutationId = mutationId
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.snapshotJSON = snapshotJSON
        self.affectedFields = affectedFields
        self.undo = undo
    }
}

/// One row in the visible projection (what a person sees on this iPhone).
public struct ProjectionRow: Sendable, Equatable {
    public let taskId: String
    public let title: String
    public let syncStatus: String
    public let notes: String
    public let completedAt: String?
    public let trashedAt: String?
    public let planned: Bool
}

/// A whole-workspace snapshot (mirrors `WorkspaceSnapshot`).
public struct WorkspaceSnapshot: Sendable, Equatable {
    public let tasks: [ProjectionRow]
}

/// This client's local view of sync progress (mirrors `SyncState`).
public struct LocalSyncState: Sendable, Equatable {
    public let cursor: String?
    public let outbox: [String]
    public let readyPushes: [String]
}

public enum UndoDropReason: String, Sendable, Equatable {
    case blocked, dropped, nothingToUndo = "nothing_to_undo", transmitted, unknown
}

/// The five-field account/server namespace tuple this store is bound to
/// (mirrors desktop `DesktopApplication.ts`'s `SyncNamespace`, cited in
/// 02-03-SUMMARY.md). `bindNamespace` is the D-09/D-03 real fencing
/// trigger: a restored store whose serialized tuple disagrees with what it
/// was bound to fences itself for writes rather than silently pushing a
/// previous account's outbox into this one (04-06-PLAN.md Task 2).
public struct SyncNamespace: Sendable, Equatable, Codable {
    public let issuer: String
    public let origin: String
    public let serverInstance: String
    public let accountSubject: String
    public let generation: String

    public init(issuer: String, origin: String, serverInstance: String, accountSubject: String, generation: String) {
        self.issuer = issuer
        self.origin = origin
        self.serverInstance = serverInstance
        self.accountSubject = accountSubject
        self.generation = generation
    }

    var isComplete: Bool {
        !issuer.isEmpty && !origin.isEmpty && !serverInstance.isEmpty && !accountSubject.isEmpty && !generation.isEmpty
    }
}

public struct UndoResult: Sendable, Equatable {
    public let applied: Bool
    public let reason: UndoDropReason
}

/// The Swift reimplementation of `apps/desktop/store-worker/local-store.ts`'s
/// public surface (04-PATTERNS.md "exact (same port surface, reimplemented
/// as a Swift protocol)"). Only the tracer's four members are implemented in
/// this plan; the rest throw `UnimplementedInTracerError` until Plans
/// 04-02/04-09 replace them (04-01-PLAN.md Task 3).
public protocol LocalStorePort: Sendable {
    /// Durably accepts one local mutation: writes the visible projection
    /// row, the immutable command bytes + fingerprint, the mutation
    /// journal entry, and the outbox row in ONE transaction (D-03), and
    /// reports local acceptance only after that transaction commits.
    func acceptMutation(_ mutation: LocalMutation) throws -> LocalAcceptance

    /// Applies a bounded pull page into the canonical shadow.
    func applyPull(_ page: PullPage) throws

    /// Settles a terminal server acknowledgement: verifies mutation
    /// identity + fingerprint, applies canonical state only on a
    /// successful outcome, deletes the exact outbox row, and treats a
    /// replay of an already-settled acknowledgement as a no-op success
    /// (D-09).
    @discardableResult
    func acknowledge(_ acknowledgement: SyncAcknowledgement) throws -> WorkspaceSnapshot

    /// Mutations whose bytes have never been handed to the transport (or
    /// whose prior attempt never received an answer), in outbox order,
    /// dependency- and resource-key-ordering-safe.
    func readyMutations() throws -> [LocalMutation]

    func undoLastLocalAction() throws -> UndoResult

    func resolveConflict(conflictId: String, selection: [String: String]) throws -> WorkspaceSnapshot

    func snapshot() throws -> WorkspaceSnapshot

    func syncState() throws -> LocalSyncState
}
