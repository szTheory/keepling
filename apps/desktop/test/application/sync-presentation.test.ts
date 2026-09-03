import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { DesktopApplication, type PendingMutation } from '../../main/application/DesktopApplication.ts'
import { GRACE_PERIOD_MS, type DesktopPresentation } from '../../main/application/presentation.ts'

/**
 * O-19: MAC-04 requires a person to be able to inspect the "syncing" state
 * without reading logs. `runSyncPass()` previously published NOTHING, so
 * four of MAC-04's five states were reachable and the fifth was not.
 *
 * These cases pin three properties:
 *  1. A pass that outlives the anti-flicker grace period publishes the
 *     `updating` ("Updating…") row while it is still running.
 *  2. The syncing row is CLEARED on every exit path -- success, partial
 *     settlement, and failure -- so it can never stick.
 *  3. The syncing row makes no durability claim: it never says "Synced",
 *     and a pass whose acknowledgement does not match mutation identity AND
 *     fingerprint exactly settles nothing and lands on "Saved on this Mac".
 */

const commandBytes = JSON.stringify({ mutation_id: 'mutation-one', task_id: 'task-one', title: 'Sync me', type: 'capture_task' })

const mutation: PendingMutation = {
  acceptedAt: '2026-09-02T12:00:00.000Z',
  commandBytes,
  fingerprint: 'fingerprint-one',
  mutationId: 'mutation-one',
  taskId: 'task-one',
  title: 'Sync me',
}

type SyncStubs = {
  pull?: (cursor: string | null, limit: 50) => Promise<{ changes: unknown[]; cursor: string | null }>
  push?: (bytes: string) => Promise<{ fingerprint: string; mutationId: string } | null>
}

const buildApplication = (sync: SyncStubs, ready: PendingMutation[] = [mutation]) =>
  new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore: {
      acceptCapture: async () => { throw new Error('unused') },
      acceptMutation: async () => { throw new Error('unused') },
      acknowledge: async () => ({ tasks: [] }),
      acknowledgeSync: async () => undefined,
      applyPull: async () => undefined,
      close: async () => undefined,
      pendingMutations: async () => ready,
      readyMutations: async () => ready,
      setSyncFence: async () => undefined,
      snapshot: async () => ({ tasks: [] }),
      syncState: async () => ({ cursor: null, outbox: ready.map((entry) => entry.mutationId), readyPushes: ready.map((entry) => entry.mutationId) }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    sync: sync as any,
  })

describe('synchronization presentation (O-19 / MAC-04 fifth state)', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('publishes an inspectable syncing row while a pass is still running, then clears it on success', async () => {
    let releasePull: (() => void) | null = null
    const pullGate = new Promise<void>((resolve) => { releasePull = resolve })
    const observed: DesktopPresentation[] = []

    const application = buildApplication({
      pull: async () => {
        await pullGate
        return { changes: [], cursor: 'cursor-after-pull' }
      },
      push: async () => ({ fingerprint: mutation.fingerprint, mutationId: mutation.mutationId }),
    })
    application.subscribePresentation((presentation) => observed.push(presentation))

    const pass = application.runSyncPass()
    // Inside the anti-flicker grace period the row is deliberately quiet.
    await vi.advanceTimersByTimeAsync(GRACE_PERIOD_MS - 1)
    expect(application.presentationSnapshot().summary.kind).not.toBe('updating')

    // Past the grace period the same pass becomes visible as "Updating…".
    await vi.advanceTimersByTimeAsync(2)
    expect(application.presentationSnapshot().summary.kind).toBe('updating')
    expect(application.presentationSnapshot().summary.copy).toBe('Updating…')

    releasePull?.()
    await vi.advanceTimersByTimeAsync(0)
    await pass

    // Cleared: a completed pass never leaves the syncing row on screen.
    expect(application.presentationSnapshot().summary.kind).not.toBe('updating')
    expect(observed.some((presentation) => presentation.summary.kind === 'updating')).toBe(true)
  })

  it('clears the syncing row when the pass fails, and never leaves it stuck', async () => {
    const application = buildApplication({
      pull: async () => { throw new Error('network refused') },
      push: async () => null,
    })

    await expect(application.runSyncPass()).rejects.toThrow(/network refused/)

    const presentation = application.presentationSnapshot()
    expect(presentation.summary.kind).toBe('retryable_failure')
    expect(presentation.summary.kind).not.toBe('updating')
  })

  it('makes no durability claim: an inexact acknowledgement settles nothing and lands on "Saved on this Mac"', async () => {
    const observed: DesktopPresentation[] = []
    const application = buildApplication({
      pull: async () => ({ changes: [], cursor: 'cursor-after-pull' }),
      // Right mutation identity, WRONG fingerprint -- must not settle.
      push: async () => ({ fingerprint: 'a-different-fingerprint', mutationId: mutation.mutationId }),
    })
    application.subscribePresentation((presentation) => observed.push(presentation))

    const result = await application.runSyncPass()
    expect(result.settled).toBe(0)

    const presentation = application.presentationSnapshot()
    expect(presentation.summary.kind).toBe('local_saved')
    expect(presentation.summary.count).toBe(1)
    for (const entry of observed) {
      expect(entry.summary.copy ?? '').not.toMatch(/Synced/)
    }
  })

  it('does not clobber a more specific presentation published during the pass', async () => {
    const application = buildApplication({
      pull: async () => {
        application.publishPresentation({ affectedCount: 1, kind: 'conflict' })
        return { changes: [], cursor: 'cursor-after-pull' }
      },
      push: async () => ({ fingerprint: mutation.fingerprint, mutationId: mutation.mutationId }),
    })

    await application.runSyncPass()

    expect(application.presentationSnapshot().summary.kind).toBe('conflict')
  })
})
