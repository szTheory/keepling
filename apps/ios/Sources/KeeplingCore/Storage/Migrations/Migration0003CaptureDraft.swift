import Foundation

/// Adds the durable capture draft (04-09-PLAN.md Task 3, D-35): a nonempty
/// draft must survive backgrounding, sheet dismissal, and interruption --
/// which means the draft lives in the store, not in SwiftUI view state (a
/// backgrounded sheet's view state can be torn down by the system). One
/// singleton row, mirroring `sync_cursor`/`last_local_action`'s existing
/// singleton-row convention in Migration0001Initial.
enum Migration0003CaptureDraft {
    static let version = 3

    static let sql = """
    CREATE TABLE capture_draft (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      title TEXT NOT NULL DEFAULT '',
      add_to_today INTEGER NOT NULL DEFAULT 0 CHECK (add_to_today IN (0, 1)),
      updated_at TEXT
    ) STRICT;

    INSERT INTO capture_draft(singleton, title, add_to_today, updated_at) VALUES (1, '', 0, NULL);
    """
}
