import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { Worker } from 'node:worker_threads'
import { app, ipcMain, Menu, net, protocol, screen, session } from 'electron'

import { SafeStorageCredentialAdapter } from './adapters/credentials.ts'
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
import { removeLocalFilesAt } from '../store-worker/local-store.ts'
import { createMainWindow } from './windows/main-window.ts'
import { QuickEntryWindowController } from './windows/quick-entry-window.ts'
import { SettingsWindowController } from './windows/settings-window.ts'
import {
  captureRequestSchema,
  editRequestSchema,
  lifecycleRequestSchema,
  moveTodayRequestSchema,
  removeLocalDataRequestSchema,
  resolveConflictRequestSchema,
  workspaceLayoutStateSchema,
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

/**
 * O-11 gap closure (D-06): the SAME best-effort atomic-replace file pattern
 * `lifecycle.ts#createFileWindowStatePort` uses for window bounds, applied
 * to renderer-semantic workspace layout. Kept self-contained here (rather
 * than extending `lifecycle.ts`, which is outside this plan's authorized
 * scope) since it is a single small read/write pair, not a stateful port.
 */
const loadWorkspaceLayout = (filePath: string): unknown => {
  try {
    if (!existsSync(filePath)) return null
    return JSON.parse(readFileSync(filePath, 'utf8'))
  } catch {
    return null
  }
}

const saveWorkspaceLayout = (filePath: string, state: unknown): void => {
  try {
    const tmpPath = `${filePath}.tmp`
    writeFileSync(tmpPath, JSON.stringify(state))
    renameSync(tmpPath, filePath)
  } catch {
    // Best-effort UI convenience persistence only -- never a durability
    // prerequisite for anything this app reports as saved or synced.
  }
}

const processResourcePath = (role: 'preload' | 'renderer' | 'worker', file: string) =>
  app.isPackaged
    ? join(process.resourcesPath, role, file)
    : join(app.getAppPath(), 'dist', role, file)

class WorkerLocalStore implements LocalStorePort {
  readonly #databasePath: string
  readonly #pending = new Map<number, { reject: (error: Error) => void; resolve: (value: unknown) => void }>()
  readonly #worker: Worker
  #nextId = 1

  constructor(databasePath: string, migrationPath: string) {
    this.#databasePath = databasePath
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

  // O-12 gap closure (Rule 1 fix): `removeLocalNamespaceData` requires
  // `removeLocalFiles`/`setSyncFence` on its `LocalDataStorePort`, and this
  // proxy class never forwarded either -- so calling
  // `desktopApplication.removeLocalData` against the REAL shipped worker
  // always failed closed with `local file removal is unavailable`,
  // discovered only once this plan made the surface actually reachable
  // (`test/e2e/gap-closure.spec.ts`).
  //
  // `removeLocalFiles` deliberately does NOT round-trip through the worker
  // (unlike every other proxy method here): `removeLocalNamespaceData`
  // calls `localStore.close()` BEFORE `removeLocalFiles()` (D-38 order),
  // and THIS class's `close()` terminates the worker thread entirely (the
  // correct behavior for real app shutdown, which shares the same `close`
  // contract) -- a `removeLocalFiles` request sent after that would
  // `postMessage` to an already-exited worker and hang forever (silently
  // dropped, per the worker's own comment). `removeLocalFilesAt` is the
  // SAME plain, worker-independent function the worker itself calls for
  // this operation, so calling it directly here after the worker has
  // already been terminated is exactly as safe.
  removeLocalFiles(): { remaining: string[]; removed: string[] } {
    return removeLocalFilesAt(this.#databasePath)
  }

  setSyncFence(reason: string | null): Promise<void> {
    return this.#request('setSyncFence', reason)
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
  // O-15 gap closure: this is the SAME `SafeStorageCredentialAdapter`
  // Plan 03-02 built and unit-tested (`test/e2e/real-stack-sync.spec.ts`) --
  // it was never constructed here before this plan, so the credential path
  // the shipped app actually ran was `credentials: undefined`
  // (`DesktopApplication`'s `#credentials?.clear()` calls silently no-op).
  // Wiring it here is the entire fix: no other file reads or writes a
  // credential value anywhere in `main/`, `preload/`, or `renderer/`
  // (verified by grep before this change; see 03-13-SUMMARY.md).
  const credentials = new SafeStorageCredentialAdapter({
    filePath: join(app.getPath('userData'), 'credential.enc'),
  })
  const desktopApplication = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    credentials,
    identity: { randomId: randomUUID },
    localStore,
    sync,
  })
  await desktopApplication.reconcile()

  // Test-only introspection seam for shipped-entry-point gap-closure proof
  // (`test/e2e/gap-closure.spec.ts`), following the SAME pattern already
  // used above by `KEEPLING_TEST_SYNC_MODE` / `KEEPLING_TEST_USER_DATA_DIR`:
  // gated behind an explicit env var no real user session would ever set,
  // never active by default. This is NOT the prohibited
  // `test/fixtures/wired-app-harness.ts` reference entry point -- it is a
  // narrow read-only handle into the REAL objects this REAL `bootstrap()`
  // already constructed, exposed only so a Playwright test driving the real
  // packaged `dist/main/index.cjs` can prove the credential adapter is
  // actually the one wired in, without adding any new production-reachable
  // IPC surface.
  if (process.env.KEEPLING_TEST_EXPOSE_INTERNALS === '1') {
    ;(globalThis as unknown as { __keeplingTestCredentials?: SafeStorageCredentialAdapter })
      .__keeplingTestCredentials = credentials
    ;(globalThis as unknown as { __keeplingTestDesktopApplication?: DesktopApplication })
      .__keeplingTestDesktopApplication = desktopApplication
  }

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
  const workspaceLayoutPath = join(app.getPath('userData'), 'workspace-layout.json')

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
  // O-12 gap closure: `DesktopApplication.removeLocalData` (Plan 03-05) is
  // now reachable end to end -- named preload contract, sender-validated
  // handler, same trust check as every other operation above. Its input
  // type is `{ confirmRemoveAnyway: boolean }` only: no sync/network port
  // is threaded through this handler, so server deletion stays structurally
  // unreachable from this surface, exactly as `removeLocalNamespaceData`
  // requires.
  ipcMain.handle('keepling:remove-local-data', async (event, rawCommand) => {
    assertTrustedSender(event)
    return desktopApplication.removeLocalData(parseTrustedRequest(removeLocalDataRequestSchema, rawCommand))
  })
  // O-11 gap closure (D-06): best-effort, main-owned, non-durable UI
  // convenience persistence for renderer-semantic workspace layout state
  // (destination, surviving selection, semantic scroll anchor, recoverable
  // draft). A read failure or a malformed/tampered file degrades to "no
  // restoration" (never a thrown error to the renderer); a write failure is
  // silently best-effort, mirroring `createFileWindowStatePort` exactly --
  // this is UI convenience state, never a durability boundary (D-03/D-21).
  ipcMain.handle('keepling:restore-workspace-layout', async (event) => {
    assertTrustedSender(event)
    const raw = loadWorkspaceLayout(workspaceLayoutPath)
    if (raw === null) return null
    const parsed = workspaceLayoutStateSchema.safeParse(raw)
    return parsed.success ? parsed.data : null
  })
  ipcMain.handle('keepling:persist-workspace-layout', async (event, rawState) => {
    assertTrustedSender(event)
    saveWorkspaceLayout(workspaceLayoutPath, parseTrustedRequest(workspaceLayoutStateSchema, rawState))
    return null
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
