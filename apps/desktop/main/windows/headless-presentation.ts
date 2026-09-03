import type { App, BrowserWindow as BrowserWindowType } from 'electron'

/**
 * Opt-in headless presentation for the Electron E2E lane (`KEEPLING_TEST_HEADLESS=1`).
 *
 * Playwright drives the renderer over CDP, which never requires a visible
 * native window: every window in this app is already constructed
 * `show: false` and presented later by an explicit `.show()`. Suppressing
 * exactly that presentation step -- and nothing else -- lets a developer run
 * the E2E lane on their own Mac without it seizing the screen, while leaving
 * the whole main process, the real preload bridge, the real renderer, and the
 * real store running unchanged.
 *
 * This is deliberately NOT a weaker app. It is the same app with its windows
 * off-screen, which means any assertion that depends on REAL presentation --
 * focus, window ordering, the AX tree the window server publishes -- cannot
 * be trusted here. Those specs are tagged `@windowed` and are excluded when
 * headless rather than weakened to pass. Headless is never the default, and
 * never used in CI: CI has no screen to take over and benefits from the
 * windowed path being exercised.
 *
 * Follows the established `KEEPLING_TEST_*` seam convention
 * (`KEEPLING_TEST_SYNC_MODE`, `KEEPLING_TEST_USER_DATA_DIR`,
 * `KEEPLING_TEST_EXPOSE_INTERNALS`): explicit env var, no real user session
 * would ever set it, inert by default.
 */

const isHeadlessPresentation = (): boolean => process.env.KEEPLING_TEST_HEADLESS === '1'

type PresentationMethod = 'moveTop' | 'show' | 'showInactive'

const SUPPRESSED_METHODS: readonly PresentationMethod[] = ['moveTop', 'show', 'showInactive']

/**
 * Neutralises the presentation methods on `BrowserWindow.prototype` so every
 * window -- main, Quick Entry, Settings, and any future one -- is covered by
 * construction rather than by remembering to guard each call site. Also drops
 * the Dock icon so launching the app does not steal activation from whatever
 * the developer is actually doing.
 *
 * Returns `false` (and changes nothing) when the flag is absent, so the
 * production path is byte-for-byte the behaviour it has always had.
 */
const installHeadlessPresentation = (
  browserWindow: typeof BrowserWindowType,
  application: Pick<App, 'dock'>,
): boolean => {
  if (!isHeadlessPresentation()) return false

  const prototype = browserWindow.prototype as unknown as Record<PresentationMethod, () => void>
  for (const method of SUPPRESSED_METHODS) {
    prototype[method] = function suppressedPresentation(this: BrowserWindowType): void {
      // Intentionally empty: the window stays loaded, scriptable and
      // inspectable over CDP -- it is simply never presented.
    }
  }
  application.dock?.hide()
  return true
}

export { installHeadlessPresentation, isHeadlessPresentation }
