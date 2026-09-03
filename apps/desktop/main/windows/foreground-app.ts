import type { ForegroundAppPort } from './quick-entry-window.ts'

/**
 * The subset of Electron's `app` this adapter needs, injected as a port so
 * the focus-return DECISION is provable in plain vitest without a live
 * Electron process or a real macOS window server.
 */
type ApplicationActivationPort = {
  hide(): void
  isHidden(): boolean
  show(): void
}

/** The subset of a `BrowserWindow` needed to re-focus Keepling's own window. */
type FocusableWindow = {
  focus(): void
  isDestroyed(): boolean
  show(): void
}

type ForegroundAppOptions = {
  application: ApplicationActivationPort
  getMainWindow(): FocusableWindow | null
  isKeeplingFrontmost(): boolean
  /** Injected so the un-hide settle loop is provable without real timers. */
  settleIntervalMs?: number
  settleTimeoutMs?: number
  wait?: (milliseconds: number) => Promise<void>
}

const DEFAULT_SETTLE_INTERVAL_MS = 25
const DEFAULT_SETTLE_TIMEOUT_MS = 2_000

const realWait = (milliseconds: number) => new Promise<void>((resolve) => { setTimeout(resolve, milliseconds) })

/**
 * Opaque handle (see `ForegroundAppPort`): it deliberately carries only
 * whether Keepling itself owned the foreground when Quick Entry was
 * invoked. It never names the other application -- Keepling has no business
 * knowing which app the user came from, and identifying it would require a
 * TCC Automation prompt we refuse to ask a dogfooder for.
 */
type ForegroundAppHandle = { readonly keeplingWasFrontmost: boolean }

const KEEPLING_FOREGROUND_HANDLE = 'keepling:foreground-handle'

type TaggedHandle = ForegroundAppHandle & { readonly tag: typeof KEEPLING_FOREGROUND_HANDLE }

const isTaggedHandle = (handle: unknown): handle is TaggedHandle =>
  typeof handle === 'object' &&
  handle !== null &&
  (handle as { tag?: unknown }).tag === KEEPLING_FOREGROUND_HANDLE

/**
 * Production `ForegroundAppPort` (D-11 focus return, MAC-02).
 *
 * macOS hands activation back to the previously active application when an
 * application hides ITSELF, and it does so with no TCC permission, no native
 * module, and no AppleScript. Because the prior application is *reactivated*
 * rather than reopened, its caret, selection, and scroll position survive
 * untouched -- which is exactly what row A9 of the macOS integration lane
 * measures through the real accessibility tree.
 *
 * So `captureActiveApp()` never needs to identify the other application. It
 * only records the one thing Electron alone can answer: was Keepling itself
 * frontmost when Quick Entry opened?
 *
 *   * Keepling was NOT frontmost -> `hide()` the application on restore, and
 *     activation returns to whatever the user was in.
 *   * Keepling WAS frontmost -> hiding would make the app the user is
 *     actively working in vanish. Focus the main window instead.
 *
 * Capture also un-hides the application if a previous restore hid it, so the
 * second and every later Quick Entry invocation shows a real, visible window
 * instead of a window ordered into a hidden application.
 */
class ElectronForegroundApp implements ForegroundAppPort {
  readonly #application: ApplicationActivationPort
  readonly #getMainWindow: () => FocusableWindow | null
  readonly #isKeeplingFrontmost: () => boolean
  readonly #settleIntervalMs: number
  readonly #settleTimeoutMs: number
  readonly #wait: (milliseconds: number) => Promise<void>

  constructor(options: ForegroundAppOptions) {
    this.#application = options.application
    this.#getMainWindow = options.getMainWindow
    this.#isKeeplingFrontmost = options.isKeeplingFrontmost
    this.#settleIntervalMs = options.settleIntervalMs ?? DEFAULT_SETTLE_INTERVAL_MS
    this.#settleTimeoutMs = options.settleTimeoutMs ?? DEFAULT_SETTLE_TIMEOUT_MS
    this.#wait = options.wait ?? realWait
  }

  async captureActiveApp(): Promise<TaggedHandle> {
    // Read frontmost-ness BEFORE any un-hide, or the answer is always "yes".
    const keeplingWasFrontmost = this.#isKeeplingFrontmost()
    if (this.#application.isHidden()) {
      this.#application.show()
      // `NSApplication.unhide:` finishes on a LATER run-loop turn: it
      // re-orders and re-keys the previously visible windows (the main
      // window) after it returns. Measured in lane row A9 -- Quick Entry was
      // shown first, the un-hide then put the main window back in front, and
      // the user's keystrokes went into the MAIN window's capture field
      // instead. So wait for the un-hide to SETTLE (Keepling owns a focused
      // window again) before the caller shows Quick Entry, rather than
      // sleeping a fixed amount and hoping. Bounded: a machine that never
      // settles still proceeds instead of hanging the shortcut.
      const deadline = Date.now() + this.#settleTimeoutMs
      while (!this.#isKeeplingFrontmost() && Date.now() < deadline) {
        await this.#wait(this.#settleIntervalMs)
      }
    }
    return { keeplingWasFrontmost, tag: KEEPLING_FOREGROUND_HANDLE }
  }

  restoreActiveApp(handle: unknown): void {
    // A handle this adapter did not mint (a stale one from another port
    // implementation, or anything forged) restores nothing rather than
    // hiding the application on a guess.
    if (!isTaggedHandle(handle)) return
    if (handle.keeplingWasFrontmost) {
      const main = this.#getMainWindow()
      if (main === null || main.isDestroyed()) return
      main.show()
      main.focus()
      return
    }
    this.#application.hide()
  }
}

export { ElectronForegroundApp }
export type { ApplicationActivationPort, FocusableWindow, ForegroundAppHandle, ForegroundAppOptions }
