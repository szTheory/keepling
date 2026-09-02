import { randomUUID } from 'node:crypto'
import { join, resolve } from 'node:path'
import { Worker } from 'node:worker_threads'
import { app, BrowserWindow, ipcMain } from 'electron'

import {
  DesktopApplication,
  type LocalAcceptance,
  type LocalStorePort,
  type PendingMutation,
  type SyncAcknowledgement,
  type SyncPort,
  type WorkspaceSnapshot,
} from './application/DesktopApplication.ts'

type WorkerResponse = { error?: string; id: number; ok: boolean; value?: unknown }

class WorkerLocalStore implements LocalStorePort {
  readonly #pending = new Map<number, { reject: (error: Error) => void; resolve: (value: unknown) => void }>()
  readonly #worker: Worker
  #nextId = 1

  constructor(databasePath: string, migrationPath: string) {
    const workerPath = join(app.isPackaged ? process.resourcesPath : app.getAppPath(), 'dist', 'worker', 'index.cjs')
    this.#worker = new Worker(workerPath, { workerData: { databasePath, migrationPath } })
    this.#worker.on('message', (response: WorkerResponse) => {
      const pending = this.#pending.get(response.id)
      if (pending === undefined) return
      this.#pending.delete(response.id)
      if (response.ok) pending.resolve(response.value)
      else pending.reject(new Error(response.error ?? 'local store worker failed'))
    })
    this.#worker.on('error', (error) => {
      for (const pending of this.#pending.values()) pending.reject(error)
      this.#pending.clear()
    })
  }

  acceptCapture(mutation: PendingMutation): Promise<LocalAcceptance> {
    return this.#request('acceptCapture', mutation)
  }

  acknowledge(acknowledgement: SyncAcknowledgement): Promise<WorkspaceSnapshot> {
    return this.#request('acknowledge', acknowledgement)
  }

  pendingMutations(): Promise<PendingMutation[]> {
    return this.#request('pendingMutations')
  }

  snapshot(): Promise<WorkspaceSnapshot> {
    return this.#request('snapshot')
  }

  async close(): Promise<void> {
    await this.#request('close')
    await this.#worker.terminate()
  }

  #request<Result>(operation: string, payload?: unknown): Promise<Result> {
    const id = this.#nextId++
    return new Promise((resolvePromise, reject) => {
      this.#pending.set(id, {
        reject,
        resolve: (value) => resolvePromise(value as Result),
      })
      this.#worker.postMessage({ id, operation, payload })
    })
  }
}

const selectedTestProfile = process.env.KEEPLING_TEST_USER_DATA_DIR
if (selectedTestProfile) {
  const selected = resolve(selectedTestProfile)
  const forbidden = process.env.KEEPLING_FORBIDDEN_USER_DATA_DIR
  if (forbidden && selected === resolve(forbidden)) throw new Error('refusing the normal Keepling profile')
  app.setPath('userData', selected)
}

const bootstrap = async () => {
  await app.whenReady()

  const migrationPath = join(
    app.isPackaged ? process.resourcesPath : app.getAppPath(),
    'migrations',
    '0001_initial.sql',
  )
  const localStore = new WorkerLocalStore(join(app.getPath('userData'), 'namespace.sqlite3'), migrationPath)
  const syncMode = process.env.KEEPLING_TEST_SYNC_MODE
  const sync: SyncPort = {
    acknowledge: async (mutation) => syncMode === 'acknowledge' ? {
      fingerprint: mutation.fingerprint,
      mutationId: mutation.mutationId,
      outcome: 'accepted',
      snapshot: { id: mutation.taskId, title: mutation.title },
    } : null,
  }
  const desktopApplication = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    identity: { randomId: randomUUID },
    localStore,
    sync,
  })
  await desktopApplication.reconcile()

  const window = new BrowserWindow({
    height: 720,
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: join(app.isPackaged ? process.resourcesPath : app.getAppPath(), 'dist', 'preload', 'index.cjs'),
      sandbox: true,
    },
    width: 960,
  })

  const assertTrustedSender = (sender: Electron.WebContents) => {
    if (sender !== window.webContents || !sender.getURL().startsWith('file://')) {
      throw new Error('untrusted renderer sender')
    }
  }

  ipcMain.handle('keepling:capture', async (event, command: { title: string }) => {
    assertTrustedSender(event.sender)
    return desktopApplication.capture(command)
  })
  ipcMain.handle('keepling:snapshot', async (event) => {
    assertTrustedSender(event.sender)
    return desktopApplication.snapshot()
  })

  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  window.webContents.on('will-navigate', (event) => event.preventDefault())
  await window.loadFile(join(app.isPackaged ? process.resourcesPath : app.getAppPath(), 'dist', 'renderer', 'index.html'))
  window.show()

  let quitting = false
  app.on('before-quit', (event) => {
    if (quitting) return
    event.preventDefault()
    void desktopApplication.close().finally(() => {
      quitting = true
      app.quit()
    })
  })
}

void bootstrap()
