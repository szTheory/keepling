import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { DesktopApplication, type PendingMutation, type SyncMutation } from '../../main/application/DesktopApplication.ts'
import { GRACE_PERIOD_MS, type DesktopPresentation } from '../../main/application/presentation.ts'
import { isSyncUnreachable, SyncUnreachableError } from '../../main/application/sync-reachability.ts'
import { KeeplingSyncAdapter } from '../../main/adapters/sync.ts'

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

const commandBytes = JSON.stringify({ mutation_id: 'mutation-one', task_id: 'task-one', title: 'Sync me', type: 'capture_task', version: 1 })

// Both shapes at once: `pendingMutations` (reconcile) reads the
// `PendingMutation` half and `readyMutations` (a sync pass) reads the
// `SyncMutation` half. Stating both keeps the fixture an honest stand-in for
// what the real store returns -- `effect.entityId` in particular is what a
// pass hands to `push` as the undo routing key (O-45).
const mutation: PendingMutation & SyncMutation = {
  acceptedAt: '2026-09-02T12:00:00.000Z',
  commandBytes,
  dependencies: [],
  effect: { entityId: 'task-one', snapshot: { id: 'task-one', revision: 1, title: 'Sync me' } },
  fingerprint: 'fingerprint-one',
  mutationId: 'mutation-one',
  resourceKeys: ['task:task-one'],
  taskId: 'task-one',
  title: 'Sync me',
}

type SyncStubs = {
  pull?: (cursor: string | null, limit: 50) => Promise<{ changes: unknown[]; cursor: string | null }>
  push?: (bytes: string) => Promise<{ fingerprint: string; mutationId: string } | null>
}

const buildApplication = (sync: SyncStubs, ready: Array<PendingMutation & SyncMutation> = [mutation]) =>
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

/**
 * O-30 / MAC-04: `{ kind: 'offline' }` was declared, had authored copy, and
 * was unit-tested against a fixture -- and was constructed NOWHERE in
 * production. Unplugging the network showed the retryable-failure row
 * instead, so the state a person most needs to recognise ("my Mac cannot
 * reach the server; nothing is lost") was unreachable.
 *
 * Three situations previously collapsed into two rows. These cases pin the
 * separation:
 *
 *  1. No server configured -> `offline` with a null last contact. Nothing to
 *     be offline FROM, but the app must never imply it is synchronized.
 *  2. A configured server that never answered -> `offline`, carrying the
 *     REAL last successful contact when one has ever happened.
 *  3. A server that answered badly -> still `retryable_failure`. Conflating
 *     these two makes the row a lie.
 */
