import Foundation

/// Produces the exact durable command bytes for one `capture_task` mutation
/// -- the same shape `apps/desktop/main/application/DesktopApplication.ts`'s
/// `capture` method fixes inline (04-01-PLAN.md Task 3): `mutation_id`,
/// `task_id`, `title`, `type`, `version`, JSON-serialized with alphabetized
/// keys so the bytes (and therefore the fingerprint) are deterministic.
///
/// `type` stays IN the bytes because an outbox that survives a relaunch has
/// nothing else to route by, and re-serializing on retry is forbidden --
/// the server verifies it against the endpoint and never routes on it.
public enum CaptureCommand {
    public struct Built: Sendable, Equatable {
        public let commandBytes: String
        public let fingerprint: String
        public let mutationId: String
        public let taskId: String
        public let title: String
    }

    public enum ValidationError: Error, Equatable {
        case titleOutOfBounds
    }

    /// `mutationId`/`taskId`/`acceptedAt` are supplied rather than generated
    /// here so a test can pin the bytes and so the caller owns identity.
    public static func build(
        title rawTitle: String,
        mutationId: String,
        taskId: String
    ) throws -> Built {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.unicodeScalars.count <= 512 else {
            throw ValidationError.titleOutOfBounds
        }

        // Keys are written in sorted order to match the contract's request
        // body shape deterministically -- the server does not care about
        // key order, but a deterministic fingerprint requires the SAME
        // bytes on every serialization of the same logical command.
        let commandBytes = """
        {"mutation_id":\(jsonString(mutationId)),"task_id":\(jsonString(taskId)),"title":\(jsonString(title)),"type":"capture_task","version":1}
        """
        let fingerprint = sha256Hex(commandBytes)

        return Built(commandBytes: commandBytes, fingerprint: fingerprint, mutationId: mutationId, taskId: taskId, title: title)
    }
}

private func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let encoded = String(data: data, encoding: .utf8)!
    return String(encoded.dropFirst().dropLast())
}
