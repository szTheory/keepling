import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Quick Entry E2E evidence for Plan 03-04 Task 2 (D-09/D-10/D-11, MAC-02
 * probe predicate).
 *
 * IMPORTANT SCOPE NOTE: this launches `dist-harness/harness.cjs`, an
 * E2E-only reference wiring (`test/fixtures/wired-app-harness.ts`) that
 * composes the real `QuickEntryWindowController`, `createMainWindow`, and
 * `buildApplicationMenu` in a real Electron process -- it does NOT launch
 * the shipped app's actual entry point (`dist/main/index.cjs`), because
 * wiring these modules into `apps/desktop/main/index.ts` would cross this
 * wave's scope fence (Plan 03-10 owns that file). This is real, passing,
 * non-vacuous evidence that the Quick Entry modules behave correctly; it is
 * NOT evidence that they are reachable from the shipped app today. See this
 * plan's SUMMARY "Known Gaps" for the exact remaining integration step.
 */
/**
 * WINDOWED-ONLY (`@windowed`). Every test in this file is excluded from a
 * `KEEPLING_TEST_HEADLESS=1` run, because this file's central predicate --
 * `isQuickEntryOpen()` -> the real controller's `isOpen()` -> the real
 * `BrowserWindow.isVisible()` -- is exactly what headless presentation
 * suppresses. Measured: with the seam installed,
 * `keyboard-quick-entry.spec.ts:169` FAILS outright (it asserts
 * `isOpen() === true`), and the `isOpen() === false` assertions at :122 and
 * :148 would pass VACUOUSLY, unable to distinguish "hidden after commit"
 * from "never presented at all". A spec that cannot be trusted headless
 * runs windowed or not at all -- never headless-and-weakened.
 *
 * Run these explicitly with: `pnpm test:desktop:e2e keyboard-quick-entry`
 * (no headless flag), or `pnpm test:desktop:e2e --grep @windowed`.
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const build = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (build.status !== 0) throw new Error('desktop build failed before keyboard-quick-entry E2E')
  const harness = spawnSync('pnpm', ['run', 'build:harness'], { cwd: desktopRoot, stdio: 'inherit' })
  if (harness.status !== 0) throw new Error('harness build failed before keyboard-quick-entry E2E')
  if (!existsSync(`${desktopRoot}/dist-harness/harness.cjs`)) {
    throw new Error('harness build did not produce dist-harness/harness.cjs')
  }
})

const launch = async (
  profilePath: string,
  env: Record<string, string> = {},
): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: ['dist-harness/harness.cjs'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_USER_DATA_DIR: profilePath, ...env },
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

const findQuickEntryPage = (application: ElectronApplication): Page | undefined =>
  application.windows().find((page) => page.url().includes('view=quick-entry'))

/**
 * Opens (or re-shows) the resident Quick Entry window. The underlying
 * `BrowserWindow` -- and therefore its Playwright `Page` -- is only ever
 * CREATED once (MAC-02 probe predicate: repeated invocation reuses it), so
 * a `waitForEvent('window')` only resolves on the FIRST call; later calls
 * must reuse the already-known page instead.
 */
const openQuickEntry = async (application: ElectronApplication): Promise<Page> => {
  const existing = findQuickEntryPage(application)
  if (existing !== undefined) {
    await application.evaluate(async () => {
      const harness = (globalThis as unknown as { __testHarness: { quickEntry: { open: () => Promise<void> } } })
        .__testHarness
      await harness.quickEntry.open()
    })
    return existing
  }

  const [quickEntryWindow] = await Promise.all([
    application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
    application.evaluate(async () => {
      const harness = (globalThis as unknown as { __testHarness: { quickEntry: { open: () => Promise<void> } } })
        .__testHarness
      await harness.quickEntry.open()
    }),
  ])
  await quickEntryWindow.waitForLoadState('domcontentloaded')
  return quickEntryWindow
}

/**
 * `Page` (a whole BrowserWindow's document) doesn't support Playwright's
 * `toBeHidden`/`toBeVisible` locator matchers -- those apply to elements.
 * Poll the real controller's own `isOpen()` (window.isVisible()) instead.
 */
const isQuickEntryOpen = (application: ElectronApplication): Promise<boolean> =>
  application.evaluate(
    () => (globalThis as unknown as { __testHarness: { quickEntry: { isOpen: () => boolean } } }).__testHarness
      .quickEntry.isOpen(),
  )

test('one shortcut invocation opens exactly one Quick Entry window, focused on the title field', { tag: '@windowed' }, async () => {
  const profilePath = allocateDisposableProfile('quick-entry-single-window')
  const { application } = await launch(profilePath)
  try {
    const quickEntryWindow = await openQuickEntry(application)
    await expect(quickEntryWindow.getByLabel('What do you want to keep?')).toBeFocused()

    // Repeated invocation focuses the SAME window rather than creating a
    // second one (MAC-02 probe predicate).
    const windowCountBefore = application.windows().length
    await application.evaluate(async () => {
      const harness = (globalThis as unknown as { __testHarness: { quickEntry: { open: () => Promise<void> } } })
        .__testHarness
      await harness.quickEntry.open()
    })
    expect(application.windows().length).toBe(windowCountBefore)
  } finally {
    await application.close()
  }
})

