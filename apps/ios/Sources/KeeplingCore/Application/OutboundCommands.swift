import Foundation

/// The durable outbound intent for every supported iPhone command --
/// capture, edit, clarify, return to inbox, plan for today, unplan,
/// complete, reopen, trash, restore. Mirrors
/// `apps/desktop/main/application/outbound-commands.ts` command-for-command
/// (04-08-PLAN.md Task 1); nothing outside this fixed set is in scope for
/// Phase 4 (no organizations, activity, or search).
///
/// This type is deliberately pure: no store, no clock, no transport. Given a
/// basis and an intent it returns bytes, a fingerprint, and a mutation
/// identity, so the shapes are assertable against the contract without a
/// running app. `CaptureCommand.swift` (the tracer's capture-only command)
/// is left untouched; `capture` here is a second, independent producer of
/// the SAME wire shape so a caller driving the full command set can reach
/// it through ONE type without special-casing capture.
///
/// `Basis` is what this client believes the SERVER holds right now for one
/// task: the last-queued outbox effect if one exists, otherwise the
/// canonical/visible projection row. This module only consumes that value;
/// the caller (the local store / a future plan's UI layer) computes the
/// chain.
///
/// Edit and clarify send ONLY the touched fields together with their
/// matching base values (Phase 1/Phase 3 rule, carried across unchanged):
/// an untouched field is absent from both `fields` and `base_values`
/// because the locked server task and the pure domain reducer own rebase
/// and conflict decisions, and sending an untouched field converts a
/// non-conflict into a conflict.
///
/// `type` stays IN the bytes as an optional discriminator the server
/// verifies against the endpoint and never routes on -- an outbox that
/// survives a relaunch has nothing else to route by, and re-serializing on
/// retry is forbidden (the retry path reads these exact stored bytes).
public enum OutboundCommands {
    public enum ValidationError: Error, Equatable {
        case titleOutOfBounds
        case notesOutOfBounds
        case invalidRevision
        case noTouchedFields
    }

    /// The last state this client believes the server holds for one task.
    /// `expectedRevision` has a contract minimum of 1; a freshly captured,
    /// unacknowledged task resolves to 1 rather than a fabricated number.
    /// The lifecycle fields (`baseCompletedAt`/`baseTrashedAt`/`basePlanned`)
    /// are local-projection-only concepts (mirrors `visible_projection`'s
    /// own columns) carried through unaffected commands so an edit or a
    /// return-to-inbox does not blank a lifecycle state it never touched.
    public struct Basis: Sendable, Equatable {
        public let baseTitle: String
        public let baseNotes: String
        public let basePlannedOn: String?
        public let baseCompletedAt: String?
        public let baseTrashedAt: String?
        public let basePlanned: Bool
        public let expectedRevision: Int

        public init(
            baseTitle: String,
            baseNotes: String,
            basePlannedOn: String? = nil,
            baseCompletedAt: String? = nil,
            baseTrashedAt: String? = nil,
            basePlanned: Bool = false,
            expectedRevision: Int
        ) {
            self.baseTitle = baseTitle
            self.baseNotes = baseNotes
            self.basePlannedOn = basePlannedOn
            self.baseCompletedAt = baseCompletedAt
            self.baseTrashedAt = baseTrashedAt
            self.basePlanned = basePlanned
            self.expectedRevision = expectedRevision
        }
    }

    /// A touched-field edit request. `title`/`notes` are `nil` when
    /// untouched -- absence, not an unchanged copy, is what keeps an
    /// untouched field out of the bytes.
    public struct TouchedFields: Sendable, Equatable {
        public let title: String?
        public let notes: String?
        public init(title: String? = nil, notes: String? = nil) {
            self.title = title
            self.notes = notes
        }
        var isEmpty: Bool { title == nil && notes == nil }
    }

    public enum Lifecycle: String, Sendable, Equatable {
        case complete = "complete_task"
        case reopen = "reopen_task"
        case trash = "trash_task"
        case restore = "restore_task"
    }

    /// The durable outbound command: immutable bytes, a SHA-256 fingerprint
    /// over those exact bytes, a stable mutation identity, its resource
    /// key(s) for outbox lane ordering, and the local projection effect
    /// (mirrors desktop's `OutboundCommand`/`effect`).
    public struct Built: Sendable, Equatable {
        public let type: String
        public let commandBytes: String
        public let fingerprint: String
        public let mutationId: String
        public let taskId: String
        public let resourceKeys: [String]
        public let effect: Effect

