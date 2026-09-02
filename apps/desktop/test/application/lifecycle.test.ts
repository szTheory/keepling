import { describe, expect, it, vi } from 'vitest'

import { DesktopLifecycle, createFileWindowStatePort, type WindowSnapshot, type WindowStatePort } from '../../main/lifecycle.ts'

/**
 * `DesktopLifecycle` is deliberately pure of any LIVE Electron object -- it
 * only ever receives a `createWindow` factory, an injected `app`/`screen`
 * port, and an injected `windowState` port -- so its close/activate/quit
 * decisions are provable with plain fakes in Node/vitest, exactly like
 * Plan 03-10's `main/protocol.ts` decision functions. Real E2E proof against
 * a live Electron process (recreation, real bounds, real quit) lives in
 * `test/e2e/lifecycle.spec.ts`.
 */

type Listener = (...args: unknown[]) => void

class FakeWindow {
  readonly #listeners = new Map<string, Listener[]>()
  #bounds: { height: number; width: number; x: number; y: number }
  #destroyed = false
  #fullscreen: boolean
  focusCalls = 0
  loadedUrl: string | null = null
  showCalls = 0

  constructor(bounds: { height: number; width: number; x: number; y: number }, fullscreen: boolean) {
    this.#bounds = bounds
    this.#fullscreen = fullscreen
  }

  on(event: string, listener: Listener): void {
    const existing = this.#listeners.get(event) ?? []
    existing.push(listener)
    this.#listeners.set(event, existing)
  }

  emit(event: string): void {
    for (const listener of this.#listeners.get(event) ?? []) listener()
  }

  getBounds() {
    return this.#bounds
  }

  isFullScreen() {
    return this.#fullscreen
  }

  isDestroyed() {
    return this.#destroyed
  }

  show(): void {
    this.showCalls += 1
  }

  focus(): void {
    this.focusCalls += 1
  }

  async loadURL(url: string): Promise<void> {
    this.loadedUrl = url
  }

  destroy(): void {
    this.#destroyed = true
    this.emit('closed')
  }
}

class FakeApp {
  readonly #listeners = new Map<string, Listener[]>()
  exitCalls = 0

  on(event: string, listener: Listener): void {
    const existing = this.#listeners.get(event) ?? []
    existing.push(listener)
    this.#listeners.set(event, existing)
  }

