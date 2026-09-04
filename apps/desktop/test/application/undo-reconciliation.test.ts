import { describe, expect, it } from 'vitest'

import { DesktopApplication } from '../../main/application/DesktopApplication.ts'
import type {
  LocalStorePort,
  SyncMutation,
  WorkspaceSnapshot,
} from '../../main/application/DesktopApplication.ts'

/**
 * O-45, the decision this plan had to make deliberately rather than by
 * accident.
 *
 * The hardest case is an undo of a mutation whose acknowledgement has not
 * arrived, so no server-issued handle exists to reference. Three answers
 * were available: accept it locally and drop it (the DEFECT -- an undo
 * durable on this Mac and invisible to the server forever), defer it until
 * the handle lands, or refuse it at the point of action with honest copy.
 *
 * This client REFUSES, and says so. Deferring would mean holding an intent
 * with no bytes, materialising them later from a handle that may never
 * arrive, and inventing an in-doubt state to describe the wait -- a second
 * durability mechanism, and a decision on `{ kind: 'uncertain' }` (O-47)
 * that this plan does not carry authority to make. Refusing keeps one
 * mechanism and keeps the failure loud, which is what the truth "never
 * silently dropped" actually requires.
 *
 * The refusal is SURFACED through the main-owned presentation row -- the
 * same channel `offline`, `conflict` and `rejected` already reach the
 * shipped window through -- so it is a state a person can inspect, not a
 * return value the renderer discards (which is what happened to the old
 * "Nothing to undo." message: `DesktopShell` calls `void
 * facade.undoLastChange()`).
 */

const TASK_ID = 'task-1'
const HANDLE = 'h'.repeat(43)

const snapshotOf = (title: string): WorkspaceSnapshot => ({
  tasks: [{ id: TASK_ID, syncStatus: 'saved_on_this_mac', title }],
})

type Harness = {
  application: DesktopApplication
  enqueued: SyncMutation[]
}

const harness = (options: {
  now?: string
  target?: {
    availability: { expiresAt: string; handle: string; label: string } | null
    mutationId: string | null
    previous: { notes: string; title: string }
    taskId: string
  } | null
}): Harness => {
  const enqueued: SyncMutation[] = []
  const localStore = {
    acceptCapture: async () => {
      throw new Error('unused')
    },
    acknowledge: async () => snapshotOf('after'),
    close: async () => undefined,
    pendingMutations: async () => [],
    snapshot: async () => snapshotOf('after'),
    taskSyncBasis: () => ({
      baseNotes: 'after',
      basePlannedOn: null,
      baseTitle: 'after',
      expectedRevision: 2,
    }),
    undoLastLocalAction: (outbound?: SyncMutation) => {
      if (outbound === undefined) return { applied: false, snapshot: snapshotOf('after') }
      enqueued.push(outbound)
      return { applied: true, snapshot: snapshotOf('before') }
    },
    undoTarget: () => options.target ?? null,
  } satisfies LocalStorePort

  return {
    application: new DesktopApplication({
      clock: { now: () => options.now ?? '2026-09-04T12:00:00.000Z' },
      identity: { randomId: () => 'mutation-undo' },
      localStore,
      sync: {},
    }),
    enqueued,
  }
}

const available = {
  availability: { expiresAt: '2026-09-05T12:00:00.000Z', handle: HANDLE, label: 'Undo task edit' },
  mutationId: 'mutation-edit',
  previous: { notes: 'before', title: 'before' },
  taskId: TASK_ID,
}

describe('undo reconciliation (O-45)', () => {
  it('enqueues an undo_task command referencing the RETAINED handle', async () => {
    const { application, enqueued } = harness({ target: available })
    const result = await application.undoLastLocalAction()

    expect(result.applied).toBe(true)
    expect(enqueued).toHaveLength(1)
    expect(JSON.parse(enqueued[0]!.commandBytes)).toEqual({
      handle: HANDLE,
      mutation_id: 'mutation-undo',
      type: 'undo_task',
      version: 1,
    })
    // Ordering is 03-22's resource key, not a second mechanism.
    expect(enqueued[0]!.resourceKeys).toEqual([`task:${TASK_ID}`])
    expect(enqueued[0]!.dependencies).toEqual([])
  })

  it('REFUSES, loudly and visibly, when no handle was ever retained', async () => {
    const { application, enqueued } = harness({ target: { ...available, availability: null } })
    const result = await application.undoLastLocalAction()

    expect(result).toMatchObject({ applied: false, reason: 'unsent' })
    expect(enqueued).toEqual([])
    const presentation = application.presentationSnapshot().summary
    expect(presentation.kind).toBe('undo_unavailable')
    expect(presentation.copy).toBe(
      'This change hasn’t reached the server yet, so it can’t be undone. Nothing was changed.',
    )
    // A remedy, not a label (O-42): syncing is what makes the handle arrive.
    expect(presentation.actions).toEqual([{ code: 'retry', label: 'Retry' }])
  })

  it('REFUSES, loudly and visibly, when the server-issued handle has expired', async () => {
    const { application, enqueued } = harness({
      now: '2026-09-06T12:00:00.000Z',
      target: available,
    })
    const result = await application.undoLastLocalAction()

    expect(result).toMatchObject({ applied: false, reason: 'expired' })
    expect(enqueued).toEqual([])
    const presentation = application.presentationSnapshot().summary
    expect(presentation.kind).toBe('undo_unavailable')
    expect(presentation.copy).toBe('This change can no longer be undone. Nothing was changed.')
    // Nothing here is retryable, so nothing is offered.
    expect(presentation.actions).toEqual([])
  })

  it('reports nothing to undo without publishing an interruption', async () => {
    const { application, enqueued } = harness({ target: null })
    const result = await application.undoLastLocalAction()
    expect(result).toMatchObject({ applied: false, reason: 'nothing_to_undo' })
    expect(enqueued).toEqual([])
    expect(application.presentationSnapshot().summary.kind).toBe('opening')
  })

  it('NEVER synthesises a handle when the store cannot answer for one', async () => {
    const application = new DesktopApplication({
      clock: { now: () => '2026-09-04T12:00:00.000Z' },
      identity: { randomId: () => 'mutation-undo' },
      localStore: {
        acceptCapture: async () => {
          throw new Error('unused')
        },
        acknowledge: async () => snapshotOf('after'),
        close: async () => undefined,
        pendingMutations: async () => [],
        snapshot: async () => snapshotOf('after'),
        undoLastLocalAction: () => ({ applied: true, snapshot: snapshotOf('before') }),
      } satisfies LocalStorePort,
      sync: {},
    })
    // Absent capability is a LOUD FAILURE, never a silent local-only undo.
    await expect(application.undoLastLocalAction()).rejects.toThrow('undo reconciliation is unavailable')
  })
})