        /// Every field the visible projection can show, carried through
        /// verbatim by a command that does not touch it -- never dropped,
        /// since the projection is a replay of (canonical shadow + outbox)
        /// and a missing field would blank the row on the next replay.
        public struct Effect: Sendable, Equatable {
            public let title: String
            public let notes: String
            public let completedAt: String?
            public let trashedAt: String?
            public let planned: Bool
            public let revision: Int
        }
    }

    private static func assertBasis(_ basis: Basis) throws {
        guard basis.expectedRevision >= 1 else { throw ValidationError.invalidRevision }
    }

    private static func fingerprint(_ bytes: String) -> String { sha256Hex(bytes) }

    private static func resourceKeys(taskId: String) -> [String] { ["task:\(taskId)"] }

    // MARK: - capture

    /// Produces the SAME wire shape as `CaptureCommand.build`, as a second,
    /// independent entry point into the full supported set this module
    /// owns. `CaptureCommand.swift` itself is left in place (the tracer's
    /// own producer); this exists so a caller driving the full command set
    /// through ONE type does not special-case capture.
    public static func capture(title rawTitle: String, mutationId: String, taskId: String) throws -> Built {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.unicodeScalars.count <= 512 else { throw ValidationError.titleOutOfBounds }
        let commandBytes = """
        {"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"title":\(jsonString(title)),"type":"capture_task","version":1}
        """
        return Built(
            type: "capture_task",
            commandBytes: commandBytes,
            fingerprint: fingerprint(commandBytes),
            mutationId: mutationId,
            taskId: taskId,
            resourceKeys: resourceKeys(taskId: taskId),
            effect: .init(title: title, notes: "", completedAt: nil, trashedAt: nil, planned: false, revision: 1)
        )
    }

    // MARK: - edit / clarify

    /// `clarify` produces the IDENTICAL wire shape as `edit` -- the contract
    /// aliases `ClarifyTaskCommand` to `EditTaskCommand` (both edit touched
    /// details; clarify additionally moves the task out of Inbox as a
    /// server-side effect this client does not need to express in the
    /// bytes). `asClarify` only changes the `type` discriminator.
    public static func edit(
        taskId: String,
        touched: TouchedFields,
        basis: Basis,
        mutationId: String,
        asClarify: Bool = false
    ) throws -> Built {
        try assertBasis(basis)
        guard !touched.isEmpty else { throw ValidationError.noTouchedFields }

        var fieldPairs: [(String, String)] = []
        var basePairs: [(String, String)] = []
        var resultTitle = basis.baseTitle
        var resultNotes = basis.baseNotes

        if let title = touched.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 512 else { throw ValidationError.titleOutOfBounds }
            fieldPairs.append(("title", jsonString(trimmed)))
            basePairs.append(("title", jsonString(basis.baseTitle)))
            resultTitle = trimmed
        }
        if let notes = touched.notes {
            guard notes.unicodeScalars.count <= 50_000 else { throw ValidationError.notesOutOfBounds }
            fieldPairs.append(("notes", jsonString(notes)))
            basePairs.append(("notes", jsonString(basis.baseNotes)))
            resultNotes = notes
        }

