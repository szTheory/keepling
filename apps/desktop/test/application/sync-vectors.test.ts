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

type WireMutation = {
  accepted_at: string
  command_bytes: string
  dependencies: string[]
  effect: { entity_id: string; snapshot: SyncMutation['effect']['snapshot'] }
  fingerprint: string
  mutation_id: string
  resource_keys: string[]
}

const vectorMutation = (mutation: WireMutation): SyncMutation => ({
  acceptedAt: mutation.accepted_at,
  commandBytes: mutation.command_bytes,
  dependencies: mutation.dependencies,
  effect: { entityId: mutation.effect.entity_id, snapshot: mutation.effect.snapshot },
  fingerprint: mutation.fingerprint,
  mutationId: mutation.mutation_id,
  resourceKeys: mutation.resource_keys,
})

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
            store.acceptMutation(vectorMutation(action.mutation))
            break
          case 'pull':
            store.applyPull({
              changes: action.page.changes.map((change) => ({
                entityId: change.entity_id,
                snapshot: change.snapshot,
              })),
              cursor: action.page.cursor,
            } as PullPage)
            break
          case 'ready_pushes':
            observedReady.push(...store.readyMutations().map((mutation) => mutation.mutationId))
            break
          case 'acknowledge':
            store.acknowledgeSync({
              fingerprint: action.acknowledgement.fingerprint,
              mutationId: action.acknowledgement.mutation_id,
              outcome: action.acknowledgement.outcome,
              snapshot: action.acknowledgement.snapshot,
            })
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

      expect(store.syncState()).toMatchObject({
        cursor: vector.expect.cursor,
        outbox: vector.expect.outbox,
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
      fingerprint: '488519b4c58a327e9187c0528c17f82dffa7d07c0f4d250cb288d627ce3f1e0b',
      mutationId: 'mutation-exact',
      resourceKeys: ['task:task-exact'],
    }
    const application = new DesktopApplication({
      clock: { now: () => vectors.fixed_clock },
      identity: { randomId: () => 'unused' },
      localStore: {
        abandonTransmission: async (mutationId) => { events.push(`abandon:${mutationId}`) },
        acceptCapture: async () => { throw new Error('unused') },
        acceptMutation: async () => { throw new Error('unused') },
        acknowledge: async () => ({ tasks: [] }),
        acknowledgeSync: async () => undefined,
        applyPull: async () => undefined,
        // O-51: recorded in the SAME ordered log as the pull and the push,
        // so "in flight is entered before the bytes are handed over" is a
        // property of the observed sequence rather than a claim about it.
        beginTransmission: async (mutationId) => { events.push(`begin:${mutationId}`) },
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

    // The push answered with an unmatched acknowledgement (`null`), so the
    // row is released as UNCERTAIN rather than left in flight -- and never
    // back to queued, which is what would make it droppable again.
    expect(events).toEqual([
      'pull:50',
      'begin:mutation-exact',
      `push:${commandBytes}`,
      'abandon:mutation-exact',
    ])
  })

  it('fences prior intent when any server-derived namespace dimension changes', () => {
    const root = mkdtempSync(join(tmpdir(), 'keepling-sync-namespace-'))
    roots.push(root)
    const store = openStore(join(root, 'namespace.sqlite'))
    const namespace = {
      accountSubject: 'account-one',
      generation: 'generation-one',
      issuer: 'keepling-server',
      origin: 'https://keepling.example',
      serverInstance: 'server-one',
    }
    expect(store.bindNamespace(namespace)).toBe(true)
    store.acceptMutation(vectorMutation(vectors.cases[0]!.actions[0]!.mutation))

    expect(store.bindNamespace({ ...namespace, accountSubject: 'account-two' })).toBe(false)
    expect(store.syncState()).toMatchObject({
      outbox: ['mutation-001'],
      readyPushes: [],
    })
    store.close()
  })
})
