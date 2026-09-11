-- 0003: a durable local home for every refused change (D-37, T-06-06-01/02/03).
--
-- WHY THIS EXISTS
--
-- `acknowledge()` already refuses to let a REFUSED command's local row be
-- overwritten by the shadow *inside the same acknowledgement* -- see the
-- comment above `#replayVisible()`'s call site in local-store.ts. What it
-- could not do before this migration is survive the NEXT pull: a refused
-- command leaves the outbox the moment the server answers (it is terminal;
-- retrying the same immutable bytes cannot change the server's mind), and
-- once it is gone `#replayVisible()` has nothing left to tell it "don't
-- replace this entity from the shadow". The next pull would then reassert
-- the server's pre-refusal state over a change the person watched get
-- accepted locally -- silently, because nothing recorded that a refusal had
-- ever happened for anything but a title.
--
-- This table is that record. It exists for EVERY refusal outcome the
-- acknowledgement path recognises (title divergence, a lifecycle/Trash
-- divergence, or any other field the server names), not only the one the
-- pre-existing title-only `conflicts` table could represent. `conflicts`
-- itself is untouched by this migration -- it still feeds the existing
-- title-only chooser (O-44's disclosed limit) until a later plan replaces
-- that reader with one over this table.
--
-- THE SHAPE, AND WHY EACH COLUMN EXISTS
--
--   mutation_id   The mutation whose acknowledgement produced this refusal.
--                 Primary key: a retried acknowledgement of the SAME
--                 mutation id upserts this row rather than duplicating it.
--   entity_id     The task the refusal is about, so `#replayVisible()` can
--                 look this up by the same identifier it already replays
--                 the shadow and the outbox by.
--   outcome       The acknowledgement outcome that produced the record
--                 ('conflict' today; recorded as data, not assumed by the
--                 reader, so a future refusal outcome does not require a
--                 schema change to be representable).
--   fields_json   One entry per diverging field the server named, each
--                 carrying `field`, `mine` and `current`. An absent side
--                 (most often the server's current value for a non-title
--                 field, which this acknowledgement shape does not yet
--                 plumb through) is stored as an explicit JSON `null`,
--                 never by omitting the field entry entirely -- a
--                 lifecycle/Trash divergence is still named, even with an
--                 unknown current value, rather than recording nothing.
--   unresolved    1 until a person acts on the refusal; `#replayVisible()`
--                 reads this flag and nothing else to decide whether to
--                 skip an entity. Read-only from the replay's side, so
--                 repeated pulls against the same unresolved refusal are
--                 idempotent -- only the resolution path (`resolveRefusal`)
--                 clears it.
--   recorded_at   When this row was last written, for diagnostics only.
--
-- The index on (entity_id, unresolved) is what `#replayVisible()` queries
-- for every entity it is about to touch, so it stays a point lookup rather
-- than a table scan as the table grows.
--
-- DOWN (documentary only -- this runner is forward-only and never executes
-- a down direction; see 0002_outbox_state.sql and `#applyMigration`, which
-- only ever applies files in order and never reverses one). If this
-- migration is ever reversed by hand, the exact inverse is:
--   DROP INDEX refusal_records_entity_unresolved;
--   DROP TABLE refusal_records;
-- Safe in that direction alone: nothing created by 0001 or 0002 references
-- `refusal_records`, so no other table needs to change to roll back to the
-- prior schema, and a database with no rows in the table (the common case)
-- loses nothing by the drop.

CREATE TABLE refusal_records (
  mutation_id TEXT PRIMARY KEY REFERENCES immutable_commands(mutation_id),
  entity_id TEXT NOT NULL,
  outcome TEXT NOT NULL,
  fields_json TEXT NOT NULL CHECK (json_valid(fields_json)),
  unresolved INTEGER NOT NULL DEFAULT 1 CHECK (unresolved IN (0, 1)),
  recorded_at TEXT NOT NULL
) STRICT;

CREATE INDEX refusal_records_entity_unresolved ON refusal_records(entity_id, unresolved);