  emit(event: string, ...args: unknown[]): void {
    for (const listener of this.#listeners.get(event) ?? []) listener(...args)
  }

  exit(): void {
    this.exitCalls += 1
  }
}

const PRIMARY_WORK_AREA = { height: 900, width: 1600, x: 0, y: 0 }

const fakeScreen = {
  getDisplayMatching: () => ({ workArea: PRIMARY_WORK_AREA }),
  getPrimaryDisplay: () => ({ workArea: PRIMARY_WORK_AREA }),
}

const makeWindowStateStub = (initial: WindowSnapshot | null = null): WindowStatePort & { saved: WindowSnapshot[] } => {
  let current = initial
  const saved: WindowSnapshot[] = []
  return {
    load: () => current,
    save: (snapshot) => {
      current = snapshot
      saved.push(snapshot)
    },
    saved,
  }
}

const build = (options: { windowState?: WindowStatePort; quitBoundMs?: number } = {}) => {
  const app = new FakeApp()
  const windows: FakeWindow[] = []
  const createWindow = vi.fn((opts: { bounds?: { height: number; width: number; x: number; y: number }; fullscreen?: boolean }) => {
    const window = new FakeWindow(
      opts.bounds ?? { height: 780, width: 1180, x: 10, y: 10 },
      opts.fullscreen ?? false,
    )
    windows.push(window)
    return window as unknown as import('electron').BrowserWindow
  })
  const desktopApplicationClose = vi.fn().mockResolvedValue(undefined)
  const onBeforeQuit = vi.fn()
  const windowState = options.windowState ?? makeWindowStateStub()

  const lifecycle = new DesktopLifecycle({
    app: app as unknown as import('electron').App,
    createWindow: createWindow as unknown as (opts: never) => import('electron').BrowserWindow,
    desktopApplication: { close: desktopApplicationClose },
    onBeforeQuit,
    quitBoundMs: options.quitBoundMs,
    rendererUrl: 'app://renderer/index.html',
    screen: fakeScreen as unknown as import('electron').Screen,
    windowState,
  })

  return { app, createWindow, desktopApplicationClose, lifecycle, onBeforeQuit, windowState, windows }
}

describe('DesktopLifecycle', () => {
  it('creates and loads a window on first ensureWindow, and shows it', async () => {
    const { createWindow, lifecycle, windows } = build()
    const window = await lifecycle.ensureWindow()
    expect(createWindow).toHaveBeenCalledTimes(1)
    expect((window as unknown as FakeWindow).loadedUrl).toBe('app://renderer/index.html')
    expect((window as unknown as FakeWindow).showCalls).toBe(1)
    expect(windows).toHaveLength(1)
  })

  it('returns and focuses the existing window instead of creating a second one', async () => {
    const { createWindow, lifecycle } = build()
    const first = await lifecycle.ensureWindow()
    const second = await lifecycle.ensureWindow()
    expect(second).toBe(first)
    expect(createWindow).toHaveBeenCalledTimes(1)
    expect((second as unknown as FakeWindow).focusCalls).toBe(1)
  })

  it('D-20: recreates a fresh window after the previous one is destroyed (Dock activation / second launch)', async () => {
    const { createWindow, lifecycle } = build()
    const first = await lifecycle.ensureWindow()
    ;(first as unknown as FakeWindow).destroy()
    expect(lifecycle.getMainWindow()).toBeNull()

    const second = await lifecycle.ensureWindow()
    expect(second).not.toBe(first)
    expect(createWindow).toHaveBeenCalledTimes(2)
  })

  it('D-06: persists bounds/fullscreen on close, and the next window is created from the clamped persisted snapshot', async () => {
    const { createWindow, lifecycle, windowState } = build()
    const first = await lifecycle.ensureWindow()
    ;(first as unknown as FakeWindow & { emit: (event: string) => void }).emit('close')
    ;(first as unknown as FakeWindow).destroy()

    expect(windowState.saved).toHaveLength(1)
    expect(windowState.saved[0]).toEqual({ bounds: { height: 780, width: 1180, x: 10, y: 10 }, fullscreen: false })

    await lifecycle.ensureWindow()
    expect(createWindow).toHaveBeenLastCalledWith({
      bounds: { height: 780, width: 1180, x: 10, y: 10 },
      fullscreen: false,
    })
  })

  it('D-06: clamps an out-of-bounds persisted snapshot into the current visible work area instead of restoring it off-screen', async () => {
    const windowState = makeWindowStateStub({ bounds: { height: 40, width: 40, x: 99_999, y: 99_999 }, fullscreen: false })
    const { createWindow, lifecycle } = build({ windowState })

    await lifecycle.ensureWindow()
    const passed = createWindow.mock.calls[0]![0] as { bounds: { height: number; width: number; x: number; y: number } }
    expect(passed.bounds.x + passed.bounds.width).toBeLessThanOrEqual(PRIMARY_WORK_AREA.x + PRIMARY_WORK_AREA.width)
    expect(passed.bounds.y + passed.bounds.height).toBeLessThanOrEqual(PRIMARY_WORK_AREA.y + PRIMARY_WORK_AREA.height)
    // Below the main window's own enforced minimums (see windows/mainWindowState.ts).
    expect(passed.bounds.width).toBeGreaterThanOrEqual(680)
    expect(passed.bounds.height).toBeGreaterThanOrEqual(520)
  })

  it('D-20: activate and second-instance both recreate the window when none exists', async () => {
    const { app, createWindow, lifecycle } = build()
    lifecycle.registerAppHandlers()

    app.emit('activate')
    await Promise.resolve()
    expect(createWindow).toHaveBeenCalledTimes(1)

    ;(lifecycle.getMainWindow() as unknown as FakeWindow).destroy()
    app.emit('second-instance')
    await Promise.resolve()
    expect(createWindow).toHaveBeenCalledTimes(2)
  })

  it('D-21: before-quit prevents Electron default, runs cleanup, closes the local store, and exits -- once', async () => {
    const { app, desktopApplicationClose, lifecycle, onBeforeQuit } = build()
    lifecycle.registerAppHandlers()
    await lifecycle.ensureWindow()

    let prevented = 0
    app.emit('before-quit', { preventDefault: () => { prevented += 1 } })
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(prevented).toBe(1)
    expect(onBeforeQuit).toHaveBeenCalledTimes(1)
    expect(desktopApplicationClose).toHaveBeenCalledTimes(1)
    expect(app.exitCalls).toBe(1)

    // A second before-quit (Electron re-dispatch during our own app.exit()
    // path in a real process) must not preventDefault again or re-run cleanup.
    app.emit('before-quit', { preventDefault: () => { prevented += 1 } })
    expect(prevented).toBe(1)
  })

  it('D-21 prohibition: quit is bounded and exits even if the local store close() never resolves -- never a wait on the network or a hung worker', async () => {
    vi.useFakeTimers()
    try {
      const app = new FakeApp()
      const createWindow = vi.fn(
        () => new FakeWindow({ height: 780, width: 1180, x: 10, y: 10 }, false) as unknown as import('electron').BrowserWindow,
      )
      const hungClose = vi.fn(() => new Promise<void>(() => {})) // never resolves
      const lifecycle = new DesktopLifecycle({
        app: app as unknown as import('electron').App,
        createWindow: createWindow as unknown as (opts: never) => import('electron').BrowserWindow,
        desktopApplication: { close: hungClose },
        quitBoundMs: 5_000,
        rendererUrl: 'app://renderer/index.html',
        screen: fakeScreen as unknown as import('electron').Screen,
        windowState: makeWindowStateStub(),
      })
      lifecycle.registerAppHandlers()

      app.emit('before-quit', { preventDefault: () => {} })
      await vi.advanceTimersByTimeAsync(5_000)

      expect(app.exitCalls).toBe(1)
    } finally {
      vi.useRealTimers()
    }
  })
})

describe('createFileWindowStatePort', () => {
  it('returns null when no file exists yet', () => {
    const port = createFileWindowStatePort('/nonexistent/keepling-lifecycle-test/window-state.json')
    expect(port.load()).toBeNull()
  })

  it('round-trips a saved snapshot through a real temp file', async () => {
    const { mkdtempSync, rmSync } = await import('node:fs')
    const { tmpdir } = await import('node:os')
    const { join } = await import('node:path')
    const dir = mkdtempSync(join(tmpdir(), 'keepling-lifecycle-state-'))
    try {
      const filePath = join(dir, 'window-state.json')
      const port = createFileWindowStatePort(filePath)
      expect(port.load()).toBeNull()

      const snapshot: WindowSnapshot = { bounds: { height: 700, width: 1000, x: 5, y: 5 }, fullscreen: true }
      port.save(snapshot)
      expect(port.load()).toEqual(snapshot)
    } finally {
      rmSync(dir, { force: true, recursive: true })
    }
  })

  it('degrades to null (never throws) when the persisted file is corrupt/malformed', async () => {
    const { mkdtempSync, rmSync, writeFileSync } = await import('node:fs')
    const { tmpdir } = await import('node:os')
    const { join } = await import('node:path')
    const dir = mkdtempSync(join(tmpdir(), 'keepling-lifecycle-state-corrupt-'))
    try {
      const filePath = join(dir, 'window-state.json')
      writeFileSync(filePath, 'not json{{{')
      const port = createFileWindowStatePort(filePath)
      expect(port.load()).toBeNull()
    } finally {
      rmSync(dir, { force: true, recursive: true })
    }
  })
})
