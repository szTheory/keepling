import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { afterEach, describe, expect, it } from 'vitest'

import { buildOutboundCommand } from '../../main/application/outbound-commands.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'
import type { SyncMutation } from '../../main/application/DesktopApplication.ts'

/**
 * O-51 / D-52, Task 2: the outbox state machine, and the ONE thing it
 * exists to make safe -- an undo may drop a command only when this store can
 * prove the command's bytes were never handed to the transport.
 *
 * The whole point is that "still in the outbox" is NOT that proof. A row
 * sits there unchanged while its POST is in flight, so every case below
 * distinguishes the two by state rather than by presence.
 */

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const TASK_ID = 'task-transmission'
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

const openStore = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-transmission-'))
  roots.push(root)
  const databasePath = join(root, 'namespace.sqlite3')
  const store = new NodeSqliteLocalStore({
    databasePath,
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  })
  return { databasePath, root, store }
}

const outbound = (built: ReturnType<typeof buildOutboundCommand>, mutationId: string): SyncMutation => ({
  acceptedAt: '2026-09-04T12:01:00.000Z',
  commandBytes: built.commandBytes,
  dependencies: [],
  effect: built.effect,
  fingerprint: createHash('sha256').update(built.commandBytes).digest('hex'),
  mutationId,
  resourceKeys: built.resourceKeys,
})

/** A captured, acknowledged task plus one edit through the shipped path. */
const editedTask = (store: NodeSqliteLocalStore, mutationId = 'mutation-edit', title = 'Book the ferry to Mull') => {
  if (store.snapshot().tasks.length === 0) {
    store.acceptCapture(capture)
    store.acknowledge({
      fingerprint: capture.fingerprint,
      mutationId: capture.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', revision: 1, title: 'Book the ferry' },
    })
  }
  const built = buildOutboundCommand(
    { kind: 'edit', notes: '', taskId: TASK_ID, title },
    store.taskSyncBasis(TASK_ID),
    mutationId,
  )
  const mutation = outbound(built, mutationId)
  store.editTask({ notes: '', taskId: TASK_ID, title }, mutation)
  return mutation
}

const states = (databasePath: string): Array<{ mutationId: string; state: string }> => {
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    return database
      .prepare('SELECT mutation_id AS mutationId, state FROM outbox ORDER BY sequence')
      .all() as Array<{ mutationId: string; state: string }>
  } finally {
    database.close()
  }
}

const commandCount = (databasePath: string, mutationId: string): number => {
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    const row = database
      .prepare('SELECT COUNT(*) AS total FROM immutable_commands WHERE mutation_id = ?')
      .get(mutationId) as { total: number }
    return row.total
  } finally {
    database.close()
  }
}

describe('outbox transmission state (O-51 / D-52)', () => {
  it('marks a row in flight before its bytes are transmitted, and withholds it from the ready set', () => {
    const { databasePath, store } = openStore()
    const edit = editedTask(store)
    expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'queued' }])
    expect(store.readyMutations().map((mutation) => mutation.mutationId)).toEqual([edit.mutationId])

    store.beginTransmission(edit.mutationId, edit.fingerprint)
    expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'in_flight' }])
    // A live request must not be re-selected and posted a second time.
    expect(store.readyMutations()).toEqual([])
    store.close()
  })

  /**
   * A transport failure does NOT return a row to `queued`. `fetch`
   * rejecting cannot distinguish "the request never left" from "it left and
   * the answer was lost" (O-47), so the row is ambiguous from then on --
   * still pushed, because retransmitting the same immutable bytes under the
   * same mutation identity is safe, but never droppable again.
   */
  it('never returns a row to queued once its bytes were handed to the transport', () => {
    const { databasePath, store } = openStore()
    const edit = editedTask(store)

    store.beginTransmission(edit.mutationId, edit.fingerprint)
    store.abandonTransmission(edit.mutationId)
    expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'uncertain' }])
    // Still pushed, with the SAME bytes -- never re-serialized.
    expect(store.readyMutations().map((mutation) => mutation.commandBytes)).toEqual([edit.commandBytes])

    store.beginTransmission(edit.mutationId, edit.fingerprint)
    store.abandonTransmission(edit.mutationId)
    expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'uncertain' }])
    store.close()
  })

  it('refuses to mark a transmission whose fingerprint is not the stored command', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    expect(() => store.beginTransmission(edit.mutationId, 'f'.repeat(64))).toThrow(/transmission/)
    expect(() => store.beginTransmission('mutation-that-does-not-exist', edit.fingerprint)).toThrow(/transmission/)
    store.close()
  })

  /**
   * A process that dies mid-POST leaves `in_flight` with no outcome. The
   * next open must NOT reset it to `queued`: this client genuinely does not
   * know whether those bytes reached the server.
   */
  it('recovers an interrupted transmission as uncertain, never as queued', () => {
    const { databasePath, root, store } = openStore()
    const edit = editedTask(store)
    store.beginTransmission(edit.mutationId, edit.fingerprint)
    // No abandon, no acknowledgement: the process simply ends here.
    store.close()

    const reopened = new NodeSqliteLocalStore({
      databasePath: join(root, 'namespace.sqlite3'),
      migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
    })
    try {
      expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'uncertain' }])
      expect(reopened.readyMutations().map((mutation) => mutation.mutationId)).toEqual([edit.mutationId])
      expect(reopened.undoUnsentLocalAction().reason).toBe('transmitted')
    } finally {
      reopened.close()
    }
  })
})