        // Sorted so the fields/base_values key order is deterministic.
        let fieldsJSON = jsonObjectLiteral(fieldPairs.sorted { $0.0 < $1.0 })
        let baseValuesJSON = jsonObjectLiteral(basePairs.sorted { $0.0 < $1.0 })
        let type = asClarify ? "clarify_task" : "edit_task"
        let commandBytes = """
        {"base_values":\(baseValuesJSON),"expected_revision":\(basis.expectedRevision),"fields":\(fieldsJSON),"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"type":"\(type)","version":1}
        """
        return Built(
            type: type,
            commandBytes: commandBytes,
            fingerprint: fingerprint(commandBytes),
            mutationId: mutationId,
            taskId: taskId,
            resourceKeys: resourceKeys(taskId: taskId),
            effect: .init(
                title: resultTitle,
                notes: resultNotes,
                completedAt: basis.baseCompletedAt,
                trashedAt: basis.baseTrashedAt,
                planned: basis.basePlanned,
                revision: basis.expectedRevision + 1
            )
        )
    }

    // MARK: - return to inbox

    /// Explicit restoration of canonical Inbox membership: the local effect
    /// clears completion/trash state and un-plans, since "return to inbox"
    /// means the task is no longer Completed, Trashed, or on Today.
    public static func returnToInbox(taskId: String, basis: Basis, mutationId: String) throws -> Built {
        try assertBasis(basis)
        let commandBytes = """
        {"expected_revision":\(basis.expectedRevision),"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"type":"return_to_inbox","version":1}
        """
        return Built(
            type: "return_to_inbox",
            commandBytes: commandBytes,
            fingerprint: fingerprint(commandBytes),
            mutationId: mutationId,
            taskId: taskId,
            resourceKeys: resourceKeys(taskId: taskId),
            effect: .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: nil, trashedAt: nil, planned: false, revision: basis.expectedRevision + 1)
        )
    }

    // MARK: - lifecycle: complete / reopen / trash / restore

    /// `acceptedAt` is this device's own local clock reading, used ONLY for
    /// the optimistic local effect (`completed_at`/`trashed_at`) -- it never
    /// appears in the wire bytes themselves, since `TaskLifecycleCommand`
    /// carries no timestamp field; the server's own acceptance time is what
    /// actually lands in `canonical_shadow` once a real acknowledgement or
    /// pull replaces this optimistic guess.
    public static func lifecycle(
        _ transition: Lifecycle,
        taskId: String,
        basis: Basis,
        mutationId: String,
        acceptedAt: String
    ) throws -> Built {
        try assertBasis(basis)
        let commandBytes = """
        {"expected_revision":\(basis.expectedRevision),"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"type":"\(transition.rawValue)","version":1}
        """
        let effect: Built.Effect
        switch transition {
        case .complete:
            effect = .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: acceptedAt, trashedAt: basis.baseTrashedAt, planned: basis.basePlanned, revision: basis.expectedRevision + 1)
        case .reopen:
            effect = .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: nil, trashedAt: basis.baseTrashedAt, planned: basis.basePlanned, revision: basis.expectedRevision + 1)
        case .trash:
            effect = .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: basis.baseCompletedAt, trashedAt: acceptedAt, planned: basis.basePlanned, revision: basis.expectedRevision + 1)
        case .restore:
            effect = .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: basis.baseCompletedAt, trashedAt: nil, planned: basis.basePlanned, revision: basis.expectedRevision + 1)
        }
        return Built(
            type: transition.rawValue,
            commandBytes: commandBytes,
            fingerprint: fingerprint(commandBytes),
            mutationId: mutationId,
            taskId: taskId,
            resourceKeys: resourceKeys(taskId: taskId),
            effect: effect
        )
    }

    // MARK: - plan for today / unplan

    /// The account day a `plan_for_today` resolves is the SERVER's, derived
    /// from the account timezone at acceptance -- this client does not know
    /// it and must not invent one. The local `planned` boolean flips
    /// optimistically for immediate UI feedback; the actual date arrives
    /// only from a real acknowledgement or pull.
    public static func planForToday(_ planned: Bool, taskId: String, basis: Basis, mutationId: String) throws -> Built {
        try assertBasis(basis)
        let type = planned ? "plan_for_today" : "unplan_task"
        let basePlannedJSON = basis.basePlannedOn.map(jsonString) ?? "null"
        let commandBytes = """
        {"base_planned_on":\(basePlannedJSON),"expected_revision":\(basis.expectedRevision),"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"type":"\(type)","version":1}
        """
        return Built(
            type: type,
            commandBytes: commandBytes,
            fingerprint: fingerprint(commandBytes),
            mutationId: mutationId,
            taskId: taskId,
            resourceKeys: resourceKeys(taskId: taskId),
            effect: .init(title: basis.baseTitle, notes: basis.baseNotes, completedAt: basis.baseCompletedAt, trashedAt: basis.baseTrashedAt, planned: planned, revision: basis.expectedRevision + 1)
        )
    }
}

// MARK: - JSON literal helpers (deterministic, sorted-key bytes)

private func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let encoded = String(data: data, encoding: .utf8)!
    return String(encoded.dropFirst().dropLast())
}

private func jsonObjectLiteral(_ pairs: [(String, String)]) -> String {
    "{" + pairs.map { "\(jsonString($0.0)):\($0.1)" }.joined(separator: ",") + "}"
}
