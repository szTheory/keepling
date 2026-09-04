import { createHash } from 'node:crypto'
import { chmodSync, existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { Worker } from 'node:worker_threads'

import { expect, test } from '@playwright/test'

import { DesktopApplication, type LocalStorePort } from '../../main/application/DesktopApplication.ts'
import { removeLocalNamespaceData } from '../../main/recovery/remove-local-data.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * D-22/D-34/D-38 recovery-shell proof (T-KPL03-05-02/-04). Two layers:
 *
 * 1. `DesktopApplication`-level tests prove the closed contract every
 *    caller (worker, IPC handler, bootstrap) must see: a broken local
 *    store NEVER resolves `snapshot()` with a false empty workspace, and
 *    `reconcile()` -- the very first call `bootstrap()` makes -- NEVER
 *    throws out of a store failure (it would otherwise be an unhandled
 *    rejection that kills the whole main process before any window opens).
 * 2. `dist/worker/index.cjs`-level tests spawn the REAL worker thread built
 *    from current source (same `pnpm run build` every sibling e2e spec's
 *    own `beforeAll` runs), proving the actual worker protocol reports a
 *    closed failure code and transparently retries opening on the next
 *    request once an external condition (a permission fix) is repaired --
 *    never auto-resetting.
 */

const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))
const migrationPath = join(desktopRoot, 'migrations', '0001_initial.sql')
const workerPath = join(desktopRoot, 'dist', 'worker', 'index.cjs')

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build:worker'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop worker build failed before sync-recovery E2E')
  if (!existsSync(workerPath)) throw new Error('desktop build did not produce dist/worker/index.cjs')
})

const roots: string[] = []
const permissionFixups: Array<() => void> = []

test.afterEach(() => {
  for (const restore of permissionFixups.splice(0)) restore()
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixtureRoot = (name: string): string => {
  const root = mkdtempSync(join(tmpdir(), `keepling-sync-recovery-${name}-`))
  roots.push(root)
  return root
}

test('D-22: a broken local store never returns a false empty workspace, and surfaces store_unavailable', async () => {
  let shouldFail = true
  const localStore: LocalStorePort = {
    acceptCapture: async () => { throw new Error('unused') },
    acknowledge: async () => ({ tasks: [] }),
    close: async () => undefined,
    pendingMutations: async () => [],
    snapshot: async () => {
      if (shouldFail) throw new Error('unable to open database file')
      return { tasks: [{ id: 'task-real', syncStatus: 'saved_on_this_mac' as const, title: 'Real task' }] }
    },
  }
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore,
    sync: {},
  })

  await expect(application.snapshot()).rejects.toThrow(/unable to open database file/)
  expect(application.presentationSnapshot().summary.kind).toBe('store_unavailable')
  expect(application.presentationSnapshot().summary.actions.map((action) => action.code)).toEqual([
    'retry_opening', 'show_recovery_options',
  ])

  // "Retry Opening" is just the SAME operation again -- an external repair
  // (permission fixed, disk freed) must make it succeed without any reset.
  shouldFail = false
  await expect(application.snapshot()).resolves.toEqual({
    tasks: [{ id: 'task-real', syncStatus: 'saved_on_this_mac', title: 'Real task' }],
  })
})

test('D-22: reconcile() at startup degrades to store_unavailable instead of throwing out of bootstrap()', async () => {
  const events: string[] = []
  const localStore: LocalStorePort = {
    acceptCapture: async () => { throw new Error('unused') },
    acknowledge: async () => { events.push('acknowledge'); return { tasks: [] } },
    close: async () => undefined,
    pendingMutations: async () => { throw new Error('database disk image is malformed') },
    snapshot: async () => ({ tasks: [] }),
  }
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore,
    sync: { acknowledge: async () => { events.push('sync:acknowledge'); return null } },
  })

  // Must resolve, not reject -- `bootstrap()` calls this unguarded.
  await expect(application.reconcile()).resolves.toEqual({ settled: 0 })
  expect(application.presentationSnapshot().summary.kind).toBe('store_unavailable')
  expect(events).toEqual([])
})

type WorkerResponse = { code?: string; error?: string; id: number; ok: boolean; value?: unknown }

const requestFromWorker = (
  worker: Worker,
  id: number,
  operation: string,
  payload?: unknown,
): Promise<WorkerResponse> =>
  new Promise((resolve) => {
    const onMessage = (response: WorkerResponse) => {
      if (response.id !== id) return
      worker.off('message', onMessage)
      resolve(response)
    }
    worker.on('message', onMessage)
    worker.postMessage({ id, operation, payload })
  })

