import Foundation

/// Generated wire DTOs never become persistence records
/// (`docs/architecture/REPOSITORY.md`'s four-deliberate-representations
/// rule, D-30 inherited from Phase 3). Every generated value that crosses
/// from `Transport/Generated/*.swift` into `LocalStorePort.swift`'s
/// `SyncAcknowledgement` or `Sync/SyncReducerState.swift`'s
/// `SyncPullPage`/`SyncPullChange`/`SyncSnapshot` passes through exactly
/// one of the named functions below -- enforced structurally by
/// `WireMapperBoundaryTests.swift`'s source scan, not by convention.
public enum WireMapperError: Error, Equatable {
    /// A wire value this mapper cannot represent, naming the offending
    /// field. Never substitutes a default or zero value -- a silently
    /// defaulted revision or fingerprint is exactly the class of bug that
    /// makes an acknowledgement match the wrong mutation.
    case invalidField(String)
}

/// The client's own model of the server-issued undo capability (mirrors
/// `apps/desktop/main/adapters/sync.ts`'s `SyncUndoAvailability`/
/// `mapUndoAvailability`). Present only when the accepted command was one
/// the server can compensate.
public struct SyncUndoAvailability: Sendable, Equatable {
    public let handle: String
    public let label: String
    public let expiresAt: String

    public init(handle: String, label: String, expiresAt: String) {
        self.handle = handle
        self.label = label
        self.expiresAt = expiresAt
    }
}

public enum WireMappers {
    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// `Components.Schemas.CommandAcknowledgement` -> `SyncAcknowledgement`
    /// (`LocalStorePort.swift`, the store's own acknowledgement input
    /// shape). `expectedFingerprint` is the CALLER's own stored
    /// fingerprint -- from the durable outbox row -- never re-derived from
    /// the wire response, mirroring desktop's
    /// `mapAcknowledgement(value, expectedFingerprint)`.
    public static func mapCommandAcknowledgement(
        _ acknowledgement: Components.Schemas.CommandAcknowledgement,
        expectedFingerprint: String
    ) throws -> SyncAcknowledgement {
        guard !acknowledgement.mutation_id.isEmpty else {
            throw WireMapperError.invalidField("mutation_id")
        }
        let outcome: SyncAcknowledgement.Outcome = acknowledgement.outcome == .accepted ? .accepted : .alreadySatisfied
        let snapshotJSON = try encodeToJSONString(acknowledgement.snapshot, field: "snapshot")
        return SyncAcknowledgement(
            mutationId: acknowledgement.mutation_id,
            fingerprint: expectedFingerprint,
            outcome: outcome,
            snapshotJSON: snapshotJSON
        )
    }

    /// `Components.Schemas.RestoreAcknowledgement` -> `SyncAcknowledgement`
    /// (04-08-PLAN.md Task 2). `restore-task`'s 200 answer is a richer,
    /// contract-distinct shape than the other nine commands' shared
    /// `CommandAcknowledgement` (it additionally carries `destinations` and
    /// `warnings`) -- those two fields are genuinely out of THIS plan's
    /// scope (no presentation surface consumes them yet) and are
    /// deliberately dropped here rather than smuggled into `snapshotJSON`
    /// unexamined; only `id`/`revision` (the fields `SyncAcknowledgement`'s
    /// settlement path actually reads) are carried through.
    public static func mapRestoreAcknowledgement(
        _ acknowledgement: Components.Schemas.RestoreAcknowledgement,
        expectedFingerprint: String
    ) throws -> SyncAcknowledgement {
        guard !acknowledgement.mutation_id.isEmpty else {
            throw WireMapperError.invalidField("mutation_id")
        }
        let outcome: SyncAcknowledgement.Outcome = acknowledgement.outcome == .accepted ? .accepted : .alreadySatisfied
        let snapshotJSON = try encodeToJSONString(acknowledgement.snapshot, field: "snapshot")
        return SyncAcknowledgement(
            mutationId: acknowledgement.mutation_id,
            fingerprint: expectedFingerprint,
            outcome: outcome,
            snapshotJSON: snapshotJSON
        )
    }

