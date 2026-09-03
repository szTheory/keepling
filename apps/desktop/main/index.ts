import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { Worker } from 'node:worker_threads'
import { app, ipcMain, Menu, net, protocol, screen, session, shell } from 'electron'

import { BrowserDelegatedAuthorization, KEEPLING_REDIRECT_URI } from './adapters/auth.ts'
import { SafeStorageCredentialAdapter } from './adapters/credentials.ts'
import { FileServerConfiguration } from './adapters/server-config.ts'
import { KeeplingSyncAdapter } from './adapters/sync.ts'
import {
  DesktopApplication,
  type ConflictRecord,
  type EditTaskCommand,
  type LifecycleCommand,
  type LocalAcceptance,
  type LocalStorePort,
  type MoveTodayCommand,
  type PendingMutation,
  type PullPage,
  type SyncAcknowledgement,
  type SyncMutation,
  type SyncNamespace,
  type SyncPort,
  type SyncState,
  type WorkspaceSnapshot,
} from './application/DesktopApplication.ts'
import { createFileWindowStatePort, DesktopLifecycle } from './lifecycle.ts'
import { buildApplicationMenu } from './menu.ts'
import {
  APP_PROTOCOL_ORIGIN,
  APP_PROTOCOL_SCHEME,
  CONTENT_SECURITY_POLICY,
  IpcSecurityError,
  assertTrustedIpcSender,
  isTrustedIpcSender,
  parseTrustedRequest,
  resolvePackagedAssetPath,
  shouldGrantPermission,
} from './protocol.ts'
import { removeLocalFilesAt } from '../store-worker/local-store.ts'
import { createMainWindow } from './windows/main-window.ts'
import { QuickEntryWindowController } from './windows/quick-entry-window.ts'
import { SettingsWindowController } from './windows/settings-window.ts'
import {
  accountConnectRequestSchema,
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

  // O-16 (Rule 1 fix): these five were implemented in
  // `store-worker/local-store.ts` but were never forwarded here OR routed in
  // `store-worker/index.ts`, so `DesktopApplication`'s optional-capability
  // checks quietly degraded `runSyncPass()` to reconcile-only and
  // `activateNamespace()` threw `namespace binding is unavailable`. Never
  // caught before because the shipped app had no real sync adapter to push
  // through -- the same "only ever ran in tests" defect class as O-16
  // itself.
  applyPull(page: PullPage): Promise<void> {
    return this.#request('applyPull', page)
  }

  readyMutations(): Promise<SyncMutation[]> {
    return this.#request('readyMutations')
  }

  acknowledgeSync(acknowledgement: SyncAcknowledgement): Promise<void> {
    return this.#request('acknowledgeSync', acknowledgement)
  }

  bindNamespace(namespace: SyncNamespace): Promise<boolean> {
    return this.#request('bindNamespace', namespace)
  }

  syncState(): Promise<SyncState> {
    return this.#request('syncState')
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

// Same-profile ownership lock (D-19). Unchanged: one profile is owned by
// exactly one process; isolated profiles stay independent.
const ownsSelectedProfile = app.requestSingleInstanceLock()

// Derived from the single redirect-URI constant the authorization adapter
// and the server's exact-match allowlist both use, so the scheme registered
// with macOS can never drift from the callback actually accepted.
const AUTH_PROTOCOL_SCHEME = new URL(KEEPLING_REDIRECT_URI).protocol.slice(0, -1)
const AUTH_CALLBACK_PREFIX = `${AUTH_PROTOCOL_SCHEME}://`

/**
 * O-16: the `keepling://auth/callback` return path from the SYSTEM BROWSER.
 *
 * Registered at module scope, before `app.whenReady()`, because macOS can
 * deliver `open-url` for the URL that LAUNCHED the app before `bootstrap()`
 * has finished constructing the authorization adapter. Anything that arrives
 * early is queued and flushed once the adapter exists, so a cold-start
 * callback is never dropped.
 *
 * Every URL routed here is UNTRUSTED INPUT -- private-use-scheme
 * registration is first-come on macOS -- so nothing beyond a cheap prefix
 * filter happens at this layer. All real validation (exact scheme/host/path,
 * exact state matching against one in-flight request, PKCE verifier
 * possession) lives in `BrowserDelegatedAuthorization#handleCallback`.
 */
const queuedAuthorizationCallbacks: string[] = []
let deliverAuthorizationCallback: ((callbackUrl: string) => void) | null = null

const routeAuthorizationCallback = (candidate: unknown): void => {
  if (typeof candidate !== 'string' || !candidate.startsWith(AUTH_CALLBACK_PREFIX)) return
  if (deliverAuthorizationCallback === null) queuedAuthorizationCallbacks.push(candidate)
  else deliverAuthorizationCallback(candidate)
}

app.on('open-url', (event, url) => {
  event.preventDefault()
  routeAuthorizationCallback(url)
})
app.on('second-instance', (_event, argv) => {
  for (const argument of argv) routeAuthorizationCallback(argument)
})
for (const argument of process.argv.slice(1)) routeAuthorizationCallback(argument)

const bootstrap = async () => {
  await app.whenReady()

  const migrationPath = join(
    app.isPackaged ? process.resourcesPath : app.getAppPath(),
    'migrations',
    '0001_initial.sql',
  )
  const localStore = new WorkerLocalStore(join(app.getPath('userData'), 'namespace.sqlite3'), migrationPath)

  // O-16 gap closure. Before this plan the ONLY `SyncPort` this shipped
  // entry point ever constructed was the inline fixture below, whose
  // `acknowledge` returned `null` unless `KEEPLING_TEST_SYNC_MODE` was set
  // -- so the shipped app never contacted a server at all, nothing ever
  // reached PostgreSQL, and "Synced" was structurally unreachable.
  // `KeeplingSyncAdapter` was imported by exactly one file, a test.
  //
  // The fixture survives ONLY behind its explicit environment gate (the
  // same seam `KEEPLING_TEST_USER_DATA_DIR` already uses); the default,
  // real-user path below constructs the real adapter against the configured
  // server.
  const syncMode = process.env.KEEPLING_TEST_SYNC_MODE
  const testStubSync: SyncPort = {
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

  const serverConfiguration = new FileServerConfiguration({
    filePath: join(app.getPath('userData'), 'server.json'),
  })
  let configuredServerUrl = await serverConfiguration.load()

  // A stable per-installation identity. It is an opaque random UUID with no
  // device, account, or user information in it, and it never appears in
  // diagnostic telemetry -- the server uses it only to name one grant family
  // so a single Mac can be revoked independently.
  const installationIdPath = join(app.getPath('userData'), 'installation.json')
  const installationId = (() => {
    const stored = loadWorkspaceLayout(installationIdPath) as { installationId?: unknown } | null
    if (stored !== null && typeof stored.installationId === 'string' && stored.installationId.length > 0) {
      return stored.installationId
    }
    const generated = randomUUID()
    saveWorkspaceLayout(installationIdPath, { installationId: generated })
    return generated
  })()

  let syncAdapter: KeeplingSyncAdapter | null = null
  let authorization: BrowserDelegatedAuthorization | null = null

  const configureServer = (baseUrl: string): void => {
    const adapter = new KeeplingSyncAdapter({
      accessToken: async () => (authorization === null ? null : authorization.accessToken()),
      baseUrl,
    })
    syncAdapter = adapter
    authorization = new BrowserDelegatedAuthorization({
      clock: { now: () => Date.now() },
      credentials,
      exchange: adapter,
      installationId,
      label: 'Keepling for Mac',
      openExternal: (url) => shell.openExternal(url),
      serverBaseUrl: baseUrl,
    })
  }

  // A stable `SyncPort` that delegates to whichever adapter is currently
  // configured, so changing servers never requires rebuilding
  // `DesktopApplication`. With no server configured every operation is a
  // no-op -- the app stays completely usable offline, and D-03 correctly
  // refuses to claim "Synced".
  const realSync: SyncPort = {
    // Exact acknowledgement (D-03): reconciliation asks the server for the
    // receipt of THIS mutation identity and compares the fingerprint;
    // `DesktopApplication.reconcile` discards anything that does not match
    // both.
    acknowledge: async (mutation) => {
      if (syncAdapter === null) return null
      try {
        return await syncAdapter.lookup(mutation.mutationId, mutation.fingerprint)
      } catch {
        return null
      }
    },
    pull: async (cursor, limit) => (syncAdapter === null ? { changes: [], cursor } : syncAdapter.pull(cursor, limit)),
    // The EXACT serialized command bytes are retried, never re-serialized.
    push: async (commandBytes) => (syncAdapter === null ? null : syncAdapter.push(commandBytes)),
  }
  const sync: SyncPort = syncMode === undefined ? realSync : testStubSync
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
  // Registering the private-use scheme is what makes the browser's
  // `keepling://auth/callback` return reach THIS app at all.
  app.setAsDefaultProtocolClient(AUTH_PROTOCOL_SCHEME)
  if (configuredServerUrl !== null) configureServer(configuredServerUrl)

  const desktopApplication = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    credentials,
    identity: { randomId: randomUUID },
    localStore,
    sync,
  })
  await desktopApplication.reconcile()

  /**
   * The single place an authorization callback is applied. On success the
   * server-derived namespace binds the local store (a mismatch fences it
   * rather than mixing two accounts' data), and only then does a real
   * synchronization pass run.
   */
  const applyAuthorizationCallback = async (callbackUrl: string): Promise<void> => {
    if (authorization === null) return
    const outcome = await authorization.handleCallback(callbackUrl)
    if (outcome.kind !== 'authorized') {
      // A rejected/failed callback never mutates credentials and never
      // claims progress. Only a genuine authentication failure (not an
      // unsolicited callback from another app) surfaces the closed
      // `authentication_required` recovery presentation.
      if (outcome.kind === 'failed') desktopApplication.publishPresentation({ kind: 'authentication_required' })
      return
    }
    const bound = await desktopApplication.activateNamespace(outcome.namespace).catch(() => false)
    if (!bound) return
    await localStore.setSyncFence(null)
    await desktopApplication.runSyncPass().catch(() => ({ pulled: 0, settled: 0 }))
  }

  deliverAuthorizationCallback = (callbackUrl) => void applyAuthorizationCallback(callbackUrl)
  for (const queued of queuedAuthorizationCallbacks.splice(0)) deliverAuthorizationCallback(queued)

  type AccountStatus = {
    disclosure: { copy: string; kind: 'unsigned_dogfood' } | null
    namespace: SyncNamespace | null
    serverUrl: string | null
    state: 'authorizing' | 'connected' | 'not_configured' | 'signed_out'
  }

  const readAccountStatus = async (): Promise<AccountStatus> => {
    const stored = authorization === null ? null : await authorization.loadCredentials()
    const state: AccountStatus['state'] = configuredServerUrl === null
      ? 'not_configured'
      : stored !== null
        ? 'connected'
        : authorization?.hasAuthorizationInFlight() === true
          ? 'authorizing'
          : 'signed_out'
    return {
      disclosure: credentials.settingsDisclosure(),
      namespace: stored?.namespace ?? null,
      serverUrl: configuredServerUrl,
      state,
    }
  }

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

  /**
   * O-16 account surface trust. Identical policy to `assertTrustedSender`
   * (exact `WebContents` id, main frame only, frame URL inside the packaged
   * `app://renderer/` origin) evaluated against BOTH main-owned windows that
   * legitimately reach this surface: the main window (which resolves the
   * `sign_in` recovery action) and Settings (which owns server selection and
   * sign-out). A forged sender id, a subframe, or a frame outside the
   * packaged origin still fails closed.
   */
  const assertTrustedAccountSender = (event: Electron.IpcMainInvokeEvent) => {
    const senderFrame = event.senderFrame
    const shared = {
      isMainFrame: senderFrame !== null && senderFrame === event.sender.mainFrame,
      senderFrameUrl: senderFrame?.url ?? null,
      senderId: event.sender.id,
    }
    const trustedIds = [
      lifecycle.getMainWindow()?.webContents.id ?? -1,
      settings.getWindow()?.webContents.id ?? -1,
    ]
    if (!trustedIds.some((trustedSenderId) => isTrustedIpcSender({ ...shared, trustedSenderId }))) {
      throw new IpcSecurityError('untrusted_sender')
    }
  }

  ipcMain.handle('keepling:account:status', async (event) => {
    assertTrustedAccountSender(event)
    return readAccountStatus()
  })
  // Server selection plus browser-delegated authorization. `serverUrl` is
  // the ONLY input; a disallowed origin is rejected before anything is
  // written, so a bad address can never replace a working one.
  ipcMain.handle('keepling:account:connect', async (event, rawRequest) => {
    assertTrustedAccountSender(event)
    const request = parseTrustedRequest(accountConnectRequestSchema, rawRequest)
    let selected: string
    try {
      selected = await serverConfiguration.save(request.serverUrl)
    } catch {
      return { kind: 'rejected', reason: 'invalid_server_address' }
    }
    configuredServerUrl = selected
    configureServer(selected)
    if (authorization === null) return { kind: 'rejected', reason: 'authorization_unavailable' }
    await authorization.begin()
    return { kind: 'browser_opened', status: await readAccountStatus() }
  })
  // Resolves the `sign_in` recovery action that already exists in the
  // presentation vocabulary. Takes no argument and returns only status: the
  // credential is acquired in the system browser, never in a renderer.
  ipcMain.handle('keepling:account:begin-sign-in', async (event) => {
    assertTrustedAccountSender(event)
    if (authorization !== null) await authorization.begin()
    return readAccountStatus()
  })
  // Sign-out order is load-bearing (D-25) and unchanged: local intent is
  // fenced and the credential cleared BEFORE any best-effort remote
  // revocation, so losing the network can never leave this Mac believing it
  // is still signed in.
  ipcMain.handle('keepling:account:disconnect', async (event) => {
    assertTrustedAccountSender(event)
    // Rule 1 fix, found by the real-stack sign-out proof: the fence order
    // means the credential is ALREADY cleared by the time the revocation
    // callback runs, so an adapter reading the token from storage always
    // failed `authentication_required` and the best-effort revocation
    // silently never happened. Capturing the bearer token BEFORE sign-out
    // and revoking with THAT preserves the fence order exactly (local
    // intent fenced and credential cleared first) while letting the
    // revocation actually authenticate.
    const revocationToken = authorization === null ? null : await authorization.accessToken()
    const revocationAdapter = configuredServerUrl === null || revocationToken === null
      ? null
      : new KeeplingSyncAdapter({ accessToken: () => revocationToken, baseUrl: configuredServerUrl })
    await desktopApplication.signOut(async () => {
      if (revocationAdapter !== null) await revocationAdapter.revoke(installationId)
    })
    return readAccountStatus()
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
