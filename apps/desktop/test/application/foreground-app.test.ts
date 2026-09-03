import { describe, expect, it } from 'vitest'

import { ElectronForegroundApp, type FocusableWindow } from '../../main/windows/foreground-app.ts'

/**
 * `ElectronForegroundApp` decides ONE thing: whether returning focus means
 * hiding Keepling (the user came from another application) or re-focusing
 * Keepling's own window (the user was already in Keepling). Row A9 of the
 * macOS integration lane measures the first branch against a real prior
 * application through the real accessibility tree; it cannot measure the
 * second, because there is no prior application to come back from. So the
 * "never hide when Keepling was already frontmost" guarantee is proven here,
 * deterministically, instead of being assumed.
 */

class FakeApplication {
  hideCalls = 0
  showCalls = 0
  #hidden: boolean

  constructor(hidden = false) {
    this.#hidden = hidden
  }

  hide(): void {
    this.hideCalls += 1
    this.#hidden = true
  }

  isHidden(): boolean {
    return this.#hidden
  }

  show(): void {
    this.showCalls += 1
    this.#hidden = false
  }
}

class FakeWindow implements FocusableWindow {
  focusCalls = 0
  showCalls = 0
  #destroyed: boolean

  constructor(destroyed = false) {
    this.#destroyed = destroyed
  }

  focus(): void {
    this.focusCalls += 1
  }

  isDestroyed(): boolean {
    return this.#destroyed
  }

  show(): void {
    this.showCalls += 1
  }
}

const build = (options: {
  frontmost: boolean | (() => boolean)
  hidden?: boolean
  mainWindow?: FakeWindow | null
  wait?: (milliseconds: number) => Promise<void>
}) => {
  const application = new FakeApplication(options.hidden ?? false)
  const mainWindow = options.mainWindow === undefined ? new FakeWindow() : options.mainWindow
  const port = new ElectronForegroundApp({
    application,
    getMainWindow: () => mainWindow,
    isKeeplingFrontmost: typeof options.frontmost === 'function' ? options.frontmost : () => options.frontmost as boolean,
    settleIntervalMs: 0,
    settleTimeoutMs: 200,
    wait: options.wait ?? (async () => {}),
  })
  return { application, mainWindow, port }
}

describe('ElectronForegroundApp', () => {
  it('hides the application on restore when Quick Entry was invoked from another application', async () => {
    const { application, mainWindow, port } = build({ frontmost: false })

    port.restoreActiveApp(await port.captureActiveApp())

    expect(application.hideCalls).toBe(1)
    expect(mainWindow?.showCalls).toBe(0)
    expect(mainWindow?.focusCalls).toBe(0)
  })

  it('never hides the application when Quick Entry was invoked from Keepling itself', async () => {
    const { application, mainWindow, port } = build({ frontmost: true })

    port.restoreActiveApp(await port.captureActiveApp())

    expect(application.hideCalls).toBe(0)
    expect(mainWindow?.showCalls).toBe(1)
    expect(mainWindow?.focusCalls).toBe(1)
  })

  it('reads frontmost-ness before un-hiding, so a hidden application is un-hidden for the next capture', async () => {
    const { application, port } = build({ frontmost: false, hidden: true })

    const handle = await port.captureActiveApp()

    expect(application.showCalls).toBe(1)
    expect(application.isHidden()).toBe(false)
    expect(handle.keeplingWasFrontmost).toBe(false)
  })

  it('leaves an already-visible application alone at capture time', async () => {
    const { application, port } = build({ frontmost: true })

    await port.captureActiveApp()

    expect(application.showCalls).toBe(0)
  })

  it('restores nothing rather than hiding on a guess when the handle is not one it minted', () => {
    const { application, mainWindow, port } = build({ frontmost: false })

    for (const foreign of [null, undefined, 'prior-app-0', {}, { keeplingWasFrontmost: false }]) {
      port.restoreActiveApp(foreign)
    }

    expect(application.hideCalls).toBe(0)
    expect(mainWindow?.showCalls).toBe(0)
  })

  it('does not touch a destroyed or absent main window on the Keepling-frontmost path', async () => {
    const destroyed = build({ frontmost: true, mainWindow: new FakeWindow(true) })
    destroyed.port.restoreActiveApp(await destroyed.port.captureActiveApp())
    expect(destroyed.mainWindow?.showCalls).toBe(0)
    expect(destroyed.application.hideCalls).toBe(0)

    const absent = build({ frontmost: true, mainWindow: null })
    absent.port.restoreActiveApp(await absent.port.captureActiveApp())
    expect(absent.application.hideCalls).toBe(0)
  })

  it('waits for the un-hide to settle before returning, so Quick Entry is shown after the main window is back', async () => {
    let frontmost = false
    let waits = 0
    const { port } = build({
      frontmost: () => frontmost,
      hidden: true,
      wait: async () => {
        waits += 1
        // `NSApplication.unhide:` re-keys the main window several run-loop
        // turns after it returns; model that instead of assuming it is
        // instantaneous.
        if (waits === 3) frontmost = true
      },
    })

    const handle = await port.captureActiveApp()

    expect(waits).toBe(3)
    expect(handle.keeplingWasFrontmost).toBe(false)
  })

  it('gives up on the settle at a bounded deadline rather than hanging the shortcut forever', async () => {
    let waits = 0
    const { port } = build({
      frontmost: false,
      hidden: true,
      wait: async () => { waits += 1 },
    })

    await expect(port.captureActiveApp()).resolves.toMatchObject({ keeplingWasFrontmost: false })
    expect(waits).toBeGreaterThan(0)
  })
})