    /// `Components.Schemas.UndoAvailability` -> `SyncUndoAvailability`. A
    /// handle whose shape the contract does not publish throws NAMING THE
    /// FIELD rather than being retained -- retaining a malformed handle
    /// would durably queue a body the server answers 400 `invalid_command`
    /// to, and repairing one would be synthesising a capability, exactly
    /// mirroring desktop's identical validation in `mapUndoAvailability`.
    public static func mapUndoAvailability(_ undo: Components.Schemas.UndoAvailability) throws -> SyncUndoAvailability {
        guard undo.handle.range(of: "^[A-Za-z0-9_-]{43,128}$", options: .regularExpression) != nil else {
            throw WireMapperError.invalidField("handle")
        }
        guard !undo.label.isEmpty else {
            throw WireMapperError.invalidField("label")
        }
        return SyncUndoAvailability(handle: undo.handle, label: undo.label, expiresAt: iso8601String(from: undo.expires_at))
    }

    /// One `SyncFeedEnvelope` -> `SyncPullChange`, or `nil` when the
    /// envelope is not a task/organization snapshot the reducer's
    /// canonical shadow can represent, or is missing the `entity_id` the
    /// reducer keys on (mirrors desktop `pull()`'s `flatMap` discard of
    /// `command_outcome`/`conflict_snapshot`/`collection_tombstone`/
    /// `undo_metadata` rows). This is a structural discard, never a thrown
    /// error -- those envelope kinds are real, valid wire payloads that
    /// simply carry no canonical-shadow effect for this reducer.
    public static func mapSyncFeedEnvelope(_ envelope: Components.Schemas.SyncFeedEnvelope) -> SyncPullChange? {
        guard let entityId = envelope.entity_id else { return nil }
        switch envelope.payload {
        case .TaskSnapshot(let snapshot):
            return SyncPullChange(entityId: entityId, snapshot: mapSyncTaskSnapshot(snapshot))
        case .SyncOrganizationSnapshot(let snapshot):
            return SyncPullChange(entityId: entityId, snapshot: mapSyncOrganizationSnapshot(snapshot))
        case .SyncCommandOutcomePayload, .PersistedConflict, .SyncCollectionTombstone, .SyncUndoMetadata:
            return nil
        }
    }

    /// `Components.Schemas.SyncFeedPage` -> `SyncPullPage`. `cursorFallback`
    /// is the cursor the caller sent the request WITH -- used only when the
    /// server's own `coverage_cursor` is null, exactly as desktop's
    /// `pull()` does (`page.coverage_cursor ?? cursor`).
    public static func mapSyncFeedPage(_ page: Components.Schemas.SyncFeedPage, cursorFallback: String?) -> SyncPullPage {
        SyncPullPage(cursor: page.coverage_cursor ?? cursorFallback ?? "", changes: page.changes.compactMap(mapSyncFeedEnvelope))
    }

    /// `Components.Schemas.SyncBootstrapEntity` -> `SyncPullChange`. Unlike
    /// the feed, every bootstrap entity IS a task/organization snapshot by
    /// contract (`SyncBootstrapEntity.snapshot`'s `oneOf` has exactly those
    /// two members) -- there is no discard case here.
    public static func mapSyncBootstrapEntity(_ entity: Components.Schemas.SyncBootstrapEntity) -> SyncPullChange {
        switch entity.snapshot {
        case .TaskSnapshot(let snapshot):
            return SyncPullChange(entityId: entity.entity_id, snapshot: mapSyncTaskSnapshot(snapshot))
        case .SyncOrganizationSnapshot(let snapshot):
            return SyncPullChange(entityId: entity.entity_id, snapshot: mapSyncOrganizationSnapshot(snapshot))
        }
    }

    public static func mapSyncBootstrapPage(_ page: Components.Schemas.SyncBootstrapPage) -> [SyncPullChange] {
        page.entities.map(mapSyncBootstrapEntity)
    }

    /// Maps the task-snapshot variant of a sync change.
    ///
    /// Takes `TaskSnapshot` -- the schema the server has always sent -- and
    /// not the `SyncTaskSnapshot` this used to name, which required
    /// `project_id`/`tag_ids` and matched nothing the server produces
    /// (04-18-PLAN.md Task 3).
    private static func mapSyncTaskSnapshot(_ snapshot: Components.Schemas.TaskSnapshot) -> SyncSnapshot {
        SyncSnapshot(id: snapshot.id, revision: Int(snapshot.revision), extra: ["title": .string(snapshot.title)])
    }

    private static func mapSyncOrganizationSnapshot(_ snapshot: Components.Schemas.SyncOrganizationSnapshot) -> SyncSnapshot {
        SyncSnapshot(id: snapshot.id, revision: Int(snapshot.revision), extra: ["name": .string(snapshot.name)])
    }

    private static func encodeToJSONString<T: Encodable>(_ value: T, field: String) throws -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw WireMapperError.invalidField(field)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw WireMapperError.invalidField(field)
        }
        return string
    }
}
