import { createHash } from 'node:crypto'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { afterEach, describe, expect, it } from 'vitest'

import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * O-51 / D-52, Task 1: the generalised migration runner and the 0002 outbox
 * state column, proved against REAL pre-0002 databases on disk.
 *
 * The riskiest thing in this plan is durable: a migration that ships. So no
 * case here asserts that a migration "would" work. Every case builds a real
 * database with the SHIPPED code path at the older schema, closes it, and
 * reopens it through the runner -- which is the same sequence a person's
 * Mac performs when they update the app.
 */

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixtureRoot = (name: string): string => {
  const root = mkdtempSync(join(tmpdir(), `keepling-outbox-state-${name}-`))
  roots.push(root)
  return root
}

const migrationsDirectory = dirname(fileURLToPath(new URL('../../migrations/0001_initial.sql', import.meta.url)))
const migrationPath = join(migrationsDirectory, '0001_initial.sql')

/**
 * A migrations directory holding ONLY `0001_initial.sql` -- byte-identical
 * to the shipped one, so its recorded checksum is the real one. Opening a
 * store against this produces a genuine pre-0002 database rather than a
 * hand-written imitation of one.
 */
const priorSchema = (root: string): string => {
  const directory = join(root, 'prior-schema')
  mkdirSync(directory, { recursive: true })
  const copied = join(directory, '0001_initial.sql')
  copyFileSync(migrationPath, copied)
  return copied
}

const mutationFor = (mutationId: string, taskId: string, title: string) => {
  const commandBytes = JSON.stringify({ mutation_id: mutationId, task_id: taskId, title, type: 'capture_task', version: 1 })
  return {
    acceptedAt: '2026-09-04T12:00:00.000Z',
    commandBytes,
    fingerprint: createHash('sha256').update(commandBytes).digest('hex'),
    mutationId,
    taskId,
    title,
  }
}

const readOutboxRows = (databasePath: string) => {
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    return database
      .prepare(
        `SELECT outbox.mutation_id AS mutationId, outbox.sequence AS sequence, outbox.state AS state,
                immutable_commands.command_bytes AS commandBytes
         FROM outbox JOIN immutable_commands USING (mutation_id) ORDER BY outbox.sequence`,
      )
      .all() as Array<{ commandBytes: string; mutationId: string; sequence: number; state: string }>
  } finally {
    database.close()
  }
}

const readLedger = (databasePath: string) => {
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    return database.prepare('SELECT version, checksum FROM schema_migrations ORDER BY version').all() as Array<{
      checksum: string
      version: number
    }>
  } finally {
    database.close()
  }
}

const checksumOf = (path: string): string =>
  createHash('sha256').update(readFileSync(path, 'utf8')).digest('hex')

