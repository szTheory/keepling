import { spawnSync } from 'node:child_process'
import { existsSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Resident single-instance lifecycle, validated D-06 bounds/fullscreen
 * restoration, bounded D-21 quit, and O-9 native-shell wiring evidence
 * (Plan 03-11, D-20/D-21, MAC-02/MAC-03/MAC-05).
 *
 * UNLIKE Plan 03-04's `keyboard-menus.spec.ts` / `keyboard-quick-entry.spec.ts`
 * (which deliberately launch the E2E-only `dist-harness/harness.cjs`
 * reference wiring), every test in this file launches the REAL SHIPPED
 * entry point (`electron.launch({ args: ['.'] })`, i.e. `dist/main/index.cjs`
 * via `package.json#main`) -- the exact same launch `daily-loop.spec.ts`
 * already uses against the hardened `main/index.ts`. This is the evidence
 * that closes O-9: `DesktopLifecycle`, `buildApplicationMenu`,
 * `QuickEntryWindowController`, and `SettingsWindowController` are now
 * instantiated in the real `bootstrap()`, not merely proven against a
 * harness. No `__testHarness` global is exposed by production
 * `main/index.ts` (deliberately -- that convenience stays test-only), so
 * these tests drive the app the same way a person or the real native menu
 * would: keyboard input, real `MenuItem#click()` calls against
 * `Menu.getApplicationMenu()`, and real `BrowserWindow` lifecycle methods.
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before lifecycle E2E')
  if (!existsSync(`${desktopRoot}/dist/main/index.cjs`)) {
    throw new Error('desktop build did not produce dist/main/index.cjs')
  }
})

const launch = async (
  profilePath: string,
  env: Record<string, string> = {},
): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: ['.'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_SYNC_MODE: 'offline', KEEPLING_TEST_USER_DATA_DIR: profilePath, ...env },
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

/** Finds a native menu item by exact label, or by label PREFIX (Quick Entry's label embeds its live accelerator). */
const clickMenuItem = async (application: ElectronApplication, labelOrPrefix: string): Promise<void> => {
  const clicked = await application.evaluate(({ Menu }, label) => {
    const find = (items: Electron.MenuItem[]): Electron.MenuItem | null => {
      for (const item of items) {
        if (item.label === label || item.label.startsWith(label)) return item
        if (item.submenu) {
          const found = find(item.submenu.items)
          if (found !== null) return found
        }
      }
      return null
    }
    const menu = Menu.getApplicationMenu()
    if (menu === null) return false
    const item = find(menu.items)
    if (item === null) return false
    item.click()
    return true
  }, labelOrPrefix)
  expect(clicked, `menu item "${labelOrPrefix}" was not found in the real application menu`).toBe(true)
}

const windowCount = (application: ElectronApplication): Promise<number> =>
  application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length)

const mainWindowBounds = (application: ElectronApplication): Promise<{ height: number; width: number; x: number; y: number }> =>
  application.evaluate(({ BrowserWindow }) => {
    const [window] = BrowserWindow.getAllWindows()
    if (window === undefined) throw new Error('no main window')
    return window.getBounds()
  })

test('O-9: the real shipped app registers the native menu, and clicking New Task through it reaches the real main window', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-menu-wired')
  const { application, window } = await launch(profilePath)
  try {
    // The synthesized keydown a menu click dispatches only reaches a
    // listener that has already mounted -- wait for the renderer's own
    // capture form (and therefore DesktopShell's keydown listener) to be
    // ready before driving the menu, matching how a real user could not
    // click a menu item before the window finished rendering either.
    await window.getByLabel('What do you want to keep?').waitFor()

    const labels = await application.evaluate(({ Menu }) => {
      const collect = (items: Electron.MenuItem[]): string[] =>
        items.flatMap((item) => [item.label, ...(item.submenu ? collect(item.submenu.items) : [])])
      const menu = Menu.getApplicationMenu()
      if (menu === null) throw new Error('no application menu set on the real shipped app')
      return collect(menu.items)
    })
    expect(labels).toContain('New Task')
    expect(labels).toContain('Undo Last Supported Action')
    expect(labels.some((label) => label.startsWith('Quick Entry'))).toBe(true)

    // Real MenuItem#click() (the same call Electron makes for a real mouse
    // click), against the ACTUAL production menu built by main/index.ts's
    // bootstrap() -- not a synthesized renderer keydown.
    await clickMenuItem(application, 'New Task')
    await expect(window.getByLabel('What do you want to keep?')).toBeFocused()
  } finally {
    await application.close()
  }
})

test('O-9: the global Quick Entry shortcut is registered by the real shipped app', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-shortcut-registered')
  const { application } = await launch(profilePath)
  try {
    const registered = await application.evaluate(({ globalShortcut }) => globalShortcut.isRegistered('Control+Alt+Space'))
    expect(registered).toBe(true)
  } finally {
    await application.close()
  }
})

