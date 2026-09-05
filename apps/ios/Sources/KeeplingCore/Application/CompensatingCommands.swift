import Foundation

/// Builds the compensating `undo_task` command for the current
/// `UndoAvailability`, or refuses -- never both, and never a silent no-op
/// (D-34: the prohibition this whole type exists to satisfy). Undo is a
/// compensating SEMANTIC action, never a local retraction: the server owns
/// whether the compensation applied, so the client sends a fresh mutation
/// identity carrying the server-issued handle and settles on the server's
/// own answer exactly as it does for any other command -- the compensating
/// bytes this type returns travel through `KeeplingSyncAdapter.push`'s same
/// `undo_task` routing and `GRDBLocalStore.acceptMutation`'s same outbox
/// path as any of `OutboundCommands`' ten commands.
///
/// Deliberately pure: no store, no clock, no transport. `currentTitle`/
/// `currentEffect` are the CALLER's own read of the task's CURRENT local
/// projection state, carried through unchanged (mirrors
/// `OutboundCommands.edit`'s "carry the base value through" discipline) --
/// the compensating command's own local optimistic effect must not blank a
/// field it does not touch, because the REAL local effect of the
/// compensation itself is not known until the server settles the
/// `undo_task` acknowledgement.
public enum CompensatingCommands {
    /// Mirrors `packages/contracts/vectors/undo.json`'s `supported` set --
    /// the closed matrix of ORIGINAL command types the server can
    /// compensate. Checked defensively: in practice `UndoAvailability` is
    /// only ever derived from a settled acknowledgement that already
    /// carries a server-issued handle, and the server only ever mints one
    /// for a command in this matrix -- this gate exists so a regression in
    /// that server contract is caught here, loudly, rather than silently
    /// building bytes the server would refuse.
    public static let supportedOriginalCommandTypes: Set<String> = [
        "edit_task", "clarify_task", "return_to_inbox", "plan_for_today",
        "unplan_task", "complete_task", "reopen_task", "trash_task", "restore_task",
    ]

    /// Authored refusal copy (D-34's own prohibition: refuse LOUDLY at the
    /// point of action, never silently and never deferred). Mirrors
    /// desktop's `undo_unavailable` presentation copy, adapted to this
    /// client's own vocabulary -- neither case claims a fact this client
    /// cannot know (it never guesses "in flight" vs "never sent", because
    /// `UndoAvailability` structurally cannot exist for an unacknowledged
    /// mutation in the first place: it is derived only from a SETTLED
    /// acknowledgement).
    public enum UndoRefusalReason: Sendable, Equatable {
        /// Covers BOTH "nothing has ever been accepted" and "the last
        /// accepted command's mutation was never acknowledged" -- an
        /// `UndoAvailability` only ever exists once a server-issued handle
        /// has actually settled, so an unacknowledged mutation
        /// structurally never produces one; refusing here IS refusing
        /// that case, with zero store mutations, because this type never
        /// touches a store.
        case nothingToUndo
        /// The defensive matrix gate tripped -- should never happen in
        /// production (see `supportedOriginalCommandTypes`'s own doc
        /// comment).
        case unsupportedOriginalCommandType

        public var copy: String {
            switch self {
            case .nothingToUndo:
                return "This change hasn’t reached the server yet, so it can’t be undone. Nothing was changed."
            case .unsupportedOriginalCommandType:
                return "This change can’t be undone. Nothing was changed."
            }
        }
    }

    /// The durable compensating command: immutable bytes, a SHA-256
    /// fingerprint over those exact bytes, a FRESH mutation identity, its
    /// resource key(s), and the CARRIED-THROUGH (never blanked) local
    /// projection effect -- shaped identically to what
    /// `LocalMutation.init` and `KeeplingSyncAdapter.push`'s `undo_task`
    /// routing both expect, so a caller hands this straight to
    /// `acceptMutation` exactly as it would any `OutboundCommands.Built`.
    public struct Built: Sendable, Equatable {
        public let type: String
        public let commandBytes: String
        public let fingerprint: String
        public let mutationId: String
        public let taskId: String
        public let resourceKeys: [String]
        public let title: String
        public let effect: LocalMutation.ProjectionEffect
    }

    public enum InvocationOutcome: Sendable, Equatable {
        case compensating(Built)
        case refused(UndoRefusalReason)
    }

    /// Invokes undo against `current`. `current == nil` refuses with
    /// `.nothingToUndo` and returns without building anything -- zero
    /// store mutations, because there is nothing here to mutate a store
    /// with.
    public static func invoke(
        current: UndoAvailability?,
        mutationId: String,
        currentTitle: String,
        currentEffect: LocalMutation.ProjectionEffect
    ) -> InvocationOutcome {
        guard let current else { return .refused(.nothingToUndo) }
        guard supportedOriginalCommandTypes.contains(current.originalCommandType) else {
            return .refused(.unsupportedOriginalCommandType)
        }
        let commandBytes = """
        {"handle":\(jsonString(current.handle)),"mutation_id":\(jsonString(mutationId)),"type":"undo_task","version":1}
        """
        let built = Built(
            type: "undo_task",
            commandBytes: commandBytes,
            fingerprint: sha256Hex(commandBytes),
            mutationId: mutationId,
            taskId: current.taskId,
            resourceKeys: ["task:\(current.taskId)"],
            title: currentTitle,
            effect: currentEffect
        )
        return .compensating(built)
    }
}

private func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let encoded = String(data: data, encoding: .utf8)!
    return String(encoded.dropFirst().dropLast())
}
