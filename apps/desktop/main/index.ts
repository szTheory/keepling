import { randomUUID } from 'node:crypto'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { Worker } from 'node:worker_threads'
import { app, ipcMain, Menu, net, protocol, screen, session } from 'electron'

import {
  DesktopApplication,
  type ConflictRecord,
  type EditTaskCommand,
  type LifecycleCommand,
  type LocalAcceptance,
  type LocalStorePort,
  type MoveTodayCommand,
  type PendingMutation,
  type SyncAcknowledgement,
  type SyncPort,
  type WorkspaceSnapshot,
} from './application/DesktopApplication.ts'
import { createFileWindowStatePort, DesktopLifecycle } from './lifecycle.ts'
import { buildApplicationMenu } from './menu.ts'
import {
  APP_PROTOCOL_ORIGIN,
  APP_PROTOCOL_SCHEME,
  CONTENT_SECURITY_POLICY,
  assertTrustedIpcSender,
  parseTrustedRequest,
  resolvePackagedAssetPath,
  shouldGrantPermission,
} from './protocol.ts'
import { createMainWindow } from './windows/main-window.ts'
import { QuickEntryWindowController } from './windows/quick-entry-window.ts'
import { SettingsWindowController } from './windows/settings-window.ts'
import {
  captureRequestSchema,
  editRequestSchema,
  lifecycleRequestSchema,
  moveTodayRequestSchema,
  resolveConflictRequestSchema,
} from '../preload/contracts.ts'

// MUST run before app.whenReady() -- Electron requires privileged-scheme
// registration at module evaluation time, before the app is ready.
protocol.registerSchemesAsPrivileged([
  {
    privileges: { bypassCSP: false, corsEnabled: false, secure: true, standard: true, supportFetchAPI: true },
    scheme: APP_PROTOCOL_SCHEME,
  },
])

type WorkerResponse = { error?: string; id: number; ok: boolean; value?: unknown }

const processResourcePath = (role: 'preload' | 'renderer' | 'worker', file: string) =>
  app.isPackaged
    ? join(process.resourcesPath, role, file)
    : join(app.getAppPath(), 'dist', role, file)

class WorkerLocalStore implements LocalStorePort {
  readonly #pending = new Map<number, { reject: (error: Error) => void; resolve: (value: unknown) => void }>()
  readonly #worker: Worker
  #nextId = 1

