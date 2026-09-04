import { describe, expect, it } from 'vitest'

import { DesktopApplication, type SyncAcknowledgement, type SyncMutation } from '../../main/application/DesktopApplication.ts'
import type { DesktopPresentation } from '../../main/application/presentation.ts'
import { SYNC_FAILURE_AUTHENTICATION_REQUIRED, SyncUnreachableError } from '../../main/application/sync-reachability.ts'

/**
 * O-38, half (b): a conflict the server raised must reach a PERSON.
 *
 * Half (a) -- the adapter no longer throwing on a 409/422 -- is proved in
 * `server-refusal.test.ts` and end to end in the real-stack lane. Widening
 * the adapter alone would have converted a loud failure into a silent one,
 * which is the defect class this phase keeps finding rather than a fix for
 * it. These cases pin the other half: that a settled conflict or rejection
 * becomes the authored row, with its recovery action, at the top of the
 * presentation stream.
 *
 * Before this, `{ kind: 'conflict' }` and `{ kind: 'rejected' }` had
 * authored copy, a unit-test fixture, and NO production construction site
 * anywhere -- the same shape as O-30.
 */

const bytes = JSON.stringify({
  expected_revision: 3,
  mutation_id: 'm-1',
  task_id: 't-1',
  type: 'complete_task',
  version: 1,
})

const ready: SyncMutation = {
  acceptedAt: '2026-09-04T12:00:00.000Z',
  commandBytes: bytes,
  dependencies: [],
  effect: { entityId: 't-1', snapshot: { id: 't-1', revision: 3, title: 'Book the ferry' } },
  fingerprint: 'fingerprint-one',
  mutationId: 'm-1',
  resourceKeys: ['task:t-1'],
}

const buildApplication = (
  push: (commandBytes: string) => Promise<SyncAcknowledgement | null>,
  readyMutations: SyncMutation[] = [ready],
) => {
  const published: DesktopPresentation[] = []
  const acknowledged: SyncAcknowledgement[] = []
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-04T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore: {
      // O-51: this double records transmission state instead of storing it.
      // The application refuses to push at all through a store that cannot,
      // so these are required rather than decorative.
      abandonTransmission: async () => undefined,
      acceptCapture: async () => { throw new Error('unused') },
      acknowledge: async () => ({ tasks: [] }),
      acknowledgeSync: async (acknowledgement) => { acknowledged.push(acknowledgement) },
      beginTransmission: async () => undefined,
      applyPull: async () => undefined,
      close: async () => undefined,
      pendingMutations: async () => [],
      readyMutations: async () => readyMutations,
      snapshot: async () => ({ tasks: [] }),
      syncState: async () => ({ cursor: null, outbox: [], readyPushes: [] }),
    },
    sync: {
      configured: () => true,
      pull: async () => ({ changes: [], cursor: null }),
      push,
    },
  })
  application.subscribePresentation((presentation) => published.push(presentation))
  return { acknowledged, application, published }
}

const settledRow = (published: DesktopPresentation[]) => published.at(-1)!.summary

