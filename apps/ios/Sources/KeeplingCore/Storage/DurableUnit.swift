import Foundation

/// The store's durable unit: the `.sqlite` database file plus its `-wal`
/// and `-shm` sidecars, treated as ONE value (D-09, D-38 inherited).
///
/// A code path that reads, moves, copies, deletes, or backup-excludes the
/// `.sqlite` file alone -- forgetting the two sidecars a live WAL-mode
/// connection depends on -- is exactly the defect this type exists to
/// prevent: a partial operation can hand a "restored" store a database file
/// with no matching WAL, silently losing every not-yet-checkpointed write.
/// Every place `GRDBLocalStore` handles its own store path goes through
/// this type (04-06-PLAN.md Task 2).
public struct DurableUnit: Sendable, Equatable {
    /// Every path this unit owns, in a fixed order: the database file
    /// first, then its two sidecars. `move`/`copy`/`delete` iterate this
    /// list and act only on paths that currently exist -- a WAL-mode
    /// connection that has never had a concurrent reader may not yet have
    /// created a `-shm` file, and that absence is not itself a fault.
    public let databasePath: String

    public var walPath: String { databasePath + "-wal" }
    public var shmPath: String { databasePath + "-shm" }
    public var allPaths: [String] { [databasePath, walPath, shmPath] }

    /// The exact suffixes named above, for callers (tests) that need to
    /// name a specific member of the unit without restating the strings.
    public enum Member: String, Sendable, Equatable, CaseIterable {
        case database = ""
        case wal = "-wal"
        case shm = "-shm"
    }

    public enum DurableUnitError: Error, Equatable {
        /// A move/copy/delete was stopped before touching the filesystem
        /// (or was fully rolled back after a partial attempt) because one
        /// member's operation could not proceed. Names the member so a
        /// test asserting "acts on all three or none" can name exactly
        /// which one it forced to fail.
        case partialOperationPrevented(DurableUnit.Member)
    }

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    // MARK: - Backup exclusion (D-09)

    /// Marks every member that currently exists as excluded from device
    /// backup. Never throws on a member that does not exist -- a fresh
    /// store may not have a `-shm` file yet, and that is not a failure of
    /// this call.
    public func excludeFromBackup() throws {
        for path in allPaths where FileManager.default.fileExists(atPath: path) {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
    }

    /// Reads back whether every EXISTING member is currently marked
    /// excluded from backup. A unit with no members on disk yet reports
    /// `true` vacuously -- there is nothing to have failed to exclude.
    public func isFullyExcludedFromBackup() throws -> Bool {
        for path in allPaths where FileManager.default.fileExists(atPath: path) {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isExcludedFromBackupKey])
            if values.isExcludedFromBackup != true { return false }
        }
        return true
    }

    // MARK: - All-or-none move / copy / delete (D-09)

    /// Copies every existing member to the same-suffixed path rooted at
    /// `destinationDatabasePath`. All existing members copy, or none do --
    /// staged via temporary destination files that are only "revealed" (by
    /// removing them, since a genuine rollback here means "as if the copy
    /// never started") once every member has copied successfully; on any
    /// failure, every already-copied destination is removed before the
    /// error propagates.
    ///
    /// `__test_failAt` is a test-only injection point (never exercised by
    /// production callers, which always pass `nil`) forcing the named
    /// member's copy to fail -- the mechanism `BackupReplayTests`/
    /// `DurableUnitTests`-style callers use to prove the all-or-none claim
    /// structurally rather than by inspection.
    public func copy(to destinationDatabasePath: String, __test_failAt: Member? = nil) throws {
        try transferAllOrNone(
            destinationDatabasePath: destinationDatabasePath,
            failAt: __test_failAt,
            operation: { source, destination in try FileManager.default.copyItem(atPath: source, toPath: destination) },
            rollback: { _, destination in try? FileManager.default.removeItem(atPath: destination) }
        )
    }

    /// Moves every existing member to the same-suffixed path rooted at
    /// `destinationDatabasePath`. All existing members move, or none do --
    /// on a forced/failed member, every already-moved member is moved back
    /// to its original path rather than merely having its destination
    /// deleted, so a rolled-back move never loses data.
    public func move(to destinationDatabasePath: String, __test_failAt: Member? = nil) throws {
        try transferAllOrNone(
            destinationDatabasePath: destinationDatabasePath,
            failAt: __test_failAt,
            operation: { source, destination in try FileManager.default.moveItem(atPath: source, toPath: destination) },
            rollback: { source, destination in try? FileManager.default.moveItem(atPath: destination, toPath: source) }
        )
    }

    /// Deletes every existing member. All existing members are removed, or
    /// none are: each is first renamed aside to a temporary name (staged),
    /// and only once every member has staged successfully are the
    /// temporary names actually removed. On any staging failure, every
    /// already-staged member is renamed back to its original path before
    /// the error propagates -- so a forced mid-delete failure leaves the
    /// unit exactly as it was, not partially deleted.
    public func delete(__test_failAt: Member? = nil) throws {
        let existingMembers = Member.allCases.filter { FileManager.default.fileExists(atPath: databasePath + $0.rawValue) }
        var staged: [(original: String, temp: String)] = []
        do {
            for member in existingMembers {
                if member == __test_failAt {
                    throw DurableUnitError.partialOperationPrevented(member)
                }
                let original = databasePath + member.rawValue
                let temp = original + ".durable-unit-delete.tmp"
                try FileManager.default.moveItem(atPath: original, toPath: temp)
                staged.append((original, temp))
            }
        } catch {
            for (original, temp) in staged {
                try? FileManager.default.moveItem(atPath: temp, toPath: original)
            }
            throw error
        }
        for (_, temp) in staged {
            try? FileManager.default.removeItem(atPath: temp)
        }
    }

    /// Replaces every member this unit has at `databasePath` with `other`'s
    /// members -- the operation `BackupReplayTests` uses to model "a
    /// device backup restore, overwriting the current store file": delete
    /// this unit's own existing members first (all-or-none), then copy
    /// `other`'s existing members into this unit's paths (all-or-none). If
    /// the copy step fails after a successful delete, this unit is left
    /// with no members at all rather than a mixed pre/post-restore state --
    /// disclosed here as the honest limit of composing two already-atomic
    /// primitives rather than a single deeper transaction.
    public func restoreContents(of other: DurableUnit) throws {
        try delete()
        try other.copy(to: databasePath)
    }

    private func transferAllOrNone(
        destinationDatabasePath: String,
        failAt: Member?,
        operation: (String, String) throws -> Void,
        rollback: (String, String) -> Void
    ) throws {
        var completed: [(source: String, destination: String)] = []
        do {
            for member in Member.allCases {
                let source = databasePath + member.rawValue
                guard FileManager.default.fileExists(atPath: source) else { continue }
                if member == failAt {
                    throw DurableUnitError.partialOperationPrevented(member)
                }
                let destination = destinationDatabasePath + member.rawValue
                try operation(source, destination)
                completed.append((source, destination))
            }
        } catch {
            for (source, destination) in completed {
                rollback(source, destination)
            }
            throw error
        }
    }
}
