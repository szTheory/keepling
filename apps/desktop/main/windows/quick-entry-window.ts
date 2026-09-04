import { BrowserWindow, globalShortcut, ipcMain, type IpcMainEvent, type IpcMainInvokeEvent } from 'electron'

import type { DesktopApplication, QuickEntryDraft } from '../application/DesktopApplication.ts'

/**
 * Global-shortcut registration, injected so tests can prove collision and
 * rebind behavior deterministically without touching the real OS-level
 * accelerator table (D-09/D-10, MAC-02 probe predicate).
 */
type GlobalShortcutPort = {
  isRegistered(accelerator: string): boolean
  register(accelerator: string, callback: () => void): boolean
  unregister(accelerator: string): void
}

/**
 * Captures/restores the previously active (foreground) application, so a
 * successful local commit can return focus to it (D-11) without Keepling
 * ever needing to know what that application was beyond an opaque handle.
 * Injected so tests can prove focus-return across multiple prior apps
 * without depending on real macOS window-server state.
 */
type ForegroundAppPort = {
  captureActiveApp(): Promise<unknown> | unknown
  restoreActiveApp(handle: unknown): Promise<void> | void
}

const defaultGlobalShortcutPort: GlobalShortcutPort = {
  isRegistered: (accelerator) => globalShortcut.isRegistered(accelerator),
  register: (accelerator, callback) => globalShortcut.register(accelerator, callback),
  unregister: (accelerator) => globalShortcut.unregister(accelerator),
}

const DEFAULT_QUICK_ENTRY_SHORTCUT = 'Control+Alt+Space'

type ShortcutStatus = { accelerator: string; registered: boolean }

type QuickEntryWindowOptions = {
  desktopApplication: DesktopApplication
  /**
   * REQUIRED, deliberately. This was optional, and the shipped bootstrap
   * simply omitted it: every capture/restore call no-opped and Quick Entry
   * left Keepling frontmost instead of returning the user to the
   * application they came from (O-21). An optional port with exactly one
   * implementation -- in test code -- is how that defect stayed invisible,
   * so the type now refuses to compile a caller that forgets it.
   */
  foregroundApp: ForegroundAppPort
  globalShortcutPort?: GlobalShortcutPort
  preloadPath: string
  rendererUrl: string
}

/**
 * Owns the single resident Quick Entry utility window (D-09/D-11), its
 * durable draft, and its configurable global shortcut. Registers its own
 * narrow, sender-checked IPC channels directly (no dependency on
 * `apps/desktop/preload/index.ts` or `main/index.ts`, which Plan 03-10 owns
 * for this wave) via a dedicated `utility-preload.ts` bridge. See this
 * plan's SUMMARY "Known Gaps" for the one remaining integration step:
 * instantiating this controller from the real app bootstrap.
 */
class QuickEntryWindowController {
  readonly #desktopApplication: DesktopApplication
  readonly #foregroundApp: ForegroundAppPort
  readonly #preloadPath: string
  readonly #rendererUrl: string
  readonly #shortcutPort: GlobalShortcutPort
  #capturedForegroundHandle: unknown = null
  #lastShortcutStatus: ShortcutStatus = { accelerator: DEFAULT_QUICK_ENTRY_SHORTCUT, registered: false }
  #registeredAccelerator: string | null = null
  readonly #trustedSenders = new Set<Electron.WebContents>()
  #window: BrowserWindow | null = null

  constructor(options: QuickEntryWindowOptions) {
    this.#desktopApplication = options.desktopApplication
    this.#foregroundApp = options.foregroundApp
    this.#preloadPath = options.preloadPath
    this.#rendererUrl = options.rendererUrl
    this.#shortcutPort = options.globalShortcutPort ?? defaultGlobalShortcutPort
    this.#registerIpcHandlers()
  }

