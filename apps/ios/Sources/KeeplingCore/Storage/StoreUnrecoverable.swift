import Foundation

/// The closed set of failures that halt the local store rather than repair
/// or reset it (D-04 G4, D-37). `MigrationLedger` and the durability/
/// integrity paths in `GRDBLocalStore` are the only throwers of this type.
///
/// Plan 04-10's `unrecoverable` presentation state maps from these cases,
/// which is why this is one named type rather than string matching against
/// arbitrary `Error` descriptions.
///
/// Every case carries the schema version affected at the moment of
/// failure, so a diagnostic surface (or a future support flow) can name
/// exactly what state the store was in when it refused to continue.
public enum StoreUnrecoverable: Error, Sendable, Equatable {
    /// A `schema_migrations` row's stored checksum does not match the
    /// checksum of the migration text this build carries for that version.
    /// Someone or something edited migration history after it shipped.
    case checksumDrift(version: Int)

    /// `schema_migrations` contains a version this build has no migration
    /// for. A newer Keepling build wrote this file; opening it here would
    /// silently downgrade it.
    case aheadOfLedger(foundVersion: Int, knownVersionCount: Int)

    /// A migration's SQL threw while being applied. The transaction for
    /// that single migration rolled back in full; every migration applied
    /// before it in a prior open remains committed and untouched.
    case migrationMidApplyFailure(version: Int)

    /// `PRAGMA integrity_check` or `PRAGMA foreign_key_check` reported a
    /// problem against the currently-open schema version.
    case integrityCheckFailed(version: Int, detail: String)
}
