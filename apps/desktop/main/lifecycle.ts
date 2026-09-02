import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import type { App, BrowserWindow, Screen } from 'electron'

import type { DesktopApplication } from './application/DesktopApplication.ts'
import { clampBoundsToWorkArea } from './windows/mainWindowState.ts'

/**
 * Single-instance residency, close-vs-quit separation, validated main-window
 * restoration, and bounded quit (D-20/D-21, MAC-02/MAC-03/MAC-05).
 *
 * `DesktopLifecycle` is the ONE owner of:
 *  - the resident main window's lifetime (create/destroy/recreate),
 *  - the "close destroys the disposable window, quit is the only thing that
 *    stops the resident app" distinction Electron does not give you for
 *    free, and
 *  - the D-06 subset this main-owned module can actually observe: window
 *    bounds and fullscreen state, read directly from the Electron
 *    `BrowserWindow`/`Screen` APIs. Deeper D-06 semantic state (destination,
 *    sidebar visibility, pane sizes, selected task, scroll anchor, editor
 *    draft) is RENDERER state with no existing main<->renderer channel for
 *    it: `apps/desktop/preload/index.ts` is the frozen, hardened surface
 *    from Plan 03-10, and this plan's authorized scope is `lifecycle.ts` /
 *    `windows/main-window.ts` / `main/index.ts` only -- no renderer files.
 *    Adding that channel is real, disclosed follow-on scope; see this
 *    plan's SUMMARY "Known Gaps".
 *
 * D-21 / this plan's prohibition: quit NEVER waits on server acknowledgement,
 * a wake, a timer, a socket, or background execution. `DesktopApplication`
 * has no network call in its `close()` path (it only terminates the local
 * SQLite worker), and the bounded race in `#quit` below is a defensive
 * safety bound on that purely-local call, not evidence it talks to a
 * server -- if the local worker somehow hangs, quit still exits on time
 * rather than becoming a commit protocol.
 */

type WindowBounds = { height: number; width: number; x: number; y: number }
type WindowSnapshot = { bounds: WindowBounds; fullscreen: boolean }

interface WindowStatePort {
  load(): WindowSnapshot | null
  save(snapshot: WindowSnapshot): void
}

const isFiniteNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value)

const isWindowBounds = (value: unknown): value is WindowBounds =>
  typeof value === 'object'
  && value !== null
  && isFiniteNumber((value as Record<string, unknown>).height)
  && isFiniteNumber((value as Record<string, unknown>).width)
  && isFiniteNumber((value as Record<string, unknown>).x)
  && isFiniteNumber((value as Record<string, unknown>).y)

/**
 * Best-effort, main-owned, main-process-local persistence for window bounds
 * and fullscreen state. NEVER a durability boundary (D-03/D-21 remain the
 * SQLite worker's contract): a failed read/write here degrades silently to
 * "use the default window geometry", it never blocks capture, quit, or any
 * task mutation.
 */
const createFileWindowStatePort = (filePath: string): WindowStatePort => ({
  load: () => {
    try {
      if (!existsSync(filePath)) return null
      const parsed: unknown = JSON.parse(readFileSync(filePath, 'utf8'))
      if (typeof parsed !== 'object' || parsed === null) return null
      const candidate = parsed as Record<string, unknown>
      if (!isWindowBounds(candidate.bounds) || typeof candidate.fullscreen !== 'boolean') return null
      return { bounds: candidate.bounds, fullscreen: candidate.fullscreen }
    } catch {
      return null
    }
  },
  save: (snapshot) => {
    try {
      const tmpPath = `${filePath}.tmp`
      writeFileSync(tmpPath, JSON.stringify(snapshot))
      renameSync(tmpPath, filePath)
    } catch {
      // Best-effort UI convenience persistence only -- never a durability
      // prerequisite for anything this app reports as saved or synced.
    }
  },
})

type WindowFactory = (options: { bounds?: WindowBounds; fullscreen?: boolean }) => BrowserWindow

type DesktopLifecycleOptions = {
  app: Pick<App, 'exit' | 'on'>
  createWindow: WindowFactory
  desktopApplication: Pick<DesktopApplication, 'close'>
  /** Runs during bounded quit, BEFORE the local store closes (e.g. dispose Quick Entry, unsubscribe presentation push). Never allowed to block quit past `quitBoundMs`. */
  onBeforeQuit?: () => void | Promise<void>
  /** Upper bound (ms) on how long quit waits for local cleanup before forcing exit. D-21: never a durability wait, purely a safety bound. */
  quitBoundMs?: number
  rendererUrl: string
  screen: Pick<Screen, 'getDisplayMatching' | 'getPrimaryDisplay'>
  windowState: WindowStatePort
}

const DEFAULT_QUIT_BOUND_MS = 5_000