  #assertTrustedSender(sender: Electron.WebContents): void {
    const isOwnWindow = this.#window !== null && sender === this.#window.webContents
    if (!isOwnWindow && !this.#trustedSenders.has(sender)) {
      throw new Error('untrusted Quick Entry sender')
    }
  }

  /**
   * Registers another main-owned utility window (Settings) as trusted for
   * this same draft/shortcut IPC surface -- both Quick Entry and Settings
   * load the same `utility-preload.ts` bridge and share the shortcut
   * status/rebind operations, so the trust boundary is "a window this
   * process itself created", not "the one Quick Entry window".
   */
  trustWindow(window: BrowserWindow): void {
    // Capture the WebContents reference BEFORE registering the listener --
    // re-reading `window.webContents` from inside a `'closed'` handler
    // touches an already-destroyed native window during Electron's teardown
    // and, observed during Plan 03-11's real `app.exit()` E2E evidence
    // (`test/e2e/lifecycle.spec.ts`, Settings window + bounded quit), hangs
    // the WHOLE app indefinitely instead of exiting. Deleting from a
    // reference captured up front never re-touches the destroyed window.
    const senderContents = window.webContents
    this.#trustedSenders.add(senderContents)
    window.once('closed', () => this.#trustedSenders.delete(senderContents))
  }

  #registerIpcHandlers(): void {
    ipcMain.handle('keepling:quick-entry:capture', async (event: IpcMainInvokeEvent, command: { addToToday?: boolean; title: string }) => {
      this.#assertTrustedSender(event.sender)
      const acceptance = await this.#desktopApplication.capture({ title: command.title })
      if (command.addToToday) {
        const trimmed = command.title.trim()
        const taskId = acceptance.snapshot.tasks.find((task) => task.title === trimmed)?.id
        if (taskId !== undefined) await this.#desktopApplication.moveToday({ planned: true, taskId })
      }
      await this.#desktopApplication.clearDraft().catch(() => {})
      this.hide()
      return acceptance
    })
    ipcMain.handle('keepling:quick-entry:save-draft', async (event: IpcMainInvokeEvent, draft: QuickEntryDraft) => {
      this.#assertTrustedSender(event.sender)
      await this.#desktopApplication.saveDraft(draft)
    })
    ipcMain.handle('keepling:quick-entry:get-draft', async (event: IpcMainInvokeEvent) => {
      this.#assertTrustedSender(event.sender)
      return this.#desktopApplication.getDraft()
    })
    ipcMain.handle('keepling:quick-entry:clear-draft', async (event: IpcMainInvokeEvent) => {
      this.#assertTrustedSender(event.sender)
      await this.#desktopApplication.clearDraft()
    })
    ipcMain.handle('keepling:quick-entry:get-shortcut-status', async (event: IpcMainInvokeEvent) => {
      this.#assertTrustedSender(event.sender)
      return this.#lastShortcutStatus
    })
    ipcMain.handle('keepling:quick-entry:set-shortcut', async (event: IpcMainInvokeEvent, accelerator: string) => {
      this.#assertTrustedSender(event.sender)
      return this.rebindShortcut(accelerator)
    })
    ipcMain.on('keepling:quick-entry:hide', (event: IpcMainEvent) => {
      this.#assertTrustedSender(event.sender)
      this.hide()
    })
    ipcMain.on('keepling:quick-entry:discard', (event: IpcMainEvent) => {
      this.#assertTrustedSender(event.sender)
      void this.#desktopApplication.clearDraft()
    })
  }

  /** Registers the persisted (or default) shortcut. Call once at startup. */
  async registerShortcut(): Promise<ShortcutStatus> {
    const preferred = (await this.#desktopApplication.getShortcutPreference()) ?? DEFAULT_QUICK_ENTRY_SHORTCUT
    return this.rebindShortcut(preferred)
  }

  /**
   * Attempts to bind a new accelerator, unregistering the previous one
   * first. Never silently falls back to a different shortcut (D-10): on
   * collision it reports `registered: false` and the caller (Settings) is
   * expected to surface `Quick Entry shortcut isn't available.` with
   * `Change Shortcut…`.
   */
  async rebindShortcut(accelerator: string): Promise<ShortcutStatus> {
    if (this.#registeredAccelerator !== null) this.#shortcutPort.unregister(this.#registeredAccelerator)
    const registered = this.#shortcutPort.register(accelerator, () => void this.open())
    this.#registeredAccelerator = registered ? accelerator : null
    this.#lastShortcutStatus = { accelerator, registered }
    if (registered) await this.#desktopApplication.setShortcutPreference(accelerator).catch(() => {})
    this.#notifyShortcutStatus()
    return this.#lastShortcutStatus
  }

  #notifyShortcutStatus(): void {
    if (this.#window !== null && !this.#window.isDestroyed()) {
      this.#window.webContents.send('keepling:quick-entry:shortcut-status', this.#lastShortcutStatus)
    }
  }

  isOpen(): boolean {
    return this.#window !== null && !this.#window.isDestroyed() && this.#window.isVisible()
  }

  /**
   * O-31(a): the live window, so `main/index.ts` can publish the
   * synchronization presentation to it and validate its IPC sender against
   * the same exact-`WebContents`-id decision every other surface uses.
   * Mirrors `SettingsWindowController#getWindow`.
   */
  getWindow(): BrowserWindow | null {
    return this.#window !== null && !this.#window.isDestroyed() ? this.#window : null
  }

  /**
   * Opens (or refocuses) the single resident Quick Entry window. Repeated
   * invocation while already open focuses the existing window rather than
   * creating a second one (MAC-02 probe predicate).
   */
  async open(): Promise<void> {
    if (this.#window !== null && !this.#window.isDestroyed()) {
      if (this.#capturedForegroundHandle === null) {
        this.#capturedForegroundHandle = (await this.#foregroundApp.captureActiveApp()) ?? null
      }
      this.#window.show()
      this.#window.focus()
      this.#window.webContents.send('keepling:quick-entry:focus-title')
      return
    }

    this.#capturedForegroundHandle = (await this.#foregroundApp.captureActiveApp()) ?? null

    const window = new BrowserWindow({
      height: 228,
      maxHeight: 360,
      maxWidth: 640,
      minHeight: 228,
      minWidth: 420,
      resizable: true,
      show: false,
      skipTaskbar: true,
      title: 'Keepling Quick Entry',
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        preload: this.#preloadPath,
        sandbox: true,
      },
      width: 520,
    })
    this.#window = window
    window.setMenuBarVisibility(false)
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    window.webContents.on('will-navigate', (event) => event.preventDefault())
    // Escape/Command-W hide a nonempty Quick Entry; only Discard Draft
    // removes the draft (D-11). Never destroy on close -- the durable
    // draft lives in SQLite regardless, but the window itself stays
    // resident so reopening the same instance is instantaneous.
    window.on('close', (event) => {
      event.preventDefault()
      this.hide()
    })
    await window.loadURL(this.#rendererUrl)
    window.show()
    window.focus()
  }

  /** Hides (never destroys) the window and returns focus to the prior app. */
  hide(): void {
    if (this.#window === null || this.#window.isDestroyed()) return
    this.#window.hide()
    if (this.#capturedForegroundHandle !== null) {
      const handle = this.#capturedForegroundHandle
      this.#capturedForegroundHandle = null
      void this.#foregroundApp.restoreActiveApp(handle)
    }
  }

  /** Releases the shortcut and destroys the window. Call only at app quit. */
  dispose(): void {
    if (this.#registeredAccelerator !== null) this.#shortcutPort.unregister(this.#registeredAccelerator)
    this.#window?.destroy()
    this.#window = null
  }
}

export { DEFAULT_QUICK_ENTRY_SHORTCUT, QuickEntryWindowController }
export type { ForegroundAppPort, GlobalShortcutPort, ShortcutStatus }
