import { BrowserWindow } from 'electron'

import type { QuickEntryWindowController } from './quick-entry-window.ts'

/**
 * Opens the Settings utility window (D-14 `Command-,`). Settings shares the
 * same narrow `utility-preload.ts` bridge as Quick Entry (both need only
 * the shortcut status/rebind operations), so it is registered as a trusted
 * sender on the SAME `QuickEntryWindowController` rather than duplicating a
 * second IPC surface for a single small form.
 */
type SettingsWindowOptions = {
  preloadPath: string
  quickEntryController: QuickEntryWindowController
  rendererUrl: string
}

class SettingsWindowController {
  readonly #preloadPath: string
  readonly #quickEntryController: QuickEntryWindowController
  readonly #rendererUrl: string
  #window: BrowserWindow | null = null

  constructor(options: SettingsWindowOptions) {
    this.#preloadPath = options.preloadPath
    this.#quickEntryController = options.quickEntryController
    this.#rendererUrl = options.rendererUrl
  }

  /**
   * The live Settings window, or `null` when it has never opened or was
   * closed. Exposed so `main/index.ts` can include this window's exact
   * `WebContents` id in the trusted-sender set for the account IPC channels
   * -- Settings is the surface that owns server selection and sign-out.
   */
  getWindow(): BrowserWindow | null {
    return this.#window !== null && !this.#window.isDestroyed() ? this.#window : null
  }

  async open(): Promise<void> {
    if (this.#window !== null && !this.#window.isDestroyed()) {
      this.#window.show()
      this.#window.focus()
      return
    }

    const window = new BrowserWindow({
      height: 320,
      show: false,
      title: 'Keepling — Settings',
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        preload: this.#preloadPath,
        sandbox: true,
      },
      width: 480,
    })
    this.#window = window
    window.once('closed', () => {
      if (this.#window === window) this.#window = null
    })
    this.#quickEntryController.trustWindow(window)
    window.setMenuBarVisibility(false)
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    window.webContents.on('will-navigate', (event) => event.preventDefault())
    await window.loadURL(this.#rendererUrl)
    window.show()
    window.focus()
  }
}

export { SettingsWindowController }
export type { SettingsWindowOptions }