  constructor(databasePath: string, migrationPath: string) {
    const workerPath = processResourcePath('worker', 'index.cjs')
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

  editTask(command: EditTaskCommand): Promise<WorkspaceSnapshot> {
    return this.#request('editTask', command)
  }

  applyLifecycle(command: LifecycleCommand): Promise<WorkspaceSnapshot> {
    return this.#request('applyLifecycle', command)
  }

  applyMoveToday(command: MoveTodayCommand): Promise<WorkspaceSnapshot> {
    return this.#request('applyMoveToday', command)
  }

  undoLastLocalAction(): Promise<{ applied: boolean; snapshot: WorkspaceSnapshot }> {
    return this.#request('undoLastLocalAction')
  }

  listConflicts(): Promise<ConflictRecord[]> {
    return this.#request('listConflicts')
  }

  resolveConflict(input: { choice: 'current' | 'mine'; conflictId: string }): Promise<WorkspaceSnapshot> {
    return this.#request('resolveConflict', input)
  }

  saveDraft(draft: { addToToday: boolean; title: string }): Promise<void> {
    return this.#request('saveDraft', draft)
  }

  getDraft(): Promise<{ addToToday: boolean; title: string } | null> {
    return this.#request('getDraft')
  }

  clearDraft(): Promise<void> {
    return this.#request('clearDraft')
  }

  getShortcutPreference(): Promise<string | null> {
    return this.#request('getShortcutPreference')
  }

  setShortcutPreference(accelerator: string): Promise<void> {
    return this.#request('setShortcutPreference', accelerator)
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

const ownsSelectedProfile = app.requestSingleInstanceLock()

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
    acknowledge: async (mutation) => {
      if (syncMode === 'acknowledge') {
        return {
          fingerprint: mutation.fingerprint,
          mutationId: mutation.mutationId,
          outcome: 'accepted',
          snapshot: { id: mutation.taskId, title: mutation.title },
        }
      }
      if (syncMode === 'conflict') {
        return {
          fingerprint: mutation.fingerprint,
          mutationId: mutation.mutationId,
          outcome: 'conflict',
          snapshot: { id: mutation.taskId, title: `${mutation.title} (updated elsewhere)` },
        }
      }
      return null
    },
  }
  const desktopApplication = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    identity: { randomId: randomUUID },
    localStore,
    sync,
  })
  await desktopApplication.reconcile()

  // Registered once, on the default session, so EVERY renderer surface --
  // the main window, Quick Entry, and Settings (all constructed below) --
  // gets the same restrictive local-content, permission, and header policy
  // without per-window wiring.
  const rendererRoot = resolve(processResourcePath('renderer', '.'))
  protocol.handle(APP_PROTOCOL_SCHEME, (request) => {
    const candidate = resolvePackagedAssetPath(request.url, rendererRoot)
    if (candidate === null) return new Response('not found', { status: 404 })
    return net.fetch(pathToFileURL(candidate).toString())
  })
  session.defaultSession.setPermissionRequestHandler((_contents, permission, callback) => {
    callback(shouldGrantPermission(permission))
  })
  session.defaultSession.setPermissionCheckHandler(() => false)
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [CONTENT_SECURITY_POLICY],
      },
    })
  })

  const preloadPath = processResourcePath('preload', 'index.cjs')
  const utilityPreloadPath = processResourcePath('preload', 'utility.cjs')
  const rendererBase = `${APP_PROTOCOL_ORIGIN}/index.html`

  // The single owner of the resident main window's lifetime (D-20/D-21).
  // `createWindow` delegates to `windows/main-window.ts#createMainWindow`,
  // which ALREADY installs a deny-all `setWindowOpenHandler`/`will-navigate`
  // guard (O-10) -- the SAME unconditional policy Quick Entry/Settings use
  // below, so every window this process creates shares one reconciled
  // per-window navigation policy (see this plan's SUMMARY "Deviations" for
  // why the main window's previous allowlist-based guard was retired in
  // favor of this single policy).
  const lifecycle = new DesktopLifecycle({
    app,
    createWindow: (options) => createMainWindow({ ...options, preloadPath }),
    desktopApplication,
    onBeforeQuit: () => {
      unsubscribePresentation()
      quickEntry.dispose()
    },
    rendererUrl: rendererBase,
    screen,
    windowState: createFileWindowStatePort(join(app.getPath('userData'), 'window-state.json')),
  })

  // Every ipcMain handler consults this SAME sender/frame trust decision
  // (`main/protocol.ts#isTrustedIpcSender`) before touching
  // `DesktopApplication` -- a forged sender id, a subframe, or a frame
  // outside the packaged `app://renderer/` origin all fail closed. This
  // reads the CURRENT main window from `lifecycle` (not a captured
  // variable) because Dock activation / a second launch can recreate the
  // window after the first is closed.
  const assertTrustedSender = (event: Electron.IpcMainInvokeEvent) => {
    const window = lifecycle.getMainWindow()
    const senderFrame = event.senderFrame
    assertTrustedIpcSender({
      isMainFrame: senderFrame !== null && senderFrame === event.sender.mainFrame,
      senderFrameUrl: senderFrame?.url ?? null,
      senderId: event.sender.id,
      trustedSenderId: window?.webContents.id ?? -1,
    })
  }

  ipcMain.handle('keepling:capture', async (event, rawCommand) => {
    assertTrustedSender(event)
    return desktopApplication.capture(parseTrustedRequest(captureRequestSchema, rawCommand))
  })
  ipcMain.handle('keepling:snapshot', async (event) => {
    assertTrustedSender(event)
    return desktopApplication.snapshot()
  })
  ipcMain.handle('keepling:presentation-snapshot', async (event) => {
    assertTrustedSender(event)
    return desktopApplication.presentationSnapshot()
  })
  ipcMain.handle('keepling:edit-task', async (event, rawCommand) => {
    assertTrustedSender(event)
    return desktopApplication.editTask(parseTrustedRequest(editRequestSchema, rawCommand) as EditTaskCommand)
  })
  ipcMain.handle('keepling:lifecycle-task', async (event, rawCommand) => {
    assertTrustedSender(event)
    return desktopApplication.applyLifecycle(parseTrustedRequest(lifecycleRequestSchema, rawCommand) as LifecycleCommand)
  })
  ipcMain.handle('keepling:move-today', async (event, rawCommand) => {
    assertTrustedSender(event)
    return desktopApplication.moveToday(parseTrustedRequest(moveTodayRequestSchema, rawCommand) as MoveTodayCommand)
  })
  ipcMain.handle('keepling:undo-last-action', async (event) => {
    assertTrustedSender(event)
    return desktopApplication.undoLastLocalAction()
  })
  ipcMain.handle('keepling:list-conflicts', async (event) => {
    assertTrustedSender(event)
    return desktopApplication.listConflicts()
  })
  ipcMain.handle('keepling:resolve-conflict', async (event, rawInput) => {
    assertTrustedSender(event)
    return desktopApplication.resolveConflict(parseTrustedRequest(resolveConflictRequestSchema, rawInput))
  })
  const unsubscribePresentation = desktopApplication.subscribePresentation((presentation) => {
    const window = lifecycle.getMainWindow()
    if (window !== null) window.webContents.send('keepling:presentation-changed', presentation)
  })

  // O-9 native-shell wiring: Plan 03-04 built `menu.ts`, `windows/
  // quick-entry-window.ts`, and `windows/settings-window.ts` to production
  // quality and proved them against a test-only reference entry point
  // (`test/fixtures/wired-app-harness.ts`) -- they were never instantiated
  // here, so no user could reach Command-N, the global Quick Entry
  // shortcut, or the native menus in the shipped app. This is that
  // integration: the SAME production modules, composed against the real,
  // hardened `main/index.ts` bootstrap instead of the harness.
  const quickEntry = new QuickEntryWindowController({
    desktopApplication,
    preloadPath: utilityPreloadPath,
    rendererUrl: `${rendererBase}?view=quick-entry`,
  })
  const settings = new SettingsWindowController({
    preloadPath: utilityPreloadPath,
    quickEntryController: quickEntry,
    rendererUrl: `${rendererBase}?view=settings`,
  })

  lifecycle.registerAppHandlers()

  const shortcutStatus = await quickEntry.registerShortcut()
  const menu = buildApplicationMenu({
    getMainWindow: () => lifecycle.getMainWindow(),
    getMenuState: () => ({ hasSelection: false, selectedCompleted: false, selectedTrashed: false }),
    openQuickEntry: () => void quickEntry.open(),
    openSettings: () => void settings.open(),
    quickEntryAccelerator: shortcutStatus.accelerator,
  })
  Menu.setApplicationMenu(menu)

  await lifecycle.ensureWindow()
}

if (ownsSelectedProfile) void bootstrap()
else app.quit()