class DesktopLifecycle {
  readonly #app: Pick<App, 'exit' | 'on'>
  readonly #createWindow: WindowFactory
  readonly #desktopApplication: Pick<DesktopApplication, 'close'>
  readonly #onBeforeQuit: (() => void | Promise<void>) | undefined
  readonly #quitBoundMs: number
  readonly #rendererUrl: string
  readonly #screen: Pick<Screen, 'getDisplayMatching' | 'getPrimaryDisplay'>
  readonly #windowState: WindowStatePort
  #stopping = false
  #window: BrowserWindow | null = null

  constructor(options: DesktopLifecycleOptions) {
    this.#app = options.app
    this.#createWindow = options.createWindow
    this.#desktopApplication = options.desktopApplication
    this.#onBeforeQuit = options.onBeforeQuit
    this.#quitBoundMs = options.quitBoundMs ?? DEFAULT_QUIT_BOUND_MS
    this.#rendererUrl = options.rendererUrl
    this.#screen = options.screen
    this.#windowState = options.windowState
  }

  /** The live main window, or `null` if none currently exists (closed, not yet created). */
  getMainWindow(): BrowserWindow | null {
    return this.#window !== null && !this.#window.isDestroyed() ? this.#window : null
  }

  /**
   * Returns the existing resident window (focused/shown), or recreates a
   * fresh disposable one from the last persisted, validated, on-screen-
   * clamped bounds/fullscreen snapshot (D-06 subset, D-20 "Dock activation
   * recreates the window"). Never restores a transient/off-screen bound --
   * `clampBoundsToWorkArea` runs against the CURRENT display configuration,
   * so a bound saved against a display that is no longer connected clamps
   * into whatever display now matches instead of landing off-screen.
   */
  async ensureWindow(): Promise<BrowserWindow> {
    const existing = this.getMainWindow()
    if (existing !== null) {
      existing.show()
      existing.focus()
      return existing
    }

    const snapshot = this.#windowState.load()
    const bounds = snapshot !== null ? this.#clampToVisibleDisplay(snapshot.bounds) : undefined
    const window = this.#createWindow({ bounds, fullscreen: snapshot?.fullscreen ?? false })
    this.#window = window

    // D-20: closing the main window DESTROYS the disposable renderer window
    // (never quits the resident app -- no `window-all-closed` handler calls
    // `app.quit()`); persist the last-known geometry first so the next
    // `ensureWindow()` (Dock activation or second launch) can restore it.
    window.on('close', () => {
      if (!window.isDestroyed()) this.#persist(window)
    })
    window.on('closed', () => {
      if (this.#window === window) this.#window = null
    })

    await window.loadURL(this.#rendererUrl)
    window.show()
    return window
  }

  #clampToVisibleDisplay(bounds: WindowBounds): WindowBounds {
    const display = this.#screen.getDisplayMatching(bounds) ?? this.#screen.getPrimaryDisplay()
    return clampBoundsToWorkArea(bounds, display.workArea)
  }

  #persist(window: BrowserWindow): void {
    this.#windowState.save({ bounds: window.getBounds(), fullscreen: window.isFullScreen() })
  }

  /**
   * Wires the app-level events that make this app a resident single-
   * instance Mac application (D-20): Dock activation and a second launch
   * both recreate the window when none exists; `before-quit` always runs
   * the bounded local shutdown instead of Electron's default immediate
   * teardown.
   */
  registerAppHandlers(): void {
    // D-20: without an explicit listener, Electron's own default behavior
    // quits the whole app once the last window closes (verified directly
    // against the real shipped app while building this plan's E2E evidence
    // -- NOT macOS-exempt by default in this Electron version). A no-op
    // listener is what keeps the app resident: the main-owned store, sync
    // owner, and global Quick Entry shortcut all stay alive with zero
    // windows open, exactly as D-20 requires.
    this.#app.on('window-all-closed', () => {})
    this.#app.on('activate', () => {
      void this.ensureWindow()
    })
    this.#app.on('second-instance', () => {
      void this.ensureWindow()
    })
    this.#app.on('before-quit', (event) => {
      if (this.#stopping) return
      event.preventDefault()
      void this.#quit()
    })
  }

  async #quit(): Promise<void> {
    this.#stopping = true
    const window = this.getMainWindow()
    if (window !== null) this.#persist(window)

    try {
      await this.#onBeforeQuit?.()
    } catch {
      // Cleanup failures never block a bounded quit.
    }

    // D-21: bounded, local-only. `close()` only terminates the SQLite
    // worker and never contacts the server; the timeout race is a safety
    // bound against a hung local worker, not a network wait.
    await Promise.race([
      this.#desktopApplication.close().catch(() => {}),
      new Promise<void>((resolve) => {
        setTimeout(resolve, this.#quitBoundMs)
      }),
    ])

    this.#app.exit()
  }
}

export { DEFAULT_QUIT_BOUND_MS, DesktopLifecycle, createFileWindowStatePort }
export type { WindowBounds, WindowSnapshot, WindowStatePort }