test('the real worker thread reports a closed failure code and transparently retries opening once repaired (D-22)', async () => {
  const root = fixtureRoot('worker-permission')
  const databasePath = join(root, 'namespace.sqlite3')

  // A prior successful run left a real committed task on disk.
  const seedCommandBytes = '{"mutation_id":"mutation-seed","task_id":"task-seed","title":"Before permission loss","type":"capture_task","version":1}'
  const seedWorker = new Worker(workerPath, { workerData: { databasePath, migrationPath } })
  const seedResponse = await requestFromWorker(seedWorker, 1, 'acceptCapture', {
    acceptedAt: '2026-09-02T12:00:00.000Z',
    commandBytes: seedCommandBytes,
    fingerprint: createHash('sha256').update(seedCommandBytes).digest('hex'),
    mutationId: 'mutation-seed',
    taskId: 'task-seed',
    title: 'Before permission loss',
  })
  expect(seedResponse.ok).toBe(true)
  await requestFromWorker(seedWorker, 2, 'close')
  await seedWorker.terminate()

  // Now break the file at the OS boundary and spawn a FRESH worker
  // against it, exactly like a real relaunch after permissions changed.
  chmodSync(databasePath, 0o000)
  permissionFixups.push(() => chmodSync(databasePath, 0o644))

  const worker = new Worker(workerPath, { workerData: { databasePath, migrationPath } })
  const failure = await requestFromWorker(worker, 1, 'snapshot')
  expect(failure.ok).toBe(false)
  expect(failure.code).toBe('permission_denied')

  // Same worker, same request, after external repair -- transparent reopen,
  // never an auto-reset (the worker was never told to recreate the store).
  chmodSync(databasePath, 0o644)
  const recovered = await requestFromWorker(worker, 2, 'snapshot')
  expect(recovered.ok).toBe(true)
  expect(recovered.value).toEqual({
    tasks: [expect.objectContaining({ id: 'task-seed', title: 'Before permission loss' })],
  })

  await requestFromWorker(worker, 3, 'close')
  await worker.terminate()
})

/**
 * D-24 "Remove data from this Mac…" proof (T-KPL03-05-03). This is
 * DesktopApplication/local-store integration, not IPC/renderer -- neither
 * `main/index.ts` nor `preload/index.ts` wires `removeLocalData` to a
 * channel in this plan's authorized scope (that composition is future
 * work), so these tests drive `DesktopApplication.removeLocalData` and the
 * underlying `removeLocalNamespaceData` state machine directly against a
 * REAL `NodeSqliteLocalStore` on a disposable profile -- exactly like
 * `real-stack-sync.spec.ts`'s existing pattern for boundary-level
 * `DesktopApplication` proof.
 */
const captureCommand = (mutationId: string, taskId: string, title: string) => {
  const commandBytes = JSON.stringify({ mutation_id: mutationId, task_id: taskId, title, type: 'capture_task', version: 1 })
  return {
    acceptedAt: '2026-09-02T12:00:00.000Z',
    commandBytes,
    fingerprint: createHash('sha256').update(commandBytes).digest('hex'),
    mutationId,
    taskId,
    title,
  }
}

const openRealLocalStorePort = (databasePath: string) => {
  const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
  const port: LocalStorePort = {
    acceptCapture: async (mutation) => store.acceptCapture(mutation),
    acknowledge: async (acknowledgement) => store.acknowledge(acknowledgement),
    close: async () => store.close(),
    listConflicts: async () => store.listConflicts(),
    pendingMutations: async () => store.pendingMutations(),
    removeLocalFiles: async () => store.removeLocalFiles(),
    setSyncFence: async (reason) => store.setSyncFence(reason),
    snapshot: async () => store.snapshot(),
  }
  return { port, store }
}

test('D-24: one-step removal is refused while local-only intent exists, and the namespace remains fully usable afterward (Keep Data)', async () => {
  const root = fixtureRoot('blocked')
  const databasePath = join(root, 'namespace.sqlite3')
  const { port } = openRealLocalStorePort(databasePath)
  let nextId = 0
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => `id-${nextId++}` },
    localStore: port,
    sync: {},
  })

  await application.capture({ title: 'Unsynced local task' })
  const blocked = await application.removeLocalData({ confirmRemoveAnyway: false })
  expect(blocked).toEqual({ conflictedCount: 0, kind: 'blocked_pending_intent', pendingCount: 1 })

  // Refused removal must leave the namespace exactly as usable as before --
  // this is what makes "Sync First"/"Keep Data" safe defaults.
  await expect(application.capture({ title: 'Still works after refused removal' })).resolves.toMatchObject({
    status: 'local_saved',
  })
  expect((await application.snapshot()).tasks).toHaveLength(2)
})