test('local commit produces one task, clears the draft, hides the window, and returns focus to the prior app', { tag: '@windowed' }, async () => {
  const profilePath = allocateDisposableProfile('quick-entry-commit-focus-return')
  const { application, window } = await launch(profilePath)
  try {
    const quickEntryWindow = await openQuickEntry(application)
    await quickEntryWindow.getByLabel('What do you want to keep?').fill('Call dentist')
    await quickEntryWindow.getByRole('button', { name: 'Add Task' }).click()

    await expect.poll(() => isQuickEntryOpen(application)).toBe(false)
    await expect(window.getByText('Call dentist')).toBeVisible()

    const foregroundLog = await application.evaluate(
      () => (globalThis as unknown as { __testHarness: { foregroundLog: string[] } }).__testHarness.foregroundLog,
    )
    expect(foregroundLog).toEqual(['capture:prior-app-0', 'restore:prior-app-0'])

    // Reopening shows an empty draft (the successful commit cleared it).
    const reopened = await openQuickEntry(application)
    await expect(reopened.getByLabel('What do you want to keep?')).toHaveValue('')
  } finally {
    await application.close()
  }
})

test('a hidden nonempty draft survives Escape and window recreation until explicitly discarded', { tag: '@windowed' }, async () => {
  const profilePath = allocateDisposableProfile('quick-entry-durable-draft')
  const { application } = await launch(profilePath)
  try {
    const quickEntryWindow = await openQuickEntry(application)
    await quickEntryWindow.getByLabel('What do you want to keep?').fill('Ping accountant')
    // Debounced draft save (see quick-entry.tsx); wait past the debounce window.
    await quickEntryWindow.waitForTimeout(400)

    await quickEntryWindow.getByLabel('What do you want to keep?').press('Escape')
    await expect.poll(() => isQuickEntryOpen(application)).toBe(false)

    const reopened = await openQuickEntry(application)
    await expect(reopened.getByLabel('What do you want to keep?')).toHaveValue('Ping accountant')

    // Explicit discard, with safe "Keep Draft" initial focus (D-11).
    await reopened.getByRole('button', { name: 'Discard Draft…' }).click()
    await expect(reopened.getByRole('button', { name: 'Keep Draft' })).toBeFocused()
    await reopened.getByRole('button', { name: 'Discard Draft', exact: true }).click()

    const draft = await application.evaluate(
      () =>
        (globalThis as unknown as { __testHarness: { desktopApplication: { getDraft: () => Promise<unknown> } } })
          .__testHarness.desktopApplication.getDraft(),
    )
    expect(draft).toBeNull()
  } finally {
    await application.close()
  }
})

test('Command-Return commits, and typing during IME composition does not commit', { tag: '@windowed' }, async () => {
  const profilePath = allocateDisposableProfile('quick-entry-command-return-and-ime')
  const { application, window } = await launch(profilePath)
  try {
    const quickEntryWindow = await openQuickEntry(application)
    const titleField = quickEntryWindow.getByLabel('What do you want to keep?')

    // A composing IME session holding Enter/Return must not commit --
    // dispatched as a real composition + keydown pair (D-12).
    await titleField.fill('たなか')
    await quickEntryWindow.evaluate(() => {
      const field = document.getElementById('quick-entry-title') as HTMLInputElement
      field.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))
      field.dispatchEvent(
        new KeyboardEvent('keydown', { bubbles: true, isComposing: true, key: 'Enter', metaKey: true }),
      )
      field.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }))
    })
    await quickEntryWindow.waitForTimeout(100)
    expect(await isQuickEntryOpen(application)).toBe(true)

    await titleField.fill('Buy stamps')
    await titleField.press('Meta+Enter')
    await expect(window.getByText('Buy stamps')).toBeVisible()
  } finally {
    await application.close()
  }
})

test('shortcut collision is visible and directly rebindable, never a silent fallback (D-10)', { tag: '@windowed' }, async () => {
  const profilePath = allocateDisposableProfile('quick-entry-shortcut-collision')
  const { application } = await launch(profilePath, { KEEPLING_TEST_OCCUPIED_SHORTCUT: 'Control+Alt+Space' })
  try {
    const status = await application.evaluate(
      () =>
        (globalThis as unknown as { __testHarness: { quickEntry: { registerShortcut: () => Promise<unknown> } } })
          .__testHarness.quickEntry.registerShortcut(),
    )
    expect(status).toEqual({ accelerator: 'Control+Alt+Space', registered: false })

    const rebound = await application.evaluate(
      () =>
        (globalThis as unknown as { __testHarness: { quickEntry: { rebindShortcut: (a: string) => Promise<unknown> } } })
          .__testHarness.quickEntry.rebindShortcut('Control+Alt+K'),
    )
    expect(rebound).toEqual({ accelerator: 'Control+Alt+K', registered: true })
  } finally {
    await application.close()
  }
})