describe('a real conflict reaching a person (O-38)', () => {
  it('publishes the authored conflict copy and its Review Conflict action', async () => {
    const { application, published } = buildApplication(async () => ({
      fingerprint: ready.fingerprint,
      mutationId: ready.mutationId,
      outcome: 'conflict',
      snapshot: { affected_fields: ['title'], id: 't-1', revision: 4, title: 'Changed on the phone' },
    }))
    await application.runSyncPass()

    expect(settledRow(published)).toMatchObject({
      copy: 'This task changed somewhere else. Choose what to keep. Other tasks can continue.',
      count: 1,
      kind: 'conflict',
    })
    expect(settledRow(published).actions).toEqual([{ code: 'review_conflict', label: 'Review Conflict' }])
  })

  it('hands the conflict acknowledgement to the local store so it can be reviewed later', async () => {
    const { acknowledged, application } = buildApplication(async () => ({
      fingerprint: ready.fingerprint,
      mutationId: ready.mutationId,
      outcome: 'conflict',
      snapshot: { id: 't-1', title: 'Changed on the phone' },
    }))
    await application.runSyncPass()
    expect(acknowledged).toHaveLength(1)
    expect(acknowledged[0]!.outcome).toBe('conflict')
  })

  it('publishes the authored rejection copy and its Review action', async () => {
    const { application, published } = buildApplication(async () => ({
      fingerprint: ready.fingerprint,
      mutationId: ready.mutationId,
      outcome: 'rejected',
      snapshot: { id: 't-1', rejection_code: 'no_fields_touched' },
    }))
    await application.runSyncPass()

    expect(settledRow(published)).toMatchObject({
      copy: 'The server didn’t accept this change. Your version is still on this Mac.',
      count: 1,
      kind: 'rejected',
    })
    expect(settledRow(published).actions).toEqual([{ code: 'review', label: 'Review' }])
  })

  it('shows the conflict rather than the rejection when a pass produced both', async () => {
    // A conflict is the only one of the two that needs a CHOICE, so it must
    // not be hidden behind a row that merely informs.
    const second: SyncMutation = { ...ready, fingerprint: 'fingerprint-two', mutationId: 'm-2' }
    const { application, published } = buildApplication(
      async (commandBytes) => {
        const mutationId = (JSON.parse(commandBytes) as { mutation_id: string }).mutation_id
        return mutationId === 'm-1'
          ? { fingerprint: ready.fingerprint, mutationId: 'm-1', outcome: 'rejected', snapshot: { id: 't-1' } }
          : { fingerprint: second.fingerprint, mutationId: 'm-2', outcome: 'conflict', snapshot: { id: 't-1' } }
      },
      [ready, { ...second, commandBytes: bytes.replace('"m-1"', '"m-2"') }],
    )
    await application.runSyncPass()
    expect(settledRow(published).kind).toBe('conflict')
  })

  it('counts a conflicted or rejected command as settled, never as still pending', async () => {
    // "Saved on this Mac. Sync when you're back online" would be a promise
    // of a sync that will never happen: the server has decided.
    const { application, published } = buildApplication(async () => ({
      fingerprint: ready.fingerprint,
      mutationId: ready.mutationId,
      outcome: 'rejected',
      snapshot: { id: 't-1' },
    }))
    const result = await application.runSyncPass()
    expect(settledRow(published).kind).not.toBe('local_saved')
    // ...and it is not counted as an acceptance either.
    expect(result.settled).toBe(0)
  })

  it('publishes the sign-in row when the server answered 401', async () => {
    const { application, published } = buildApplication(async () => {
      const error = new Error('device_authentication_required') as Error & { syncFailure?: string }
      error.syncFailure = SYNC_FAILURE_AUTHENTICATION_REQUIRED
      throw error
    })
    await expect(application.runSyncPass()).rejects.toThrow('device_authentication_required')

    expect(settledRow(published)).toMatchObject({
      copy: 'Sign in to continue syncing. Changes remain safe on this Mac.',
      kind: 'authentication_required',
    })
    expect(settledRow(published).actions).toEqual([{ code: 'sign_in', label: 'Sign In' }])
  })

  it('still lands an unreachable server on the offline row, never on a conflict', async () => {
    const { application, published } = buildApplication(async () => {
      throw new SyncUnreachableError('the Keepling server could not be reached')
    })
    await expect(application.runSyncPass()).rejects.toThrow()
    expect(settledRow(published).kind).toBe('offline')
  })

  it('still lands an unclassified server failure on the retryable row', async () => {
    const { application, published } = buildApplication(async () => {
      throw new Error('infrastructure_failure')
    })
    await expect(application.runSyncPass()).rejects.toThrow('infrastructure_failure')
    expect(settledRow(published).kind).toBe('retryable_failure')
  })
})
