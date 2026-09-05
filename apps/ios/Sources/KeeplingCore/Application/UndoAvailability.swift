import Foundation

/// Derivation logic for `UndoAvailability` (the value type itself is
/// declared in `Storage/LocalStorePort.swift` -- see that file's own doc
/// comment for why: `WireMapperBoundaryTests` requires a type that shares
/// its name with a generated wire schema to be declared locally in the
/// file that uses it, not imported from elsewhere).
///
/// `GRDBLocalStore.acknowledge` is the ONLY caller: it retains the
/// singleton this type describes in `namespace_metadata` (keyed
/// `current_undo_availability`), replacing it on every settled
/// acknowledgement that carries a handle and DELETING it on every settled
/// acknowledgement that does not (`derive` returning `nil` IS that
/// clearing signal). This is what makes undo single-level: the latest
/// supported change only, matching the Mac contract -- a second accepted
/// command, even one from a different task, supersedes the first task's
/// still-unused undo.
public extension UndoAvailability {
    /// Derives the NEXT current undo availability from a just-settled
    /// acknowledgement. An acknowledgement carrying a server-issued handle
    /// (`acknowledgement.undo`) supersedes any previous availability; one
    /// carrying none clears it -- returning `nil` here IS that clearing
    /// signal, read by the caller as "delete the singleton", never as
    /// "leave the old one standing".
    ///
    /// `taskId`/`originalCommandType` are the CALLER's own read of the
    /// settled mutation's own stored fields (`immutable_commands.task_id`/
    /// the `type` discriminator inside `immutable_commands.command_bytes`)
    /// -- this function never re-derives them from the acknowledgement
    /// itself, which carries neither.
    static func derive(
        from acknowledgement: SyncAcknowledgement,
        taskId: String,
        originalCommandType: String
    ) -> UndoAvailability? {
        guard let undo = acknowledgement.undo else { return nil }
        return UndoAvailability(
            mutationId: acknowledgement.mutationId,
            taskId: taskId,
            handle: undo.handle,
            label: undo.label,
            expiresAt: undo.expiresAt,
            originalCommandType: originalCommandType
        )
    }
}