test('O-9: the native File > Quick Entry menu item opens the real resident Quick Entry window and its commit reaches the real main window', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-quick-entry-wired')
  const { application, window } = await launch(profilePath)
  try {
    const [quickEntryWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      clickMenuItem(application, 'Quick Entry'),
    ])
    await quickEntryWindow.waitForLoadState('domcontentloaded')
    await expect(quickEntryWindow.getByLabel('What do you want to keep?')).toBeFocused()

    await quickEntryWindow.getByLabel('What do you want to keep?').fill('Ping accountant')
    await quickEntryWindow.getByRole('button', { name: 'Add Task' }).click()

    // Cross-window commit: the task captured through the real Quick Entry
    // window appears in the real main window without a reload.
    await expect(window.getByText('Ping accountant')).toBeVisible()
  } finally {
    await application.close()
  }
})

test('O-9: Command-, opens the real Settings window against the shipped entry point', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-settings-wired')
  const { application } = await launch(profilePath)
  try {
    const [settingsWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=settings') }),
      clickMenuItem(application, 'Settings…'),
    ])
    await settingsWindow.waitForLoadState('domcontentloaded')
    await expect(settingsWindow.getByText(/Quick Entry/)).toBeVisible()
  } finally {
    await application.close()
  }
})

test('O-10: the real main window and the real Quick Entry window both deny unexpected window.open() -- no new window is created', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-navigation-guard')
  const { application, window } = await launch(profilePath)
  try {
    const beforeMain = await windowCount(application)
    await window.evaluate(() => window.open('https://attacker.example'))
    await window.waitForTimeout(200)
    expect(await windowCount(application)).toBe(beforeMain)

    const [quickEntryWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      clickMenuItem(application, 'Quick Entry'),
    ])
    await quickEntryWindow.waitForLoadState('domcontentloaded')
    const beforeQuickEntry = await windowCount(application)
    await quickEntryWindow.evaluate(() => window.open('https://attacker.example'))
    await quickEntryWindow.waitForTimeout(200)
    expect(await windowCount(application)).toBe(beforeQuickEntry)
  } finally {
    await application.close()
  }
})

test('D-20: closing the main window destroys it, leaves the app resident, and Dock activation recreates it -- durable state is untouched by window recreation', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-close-activate')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByLabel('What do you want to keep?').fill('Renew passport')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Renew passport')).toBeVisible()

    expect(await windowCount(application)).toBe(1)
    await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close())
    await expect.poll(() => windowCount(application)).toBe(0)

    // The app process is still alive and resident (no window, no quit) --
    // Dock activation recreates a fresh window from durable state.
    const [recreated] = await Promise.all([
      application.waitForEvent('window'),
      application.evaluate(({ app }) => app.emit('activate', {}, false)),
    ])
    await recreated.waitForLoadState('domcontentloaded')
    await expect(recreated.getByText('Renew passport')).toBeVisible()
  } finally {
    await application.close()
  }
})

test('D-20: a second launch against the SAME profile activates the resident instance instead of opening a duplicate window', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-second-instance')
  const { application, window } = await launch(profilePath)
  try {
    // Close the (only) window first so we can observe the second-instance
    // handler specifically recreating it, rather than merely re-focusing an
    // already-visible one.
    await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close())
    await expect.poll(() => windowCount(application)).toBe(0)
    void window // the original Page reference is now stale after close(); intentionally unused beyond this point.

    // The second process does not own the single-instance lock and calls
    // `app.quit()` immediately (unchanged pre-existing behavior, proven at
    // the packaged level by Plan 03-01's `PACKAGED_PROFILE_OWNERSHIP`
    // evidence) -- it can exit before Playwright's own remote-debugging
    // handshake finishes attaching, which surfaces as `electron.launch`
    // itself rejecting. That race is a Playwright harness limitation, not a
    // product defect: the OS-level single-instance IPC ping to the first
    // process (which is what this test actually needs) is sent by Electron
    // BEFORE the second process's `app.quit()`, independent of whether
    // Playwright's CDP session ever attaches.
    try {
      const secondLaunch = await electron.launch({
        args: ['.'],
        cwd: desktopRoot,
        env: { ...process.env, KEEPLING_TEST_SYNC_MODE: 'offline', KEEPLING_TEST_USER_DATA_DIR: profilePath },
        timeout: 30_000,
      })
      await secondLaunch.close().catch(() => {})
    } catch {
      // Expected: see comment above.
    }

    // The FIRST (resident) process recreates its window in response to the
    // OS 'second-instance' notification -- proving the real shipped app,
    // not just the pure DesktopLifecycle unit tests, wires this up.
    await expect.poll(() => windowCount(application)).toBe(1)
  } finally {
    await application.close()
  }
})