describe('undo of a never-transmitted mutation (O-51 / D-52)', () => {
  it('drops the command and reverts the change when the bytes never left this Mac', () => {
    const { databasePath, store } = openStore()
    const edit = editedTask(store)
    expect(store.snapshot().tasks[0]?.title).toBe('Book the ferry to Mull')

    const result = store.undoUnsentLocalAction()
    expect(result).toEqual({
      applied: true,
      reason: 'dropped',
      snapshot: expect.objectContaining({
        tasks: [expect.objectContaining({ title: 'Book the ferry' })],
      }),
    })
    // The command is GONE, so a server configured later can never flush it.
    expect(states(databasePath)).toEqual([])
    expect(commandCount(databasePath, edit.mutationId)).toBe(0)
    expect(store.readyMutations()).toEqual([])
    // One level of undo: a second press finds nothing.
    expect(store.undoUnsentLocalAction().reason).toBe('nothing_to_undo')
    store.close()
  })

  it('REFUSES a command that is in flight -- it is never dropped', () => {
    const { databasePath, store } = openStore()
    const edit = editedTask(store)
    store.beginTransmission(edit.mutationId, edit.fingerprint)

    const result = store.undoUnsentLocalAction()
    expect(result.applied).toBe(false)
    expect(result.reason).toBe('transmitted')
    // Nothing changed: the command is still queued for delivery, with the
    // same bytes, and the edit is still on screen.
    expect(states(databasePath)).toEqual([{ mutationId: edit.mutationId, state: 'in_flight' }])
    expect(commandCount(databasePath, edit.mutationId)).toBe(1)
    expect(store.snapshot().tasks[0]?.title).toBe('Book the ferry to Mull')
    store.close()
  })

  /**
   * Dropping a command that a LATER queued command was built on top of
   * would send the successor against a base the server never received.
   * 03-22's resource key is what says "these two are about the same task",
   * and it decides this the same way it decides push ordering.
   */
  it('REFUSES when a later queued command shares the resource key', () => {
    const { databasePath, store } = openStore()
    editedTask(store, 'mutation-edit-1', 'Book the ferry to Mull')
    const successor = buildOutboundCommand(
      { kind: 'edit', notes: '', taskId: TASK_ID, title: 'Book the ferry to Mull tomorrow' },
      store.taskSyncBasis(TASK_ID),
      'mutation-edit-2',
    )
    // Enqueued without recording a new undoable action, so `last_local_action`
    // still names the FIRST edit while the second sits behind it.
    store.acceptMutation(outbound(successor, 'mutation-edit-2'))

    const result = store.undoUnsentLocalAction()
    expect(result.applied).toBe(false)
    expect(result.reason).toBe('blocked')
    expect(states(databasePath).map((row) => row.mutationId)).toEqual(['mutation-edit-1', 'mutation-edit-2'])
    expect(store.snapshot().tasks[0]?.title).toBe('Book the ferry to Mull tomorrow')
    store.close()
  })

  it('REFUSES once the server has settled the command -- there is no outbox row to drop', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    store.acknowledge({
      fingerprint: edit.fingerprint,
      mutationId: edit.mutationId,
      outcome: 'accepted',
      snapshot: { id: TASK_ID, notes: '', revision: 2, title: 'Book the ferry to Mull' },
    })
    // The command left the outbox because the server settled it.
    expect(store.undoUnsentLocalAction().reason).toBe('unknown')
    store.close()
  })
})
