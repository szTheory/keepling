import Foundation

/// Mirrors `apps/desktop/migrations/0001_initial.sql` column-for-column
/// (04-PATTERNS.md "exact (same 11-table schema, same STRICT/DDL text to
/// mirror line-for-line)"). All 11 STRICT table declarations are
/// carried, including `sync_cursor` and `last_local_action` -- 04-RESEARCH.md
/// Open Question 2 resolution: D-35's prose "nine tables" enumerates nine
/// *categories* and separately names the migration ledger under D-37;
/// carrying `last_local_action` costs one table and keeps the schema a
/// literal mirror of the desktop's, which is what D-03's "mirror verbatim"
/// asks for and what makes the retained desktop fixtures portable. This
/// decision is recorded again in 04-01-SUMMARY.md.
///
/// `visible_projection.sync_status` keeps the desktop's stored enum value
/// `'saved_on_this_mac'` verbatim -- D-43's `this Mac` -> `this iPhone`
/// substitution is a presentation-layer concern only; a divergent stored
/// enum would break vector and fixture portability. Recorded again in the
/// SUMMARY as a second explicit decision.
enum Migration0001Initial {
    static let version = 1

    static let sql = """
    CREATE TABLE schema_migrations (
      version INTEGER PRIMARY KEY,
      checksum TEXT NOT NULL CHECK (length(checksum) = 64),
      applied_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE namespace_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    ) STRICT;

    CREATE TABLE canonical_shadow (
      entity_id TEXT PRIMARY KEY,
      snapshot_json TEXT NOT NULL CHECK (json_valid(snapshot_json))
    ) STRICT;

    CREATE TABLE visible_projection (
      task_id TEXT PRIMARY KEY,
      title TEXT NOT NULL CHECK (length(title) > 0),
      sync_status TEXT NOT NULL CHECK (sync_status IN ('saved_on_this_mac', 'synced')),
      notes TEXT NOT NULL DEFAULT '',
      completed_at TEXT,
      trashed_at TEXT,
      planned INTEGER NOT NULL DEFAULT 0 CHECK (planned IN (0, 1))
    ) STRICT;

    CREATE TABLE immutable_commands (
      mutation_id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      command_bytes TEXT NOT NULL,
      fingerprint TEXT NOT NULL CHECK (length(fingerprint) = 64),
      accepted_at TEXT NOT NULL,
      resource_keys_json TEXT NOT NULL CHECK (json_valid(resource_keys_json)),
      effect_snapshot_json TEXT NOT NULL CHECK (json_valid(effect_snapshot_json))
    ) STRICT;

    CREATE TABLE mutation_journal (
      mutation_id TEXT PRIMARY KEY REFERENCES immutable_commands(mutation_id),
      outcome TEXT NOT NULL CHECK (outcome IN ('pending', 'accepted', 'already_satisfied', 'rejected', 'stale', 'conflict')),
      terminal_snapshot_json TEXT CHECK (terminal_snapshot_json IS NULL OR json_valid(terminal_snapshot_json))
    ) STRICT;

    CREATE TABLE mutation_dependencies (
      mutation_id TEXT NOT NULL REFERENCES immutable_commands(mutation_id),
      dependency_mutation_id TEXT NOT NULL REFERENCES immutable_commands(mutation_id),
      PRIMARY KEY (mutation_id, dependency_mutation_id)
    ) STRICT;

    CREATE TABLE outbox (
      mutation_id TEXT PRIMARY KEY REFERENCES immutable_commands(mutation_id),
      sequence INTEGER NOT NULL UNIQUE
    ) STRICT;

    CREATE TABLE sync_cursor (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      cursor TEXT
    ) STRICT;

    CREATE TABLE conflicts (
      conflict_id TEXT PRIMARY KEY,
      mutation_id TEXT NOT NULL REFERENCES immutable_commands(mutation_id),
      details_json TEXT NOT NULL CHECK (json_valid(details_json))
    ) STRICT;

    CREATE TABLE last_local_action (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      action_json TEXT CHECK (action_json IS NULL OR json_valid(action_json))
    ) STRICT;

    INSERT INTO sync_cursor(singleton, cursor) VALUES (1, NULL);
    INSERT INTO last_local_action(singleton, action_json) VALUES (1, NULL);
    """
}
