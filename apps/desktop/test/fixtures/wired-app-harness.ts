import { randomUUID } from 'node:crypto'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { app, BrowserWindow, ipcMain, Menu } from 'electron'

import { DesktopApplication, type LocalStorePort } from '../../main/application/DesktopApplication.ts'
import { buildApplicationMenu } from '../../main/menu.ts'
import { installHeadlessPresentation } from '../../main/windows/headless-presentation.ts'
import { createMainWindow } from '../../main/windows/main-window.ts'
import {
  QuickEntryWindowController,
  type ForegroundAppPort,
  type GlobalShortcutPort,
} from '../../main/windows/quick-entry-window.ts'
import { SettingsWindowController } from '../../main/windows/settings-window.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * Deterministic global-shortcut double (MAC-02 probe predicate): real OS
 * accelerator registration depends on macOS Accessibility permissions and
 * whatever else is running on the test machine, neither of which E2E should
 * depend on to prove collision/rebind behavior. `KEEPLING_TEST_OCCUPIED_SHORTCUT`
 * lets a test pre-occupy an accelerator to prove the collision path reports
 * `registered: false` rather than silently falling back.
 */
class FakeGlobalShortcutPort implements GlobalShortcutPort {
  readonly #occupied: Set<string>
  readonly #registered = new Map<string, () => void>()

  constructor(occupied: string[]) {
    this.#occupied = new Set(occupied)
  }

  isRegistered(accelerator: string): boolean {
    return this.#registered.has(accelerator)
  }

  register(accelerator: string, callback: () => void): boolean {
    if (this.#occupied.has(accelerator)) return false
    this.#registered.set(accelerator, callback)
    return true
  }

  unregister(accelerator: string): void {
    this.#registered.delete(accelerator)
  }

  /** Test-only: invokes the callback as if the OS delivered the shortcut. */
  trigger(accelerator: string): void {
    this.#registered.get(accelerator)?.()
  }
}

/**
 * Deterministic foreground-app double (D-11 focus return): there is no real
 * "previously active application" in a test harness, so this records
 * capture/restore calls for the E2E to assert against instead of depending
 * on real macOS window-server focus state.
 */
class RecordingForegroundAppPort implements ForegroundAppPort {
  readonly log: string[] = []
  #nextHandle = 0

  captureActiveApp(): unknown {
    const handle = `prior-app-${this.#nextHandle++}`
    this.log.push(`capture:${handle}`)
    return handle
  }

