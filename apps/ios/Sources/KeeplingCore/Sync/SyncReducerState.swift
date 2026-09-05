import Foundation

/// A minimal, Sendable, Equatable JSON value used to carry a snapshot's
/// opaque application fields (e.g. `title`) through `SyncReducerState`
/// losslessly. The reducer itself never inspects anything inside `extra` --
/// exactly as the Elixir reference model's untyped JSON-map state only ever
/// reads the `"revision"` key off a snapshot and passes the rest through
/// unexamined.
public indirect enum SyncJSON: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([SyncJSON])
    case object([String: SyncJSON])

    /// Converts a `JSONSerialization`-produced value (`String`, `NSNumber`,
    /// `NSNull`, `[Any]`, `[String: Any]`) into a `SyncJSON`. `NSNumber`
    /// booleans and numbers are indistinguishable by Swift's `as? Bool`
    /// bridging alone, so the boolean check goes through `CFBooleanGetTypeID`
    /// first, before the numeric fallback.
    public static func from(_ any: Any) -> SyncJSON {
        if any is NSNull { return .null }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let string = any as? String { return .string(string) }
        if let array = any as? [Any] { return .array(array.map(SyncJSON.from)) }
        if let object = any as? [String: Any] { return .object(object.mapValues(SyncJSON.from)) }
        return .null
    }
}

/// One entity snapshot: an opaque id/revision pair plus whatever other
/// fields the wire vector carries (title, etc). Only `id` and `revision`
/// are ever read by `SyncReducer` -- mirrors `reference_model.ex`'s
/// `apply_changes/2`, which compares only `snapshot["revision"]`.
public struct SyncSnapshot: Sendable, Equatable {
    public var id: String
    public var revision: Int
    public var extra: [String: SyncJSON]

    public init(id: String, revision: Int, extra: [String: SyncJSON] = [:]) {
        self.id = id
        self.revision = revision
        self.extra = extra
    }
}

/// One durable local mutation as the reducer sees it -- the full wire
/// shape the `sync-state-machine.schema.json` `mutation` definition
/// declares, including explicit `dependencies` (unlike `LocalMutation` in
/// `LocalStorePort.swift`, which is the store's narrower tracer-era shape).
public struct SyncMutation: Sendable, Equatable {
    public var mutationId: String
    public var fingerprint: String
    public var commandBytes: String
    public var resourceKeys: [String]
    public var dependencies: [String]
    public var acceptedAt: String
    public var effectEntityId: String
    public var effectSnapshot: SyncSnapshot

    public init(
        mutationId: String,
        fingerprint: String,
        commandBytes: String,
        resourceKeys: [String],
        dependencies: [String],
        acceptedAt: String,
        effectEntityId: String,
        effectSnapshot: SyncSnapshot
    ) {
        self.mutationId = mutationId
        self.fingerprint = fingerprint
        self.commandBytes = commandBytes
        self.resourceKeys = resourceKeys
        self.dependencies = dependencies
        self.acceptedAt = acceptedAt
        self.effectEntityId = effectEntityId
        self.effectSnapshot = effectSnapshot
    }
}

/// The closed terminal-outcome set (mirrors `reference_model.ex`'s
/// `@terminal_outcomes`). Only `accepted` and `already_satisfied` are
/// "successful" for dependency-satisfaction purposes
/// (`@successful_outcomes`).
public enum SyncTerminalOutcome: String, Sendable, Equatable, CaseIterable {
    case accepted
    case alreadySatisfied = "already_satisfied"
    case rejected
    case stale
    case conflict

    public static let successful: Set<SyncTerminalOutcome> = [.accepted, .alreadySatisfied]
}

/// One journal entry: `outcome` is `"pending"` until a terminal
/// acknowledgement settles it, at which point it becomes one of
/// `SyncTerminalOutcome`'s raw values and `terminalSnapshot` is populated.
public struct SyncJournalEntry: Sendable, Equatable {
    public var acceptedAt: String
    public var commandBytes: String
    public var fingerprint: String
    public var outcome: String
    public var resourceKeys: [String]
    public var terminalSnapshot: SyncSnapshot?

    public init(
        acceptedAt: String,
        commandBytes: String,
        fingerprint: String,
        outcome: String,
        resourceKeys: [String],
        terminalSnapshot: SyncSnapshot? = nil
    ) {
        self.acceptedAt = acceptedAt
        self.commandBytes = commandBytes
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.resourceKeys = resourceKeys
        self.terminalSnapshot = terminalSnapshot
    }
}

/// A bounded page of canonical changes pulled from the server (mirrors the
/// `pull` action's `page` shape in `sync-state-machine.schema.json`).
public struct SyncPullChange: Sendable, Equatable {
    public var entityId: String
    public var snapshot: SyncSnapshot
    public init(entityId: String, snapshot: SyncSnapshot) {
        self.entityId = entityId
        self.snapshot = snapshot
    }
}

public struct SyncPullPage: Sendable, Equatable {
    public var cursor: String
    public var changes: [SyncPullChange]
    public init(cursor: String, changes: [SyncPullChange]) {
        self.cursor = cursor
        self.changes = changes
    }
}

/// A terminal server answer to one durable mutation (mirrors the
/// `acknowledge` action's `acknowledgement` shape).
public struct SyncAcknowledgementInput: Sendable, Equatable {
    public var mutationId: String
    public var fingerprint: String
    public var outcome: SyncTerminalOutcome
    public var snapshot: SyncSnapshot
    public init(mutationId: String, fingerprint: String, outcome: SyncTerminalOutcome, snapshot: SyncSnapshot) {
        self.mutationId = mutationId
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.snapshot = snapshot
    }
}

/// Errors `SyncReducer` can return. Every case corresponds 1:1 to an atom
/// `reference_model.ex` returns, plus `replayMismatch` for the Swift
/// reducer's own strengthening (idempotent replay of an already-settled
/// acknowledgement raises only when the REPLAYED outcome disagrees with
/// the one already recorded -- see `SyncReducer.acknowledge`).
public enum SyncReducerError: Error, Sendable, Equatable {
    case mutationIdentityReused
    case orphanDependency
    case pullPageTooLarge
    case acknowledgementMismatch
    case unknownMutation
    case invalidDependencyGraph
    case dependencyCycle
}

/// Named, typed fields mapping one-to-one onto `reference_model.ex`'s state
/// keys (`canonical_shadow`, `visible`, `journal`, `dependencies`,
/// `outbox`, `cursor`, `fence`) -- kept separate rather than merged into one
/// opaque blob so a vector fixture can be traced through both
/// implementations by eye (04-03-PLAN.md Task 2).
public struct SyncReducerState: Sendable, Equatable {
    public var canonicalShadow: [String: SyncSnapshot]
    public var visible: [String: SyncSnapshot]
    public var journal: [String: SyncJournalEntry]
    public var dependencies: [String: [String]]
    public var outbox: [SyncMutation]
    public var cursor: String?
    public var fence: String?

    public init(
        canonicalShadow: [String: SyncSnapshot] = [:],
        visible: [String: SyncSnapshot] = [:],
        journal: [String: SyncJournalEntry] = [:],
        dependencies: [String: [String]] = [:],
        outbox: [SyncMutation] = [],
        cursor: String? = nil,
        fence: String? = nil
    ) {
        self.canonicalShadow = canonicalShadow
        self.visible = visible
        self.journal = journal
        self.dependencies = dependencies
        self.outbox = outbox
        self.cursor = cursor
        self.fence = fence
    }
}
