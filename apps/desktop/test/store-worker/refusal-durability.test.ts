import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { afterEach, describe, expect, it } from 'vitest'

import { buildOutboundCommand, type OutboundIntent } from '../../main/application/outbound-commands.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'
import type { PullPage, SyncMutation } from '../../main/application/DesktopApplication.ts'

/**
 * D-37 close-out (plan 06-06, T-06-06-01/02/03): a change the server refuses
 * is never lost. Every case here proves a property of the REAL `node:sqlite`
 * store, never a mock -- the same discipline `outbound-mutations.test.ts`
 * and the `outbox-state-migration`/`migrations-faults` suites already use.
 */

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-refusal-durability-'))
  roots.push(root)
  return {
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  }
}

const TASK_ID = 'task-refusal'

const captureBytes = JSON.stringify({
  mutation_id: 'mutation-capture',
  task_id: TASK_ID,
  title: 'Book the ferry',
  type: 'capture_task',
  version: 1,
})

const capture = {
  acceptedAt: '2026-09-11T12:00:00.000Z',
  commandBytes: captureBytes,
  fingerprint: createHash('sha256').update(captureBytes).digest('hex'),
  mutationId: 'mutation-capture',
  taskId: TASK_ID,
  title: 'Book the ferry',
} as const

const outbound = (store: NodeSqliteLocalStore, intent: OutboundIntent, mutationId: string): SyncMutation => {
  const built = buildOutboundCommand(intent, store.taskSyncBasis(intent.taskId), mutationId)
  return {
    acceptedAt: '2026-09-11T12:05:00.000Z',
    commandBytes: built.commandBytes,
    dependencies: [],
    effect: built.effect,
    fingerprint: createHash('sha256').update(built.commandBytes).digest('hex'),
    mutationId,
    resourceKeys: built.resourceKeys,
  }
}

const openStore = () => {
  const fixtureConfig = fixture()
  const store = new NodeSqliteLocalStore(fixtureConfig)
  store.acceptCapture(capture)
  store.acknowledge({
    fingerprint: capture.fingerprint,
    mutationId: capture.mutationId,
    outcome: 'accepted',
    snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
  })
  return { ...fixtureConfig, store }
}

type RefusalRow = {
  entity_id: string
  fields_json: string
  mutation_id: string
  outcome: string
  unresolved: number
}

const readRefusalRecords = (databasePath: string): RefusalRow[] => {
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    return database
      .prepare(
        'SELECT mutation_id, entity_id, outcome, fields_json, unresolved FROM refusal_records ORDER BY mutation_id',
      )
      .all() as RefusalRow[]
  } finally {
    database.close()
  }
}

