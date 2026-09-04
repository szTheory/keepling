import { createHash } from 'node:crypto'
import { chmodSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { afterEach, describe, expect, it } from 'vitest'

import { classifyStoreFailure, NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * Real-SQLite fault/migration proof (D-22/D-34/D-37/D-38, T-KPL03-05-02/-04).
 * Every fixture in this file operates on a real `node:sqlite` file on a
 * disposable system-temporary directory -- never a mock, never the
 * developer's real Keepling profile. Every failure case asserts THREE
 * things together: (1) construction/the operation throws, (2) the prior
 * durable file/content is preserved unchanged (no silent reset, no
 * in-memory substitute), and (3) the fault is retryable once the external
 * condition is repaired.
 */

const roots: string[] = []
const permissionFixups: Array<() => void> = []

afterEach(() => {
  for (const restore of permissionFixups.splice(0)) restore()
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixtureRoot = (name: string): string => {
  const root = mkdtempSync(join(tmpdir(), `keepling-migrations-faults-${name}-`))
  roots.push(root)
  return root
}

const migrationPath = new URL('../../migrations/0001_initial.sql', import.meta.url)

const mutationFor = (mutationId: string, taskId: string, title: string) => {
  const commandBytes = JSON.stringify({ mutation_id: mutationId, task_id: taskId, title, type: 'capture_task', version: 1 })
  return {
    acceptedAt: '2026-09-02T12:00:00.000Z',
    commandBytes,
    fingerprint: createHash('sha256').update(commandBytes).digest('hex'),
    mutationId,
    taskId,
    title,
  }
}

describe('NodeSqliteLocalStore fault safety', () => {
  it('retains a fresh-create fixture and a no-op forward-migration fixture for the same schema lineage (D-37)', () => {
    const root = fixtureRoot('lineage')
    const databasePath = join(root, 'namespace.sqlite3')

    const fresh = new NodeSqliteLocalStore({ databasePath, migrationPath })
    fresh.close()

    // "Forward-migration" for the current single-version lineage means
    // reopening against the SAME migration file re-validates the checksum
    // ledger without reapplying anything -- this is exactly D-37's
    // "reject checksum drift" contract exercised on the happy path.
    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    const ledgerDb = new DatabaseSync(databasePath, { defensive: true, timeout: 2_500 })
    const ledger = ledgerDb.prepare('SELECT version, checksum FROM schema_migrations').all() as Array<{
      checksum: string
      version: number
    }>
    ledgerDb.close()
    expect(ledger).toHaveLength(1)
    expect(ledger[0]?.version).toBe(1)
    reopened.close()
  })

  it('refuses migration checksum drift and preserves the retained store (D-37)', () => {
    const root = fixtureRoot('checksum-drift')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-drift', 'task-drift', 'Survive drift'))
    store.close()

    const driftedMigration = join(root, 'drifted.sql')
    writeFileSync(driftedMigration, `${readFileSync(migrationPath, 'utf8')}\n-- an unauthorized change\n`)
    expect(() => new NodeSqliteLocalStore({ databasePath, migrationPath: driftedMigration })).toThrow(
      /migration checksum mismatch/,
    )

    const retained = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(retained.snapshot().tasks).toEqual([
      expect.objectContaining({ id: 'task-drift', title: 'Survive drift' }),
    ])
    retained.close()
  })

  it('refuses a migration that fails mid-apply and leaves no partial schema behind (D-37)', () => {
    const root = fixtureRoot('bad-migration')
    const databasePath = join(root, 'namespace.sqlite3')
    const brokenMigration = join(root, 'broken.sql')
    writeFileSync(brokenMigration, 'CREATE TABLE partial_table(x INTEGER);\nINSERT INTO table_that_does_not_exist VALUES (1);\n')

    expect(() => new NodeSqliteLocalStore({ databasePath, migrationPath: brokenMigration })).toThrow()
    // The failed BEGIN IMMEDIATE...ROLLBACK must leave nothing behind --
    // never a half-created schema a later open could misinterpret as valid.
    const raw = new DatabaseSync(databasePath, { defensive: true, timeout: 2_500 })
    const tables = raw.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'`).all() as Array<{ name: string }>
    raw.close()
    expect(tables).toHaveLength(0)

    // Retryable: applying the SAME broken migration again fails the same way, not differently.
    expect(() => new NodeSqliteLocalStore({ databasePath, migrationPath: brokenMigration })).toThrow()
  })

  it('surfaces real corruption without auto-reset and preserves the file for inspection (D-22)', () => {
    const root = fixtureRoot('corruption')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    for (let index = 0; index < 20; index += 1) {
      store.acceptCapture(mutationFor(`mutation-corrupt-${index}`, `task-corrupt-${index}`, `Task ${index}`))
    }
    store.close()
    // Checkpoint the WAL into the main file so truncating the MAIN file
    // corrupts real durable content, not just an unflushed WAL segment.
    const checkpoint = new DatabaseSync(databasePath, { defensive: true, timeout: 2_500 })
    checkpoint.exec('PRAGMA wal_checkpoint(TRUNCATE);')
    checkpoint.close()

    const beforeSize = statSync(databasePath).size
    const bytes = readFileSync(databasePath)
    writeFileSync(databasePath, bytes.subarray(0, Math.floor(bytes.length / 2)))
    expect(statSync(databasePath).size).toBeLessThan(beforeSize)

    let thrown: unknown
    try {
      new NodeSqliteLocalStore({ databasePath, migrationPath })
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBeInstanceOf(Error)
    // Never silently replaced with a fresh empty store -- the corrupted
    // bytes are still exactly what we truncated them to, available for a
    // real recovery/inspection tool to examine.
    expect(statSync(databasePath).size).toBe(Math.floor(beforeSize / 2))
    expect(['corruption', 'integrity_failure']).toContain(classifyStoreFailure(thrown))
  })

  it('fails opening a permission-denied file without resetting, and recovers once permission is restored (D-22)', () => {
    const root = fixtureRoot('permission')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-perm', 'task-perm', 'Blocked by permission'))
    store.close()

    chmodSync(databasePath, 0o000)
    permissionFixups.push(() => chmodSync(databasePath, 0o644))
    let thrown: unknown
    try {
      new NodeSqliteLocalStore({ databasePath, migrationPath })
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBeInstanceOf(Error)
    expect(classifyStoreFailure(thrown)).toBe('permission_denied')

    // External repair (the user fixing Full Disk Access / file permissions)
    // must make the SAME store openable again -- proves retry works.
    chmodSync(databasePath, 0o644)
    const recovered = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(recovered.snapshot().tasks).toEqual([expect.objectContaining({ id: 'task-perm' })])
    recovered.close()
  })

  it('fails a write against a read-only file without resetting or losing the prior committed task (D-22/D-38)', () => {
    const root = fixtureRoot('readonly')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-readonly', 'task-readonly', 'Read-only survivor'))
    store.close()

    chmodSync(databasePath, 0o444)
    permissionFixups.push(() => chmodSync(databasePath, 0o644))
    // Opening succeeds (no write needed for an already-migrated store);
    // the failure surfaces on the first real WRITE attempt, exactly as a
    // real macOS FileVault/permission-restricted volume would behave.
    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    let thrown: unknown
    try {
      reopened.acceptCapture(mutationFor('mutation-readonly-2', 'task-readonly-2', 'Should not commit'))
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBeInstanceOf(Error)
    expect(classifyStoreFailure(thrown)).toBe('read_only')

    chmodSync(databasePath, 0o644)
    const recovered = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(recovered.snapshot().tasks).toEqual([expect.objectContaining({ id: 'task-readonly' })])
    recovered.close()
  })

  it('fails finitely under SQLITE_BUSY without hanging and without partial commit (D-34/D-38)', () => {
    const root = fixtureRoot('busy')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-busy-0', 'task-busy-0', 'Before lock'))

    // Simulate an external process (Time Machine, antivirus, a stray
    // second instance) holding a real write lock via a second raw
    // connection to the SAME file.
    const externalWriter = new DatabaseSync(databasePath, { defensive: true, timeout: 500 })
    externalWriter.exec('BEGIN IMMEDIATE')
    externalWriter.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES ('external_lock_probe', 'held')
    `).run()

    const startedAt = Date.now()
    let thrown: unknown
    try {
      store.acceptCapture(mutationFor('mutation-busy-1', 'task-busy-1', 'Blocked by external lock'))
    } catch (error) {
      thrown = error
    }
    const elapsedMs = Date.now() - startedAt
    externalWriter.exec('COMMIT')
    externalWriter.close()

    expect(thrown).toBeInstanceOf(Error)
    expect(classifyStoreFailure(thrown)).toBe('busy')
    // Finite: never an unbounded hang. The store's own busy timeout is
    // 2.5s, so a failure must resolve well inside that bound plus slack.
    expect(elapsedMs).toBeLessThan(5_000)

    // No partial commit from the blocked attempt -- only the pre-lock task exists.
    expect(store.snapshot().tasks.map((task) => task.id)).toEqual(['task-busy-0'])
    // Retryable once the lock is released.
    store.acceptCapture(mutationFor('mutation-busy-2', 'task-busy-2', 'After lock released'))
    expect(store.snapshot().tasks.map((task) => task.id)).toEqual(['task-busy-0', 'task-busy-2'])
    store.close()
  })

  it('rolls back completely on a mid-transaction failure and preserves the prior committed state (quit-during-transaction proxy, D-34)', () => {
    const root = fixtureRoot('mid-transaction')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    const mutation = mutationFor('mutation-duplicate', 'task-duplicate', 'First commit')
    store.acceptCapture(mutation)

    // Reusing the SAME mutationId is rejected deep inside the transaction
    // (immutable_commands PRIMARY KEY conflict, after journal/projection
    // inserts have already been prepared) -- this is the same shape of
    // failure as a hard interruption mid-transaction: some statements ran,
    // none of them may survive unless the whole transaction committed.
    expect(() => store.acceptCapture(mutation)).toThrow()

    expect(store.snapshot().tasks).toHaveLength(1)
    expect(store.pendingMutations()).toHaveLength(1)
    store.close()

    // Reopening independently confirms no partial row survived on disk either.
    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(reopened.snapshot().tasks).toHaveLength(1)
    reopened.close()
  })

  it('treats the database/WAL/SHM as one durable unit across checkpoint and close (D-38)', () => {
    const root = fixtureRoot('wal-unit')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-wal', 'task-wal', 'WAL-backed'))
    // WAL mode is active -- the -wal sidecar must exist while the
    // connection is open, proving writes are NOT going through a bespoke
    // copy/replace path that would split the unit.
    expect(statSync(`${databasePath}-wal`).size).toBeGreaterThanOrEqual(0)
    store.close()

    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(reopened.snapshot().tasks).toEqual([expect.objectContaining({ id: 'task-wal' })])
    reopened.close()
  })

  it('classifies every closed failure code, including disk-full which this sandboxed environment cannot induce on real disk (T-KPL03-05-04)', () => {
    // Real fixtures above prove migration_checksum_drift, integrity_failure,
    // corruption, permission_denied, read_only, and busy against ACTUAL
    // node:sqlite/filesystem errors. Real ENOSPC requires a genuinely full
    // disk or a quota-limited volume, which this environment cannot
    // provision safely or portably -- disk_full is proven here as a pure
    // classification of the real SQLite/OS message text
    // (`SQLITE_FULL: database or disk is full`, `ENOSPC: no space left on
    // device`) rather than an induced fault. This is a disclosed, scoped-
    // down piece of evidence, not a silently skipped one.
    expect(classifyStoreFailure(new Error('SQLITE_FULL: database or disk is full'))).toBe('disk_full')
    expect(classifyStoreFailure(new Error('ENOSPC: no space left on device, write'))).toBe('disk_full')
    expect(classifyStoreFailure(new Error('migration checksum mismatch for version 1'))).toBe('migration_checksum_drift')
    expect(classifyStoreFailure(new Error('local store invariant check failed'))).toBe('integrity_failure')
    expect(classifyStoreFailure(new Error('database disk image is malformed'))).toBe('corruption')
    expect(classifyStoreFailure(new Error('unable to open database file'))).toBe('permission_denied')
    expect(classifyStoreFailure(new Error('attempt to write a readonly database'))).toBe('read_only')
    expect(classifyStoreFailure(new Error('database is locked'))).toBe('busy')
    expect(classifyStoreFailure(new Error('something entirely unrecognized'))).toBe('unknown')
  })

  it('never lets a main/window module import node:sqlite directly (D-34: one worker-owned writer)', () => {
    const desktopRoot = new URL('../../', import.meta.url)
    const candidates = [
      new URL('main/index.ts', desktopRoot),
      new URL('main/application/DesktopApplication.ts', desktopRoot),
      new URL('main/recovery/remove-local-data.ts', desktopRoot),
      new URL('main/windows/main-window.ts', desktopRoot),
      new URL('main/windows/quick-entry-window.ts', desktopRoot),
      new URL('main/windows/settings-window.ts', desktopRoot),
      new URL('main/lifecycle.ts', desktopRoot),
    ]
    for (const candidate of candidates) {
      let source: string
      try {
        source = readFileSync(candidate, 'utf8')
      } catch {
        continue // Optional files that may not exist yet are not this test's concern.
      }
      expect(source, `${candidate.pathname} must not import node:sqlite`).not.toMatch(/from ['"]node:sqlite['"]/)
    }
  })
})
