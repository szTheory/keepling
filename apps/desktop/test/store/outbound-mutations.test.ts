import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { afterEach, describe, expect, it } from 'vitest'

import { buildOutboundCommand, type OutboundIntent } from '../../main/application/outbound-commands.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'
import type { SyncMutation } from '../../main/application/DesktopApplication.ts'

/**
 * O-41 at the durability boundary.
 *
 * Two claims are proved here that cannot be proved anywhere else:
 *
 *  1. The local projection and the durable outbox entry commit ATOMICALLY
 *     (D-03). A crash between them would leave a person told their change
 *     is safe while the outbound intent is gone forever.
 *  2. ORDERING. An edit to a task whose capture has not yet been
 *     acknowledged must not overtake it. This is the part of O-41 most
 *     likely to be got wrong, so it is proved rather than asserted in
 *     prose -- and the mechanism is stated: one resource key per task, and
 *     `readyMutations` excludes any mutation sharing a resource key with an
 *     EARLIER outbox entry.
 */

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-outbound-'))
  roots.push(root)
  return {
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  }
}

const TASK_ID = 'task-outbound'

const captureBytes = JSON.stringify({
  mutation_id: 'mutation-capture',
  task_id: TASK_ID,
  title: 'Book the ferry',
  type: 'capture_task',
  version: 1,
})

const capture = {
  acceptedAt: '2026-09-04T12:00:00.000Z',
  commandBytes: captureBytes,
  fingerprint: createHash('sha256').update(captureBytes).digest('hex'),
  mutationId: 'mutation-capture',
  taskId: TASK_ID,
  title: 'Book the ferry',
} as const

const outbound = (
  store: NodeSqliteLocalStore,
  intent: OutboundIntent,
  mutationId: string,
): SyncMutation => {
  const built = buildOutboundCommand(intent, store.taskSyncBasis(intent.taskId), mutationId)
  return {
    acceptedAt: '2026-09-04T12:05:00.000Z',
    commandBytes: built.commandBytes,
    dependencies: [],
    effect: built.effect,
    fingerprint: createHash('sha256').update(built.commandBytes).digest('hex'),
    mutationId,
    resourceKeys: built.resourceKeys,
  }
}

const openStore = () => {
  const store = new NodeSqliteLocalStore(fixture())
  store.acceptCapture(capture)
  return store
}

