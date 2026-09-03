import { parentPort, workerData } from 'node:worker_threads'

import { classifyStoreFailure, NodeSqliteLocalStore, removeLocalFilesAt, type LocalStoreOptions } from './local-store.ts'

type WorkerRequest = {
  id: number
  operation:
    | 'acceptCapture'
    | 'acknowledge'
    | 'acknowledgeSync'
    | 'applyLifecycle'
    | 'applyMoveToday'
    | 'applyPull'
    | 'bindNamespace'
    | 'clearDraft'
    | 'close'
    | 'editTask'
    | 'getDraft'
    | 'getShortcutPreference'
    | 'listConflicts'
    | 'pendingMutations'
    | 'readyMutations'
    | 'recordSuccessfulContact'
    | 'removeLocalFiles'
    | 'resolveConflict'
    | 'saveDraft'
    | 'setShortcutPreference'
    | 'setSyncFence'
    | 'snapshot'
    | 'syncState'
    | 'undoLastLocalAction'
  payload?: unknown
}

if (parentPort === null) throw new Error('Keepling store worker requires a parent port')

/**
 * D-22 startup fault safety. Opening the store can fail for real reasons
 * (migration checksum drift, integrity/corruption, permission/read-only,
 * disk-full, a lock held by another process). A worker-thread top-level
 * throw here would crash the WHOLE worker thread before it can ever answer
 * a request, leaving `WorkerLocalStore#request` callers hanging forever
 * (postMessage to an already-exited worker is silently dropped). Instead,
 * construction failure is caught and the worker stays alive: every
 * subsequent request transparently retries opening the store first (so an
 * externally repaired permission/disk-full condition self-heals on the
 * NEXT retry -- e.g. a renderer's ordinary "Retry Opening" action, which is
 * just another `snapshot`/`presentation-snapshot` round-trip) and reports a
 * closed failure code on failure. The store is NEVER auto-reset/replaced.
 */
let store: NodeSqliteLocalStore | null = null
const openStore = (): NodeSqliteLocalStore => new NodeSqliteLocalStore(workerData as LocalStoreOptions)
try {
  store = openStore()
} catch {
  store = null
}

const databasePath = (workerData as LocalStoreOptions).databasePath

parentPort.on('message', (request: WorkerRequest) => {
  try {
    let value: unknown
    switch (request.operation) {
      // `close`/`removeLocalFiles` never need a healthy open store: closing
      // a never-opened store is a no-op, and removal must work even when
      // the store failed to open in the first place (corruption, checksum
      // drift, permission denial) -- see `deriveLocalFilePaths`'s comment.
      case 'close':
        store?.close()
        value = null
        break
      case 'removeLocalFiles':
        value = removeLocalFilesAt(databasePath)
        break
      default:
        break
    }
    if (request.operation === 'close' || request.operation === 'removeLocalFiles') {
      parentPort?.postMessage({ id: request.id, ok: true, value })
      return
    }
    // Every remaining operation needs a healthy open store. Transparently
    // retry opening first -- an externally repaired permission/disk-full
    // condition self-heals on the NEXT ordinary request (e.g. a renderer's
    // "Retry Opening" action, which is just another `snapshot` round-trip).
    if (store === null) store = openStore()
    switch (request.operation) {
      case 'acceptCapture':
        value = store.acceptCapture(request.payload as Parameters<typeof store.acceptCapture>[0])
        break
      case 'acknowledge':
        value = store.acknowledge(request.payload as Parameters<typeof store.acknowledge>[0])
        break
      case 'pendingMutations':
        value = store.pendingMutations()
        break
      case 'snapshot':
        value = store.snapshot()
        break
      case 'editTask':
        value = store.editTask(request.payload as Parameters<typeof store.editTask>[0])
        break
      case 'applyLifecycle':
        value = store.applyLifecycle(request.payload as Parameters<typeof store.applyLifecycle>[0])
        break
      case 'applyMoveToday':
        value = store.applyMoveToday(request.payload as Parameters<typeof store.applyMoveToday>[0])
        break
      case 'undoLastLocalAction':
        value = store.undoLastLocalAction()
        break
      case 'listConflicts':
        value = store.listConflicts()
        break
      case 'resolveConflict':
        value = store.resolveConflict(request.payload as Parameters<typeof store.resolveConflict>[0])
        break
      case 'saveDraft':
        store.saveDraft(request.payload as Parameters<typeof store.saveDraft>[0])
        value = null
        break
      case 'getDraft':
        value = store.getDraft()
        break
      case 'clearDraft':
        store.clearDraft()
        value = null
        break
      case 'getShortcutPreference':
        value = store.getShortcutPreference()
        break
      case 'setShortcutPreference':
        store.setShortcutPreference(request.payload as Parameters<typeof store.setShortcutPreference>[0])
        value = null
        break
      case 'setSyncFence':
        store.setSyncFence(request.payload as Parameters<typeof store.setSyncFence>[0])
        value = null
        break
      // O-16 (Rule 1 fix): the bounded pull-before-push synchronization
      // operations `NodeSqliteLocalStore` has always implemented were never
      // reachable through this worker protocol, so `DesktopApplication`'s
      // optional-capability checks silently degraded `runSyncPass()` to
      // reconcile-only and `activateNamespace()` threw -- discovered only
      // once Plan 03-14 wired the REAL sync adapter into the shipped
      // bootstrap and a push actually had to happen.
      case 'applyPull':
        store.applyPull(request.payload as Parameters<typeof store.applyPull>[0])
        value = null
        break
      case 'readyMutations':
        value = store.readyMutations()
        break
      case 'acknowledgeSync':
        store.acknowledgeSync(request.payload as Parameters<typeof store.acknowledgeSync>[0])
        value = null
        break
      case 'bindNamespace':
        value = store.bindNamespace(request.payload as Parameters<typeof store.bindNamespace>[0])
        break
      case 'syncState':
        value = store.syncState()
        break
      // O-30: the durable source for the offline row's
      // `lastSuccessfulContact`. Without this route the field could only
      // ever be fabricated or absent.
      case 'recordSuccessfulContact':
        store.recordSuccessfulContact(request.payload as string)
        value = null
        break
      default: {
        const unreachable: never = request.operation
        throw new Error(`unsupported store operation: ${String(unreachable)}`)
      }
    }
    parentPort?.postMessage({ id: request.id, ok: true, value })
  } catch (error) {
    parentPort?.postMessage({
      code: classifyStoreFailure(error),
      error: error instanceof Error ? error.message : 'unknown local store failure',
      id: request.id,
      ok: false,
    })
  }
})
