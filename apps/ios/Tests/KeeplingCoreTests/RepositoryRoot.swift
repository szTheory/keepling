import Foundation

/// Resolves the monorepo root from `#filePath`, so golden vector files are
/// read straight from `packages/contracts/vectors/` in the source tree --
/// never copied into the test bundle as a SwiftPM `.copy` resource (a copy
/// is a drift vector whose paths cannot escape the target directory).
///
/// 04-RESEARCH.md assumption A3 flagged that `#filePath` behavior under
/// `xcodebuild test` sandboxing was unverified. It resolves correctly: this
/// walk, run inside `xcodebuild test -only-testing:KeeplingCoreTests`,
/// finds the real repository root on the first try. The `KEEPLING_REPO_ROOT`
/// environment-variable fallback below exists for a sandboxing regime where
/// it does not (a lane runner can set it), and whichever mechanism actually
/// resolves the root is recorded in 04-03-SUMMARY.md.
enum RepositoryRoot {
    struct ResolutionFailure: Error, CustomStringConvertible {
        let attemptedPath: String
        var description: String {
            "could not resolve the Keepling repository root by ascending from #filePath or KEEPLING_REPO_ROOT; last attempted path: \(attemptedPath)"
        }
    }

    /// The directory containing both `pnpm-workspace.yaml` and
    /// `packages/contracts/vectors` -- never a hard-coded directory name,
    /// so a rename of the checkout folder does not break resolution.
    static func resolve() throws -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        var lastAttempted = current.path

        while true {
            lastAttempted = current.path
            let workspaceMarker = current.appendingPathComponent("pnpm-workspace.yaml")
            let vectorsMarker = current.appendingPathComponent("packages/contracts/vectors")
            if fileManager.fileExists(atPath: workspaceMarker.path),
               fileManager.fileExists(atPath: vectorsMarker.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        if let envRoot = ProcessInfo.processInfo.environment["KEEPLING_REPO_ROOT"] {
            let candidate = URL(fileURLWithPath: envRoot)
            let workspaceMarker = candidate.appendingPathComponent("pnpm-workspace.yaml")
            let vectorsMarker = candidate.appendingPathComponent("packages/contracts/vectors")
            if fileManager.fileExists(atPath: workspaceMarker.path),
               fileManager.fileExists(atPath: vectorsMarker.path) {
                return candidate
            }
            lastAttempted = candidate.path
        }

        throw ResolutionFailure(attemptedPath: lastAttempted)
    }

    static func vectorsDirectory() throws -> URL {
        try resolve().appendingPathComponent("packages/contracts/vectors")
    }
}
