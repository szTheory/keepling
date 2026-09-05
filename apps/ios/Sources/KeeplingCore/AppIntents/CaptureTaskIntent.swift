import AppIntents
import Foundation

/// Reachable from Shortcuts, Siri, the Action Button, and Spotlight actions
/// (D-35, IOS-01). Runs in the main app process against
/// `IntentStoreAccess`'s single shared store handle and invokes the SAME
/// `OutboundCommands.capture` producer the capture sheet uses (04-08-PLAN.md
/// Task 1) -- an intent-captured task is indistinguishable, byte for byte,
/// from one captured through the sheet.
public struct CaptureTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture Task"
    public static let description = IntentDescription("Capture a new task in Keepling.")

    @Parameter(title: "Title")
    public var title: String

    public init() {
        self.title = ""
    }

    public init(title: String) {
        self.title = title
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$title)")
    }

    /// Refuses an empty/whitespace-only title with a named error before any
    /// store access at all, then durably accepts the capture through the
    /// same fence-checked `acceptMutation` path every other write takes
    /// (`GRDBLocalStore.acceptMutation` checks the sync fence on a read
    /// connection BEFORE any transaction opens -- no separate fence check
    /// is needed here). Returns the newly captured task's id.
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw CaptureTaskIntentError.emptyTitle
        }

        let store = try IntentStoreAccess.sharedStore()
        let mutationId = UUID().uuidString
        let taskId = UUID().uuidString
        let built = try OutboundCommands.capture(title: trimmedTitle, mutationId: mutationId, taskId: taskId)
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
        return .result(value: taskId)
    }
}

public enum CaptureTaskIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case emptyTitle

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle:
            return "The task title can't be empty."
        }
    }
}
