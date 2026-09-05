import AppIntents
import Foundation

/// Reachable from Shortcuts, Siri, the Action Button, and Spotlight actions
/// (D-35, IOS-01). Runs in the main app process against
/// `IntentStoreAccess`'s single shared store handle and invokes the SAME
/// `OutboundCommands.lifecycle(.complete, ...)` producer the task detail
/// view's Complete control uses (04-08-PLAN.md Task 1 / 04-09-PLAN.md
/// Task 3).
public struct CompleteTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Complete Task"
    public static let description = IntentDescription("Mark a Keepling task complete.")

    @Parameter(title: "Task ID")
    public var taskID: String

    public init() {
        self.taskID = ""
    }

    public init(taskID: String) {
        self.taskID = taskID
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$taskID)")
    }

    /// Against an unknown task: refuses with a named error, zero store
    /// mutations. Against an already-completed task: a no-op success --
    /// the task is read but `acceptMutation` is never called, so nothing
    /// is mutated. Against an existing open task: completes it durably
    /// through the same fence-checked `acceptMutation` path every other
    /// write takes.
    public func perform() async throws -> some IntentResult & ReturnsValue<CompleteTaskIntentOutcome> {
        let store = try IntentStoreAccess.sharedStore()
        let snapshot = try await IntentStoreAccess.performOffMain { try store.snapshot() }
        guard let row = snapshot.tasks.first(where: { $0.taskId == taskID }) else {
            throw CompleteTaskIntentError.unknownTask
        }
        guard row.completedAt == nil else {
            return .result(value: .alreadyCompleted)
        }

        let revision = try await IntentStoreAccess.performOffMain { try store.expectedRevision(forTaskId: taskID) }
        let basis = OutboundCommands.Basis(
            baseTitle: row.title,
            baseNotes: row.notes,
            baseCompletedAt: row.completedAt,
            baseTrashedAt: row.trashedAt,
            basePlanned: row.planned,
            expectedRevision: revision
        )
        let built = try OutboundCommands.lifecycle(
            .complete,
            taskId: taskID,
            basis: basis,
            mutationId: UUID().uuidString,
            acceptedAt: ISO8601DateFormatter().string(from: Date())
        )
        let mutation = LocalMutation(
            mutationId: built.mutationId,
            taskId: built.taskId,
            commandBytes: built.commandBytes,
            fingerprint: built.fingerprint,
            acceptedAt: ISO8601DateFormatter().string(from: Date()),
            resourceKeys: built.resourceKeys,
            title: built.effect.title,
            effect: LocalMutation.ProjectionEffect(
                notes: built.effect.notes,
                completedAt: built.effect.completedAt,
                trashedAt: built.effect.trashedAt,
                planned: built.effect.planned
            )
        )
        _ = try await IntentStoreAccess.performOffMain { try store.acceptMutation(mutation) }
        return .result(value: .completed)
    }
}

public enum CompleteTaskIntentOutcome: String, Sendable {
    case completed
    case alreadyCompleted
}

extension CompleteTaskIntentOutcome: AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Complete Task Outcome"
    public static let caseDisplayRepresentations: [CompleteTaskIntentOutcome: DisplayRepresentation] = [
        .completed: "Completed",
        .alreadyCompleted: "Already completed"
    ]
}

public enum CompleteTaskIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case unknownTask

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unknownTask:
            return "That task couldn't be found."
        }
    }
}
