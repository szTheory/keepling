import Foundation

/// One exported file's exact bytes, keyed by its filename within the
/// bundle. A plain value type -- never a directory URL, a file handle, or
/// anything a caller could use to discover a SECOND location on disk this
/// plan did not intend to expose.
public struct DiagnosticExportBundle: Sendable, Equatable {
    public let files: [String: Data]
    public init(files: [String: Data]) {
        self.files = files
    }
}

/// Produces the bundle the unrecoverable presentation state's Export action
/// offers (D-23, 04-15-PLAN.md Task 2). `bundle(from:)` takes a diagnostic
/// log as its ONLY parameter -- there is structurally no second parameter
/// through which a path to the on-disk task store, its journal, or any
/// other on-device file could ever arrive. This mirrors the same technique
/// `LocalNamespaceDataRemoval.removeAll(from:)` already uses to make server
/// deletion unreachable from local-data removal: the guarantee lives in the
/// function's own signature, not in a promise about what its body chooses
/// to do with a wider parameter list.
public enum DiagnosticExport {
    /// The bundle's one and only file. Named as a constant so a test
    /// enumerating the bundle's contents names the exact same value this
    /// type produces, rather than restating the string.
    public static let logFileName = "diagnostic-log.json"

    /// Every currently-retained event, serialized as a closed-vocabulary
    /// JSON array -- one object per event, each field either a named enum
    /// case, a UUID, or an ISO 8601 timestamp. No field here is free text:
    /// this function reads only `DiagnosticEvent`'s own four fields, which
    /// is itself structurally incapable of holding a task title, note,
    /// draft, credential, token, cursor, or fingerprint (see
    /// `DiagnosticEvent.swift`'s own doc comment).
    public static func serializedLog(from log: DiagnosticLog) -> Data {
        let formatter = ISO8601DateFormatter()
        let objects: [[String: String]] = log.allEvents().map { event in
            [
                "operation": describe(event.operation),
                "transition": event.transition.rawValue,
                "error_class": event.errorClass.rawValue,
                "timestamp": formatter.string(from: event.timestamp),
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys, .prettyPrinted])) ?? Data("[]".utf8)
    }

    /// The bundle: exactly one file, `logFileName`, containing
    /// `serializedLog(from:)`'s bytes -- and nothing else. A caller (a
    /// future Export action) writes `files` to a temporary directory of its
    /// own choosing and hands it to a share sheet; this function itself
    /// never touches the filesystem, so it cannot be the place a second
    /// file leaks in from.
    public static func bundle(from log: DiagnosticLog) -> DiagnosticExportBundle {
        DiagnosticExportBundle(files: [logFileName: serializedLog(from: log)])
    }

    private static func describe(_ operation: DiagnosticOperationIdentity) -> String {
        switch operation {
        case .mutation(let id): return id.uuidString
        case .none: return "none"
        }
    }
}
