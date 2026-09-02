import { parentPort, workerData } from 'node:worker_threads'

import { NodeSqliteLocalStore, type LocalStoreOptions } from './local-store.ts'

type WorkerRequest = {
  id: number
  operation: 'acceptCapture' | 'acknowledge' | 'pendingMutations' | 'snapshot' | 'close'
  payload?: unknown
}

if (parentPort === null) throw new Error('Keepling store worker requires a parent port')
const store = new NodeSqliteLocalStore(workerData as LocalStoreOptions)

parentPort.on('message', (request: WorkerRequest) => {
  try {
    let value: unknown
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
      case 'close':
        store.close()
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
      error: error instanceof Error ? error.message : 'unknown local store failure',
      id: request.id,
      ok: false,
    })
  }
})