describe('durable refusal records (D-37, Task 1)', () => {
  it('writes a durable record for a title divergence, naming the field explicitly', () => {
    const { databasePath, store } = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' }, 'm-edit'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-edit',
      outcome: 'conflict',
      snapshot: { affected_fields: ['title'], id: TASK_ID, revision: 4, title: 'Book the ferry from Oban' },
    })
    const rows = readRefusalRecords(databasePath)
    expect(rows).toEqual([
      {
        entity_id: TASK_ID,
        fields_json: JSON.stringify([{ current: 'Book the ferry from Oban', field: 'title', mine: 'Book the ferry to Mull' }]),
        mutation_id: 'm-edit',
        outcome: 'conflict',
        unresolved: 1,
      },
    ])
    store.close()
  })

  it('writes a durable record for a lifecycle/Trash divergence, naming the lifecycle field rather than a title diff', () => {
    const { databasePath, store } = openStore()
    store.applyLifecycle(
      { kind: 'trash', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, 'm-trash'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-trash',
      outcome: 'conflict',
      snapshot: { affected_fields: ['trashed_at'], id: TASK_ID, revision: 9 },
    })
    const rows = readRefusalRecords(databasePath)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.mutation_id).toBe('m-trash')
    expect(rows[0]!.unresolved).toBe(1)
    // The lifecycle field is named as data -- never a title diff standing in
    // for it. Both sides are explicit null here because this acknowledgement
    // shape does not plumb a lifecycle effect's own timestamp through
    // (`outbound-commands.ts` carries the basis title/notes/planned_on, not
    // `trashed_at`/`completed_at`) or a non-title server current value --
    // but the field itself is still recorded, which the old both-non-null
    // guard never did.
    expect(JSON.parse(rows[0]!.fields_json)).toEqual([{ current: null, field: 'trashed_at', mine: null }])
    store.close()
  })

  it('records a one-sided-null outcome explicitly rather than omitting it, unlike the old guard', () => {
    const { databasePath, store } = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' }, 'm-edit'),
    )
    // The server names `title` as diverging but this answer carries no
    // `title` key at all -- under the OLD guard (`current !== null && mine
    // !== null`) this wrote nothing to `conflicts`, and nothing anywhere
    // else either.
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-edit',
      outcome: 'conflict',
      snapshot: { affected_fields: ['title'], id: TASK_ID, revision: 4 },
    })
    const rows = readRefusalRecords(databasePath)
    expect(rows).toEqual([
      {
        entity_id: TASK_ID,
        fields_json: JSON.stringify([{ current: null, field: 'title', mine: 'Book the ferry to Mull' }]),
        mutation_id: 'm-edit',
        outcome: 'conflict',
        unresolved: 1,
      },
    ])
    // The pre-existing title-only chooser table is genuinely untouched here
    // (current is null), matching its own pre-existing, unmodified guard.
    expect(store.listConflicts()).toEqual([])
    store.close()
  })

  it('leaves a durable record rather than a gap across the point where the outbox entry becomes terminal', () => {
    const { databasePath, migrationPath, store } = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' }, 'm-edit'),
    )
    store.close()

    // Simulate the exact intermediate point the plan's guarantee is about:
    // the refusal record has been written, but the outbox entry has NOT yet
    // been deleted and the journal has NOT yet been marked terminal. Because
    // `acknowledge()` performs both inside one committed transaction, this
    // state is unreachable via a real crash (SQLite's atomicity means either
    // both happened or neither did) -- so it is constructed directly here to
    // prove the SYSTEM behaves safely if it ever were reached: the mutation
    // stays retryable and the record is not orphaned or duplicated when the
    // real acknowledgement eventually lands.
    const raw = new DatabaseSync(databasePath)
    try {
      raw.prepare(`
        INSERT INTO refusal_records(mutation_id, entity_id, outcome, fields_json, unresolved, recorded_at)
        VALUES ('m-edit', ?, 'conflict', ?, 1, ?)
      `).run(TASK_ID, JSON.stringify([{ current: 'Book the ferry from Oban', field: 'title', mine: 'Book the ferry to Mull' }]), '2026-09-11T12:10:00.000Z')
    } finally {
      raw.close()
    }

    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    try {
      // The outbox entry was never deleted in this simulated interruption --
      // a record exists, and the mutation is STILL retryable. Never both
      // "terminal outbox" and "no record": that combination is the gap this
      // plan closes.
      expect(reopened.readyMutations().map((mutation) => mutation.mutationId)).toContain('m-edit')
      expect(readRefusalRecords(databasePath)).toHaveLength(1)

      // The real acknowledgement eventually lands and upserts the SAME row
      // rather than duplicating it (also proves Task 1's last behaviour:
      // retried acknowledgements update, never duplicate).
      reopened.acknowledge({
        fingerprint: reopened.readyMutations()[0]!.fingerprint,
        mutationId: 'm-edit',
        outcome: 'conflict',
        snapshot: { affected_fields: ['title'], id: TASK_ID, revision: 4, title: 'Book the ferry from Oban' },
      })
    } finally {
      reopened.close()
    }
    const rows = readRefusalRecords(databasePath)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.mutation_id).toBe('m-edit')
  })

  it('updates the existing record on a retried acknowledgement instead of creating a duplicate', () => {
    const { databasePath, migrationPath, store } = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull' }, 'm-edit'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-edit',
      outcome: 'conflict',
      snapshot: { affected_fields: ['title'], id: TASK_ID, revision: 4, title: 'Book the ferry from Oban' },
    })
    expect(readRefusalRecords(databasePath)).toHaveLength(1)
    store.close()

    // Re-arm the outbox/journal so the SAME mutation id can be acknowledged
    // a second time, simulating a retried acknowledgement of an answer that
    // (from the server's perspective) still names a divergent title, but
    // with a NEWER current value.
    const raw = new DatabaseSync(databasePath)
    try {
      raw.prepare(`INSERT INTO outbox(mutation_id, sequence, state) VALUES ('m-edit', 999, 'queued')`).run()
      raw.prepare(`UPDATE mutation_journal SET outcome = 'pending' WHERE mutation_id = 'm-edit'`).run()
    } finally {
      raw.close()
    }

    const reopened = new NodeSqliteLocalStore({ databasePath, migrationPath })
    try {
      reopened.acknowledge({
        fingerprint: reopened.readyMutations()[0]!.fingerprint,
        mutationId: 'm-edit',
        outcome: 'conflict',
        snapshot: { affected_fields: ['title'], id: TASK_ID, revision: 5, title: 'Book the ferry from Fort William' },
      })
    } finally {
      reopened.close()
    }

    const rows = readRefusalRecords(databasePath)
    expect(rows).toHaveLength(1)
    expect(JSON.parse(rows[0]!.fields_json)).toEqual([
      { current: 'Book the ferry from Fort William', field: 'title', mine: 'Book the ferry to Mull' },
    ])
  })
})