describe('offline versus rejected (O-30 / MAC-04 fifth state)', () => {
  const buildOfflineApplication = (
    sync: SyncStubs & { configured?: () => boolean },
    options: { contacts?: string[]; lastSuccessfulContact?: string | null } = {},
  ) =>
    new DesktopApplication({
      clock: { now: () => '2026-09-03T12:00:00.000Z' },
      identity: { randomId: () => 'unused' },
      localStore: {
        acceptCapture: async () => { throw new Error('unused') },
        acknowledge: async () => ({ tasks: [] }),
        acknowledgeSync: async () => undefined,
        applyPull: async () => undefined,
        close: async () => undefined,
        pendingMutations: async () => [mutation],
        readyMutations: async () => [mutation],
        recordSuccessfulContact: async (at: string) => { options.contacts?.push(at) },
        snapshot: async () => ({ tasks: [] }),
        syncState: async () => ({
          cursor: null,
          lastSuccessfulContact: options.lastSuccessfulContact ?? null,
          outbox: [mutation.mutationId],
          readyPushes: [mutation.mutationId],
        }),
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      sync: sync as any,
    })

  it('publishes the offline row -- not retryable failure -- when a configured server could not be reached', async () => {
    const application = buildOfflineApplication(
      {
        pull: async () => { throw new SyncUnreachableError('the Keepling server could not be reached') },
        push: async () => null,
      },
      { lastSuccessfulContact: '2026-09-03T11:00:00.000Z' },
    )

    await expect(application.runSyncPass()).rejects.toThrow(/could not be reached/)

    const summary = application.presentationSnapshot().summary
    expect(summary.kind).toBe('offline')
    expect(summary.copy).toBe('Offline — showing tasks saved on this Mac')
    // The real prior contact, read back from the local store -- never fabricated.
    expect(summary.lastSuccessfulContact).toBe('2026-09-03T11:00:00.000Z')
  })

  it('reports a null last contact -- never a fabricated one -- when the server has never been reached', async () => {
    const application = buildOfflineApplication({
      pull: async () => { throw new SyncUnreachableError('connection refused') },
      push: async () => null,
    })

    await expect(application.runSyncPass()).rejects.toThrow(/connection refused/)

    const summary = application.presentationSnapshot().summary
    expect(summary.kind).toBe('offline')
    expect(summary.copy).toBe('Offline — showing tasks saved on this Mac')
    expect(summary.lastSuccessfulContact).toBeNull()
  })

  it('keeps retryable failure for a server that ANSWERED and the answer was a problem', async () => {
    const application = buildOfflineApplication({
      // A real HTTP answer that was a problem -- the transport reached the
      // server, so this is emphatically not "offline".
      pull: async () => { throw new Error('server_500') },
      push: async () => null,
    })

    await expect(application.runSyncPass()).rejects.toThrow(/server_500/)

    const summary = application.presentationSnapshot().summary
    expect(summary.kind).toBe('retryable_failure')
    expect(summary.copy).toBe('Couldn’t reach the server. Your changes stay on this Mac.')
  })

  it('records a real successful contact when the server answers, so the offline row has an honest source', async () => {
    const contacts: string[] = []
    const application = buildOfflineApplication(
      {
        pull: async () => ({ changes: [], cursor: 'cursor-after-pull' }),
        push: async () => ({ fingerprint: mutation.fingerprint, mutationId: mutation.mutationId }),
      },
      { contacts },
    )

    await application.runSyncPass()

    expect(contacts).toEqual(['2026-09-03T12:00:00.000Z'])
    expect(application.presentationSnapshot().summary.kind).toBe('healthy')
  })

  it('never claims a synchronized row when NO server is configured -- it settles offline with no contact', async () => {
    const reached: string[] = []
    const application = buildOfflineApplication({
      configured: () => false,
      pull: async () => { reached.push('pull'); return { changes: [], cursor: null } },
      push: async () => { reached.push('push'); return null },
    })

    await expect(application.runSyncPass()).resolves.toEqual({ pulled: 0, settled: 0 })

    const summary = application.presentationSnapshot().summary
    expect(summary.kind).toBe('offline')
    expect(summary.copy).toBe('Offline — showing tasks saved on this Mac')
    expect(summary.lastSuccessfulContact).toBeNull()
    // Nothing was attempted against a server that does not exist.
    expect(reached).toEqual([])
  })
})

/**
 * The transport is the only layer that knows whether bytes came back, so it
 * is the only layer allowed to decide "unreachable". These cases pin that
 * boundary directly against `KeeplingSyncAdapter#json`, with an injected
 * `fetch` standing in for the network condition.
 */
describe('transport reachability tag (O-30)', () => {
  const buildAdapter = (fetchStub: (input: string | URL, init?: RequestInit) => Promise<Response>) =>
    new KeeplingSyncAdapter({
      accessToken: () => 'access-token',
      baseUrl: 'http://127.0.0.1:9',
      fetch: fetchStub,
    })

  it('tags a request that never got an answer as unreachable', async () => {
    const adapter = buildAdapter(async () => {
      // What Node's fetch actually does for a refused connection.
      throw new TypeError('fetch failed')
    })

    const failure = await adapter.pull(null, 50).catch((error: unknown) => error)
    expect(isSyncUnreachable(failure)).toBe(true)
    expect(failure).toBeInstanceOf(Error)
    expect((failure as Error).message).toMatch(/could not be reached/)
  })

  it('does NOT tag a server that answered badly -- a 500 stays a rejected answer', async () => {
    const adapter = buildAdapter(async () =>
      new Response(JSON.stringify({ code: 'internal_error' }), { status: 500 }),
    )

    const failure = await adapter.pull(null, 50).catch((error: unknown) => error)
    // Positive read first: this really is the server's own problem code,
    // which proves the request completed rather than never happening.
    expect((failure as Error).message).toBe('internal_error')
    expect(isSyncUnreachable(failure)).toBe(false)
  })

  it('does NOT tag a malformed body -- the server answered, the answer was the problem', async () => {
    const adapter = buildAdapter(async () => new Response('not json at all', { status: 200 }))

    const failure = await adapter.pull(null, 50).catch((error: unknown) => error)
    expect(failure).toBeInstanceOf(Error)
    expect(isSyncUnreachable(failure)).toBe(false)
  })
})
