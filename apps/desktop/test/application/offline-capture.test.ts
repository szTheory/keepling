import { describe, expect, it } from 'vitest'

import {
  DesktopApplication,
  type CaptureCommand,
  type LocalAcceptance,
  type LocalStorePort,
  type PendingMutation,
  type SyncAcknowledgement,
  type SyncPort,
  type WorkspaceSnapshot,
} from '../../main/application/DesktopApplication.ts'

const emptySnapshot = (): WorkspaceSnapshot => ({ tasks: [] })

class RecordingStore implements LocalStorePort {
  accepted: PendingMutation[] = []
  acknowledgements: SyncAcknowledgement[] = []

  async acceptCapture(mutation: PendingMutation): Promise<LocalAcceptance> {
    this.accepted.push(mutation)
    return {
      fingerprint: mutation.fingerprint,
      mutationId: mutation.mutationId,
      snapshot: {
        tasks: [{ id: mutation.taskId, syncStatus: 'saved_on_this_mac', title: mutation.title }],
      },
      status: 'local_saved',
    }
  }

  async acknowledge(acknowledgement: SyncAcknowledgement): Promise<WorkspaceSnapshot> {
    this.acknowledgements.push(acknowledgement)
    return emptySnapshot()
  }

  async pendingMutations(): Promise<PendingMutation[]> {
    return [...this.accepted]
  }

  async snapshot(): Promise<WorkspaceSnapshot> {
    return emptySnapshot()
  }

  async close(): Promise<void> {}
}

const capture: CaptureCommand = { title: 'Keep the exact intent' }

describe('DesktopApplication offline capture', () => {
  it('returns local_saved only after the durable store accepts immutable command bytes', async () => {
    const store = new RecordingStore()
    const application = new DesktopApplication({
      clock: { now: () => '2026-09-02T12:00:00.000Z' },
      identity: { randomId: (() => {
        const ids = ['mutation-offline', 'task-offline']
        return () => ids.shift() ?? 'unexpected-id'
      })() },
      localStore: store,
      sync: { acknowledge: async () => null },
    })

    const result = await application.capture(capture)

    expect(result.status).toBe('local_saved')
    expect(store.accepted).toHaveLength(1)
    expect(store.accepted[0]?.commandBytes).toBe(
      '{"mutation_id":"mutation-offline","task_id":"task-offline","title":"Keep the exact intent","type":"capture_task"}',
    )
    expect(store.accepted[0]?.fingerprint).toMatch(/^[a-f0-9]{64}$/)
    expect(result.snapshot.tasks[0]?.syncStatus).toBe('saved_on_this_mac')
  })

  it('settles only an acknowledgement matching immutable mutation identity and fingerprint', async () => {
    const store = new RecordingStore()
    const acknowledgements: SyncAcknowledgement[] = []
    const sync: SyncPort = {
      acknowledge: async (mutation) => acknowledgements.shift() ?? {
        fingerprint: `mismatch-${mutation.fingerprint}`,
        mutationId: mutation.mutationId,
        outcome: 'accepted',
        snapshot: { id: mutation.taskId, title: mutation.title },
      },
    }
    const application = new DesktopApplication({
      clock: { now: () => '2026-09-02T12:00:00.000Z' },
      identity: { randomId: (() => {
        const ids = ['mutation-exact', 'task-exact']
        return () => ids.shift() ?? 'unexpected-id'
      })() },
      localStore: store,
      sync,
    })
    await application.capture(capture)

    await expect(application.reconcile()).resolves.toEqual({ settled: 0 })
    expect(store.acknowledgements).toHaveLength(0)

    const pending = store.accepted[0]!
    acknowledgements.push({
      fingerprint: pending.fingerprint,
      mutationId: pending.mutationId,
      outcome: 'accepted',
      snapshot: { id: pending.taskId, title: pending.title },
    })
    await expect(application.reconcile()).resolves.toEqual({ settled: 1 })
    expect(store.acknowledgements).toHaveLength(1)
  })
})
