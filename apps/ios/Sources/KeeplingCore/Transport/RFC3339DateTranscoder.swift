import Foundation
import OpenAPIRuntime

/// Decodes the timestamps the real server actually sends.
///
/// MEASURED DEFECT this exists to fix (04-18-PLAN.md Task 3). Phoenix emits
/// RFC 3339 with MICROSECOND precision -- `2026-09-08T17:21:54.614710Z` --
/// which is fully conformant: RFC 3339's `time-secfrac` permits any number
/// of fractional digits, and the contract says `format: date-time`, which is
/// RFC 3339.
///
/// swift-openapi-runtime's default `ISO8601DateTranscoder` is built on
/// `ISO8601DateFormatter`, which rejects fractional seconds outright unless
/// `.withFractionalSeconds` is set, and even then is only reliable for
/// three digits. So EVERY response carrying a timestamp -- which is every
/// task snapshot and every sync page -- failed to decode, surfacing as
/// `DecodingError: Expected date string to be ISO8601-formatted` wrapped in
/// `SyncUnreachable`. The server answered 201; the client could not read it.
///
/// The consequence is worth stating plainly, because it is larger than a
/// test defect: the shipping app could never have synchronised with the
/// real server. Nothing caught it because every sync test in this
/// repository used a stubbed `SyncPort` or a fake `ClientTransport` with
/// hand-written dates, and the one real-stack test was skipping.
///
/// The server is conformant and the client was not, so the fix belongs
/// here rather than in a narrower server output format -- narrowing the
/// server would also break the desktop client, which parses these strings
/// correctly today.
public struct RFC3339DateTranscoder: DateTranscoder {
    public init() {}

    /// Built per call rather than held in a `static let`.
    ///
    /// `ISO8601DateFormatter` is not `Sendable`, so a shared static is a
    /// concurrency error under Swift 6 and would need a lock to be sound.
    /// Constructing one costs microseconds and this runs a handful of times
    /// per sync page; paying that is preferable to hand-rolled locking
    /// around a mutable formatter, which is a classic source of rare,
    /// unreproducible decode failures.
    private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    /// Encodes WITHOUT fractional seconds.
    ///
    /// Deliberate: the app is a writer of commands, and a plain RFC 3339
    /// second-precision timestamp is accepted by every reader. Emitting
    /// more precision than is needed would make the client's own output a
    /// second compatibility surface to keep working.
    public func encode(_ date: Date) throws -> String {
        Self.formatter(fractionalSeconds: false).string(from: date)
    }

    public func decode(_ string: String) throws -> Date {
        if let date = Self.formatter(fractionalSeconds: true).date(from: string) { return date }
        if let date = Self.formatter(fractionalSeconds: false).date(from: string) { return date }

        // Fractional precision beyond what ISO8601DateFormatter accepts.
        // Truncate to milliseconds rather than rejecting: sub-millisecond
        // precision carries no meaning for this domain, and a timestamp the
        // server is entitled to send must not be able to fail a sync.
        if let dot = string.firstIndex(of: "."),
           let zoneStart = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let fraction = string[string.index(after: dot)..<zoneStart]
            if !fraction.isEmpty {
                let truncated = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
                let normalized = "\(string[string.startIndex..<dot]).\(truncated)\(string[zoneStart...])"
                if let date = Self.formatter(fractionalSeconds: true).date(from: normalized) { return date }
            }
        }

        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "not an RFC 3339 date-time: \(string)")
        )
    }
}
