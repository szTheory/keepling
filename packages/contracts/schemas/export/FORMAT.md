# Keepling export bundle format

This document describes Keepling's export bundle for a reader who has never seen Keepling's
source code or database. You do not need Keepling, or any special tool, to read this bundle --
`unzip`, a text editor, and any NDJSON-aware tool (or just `grep`/`jq`/a line-by-line reader) are
enough.

## What this is, and what it is not

This bundle is a complete, neutral, human-readable copy of your data, taken at a single
consistent moment in time. **It is not a backup.** Keepling's separate, automatically
restore-verified backup path is the supported way to protect your data against loss. This
export exists so you can read, keep, search, or move your data without needing to understand
Keepling's internals -- it does not carry the internal recovery machinery a real restore needs.

## Bundle layout

The bundle is a single `.zip` archive containing:

```
manifest.json                    -- see below; written LAST, always the newest file on disk
FORMAT.md                        -- this document, copied verbatim into every bundle
tasks.md                         -- a human-readable rendering of your tasks, no tooling required
data/task.ndjson                 -- one JSON object per line, one line per task
data/project.ndjson              -- one JSON object per line, one line per project
data/tag.ndjson                  -- one JSON object per line, one line per tag
data/task-activity.ndjson        -- one JSON object per line, one line per recorded activity entry
data/conflict.ndjson             -- one JSON object per line, one line per currently open conflict
data/today-order.ndjson          -- one JSON object per line, one line per Today ordering slot
data/account-settings.ndjson     -- one JSON object per line (exactly one line: your account settings)
data/access-inventory.ndjson     -- one JSON object per line, one line per device or MCP client grant
```

Every `data/*.ndjson` file is always present, even when its collection is empty. An empty
collection is a file with zero lines, never a missing file, a `null`, or an error. Absent and
empty are always distinguishable in this bundle, exactly as they are on Keepling's own consent
screen before you export.

## Compatibility: read `export_format_version` alone

`manifest.json`'s `export_format_version` is a standalone integer, starting at 1, and is the
**only** field a reader should use to decide how to parse this bundle. It is decoupled from
Keepling's wire protocol and from any Keepling release number.

- `keepling_version` and `generated_at` are **provenance only**. Never use them for a
  compatibility decision.
- The format is **additive-only** within a version: a future version-1 bundle may add new
  optional fields, but will never remove, rename, or change the meaning of a version-1 field
  you can read today.
- A version **never ages out**. Once a bundle is written in a given `export_format_version`, it
  remains readable under that version's rules forever. This is a one-way commitment: the
  compatibility promise here attaches to files that end up sitting on your disk, not to a
  service Keepling controls.

## Canonical ordering

Within each `data/*.ndjson` file, lines are ordered:

- By each record's own stable, opaque id, in ascending order; or
- By feed sequence, for any entity whose canonical order is defined by Keepling's internal
  ordered sync feed.

Two exports of an account that has not changed produce byte-identical `data/*.ndjson`, `FORMAT.md`,
and `tasks.md` files. Only `manifest.json`'s `generated_at` and `keepling_version` fields may
differ between two such exports.

## Encoding rules

- Every JSON object uses canonical (sorted) key order.
- Every instant (a point in time) is UTC, ISO-8601, e.g. `2026-09-11T18:00:00Z`.
- Every civil date (a date with no time component, such as a planned or deadline date) is a
  plain `YYYY-MM-DD` string, with no time zone or time component.
- An absent optional value is always an explicit JSON `null`, never an omitted key. Absent and
  empty must remain distinguishable everywhere in this bundle.

## Validating a bundle

`manifest.json` is written **last**, only after every other file in the bundle already exists on
disk. It records, per file, that file's exact path, its lowercase hex SHA-256 digest, and its
row count. A truncated or partially-written bundle therefore either has no `manifest.json` at
all, or has a `manifest.json` whose recorded digests and row counts do not match the files
actually present -- either way, it fails validation instead of silently passing as complete.

## Privacy

This bundle is **unencrypted plaintext**. Keepling writes it with owner-only file permissions,
but the bundle itself carries no encryption -- anyone with access to the bundle file can read
everything in it, including task titles, notes, and activity history. Keep it exactly as safely
as you would keep any other plaintext file containing your personal task list.