describe('the pull path never overwrites an unresolved refusal (D-37, Task 2)', () => {
  const trashConflict = (store: NodeSqliteLocalStore): void => {
    store.applyLifecycle(
      { kind: 'trash', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, 'm-trash'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-trash',
      outcome: 'conflict',
      snapshot: { affected_fields: ['trashed_at'], id: TASK_ID, revision: 9 },
    })
  }

  const pullNewerTitle = (store: NodeSqliteLocalStore, title: string): void => {
    const page: PullPage = {
      changes: [{ entityId: TASK_ID, snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 99, title } }],
      cursor: 'cursor-1',
    }
    store.applyPull(page)
  }

  it('leaves the local value in place across a pull while the refusal is unresolved', () => {
    const { store } = openStore()
    trashConflict(store)
    const before = store.snapshot().tasks[0]!
    pullNewerTitle(store, 'Renamed by the server')
    const after = store.snapshot().tasks[0]!
    expect(after.title).toBe(before.title)
    expect(after.syncStatus).toBe(before.syncStatus)
    store.close()
  })

  it('replays normally for an entity with no refusal record, or a resolved one', () => {
    const { store } = openStore()
    pullNewerTitle(store, 'No conflict here, replay normally')
    expect(store.snapshot().tasks[0]!.title).toBe('No conflict here, replay normally')
    store.close()
  })

  it('resumes normal replay once the refusal is marked resolved', () => {
    const { store } = openStore()
    trashConflict(store)
    pullNewerTitle(store, 'Should stay blocked')
    expect(store.snapshot().tasks[0]!.title).not.toBe('Should stay blocked')

    store.resolveRefusal('m-trash')
    pullNewerTitle(store, 'Should replay now')
    expect(store.snapshot().tasks[0]!.title).toBe('Should replay now')
    store.close()
  })

  it('produces the same outcome across two consecutive pulls -- the guard is not consumed', () => {
    const { store } = openStore()
    trashConflict(store)
    const before = store.snapshot().tasks[0]!
    pullNewerTitle(store, 'First pull attempt')
    pullNewerTitle(store, 'Second pull attempt')
    const after = store.snapshot().tasks[0]!
    expect(after.title).toBe(before.title)
    store.close()
  })
})