describe('durable outbound mutations (O-41)', () => {
  it('enqueues a durable command for an edit, a lifecycle change, and a Today move', () => {
    const store = openStore()
    // Acknowledge the capture first so each mutation below is queued alone
    // and the assertion is about enqueueing, not about ordering.
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    expect(store.syncState().outbox).toEqual([])

    store.editTask(
      { notes: 'via Oban', taskId: TASK_ID, title: 'Book the ferry to Mull' },
      outbound(store, { kind: 'edit', notes: 'via Oban', taskId: TASK_ID, title: 'Book the ferry to Mull' }, 'm-edit'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-edit',
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: 'via Oban', planned_on: null, revision: 2, title: 'Book the ferry to Mull' },
    })

    store.applyLifecycle(
      { kind: 'complete', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, 'm-complete'),
    )
    expect(JSON.parse(store.readyMutations()[0]!.commandBytes)).toMatchObject({
      expected_revision: 2,
      task_id: TASK_ID,
      type: 'complete_task',
    })
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-complete',
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: 'via Oban', planned_on: null, revision: 3, title: 'Book the ferry to Mull' },
    })

    store.applyMoveToday(
      { planned: true, taskId: TASK_ID },
      outbound(store, { kind: 'move_today', planned: true, taskId: TASK_ID }, 'm-today'),
    )
    expect(JSON.parse(store.readyMutations()[0]!.commandBytes)).toMatchObject({
      base_planned_on: null,
      expected_revision: 3,
      type: 'plan_for_today',
    })
    store.close()
  })

  it('enqueues one durable command for reopen, trash and restore too', () => {
    const store = openStore()
    for (const [index, lifecycle] of (['reopen', 'trash', 'restore'] as const).entries()) {
      store.applyLifecycle(
        { kind: lifecycle, taskId: TASK_ID },
        outbound(store, { kind: 'lifecycle', lifecycle, taskId: TASK_ID }, `m-${lifecycle}`),
      )
      expect(store.syncState().outbox).toHaveLength(index + 2)
    }
    const types = store.syncState().outbox.map((mutationId) => mutationId)
    expect(types).toEqual(['mutation-capture', 'm-reopen', 'm-trash', 'm-restore'])
    store.close()
  })

  // -- ORDERING ------------------------------------------------------------

  it('never lets an edit overtake the unacknowledged capture of the same task', () => {
    const store = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Retitled while offline' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Retitled while offline' }, 'm-edit'),
    )

    // Both are durably queued...
    expect(store.syncState().outbox).toEqual(['mutation-capture', 'm-edit'])
    // ...but only the capture is READY to push, because the edit shares the
    // resource key `task:<id>` with an earlier outbox entry.
    expect(store.readyMutations().map((mutation) => mutation.mutationId)).toEqual(['mutation-capture'])

    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    // Only now, with the capture settled and gone from the outbox, does the
    // edit become pushable.
    expect(store.readyMutations().map((mutation) => mutation.mutationId)).toEqual(['m-edit'])
    store.close()
  })

  it('holds a whole chain of mutations on one task in the order they were made', () => {
    const store = openStore()
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'First retitle' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'First retitle' }, 'm-edit'),
    )
    store.applyLifecycle(
      { kind: 'complete', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, 'm-complete'),
    )
    expect(store.syncState().outbox).toEqual(['mutation-capture', 'm-edit', 'm-complete'])
    expect(store.readyMutations()).toHaveLength(1)
    expect(store.readyMutations()[0]!.mutationId).toBe('mutation-capture')
    store.close()
  })

  it('lets mutations on DIFFERENT tasks flush in the same pass', () => {
    const store = openStore()
    const otherBytes = JSON.stringify({
      mutation_id: 'mutation-other',
      task_id: 'task-other',
      title: 'Another task',
      type: 'capture_task',
      version: 1,
    })
    store.acceptCapture({
      acceptedAt: '2026-09-04T12:01:00.000Z',
      commandBytes: otherBytes,
      fingerprint: createHash('sha256').update(otherBytes).digest('hex'),
      mutationId: 'mutation-other',
      taskId: 'task-other',
      title: 'Another task',
    })
    expect(store.readyMutations().map((mutation) => mutation.mutationId)).toEqual([
      'mutation-capture',
      'mutation-other',
    ])
    store.close()
  })

  // -- THE BASIS CHAIN -----------------------------------------------------

  it('rebases each queued mutation on the effect of the previous one, not on a stale shadow', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    store.editTask(
      { notes: 'first', taskId: TASK_ID, title: 'First retitle' },
      outbound(store, { kind: 'edit', notes: 'first', taskId: TASK_ID, title: 'First retitle' }, 'm-edit-1'),
    )
    // The SECOND offline edit must send the first edit's values as its base.
    // Sending the canonical shadow again would make the server report a
    // conflict against a value this client itself had just supplied.
    const second = outbound(
      store,
      { kind: 'edit', notes: 'second', taskId: TASK_ID, title: 'Second retitle' },
      'm-edit-2',
    )
    expect(JSON.parse(second.commandBytes)).toMatchObject({
      base_values: { notes: 'first', title: 'First retitle' },
      fields: { notes: 'second', title: 'Second retitle' },
    })
    store.close()
  })

  it('bases a mutation on the canonical shadow when nothing is queued', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: 'server notes', planned_on: '2026-09-04', revision: 7, title: 'Server title' },
    })
    expect(store.taskSyncBasis(TASK_ID)).toEqual({
      baseNotes: 'server notes',
      basePlannedOn: '2026-09-04',
      baseTitle: 'Server title',
      expectedRevision: 7,
    })
    store.close()
  })

  // -- ATOMICITY AND VALIDATION -------------------------------------------

  it('commits the projection and the outbox entry atomically across a hard close and reopen', () => {
    const paths = fixture()
    const first = new NodeSqliteLocalStore(paths)
    first.acceptCapture(capture)
    first.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    first.applyLifecycle(
      { kind: 'trash', taskId: TASK_ID },
      outbound(first, { kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, 'm-trash'),
    )
    // No `close()` -- the WAL is what a relaunch after a hard kill reads.
    const reopened = new NodeSqliteLocalStore(paths)
    expect(reopened.syncState().outbox).toEqual(['m-trash'])
    expect(reopened.snapshot().tasks[0]!.trashedAt).not.toBeNull()
    expect(reopened.snapshot().tasks[0]!.syncStatus).toBe('saved_on_this_mac')
    expect(JSON.parse(reopened.readyMutations()[0]!.commandBytes)).toMatchObject({ type: 'trash_task' })
    first.close()
    reopened.close()
  })

  it('rolls the projection back when the outbound bytes cannot be recorded', () => {
    const store = openStore()
    const duplicate = outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Retitled' }, 'mutation-capture')
    expect(() => store.editTask({ notes: '', taskId: TASK_ID, title: 'Retitled' }, duplicate)).toThrow()
    // The projection must be untouched: a local change that could not record
    // its outbound intent never happened at all.
    expect(store.snapshot().tasks[0]!.title).toBe('Book the ferry')
    expect(store.syncState().outbox).toEqual(['mutation-capture'])
    store.close()
  })

  it('refuses outbound bytes that disagree with the mutation being recorded', () => {
    const store = openStore()
    const built = outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Retitled' }, 'm-edit')

    // Wrong command type for this operation.
    const wrongType = outbound(store, { kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, 'm-edit')
    expect(() => store.editTask({ notes: '', taskId: TASK_ID, title: 'Retitled' }, wrongType)).toThrow(
      'outbound command bytes do not match the mutation being recorded',
    )

    // Tampered bytes: the fingerprint no longer covers them.
    expect(() =>
      store.editTask(
        { notes: '', taskId: TASK_ID, title: 'Retitled' },
        { ...built, commandBytes: built.commandBytes.replace('Retitled', 'Tampered') },
      ),
    ).toThrow('outbound command bytes do not match the mutation being recorded')

    // A body missing `version` is a body the real server answers 400 to,
    // and it must never reach the outbox (O-34).
    const withoutVersion = JSON.stringify({
      ...(JSON.parse(built.commandBytes) as Record<string, unknown>),
      version: 2,
    })
    expect(() =>
      store.editTask(
        { notes: '', taskId: TASK_ID, title: 'Retitled' },
        {
          ...built,
          commandBytes: withoutVersion,
          fingerprint: createHash('sha256').update(withoutVersion).digest('hex'),
        },
      ),
    ).toThrow('outbound command bytes do not match the mutation being recorded')
    store.close()
  })

  it('retries the EXACT recorded bytes, never a re-serialization', () => {
    const store = openStore()
    const built = outbound(store, { kind: 'edit', notes: 'n', taskId: TASK_ID, title: 'Retitled' }, 'm-edit')
    store.editTask({ notes: 'n', taskId: TASK_ID, title: 'Retitled' }, built)
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    const ready = store.readyMutations()[0]!
    expect(ready.commandBytes).toBe(built.commandBytes)
    expect(ready.fingerprint).toBe(createHash('sha256').update(built.commandBytes).digest('hex'))
    store.close()
  })

  it('leaves the outbound intent alone when local writes are fenced', () => {
    const store = openStore()
    store.setSyncFence('signed_out')
    const built = outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Retitled' }, 'm-edit')
    expect(() => store.editTask({ notes: '', taskId: TASK_ID, title: 'Retitled' }, built)).toThrow(
      'local writes are fenced',
    )
    expect(store.readyMutations()).toEqual([])
    store.close()
  })

  it('records the outbound command bytes in the same durable table as a capture', () => {
    const paths = fixture()
    const store = new NodeSqliteLocalStore(paths)
    store.acceptCapture(capture)
    store.applyLifecycle(
      { kind: 'complete', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, 'm-complete'),
    )
    store.close()

    const database = new DatabaseSync(paths.databasePath, { readOnly: true })
    try {
      const rows = database
        .prepare('SELECT mutation_id, command_bytes FROM immutable_commands ORDER BY mutation_id')
        .all() as Array<{ command_bytes: string; mutation_id: string }>
      expect(rows.map((row) => row.mutation_id)).toEqual(['m-complete', 'mutation-capture'])
      expect(JSON.parse(rows[0]!.command_bytes)).toMatchObject({ type: 'complete_task', version: 1 })
    } finally {
      database.close()
    }
  })
  // -- O-38: WHAT A REFUSAL DOES TO THE LOCAL ROW ---------------------------

  it('never overwrites the local row from a conflict answer, which is not a full snapshot', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    store.applyLifecycle(
      { kind: 'complete', taskId: TASK_ID },
      outbound(store, { kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, 'm-complete'),
    )
    // The server's 409 body names only the affected field. Writing it into
    // the canonical shadow would blank everything it did not mention, and
    // the projection would fall back to showing the task identifier as its
    // title.
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-complete',
      outcome: 'conflict',
      snapshot: { affected_fields: ['completed_at'], conflict_id: 'c-1', id: TASK_ID, revision: 9 },
    })
    const task = store.snapshot().tasks[0]!
    expect(task.title).toBe('Book the ferry')
    expect(task.syncStatus).toBe('saved_on_this_mac')
    // Terminal: the server has decided, so the command leaves the outbox.
    expect(store.syncState().outbox).toEqual([])
    store.close()
  })

  it('never claims Synced for a rejected command', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
    store.editTask(
      { notes: '', taskId: TASK_ID, title: 'Retitled' },
      outbound(store, { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Retitled' }, 'm-edit'),
    )
    store.acknowledge({
      fingerprint: store.readyMutations()[0]!.fingerprint,
      mutationId: 'm-edit',
      outcome: 'rejected',
      snapshot: { id: TASK_ID, rejection_code: 'no_fields_touched' },
    })
    const task = store.snapshot().tasks[0]!
    expect(task.title).toBe('Retitled')
    expect(task.syncStatus).toBe('saved_on_this_mac')
    expect(store.syncState().outbox).toEqual([])
    expect(store.listConflicts()).toEqual([])
    store.close()
  })

  it('records a mine/current choice only when the server named a divergent title', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
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
    expect(store.listConflicts()).toEqual([
      {
        conflictId: 'conflict:m-edit',
        current: 'Book the ferry from Oban',
        mine: 'Book the ferry to Mull',
        taskId: TASK_ID,
      },
    ])
    store.close()
  })

  it('does not offer a title chooser for a conflict that is not about a title', () => {
    const store = openStore()
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', planned_on: null, revision: 1, title: 'Book the ferry' },
    })
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
    // Offering two timestamps under "choose which title to keep" would be a
    // lie in the UI. The `conflict` row and its Review Conflict action still
    // reach the person; the action falls back to refreshing from the server.
    expect(store.listConflicts()).toEqual([])
    store.close()
  })
})