  restoreActiveApp(handle: unknown): void {
    this.log.push(`restore:${String(handle)}`)
  }
}

/**
 * E2E-only reference wiring for Plan 03-04's native menu, main window, and
 * Quick Entry/Settings utility windows.
 *
 * This file exists SOLELY so Playwright can prove `menu.ts`,
 * `windows/main-window.ts`, and `windows/quick-entry-window.ts` behave
 * correctly in a REAL Electron process, without touching
 * `apps/desktop/main/index.ts` (owned by Plan 03-10 for this wave -- see
 * this plan's scope fence). It intentionally re-registers the same
 * `keepling:*` IPC channels `main/index.ts` already defines for the main
 * window's existing `preload/index.ts` bridge, so the real
 * `Workspace`/`DesktopShell` renderer behaves identically here as in the
 * shipped app. It is NOT the shipped app's entry point (see
 * `package.json#main`) and MUST NOT be treated as evidence that these
 * modules are wired into production -- that remaining integration step is
 * explicitly out of scope for this plan (see its SUMMARY "Known Gaps").
 */
// This harness is launched directly as `electron dist-harness/harness.cjs`
// (not via package.json#main), so `app.getAppPath()` resolves to
// `dist-harness/`, not the `apps/desktop` package root. Resolve relative to
// this built file's own directory instead.
const desktopRoot = join(__dirname, '..')
const processResourcePath = (role: 'preload' | 'renderer' | 'worker', file: string) => join(desktopRoot, 'dist', role, file)

const selectedTestProfile = process.env.KEEPLING_TEST_USER_DATA_DIR
if (selectedTestProfile) app.setPath('userData', resolve(selectedTestProfile))

const bootstrap = async () => {
  await app.whenReady()

  // The same opt-in headless seam the shipped entry point installs. Without
  // it, `KEEPLING_TEST_HEADLESS=1` would silently NOT apply to the two specs
  // that launch this harness, and their windows would still take over the
  // screen while the run claimed to be headless.
  installHeadlessPresentation(BrowserWindow, app)

  const migrationPath = join(desktopRoot, 'migrations', '0001_initial.sql')
  const localStore: LocalStorePort = new NodeSqliteLocalStore({
    databasePath: join(app.getPath('userData'), 'namespace.sqlite3'),
    migrationPath,
  })

  const desktopApplication = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    identity: { randomId: randomUUID },
    localStore,
    sync: { acknowledge: async () => null },
  })

  const window = createMainWindow({ preloadPath: processResourcePath('preload', 'index.cjs') })

  const assertTrustedSender = (sender: Electron.WebContents) => {
    if (sender !== window.webContents || !sender.getURL().startsWith('file://')) {
      throw new Error('untrusted renderer sender')
    }
  }

  // Mirrors main/index.ts's existing channel registrations exactly (see
  // that file) so the real preload/index.ts bridge -- and therefore the
  // real DesktopShell/Workspace renderer -- behaves identically here.
  ipcMain.handle('keepling:capture', async (event, command: { title: string }) => {
    assertTrustedSender(event.sender)
    return desktopApplication.capture(command)
  })
  ipcMain.handle('keepling:snapshot', async (event) => {
    assertTrustedSender(event.sender)
    return desktopApplication.snapshot()
  })
  ipcMain.handle('keepling:presentation-snapshot', async (event) => {
    assertTrustedSender(event.sender)
    return desktopApplication.presentationSnapshot()
  })
  ipcMain.handle('keepling:edit-task', async (event, command) => {
    assertTrustedSender(event.sender)
    return desktopApplication.editTask(command)
  })
  ipcMain.handle('keepling:lifecycle-task', async (event, command) => {
    assertTrustedSender(event.sender)
    return desktopApplication.applyLifecycle(command)
  })
  ipcMain.handle('keepling:move-today', async (event, command) => {
    assertTrustedSender(event.sender)
    return desktopApplication.moveToday(command)
  })
  ipcMain.handle('keepling:undo-last-action', async (event) => {
    assertTrustedSender(event.sender)
    return desktopApplication.undoLastLocalAction()
  })
  ipcMain.handle('keepling:list-conflicts', async (event) => {
    assertTrustedSender(event.sender)
    return desktopApplication.listConflicts()
  })
  ipcMain.handle('keepling:resolve-conflict', async (event, input) => {
    assertTrustedSender(event.sender)
    return desktopApplication.resolveConflict(input)
  })
  desktopApplication.subscribePresentation((presentation) => {
    if (!window.isDestroyed()) window.webContents.send('keepling:presentation-changed', presentation)
  })

  const rendererBase = pathToFileURL(processResourcePath('renderer', 'index.html')).toString()
  const utilityPreloadPath = processResourcePath('preload', 'utility.cjs')

  const occupied = process.env.KEEPLING_TEST_OCCUPIED_SHORTCUT
    ? [process.env.KEEPLING_TEST_OCCUPIED_SHORTCUT]
    : []
  const shortcutPort = new FakeGlobalShortcutPort(occupied)
  const foregroundApp = new RecordingForegroundAppPort()

  const quickEntry = new QuickEntryWindowController({
    desktopApplication,
    foregroundApp,
    globalShortcutPort: shortcutPort,
    preloadPath: utilityPreloadPath,
    rendererUrl: `${rendererBase}?view=quick-entry`,
  })
  const settings = new SettingsWindowController({
    preloadPath: utilityPreloadPath,
    quickEntryController: quickEntry,
    rendererUrl: `${rendererBase}?view=settings`,
  })

  // Exposed BEFORE the (awaited) loadURL below: Playwright's
  // `electronApplication.evaluate()` can run as soon as the BrowserWindow
  // is constructed, which may race ahead of this async bootstrap function
  // if the harness object were assigned only at the very end.
  ;(globalThis as unknown as { __testHarness: unknown }).__testHarness = {
    desktopApplication,
    foregroundLog: foregroundApp.log,
    mainWindow: window,
    quickEntry,
    settings,
    shortcutPort,
  }

  const shortcutAccelerator = process.env.KEEPLING_TEST_QUICK_ENTRY_SHORTCUT
  if (shortcutAccelerator) await desktopApplication.setShortcutPreference(shortcutAccelerator)
  const shortcutStatus = await quickEntry.registerShortcut()

  const menu = buildApplicationMenu({
    getMainWindow: () => window,
    getMenuState: () => ({ hasSelection: false, selectedCompleted: false, selectedTrashed: false }),
    openQuickEntry: () => void quickEntry.open(),
    openSettings: () => void settings.open(),
    quickEntryAccelerator: shortcutStatus.accelerator,
  })
  Menu.setApplicationMenu(menu)

  await window.loadURL(rendererBase)
  window.show()

  app.on('before-quit', () => {
    quickEntry.dispose()
  })
}

void bootstrap()
