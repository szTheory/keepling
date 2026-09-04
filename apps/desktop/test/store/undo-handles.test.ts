import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'

import { buildOutboundCommand, buildUndoCommand } from '../../main/application/outbound-commands.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'
import type { SyncMutation } from '../../main/application/DesktopApplication.ts'

/**
 * O-45 at the durability boundary.
 *
 * Until this, `undoLastLocalAction` reversed the last action in the visible
 * projection and enqueued NOTHING -- so an undo was durable on this Mac and
 * invisible to the server forever, the same defect class as O-41 one
 * operation later. It could not be closed the way O-41 was, because
 * `POST /commands/undo-task` takes a SERVER-ISSUED handle and this client
 * retained it nowhere.
 *
 * Three claims are proved here and nowhere else:
 *
 *  1. The handle is RETAINED from the acknowledgement that carried it, and
 *     is consumed exactly once.
 *  2. An undo with no retained handle CHANGES NOTHING -- it does not
 *     silently reverse the projection and drop the intent, which is the
 *     defect being fixed.
 *  3. The projection revert and the durable undo command commit
 *     ATOMICALLY, and the undo carries the same `task:<id>` resource key as
 *     everything else, so it cannot overtake the mutation it undoes.
 */

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const TASK_ID = 'task-undo'
const HANDLE = 'h'.repeat(43)

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

const outbound = (built: ReturnType<typeof buildOutboundCommand>, mutationId: string): SyncMutation => ({
  acceptedAt: '2026-09-04T12:01:00.000Z',
  commandBytes: built.commandBytes,
  dependencies: [],
  effect: built.effect,
  fingerprint: createHash('sha256').update(built.commandBytes).digest('hex'),
  mutationId,
  resourceKeys: built.resourceKeys,
})

const openStore = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-undo-'))
  roots.push(root)
  const store = new NodeSqliteLocalStore({
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  })
  return { root, store }
}

/** A captured, server-acknowledged task, then one edit through the shipped path. */
const editedTask = (store: NodeSqliteLocalStore, editMutationId = 'mutation-edit') => {
  store.acceptCapture(capture)
  store.acknowledge({
    fingerprint: capture.fingerprint,
    mutationId: capture.mutationId,
    outcome: 'accepted',
    snapshot: { id: TASK_ID, notes: '', revision: 1, title: 'Book the ferry' },
  })
  const built = buildOutboundCommand(
    { kind: 'edit', notes: 'from Oban', taskId: TASK_ID, title: 'Book the ferry to Mull' },
    store.taskSyncBasis(TASK_ID),
    editMutationId,
  )
  const mutation = outbound(built, editMutationId)
  store.editTask({ notes: 'from Oban', taskId: TASK_ID, title: 'Book the ferry to Mull' }, mutation)
  return mutation
}

const acknowledgeEdit = (store: NodeSqliteLocalStore, mutation: SyncMutation, undo?: { expiresAt: string; handle: string; label: string }) => {
  store.acknowledge({
    fingerprint: mutation.fingerprint,
    mutationId: mutation.mutationId,
    outcome: 'accepted',
    snapshot: { id: TASK_ID, notes: 'from Oban', revision: 2, title: 'Book the ferry to Mull' },
    ...(undo === undefined ? {} : { undo }),
  })
}

const availability = (expiresAt = '2099-01-01T00:00:00.000Z') => ({
  expiresAt,
  handle: HANDLE,
  label: 'Undo task edit',
})

describe('retaining the server-issued undo handle (O-45)', () => {
  it('retains the handle the acknowledgement carried, against the mutation it undoes', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit, availability())

    expect(store.undoTarget()).toEqual({
      availability: availability(),
      mutationId: edit.mutationId,
      previous: { notes: '', title: 'Book the ferry' },
      taskId: TASK_ID,
    })
    store.close()
  })

  it('retains NOTHING when the server issued no compensation capability', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit)
    expect(store.undoTarget()?.availability).toBeNull()
    store.close()
  })

  it('reports no target at all when nothing has been done', () => {
    const { store } = openStore()
    expect(store.undoTarget()).toBeNull()
    store.close()
  })

  it('survives close and reopen -- a handle is only useful if it outlives a relaunch', () => {
    const { root, store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit, availability())
    store.close()

    const reopened = new NodeSqliteLocalStore({
      databasePath: join(root, 'namespace.sqlite3'),
      migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
    })
    expect(reopened.undoTarget()?.availability).toEqual(availability())
    reopened.close()
  })
})

describe('undoing against a retained handle (O-45)', () => {
  const enqueueUndo = (store: NodeSqliteLocalStore, target: NonNullable<ReturnType<NodeSqliteLocalStore['undoTarget']>>) => {
    const built = buildUndoCommand(
      { handle: target.availability!.handle, previous: target.previous, taskId: target.taskId },
      store.taskSyncBasis(target.taskId),
      'mutation-undo',
    )
    return store.undoLastLocalAction(outbound(built, 'mutation-undo'))
  }

  it('reverses the projection AND enqueues the undo command in one transaction', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit, availability())

    const result = enqueueUndo(store, store.undoTarget()!)
    expect(result.applied).toBe(true)
    expect(result.snapshot.tasks[0]).toMatchObject({ title: 'Book the ferry' })

    const queued = store.readyMutations()
    expect(queued).toHaveLength(1)
    expect(JSON.parse(queued[0]!.commandBytes)).toEqual({
      handle: HANDLE,
      mutation_id: 'mutation-undo',
      type: 'undo_task',
      version: 1,
    })
    store.close()
  })

  it('consumes the handle exactly once -- a one-shot capability is not replayable', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit, availability())
    enqueueUndo(store, store.undoTarget()!)
    expect(store.undoTarget()).toBeNull()
    store.close()
  })

  it('cannot overtake a queued mutation on the same task', () => {
    const { store } = openStore()
    store.acceptCapture(capture)
    // The capture is UNACKNOWLEDGED, so it is still in the outbox. An undo
    // queued behind it shares `task:<id>` and must wait.
    const built = buildUndoCommand(
      { handle: HANDLE, previous: { notes: '', title: 'Book the ferry' }, taskId: TASK_ID },
      store.taskSyncBasis(TASK_ID),
      'mutation-undo',
    )
    store.acceptMutation(outbound(built, 'mutation-undo'))
    expect(store.readyMutations().map((mutation) => mutation.mutationId)).toEqual(['mutation-capture'])
    store.close()
  })
})

describe('an undo with no server-issued handle changes NOTHING (O-45)', () => {
  it('leaves the projection and the outbox untouched when no handle was retained', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit)

    const before = store.snapshot()
    const result = store.undoLastLocalAction()
    expect(result.applied).toBe(false)
    expect(result.snapshot).toEqual(before)
    expect(store.snapshot().tasks[0]).toMatchObject({ title: 'Book the ferry to Mull' })
    expect(store.readyMutations()).toHaveLength(0)
    // The action is still there: refusing is not the same as forgetting.
    expect(store.undoTarget()?.mutationId).toBe(edit.mutationId)
    store.close()
  })

  it('refuses to reverse the projection without an outbound command, which is the defect being fixed', () => {
    const { store } = openStore()
    const edit = editedTask(store)
    acknowledgeEdit(store, edit, availability())
    // Calling with no outbound command must NOT silently apply locally.
    expect(store.undoLastLocalAction().applied).toBe(false)
    expect(store.snapshot().tasks[0]).toMatchObject({ title: 'Book the ferry to Mull' })
    store.close()
  })
})