describe('outbox transmission state migration (O-51 / D-52)', () => {
  /**
   * The truth this plan is most exposed on: an existing database opens,
   * migrates, and keeps BOTH its tasks and its queued commands.
   */
  it('migrates a real pre-0002 database and retains its tasks and its queued commands', () => {
    const root = fixtureRoot('upgrade')
    const databasePath = join(root, 'namespace.sqlite3')
    const before = new NodeSqliteLocalStore({ databasePath, migrationPath: priorSchema(root) })
    before.acceptCapture(mutationFor('mutation-legacy-1', 'task-legacy-1', 'Renew passport'))
    before.acceptCapture(mutationFor('mutation-legacy-2', 'task-legacy-2', 'Book the ferry'))
    const priorLedger = readLedger(databasePath)
    before.close()

    // A genuine pre-0002 database: one migration applied, no state column.
    expect(priorLedger.map((row) => row.version)).toEqual([1])
    expect(() => readOutboxRows(databasePath)).toThrow()

    const after = new NodeSqliteLocalStore({ databasePath, migrationPath })
    try {
      expect(after.snapshot().tasks.map((task) => task.title)).toEqual(['Renew passport', 'Book the ferry'])
      // The queued commands survive with their EXACT bytes and their order.
      const rows = readOutboxRows(databasePath)
      expect(rows.map((row) => row.mutationId)).toEqual(['mutation-legacy-1', 'mutation-legacy-2'])
      expect(rows.map((row) => row.commandBytes)).toEqual([
        mutationFor('mutation-legacy-1', 'task-legacy-1', 'Renew passport').commandBytes,
        mutationFor('mutation-legacy-2', 'task-legacy-2', 'Book the ferry').commandBytes,
      ])
      // They are still pushed -- migrating must not strand a person's work.
      expect(after.readyMutations().map((mutation) => mutation.mutationId)).toEqual([
        'mutation-legacy-1',
        'mutation-legacy-2',
      ])
    } finally {
      after.close()
    }

    // Both versions are recorded, each bound to the checksum of the file
    // that was actually applied.
    expect(readLedger(databasePath)).toEqual([
      { checksum: checksumOf(join(migrationsDirectory, '0001_initial.sql')), version: 1 },
      { checksum: checksumOf(join(migrationsDirectory, '0002_outbox_state.sql')), version: 2 },
    ])
  })

  /**
   * A row written before the state column existed has an UNKNOWN
   * transmission history -- the old client pushed without recording one, so
   * it may have been sent and its answer lost. Absent state is ambiguous
   * state, and ambiguity is never assumed to be `queued`.
   */
  it('moves rows that predate the column to uncertain, never to queued', () => {
    const root = fixtureRoot('legacy-state')
    const databasePath = join(root, 'namespace.sqlite3')
    const before = new NodeSqliteLocalStore({ databasePath, migrationPath: priorSchema(root) })
    before.acceptCapture(mutationFor('mutation-old', 'task-old', 'Older than the column'))
    before.close()

    const after = new NodeSqliteLocalStore({ databasePath, migrationPath })
    try {
      expect(readOutboxRows(databasePath)).toEqual([
        expect.objectContaining({ mutationId: 'mutation-old', state: 'uncertain' }),
      ])
      // A command enqueued AFTER the migration starts in the only state
      // that honestly describes it.
      after.acceptCapture(mutationFor('mutation-new', 'task-new', 'Enqueued after the migration'))
      expect(readOutboxRows(databasePath)).toEqual([
        expect.objectContaining({ mutationId: 'mutation-old', state: 'uncertain' }),
        expect.objectContaining({ mutationId: 'mutation-new', state: 'queued' }),
      ])
    } finally {
      after.close()
    }
  })

  /** The checksum binding is per-version and still fails LOUDLY. */
  it('refuses checksum drift in the second migration and preserves the store', () => {
    const root = fixtureRoot('drift-0002')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.acceptCapture(mutationFor('mutation-drift', 'task-drift', 'Survive drift'))
    store.close()

    const driftedDirectory = join(root, 'drifted')
    mkdirSync(driftedDirectory, { recursive: true })
    copyFileSync(migrationPath, join(driftedDirectory, '0001_initial.sql'))
    writeFileSync(
      join(driftedDirectory, '0002_outbox_state.sql'),
      `${readFileSync(join(migrationsDirectory, '0002_outbox_state.sql'), 'utf8')}\n-- an unauthorized change\n`,
    )

    expect(
      () => new NodeSqliteLocalStore({ databasePath, migrationPath: join(driftedDirectory, '0001_initial.sql') }),
    ).toThrow(/migration checksum mismatch for version 2/)

    const retained = new NodeSqliteLocalStore({ databasePath, migrationPath })
    expect(retained.snapshot().tasks).toEqual([
      expect.objectContaining({ id: 'task-drift', title: 'Survive drift' }),
    ])
    retained.close()
  })

  /**
   * The other direction: a database migrated by a NEWER app must not be
   * written by an older one. Silently ignoring a ledger version this build
   * has no file for would let an old binary write rows a newer schema's
   * constraints were meant to govern.
   */
  it('refuses to open a database whose ledger is ahead of the migrations this build carries', () => {
    const root = fixtureRoot('ahead')
    const databasePath = join(root, 'namespace.sqlite3')
    const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
    store.close()

    expect(() => new NodeSqliteLocalStore({ databasePath, migrationPath: priorSchema(root) })).toThrow(
      /database schema version 2 is ahead/,
    )
  })
})
