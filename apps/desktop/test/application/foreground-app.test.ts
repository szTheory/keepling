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

const build = (options: { frontmost: boolean; hidden?: boolean; mainWindow?: FakeWindow | null }) => {
  const application = new FakeApplication(options.hidden ?? false)
  const mainWindow = options.mainWindow === undefined ? new FakeWindow() : options.mainWindow
  const port = new ElectronForegroundApp({
    application,
    getMainWindow: () => mainWindow,
    isKeeplingFrontmost: () => options.frontmost,
  })
  return { application, mainWindow, port }
}

describe('ElectronForegroundApp', () => {
  it('hides the application on restore when Quick Entry was invoked from another application', () => {
    const { application, mainWindow, port } = build({ frontmost: false })

    port.restoreActiveApp(port.captureActiveApp())

    expect(application.hideCalls).toBe(1)
    expect(mainWindow?.showCalls).toBe(0)
    expect(mainWindow?.focusCalls).toBe(0)
  })

  it('never hides the application when Quick Entry was invoked from Keepling itself', () => {
    const { application, mainWindow, port } = build({ frontmost: true })

    port.restoreActiveApp(port.captureActiveApp())

    expect(application.hideCalls).toBe(0)
    expect(mainWindow?.showCalls).toBe(1)
    expect(mainWindow?.focusCalls).toBe(1)
  })

  it('reads frontmost-ness before un-hiding, so a hidden application is un-hidden for the next capture', () => {
    const { application, port } = build({ frontmost: false, hidden: true })

    const handle = port.captureActiveApp()

    expect(application.showCalls).toBe(1)
    expect(application.isHidden()).toBe(false)
    expect(handle.keeplingWasFrontmost).toBe(false)
  })

  it('leaves an already-visible application alone at capture time', () => {
    const { application, port } = build({ frontmost: true })

    port.captureActiveApp()

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

  it('does not touch a destroyed or absent main window on the Keepling-frontmost path', () => {
    const destroyed = build({ frontmost: true, mainWindow: new FakeWindow(true) })
    destroyed.port.restoreActiveApp(destroyed.port.captureActiveApp())
    expect(destroyed.mainWindow?.showCalls).toBe(0)
    expect(destroyed.application.hideCalls).toBe(0)

    const absent = build({ frontmost: true, mainWindow: null })
    absent.port.restoreActiveApp(absent.port.captureActiveApp())
    expect(absent.application.hideCalls).toBe(0)
  })
})