test('D-24/D-38: the second confirmation closes the store before deleting its whole file inventory and verifies absence', async () => {
  const root = fixtureRoot('removed')
  const databasePath = join(root, 'namespace.sqlite3')
  const { port, store } = openRealLocalStorePort(databasePath)
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore: port,
    sync: {},
  })
  await application.capture({ title: 'Namespace-only task' })

  // A sibling file OUTSIDE the store's own bounded inventory must never be
  // touched -- proves removal is an explicit list, never a directory glob.
  const siblingPath = join(root, 'unrelated-namespace.sqlite3')
  writeFileSync(siblingPath, 'not this namespace')

  const outcome = await application.removeLocalData({ confirmRemoveAnyway: true })
  expect(outcome).toEqual({ kind: 'removed' })
  for (const path of store.listLocalFilePaths()) expect(existsSync(path)).toBe(false)
  expect(existsSync(siblingPath)).toBe(true)
  expect(statSync(siblingPath).size).toBeGreaterThan(0)
})

test('D-24/MAC-05: fencing a namespace for removal blocks a concurrent Quick Entry/main write and yields no ready sync pushes', () => {
  const root = fixtureRoot('races')
  const databasePath = join(root, 'namespace.sqlite3')
  const store = new NodeSqliteLocalStore({ databasePath, migrationPath })
  store.acceptCapture(captureCommand('mutation-race-1', 'task-race-1', 'Pending before fence'))

  store.setSyncFence('local_removal')
  // remove-versus-sync: a concurrent sync pass must see nothing ready to push.
  expect(store.readyMutations()).toEqual([])
  // remove-versus-Quick-Entry: a concurrent capture must be refused, not silently accepted.
  expect(() => store.acceptCapture(captureCommand('mutation-race-2', 'task-race-2', 'Should be refused'))).toThrow(
    /local writes are fenced/,
  )

  // Un-fencing (Cancel/Keep Data) restores ordinary write access exactly.
  store.setSyncFence(null)
  store.acceptCapture(captureCommand('mutation-race-2', 'task-race-2', 'Now accepted'))
  expect(store.snapshot().tasks.map((task) => task.id)).toEqual(['task-race-1', 'task-race-2'])
  store.close()
})

test('D-24: never constructs or sends a server delete request -- removal has no reachable sync/network capability', async () => {
  const root = fixtureRoot('no-server-delete')
  const databasePath = join(root, 'namespace.sqlite3')
  const { port } = openRealLocalStorePort(databasePath)
  const networkCalls: string[] = []
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused' },
    localStore: port,
    sync: {
      acknowledge: async () => { networkCalls.push('acknowledge'); return null },
      pull: async () => { networkCalls.push('pull'); return { changes: [], cursor: null } },
      push: async () => { networkCalls.push('push'); return null },
    },
  })

  await expect(application.removeLocalData({ confirmRemoveAnyway: true })).resolves.toEqual({ kind: 'removed' })
  expect(networkCalls).toEqual([])
})

test('D-24: a partial external filesystem failure is reported as failed and remains inspectable and retryable, never silently claimed as removed', async () => {
  const attempts: Array<{ remaining: string[] }> = [
    { remaining: ['/still/here.sqlite3'] },
    { remaining: [] },
  ]
  const events: string[] = []
  const outcome1 = await removeLocalNamespaceData({
    confirmRemoveAnyway: true,
    localStore: {
      close: async () => { events.push('close') },
      pendingMutations: async () => [],
      removeLocalFiles: async () => attempts.shift() ?? { remaining: [] },
      setSyncFence: async (reason) => { events.push(`fence:${reason}`) },
    },
  })
  expect(outcome1).toEqual({ kind: 'failed', reason: 'still present after removal: /still/here.sqlite3' })

  // Retryable: the same call, once the external condition is repaired, succeeds.
  const outcome2 = await removeLocalNamespaceData({
    confirmRemoveAnyway: true,
    localStore: {
      close: async () => { events.push('close') },
      pendingMutations: async () => [],
      removeLocalFiles: async () => attempts.shift() ?? { remaining: [] },
      setSyncFence: async (reason) => { events.push(`fence:${reason}`) },
    },
  })
  expect(outcome2).toEqual({ kind: 'removed' })
})

test('D-24: a store close() failure is reported as failed rather than proceeding to delete files', async () => {
  const events: string[] = []
  const outcome = await removeLocalNamespaceData({
    confirmRemoveAnyway: true,
    localStore: {
      close: async () => { throw new Error('worker did not exit') },
      pendingMutations: async () => [],
      removeLocalFiles: async () => { events.push('removeLocalFiles'); return { remaining: [] } },
      setSyncFence: async (reason) => { events.push(`fence:${reason}`) },
    },
  })
  expect(outcome).toEqual({ kind: 'failed', reason: 'could not close the local store: worker did not exit' })
  expect(events).toEqual(['fence:local_removal'])
})
