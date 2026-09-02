import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { afterEach, describe, expect, it } from 'vitest'

import {
  DesktopApplication,
  type PullPage,
  type SyncMutation,
} from '../../main/application/DesktopApplication.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'
import vectors from '../../../../packages/contracts/vectors/sync.json'

const roots: string[] = []
const migrationPath = new URL('../../migrations/0001_initial.sql', import.meta.url)

const openStore = (databasePath: string) => new NodeSqliteLocalStore({ databasePath, migrationPath })

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

describe('Phase 2 synchronization vectors', () => {
  for (const vector of vectors.cases) {
    it(`matches ${vector.name}`, async () => {
      const root = mkdtempSync(join(tmpdir(), 'keepling-sync-vector-'))
      roots.push(root)
      const databasePath = join(root, 'namespace.sqlite')
      let store = openStore(databasePath)
      const observedReady: string[] = []

      for (const action of vector.actions) {
        switch (action.type) {
          case 'local_accept':
            store.acceptMutation(action.mutation as SyncMutation)
            break
          case 'pull':
            store.applyPull(action.page as PullPage)
            break
          case 'ready_pushes':
            observedReady.push(...store.readyMutations().map((mutation) => mutation.mutationId))
            break
          case 'acknowledge':
            store.acknowledgeSync(action.acknowledgement)
            break
          case 'fence':
            store.setSyncFence(action.reason)
            break
          case 'relaunch':
            store.close()
            store = openStore(databasePath)
            break
        }
      }

      expect(store.syncState()).toEqual({
        cursor: vector.expect.cursor,
        outbox: vector.expect.outbox,
        readyPushes: vector.expect.ready_pushes,
      })
      expect(observedReady).toEqual(vector.expect.ready_pushes)
      store.close()
    })
  }

  it('pulls before bounded pushes and reuses exact immutable command bytes', async () => {
    const events: string[] = []
    const commandBytes = '{"mutation_id":"mutation-exact","type":"edit_task","task_id":"task-exact"}'
    const mutation: SyncMutation = {
      acceptedAt: vectors.fixed_clock,
      commandBytes,
      dependencies: [],
      effect: { entityId: 'task-exact', snapshot: { id: 'task-exact', revision: 1 } },
      fingerprint: 'd14e3c537c334acf9214fe198011941c3e56a69737a3fbf8b3655c4bd95eb524',
      mutationId: 'mutation-exact',
      resourceKeys: ['task:task-exact'],
    }
    const application = new DesktopApplication({
      clock: { now: () => vectors.fixed_clock },
      identity: { randomId: () => 'unused' },
      localStore: {
        acceptCapture: async () => { throw new Error('unused') },
        acceptMutation: async () => { throw new Error('unused') },
        acknowledge: async () => ({ tasks: [] }),
        acknowledgeSync: async () => undefined,
        applyPull: async () => undefined,
        close: async () => undefined,
        pendingMutations: async () => [mutation],
        readyMutations: async () => [mutation],
        setSyncFence: async () => undefined,
        snapshot: async () => ({ tasks: [] }),
        syncState: async () => ({ cursor: null, outbox: ['mutation-exact'], readyPushes: ['mutation-exact'] }),
      },
      sync: {
        pull: async (_cursor, limit) => {
          events.push(`pull:${limit}`)
          return { changes: [], cursor: 'cursor-after-pull' }
        },
        push: async (bytes) => {
          events.push(`push:${bytes}`)
          return null
        },
      },
    })

    await application.runSyncPass()

    expect(events).toEqual(['pull:50', `push:${commandBytes}`])
  })
})