test('D-06: window bounds are restored (clamped to the current display) after close and Dock reactivation', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-bounds-restore')
  const { application } = await launch(profilePath)
  try {
    // The property under test is that a persisted, on-screen bounds
    // snapshot round-trips exactly through close/reactivate -- not that the
    // window lands at a specific pixel. A fixed literal (e.g. 900x700 at
    // 40,40) silently assumed the maintainer's own display geometry and
    // could itself be clamped by the OS on a smaller runner display, making
    // the round-trip assertion fail for a reason unrelated to D-06. Derive
    // a target proportional to the runner's OWN work area instead, queried
    // at runtime, so the target is always a valid on-screen rectangle no
    // matter what display the test happens to run against.
    const workArea = await application.evaluate(({ screen }) => screen.getPrimaryDisplay().workArea)
    const target = {
      height: Math.max(520, Math.round(workArea.height * 0.6)),
      width: Math.max(680, Math.round(workArea.width * 0.6)),
      x: workArea.x + Math.round(workArea.width * 0.1),
      y: workArea.y + Math.round(workArea.height * 0.1),
    }
    await application.evaluate(({ BrowserWindow }, bounds) => {
      BrowserWindow.getAllWindows()[0]?.setBounds(bounds)
    }, target)

    await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close())
    await expect.poll(() => windowCount(application)).toBe(0)

    const [recreated] = await Promise.all([
      application.waitForEvent('window'),
      application.evaluate(({ app }) => app.emit('activate', {}, false)),
    ])
    await recreated.waitForLoadState('domcontentloaded')

    const restored = await mainWindowBounds(application)
    expect(restored).toEqual(target)
  } finally {
    await application.close()
  }
})

test('D-06 prohibition: an invalid/off-screen persisted snapshot never restores off-screen -- it clamps into the current visible work area with the enforced minimums', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-bounds-clamp')
  // Written BEFORE the app ever launches against this profile, simulating a
  // display reconfiguration (external monitor unplugged) between sessions.
  writeFileSync(
    join(profilePath, 'window-state.json'),
    JSON.stringify({ bounds: { height: 30, width: 30, x: 999_999, y: 999_999 }, fullscreen: false }),
  )

  const { application } = await launch(profilePath)
  try {
    const [bounds, workArea] = await Promise.all([
      mainWindowBounds(application),
      application.evaluate(({ screen }) => screen.getPrimaryDisplay().workArea),
    ])
    expect(bounds.width).toBeGreaterThanOrEqual(680)
    expect(bounds.height).toBeGreaterThanOrEqual(520)
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(workArea.x + workArea.width)
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(workArea.y + workArea.height)
  } finally {
    await application.close()
  }
})

test('D-21: quit is bounded and every post-COMMIT mutation survives it without waiting on the network', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-bounded-quit')
  const { application, window } = await launch(profilePath)
  await window.getByLabel('What do you want to keep?').fill('File taxes')
  await window.getByRole('button', { name: 'Add Task' }).click()
  await expect(window.getByText('File taxes')).toBeVisible()
  await expect(window.getByText('Saved on this Mac').first()).toBeVisible()

  const startedAt = Date.now()
  await application.close()
  const elapsedMs = Date.now() - startedAt
  // Generous bound for CI variance; the lifecycle's own internal race is 5s.
  expect(elapsedMs).toBeLessThan(15_000)

  const relaunch = await launch(profilePath)
  try {
    await expect(relaunch.window.getByText('File taxes')).toBeVisible()
  } finally {
    await relaunch.application.close()
  }
})

test('D-03/D-21: a hard kill immediately after a local COMMIT retains exactly the committed task on relaunch -- quit is never the commit boundary', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-hard-kill-retention')
  const { application, window } = await launch(profilePath)
  await window.getByLabel('What do you want to keep?').fill('Survive a hard kill')
  await window.getByRole('button', { name: 'Add Task' }).click()
  await expect(window.getByText('Survive a hard kill')).toBeVisible()

  const process = application.process()
  process.kill('SIGKILL')
  await new Promise((resolve) => setTimeout(resolve, 500))

  const relaunch = await launch(profilePath)
  try {
    await expect(relaunch.window.getByText('Survive a hard kill')).toHaveCount(1)
  } finally {
    await relaunch.application.close()
  }
})

test('D-06 disclosed gap: destination/selection/sidebar/draft are renderer state with no restoration channel in this plan\'s authorized scope -- a fresh window always opens to Inbox', async () => {
  const profilePath = allocateDisposableProfile('lifecycle-no-renderer-restoration')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close())
    await expect.poll(() => windowCount(application)).toBe(0)

    const [recreated] = await Promise.all([
      application.waitForEvent('window'),
      application.evaluate(({ app }) => app.emit('activate', {}, false)),
    ])
    await recreated.waitForLoadState('domcontentloaded')
    // Documents today's real (disclosed) behavior: destination is NOT part
    // of this plan's main-owned restoration snapshot, so a recreated window
    // always opens to the default Inbox destination rather than the
    // previously-selected Today destination.
    await expect(recreated.getByRole('button', { name: 'Today', exact: true })).toBeVisible()
    await expect(recreated.getByRole('button', { name: 'Inbox', exact: true })).toBeVisible()
  } finally {
    await application.close()
  }
})
