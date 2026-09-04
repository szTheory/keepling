import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * VERIFICATION.md Gap 2 (03-27): behavioral, machine-independent evidence for
 * the five window sizes 03-UI-SPEC.md's "Verification Evidence Required"
 * section names (line 334) -- the one dimension of that section with no
 * executable artifact anywhere in the repository before this file. See
 * 03-UI-SPEC.md's per-dimension evidence table (amended by this same plan)
 * for how every OTHER dimension in that section is covered, and the
 * `gap_2_decision` block in 03-27-PLAN.md for why this is proven
 * behaviorally rather than by golden-image comparison.
 *
 * This file deliberately does NOT duplicate 200% zoom, forced-colors,
 * prefers-reduced-motion, or theme-change-mid-dialog -- `accessibility.spec.ts`
 * already owns those. It also does not add `toHaveScreenshot`/`toMatchSnapshot`
 * or a baseline directory of any kind.
 *
 * `@windowed`: every case depends on real Electron `BrowserWindow` content-size
 * changes and real presentation, which the headless default cannot honestly
 * assert. See `playwright.config.ts` for the `@windowed` grepInvert rule and
 * why `KEEPLING_TEST_HEADLESS=0` is required to run this file at all.
 *
 * Task 1 proves ONE window size in ONE theme end to end. Task 2 (same file)
 * expands this to all five sizes named by 03-UI-SPEC.md, in both themes.
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before appearance-matrix E2E')
  if (!existsSync(`${desktopRoot}/dist/main/index.cjs`)) {
    throw new Error('desktop build did not produce dist/main/index.cjs')
  }
})

const launch = async (profilePath: string): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: ['.'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_SYNC_MODE: 'offline', KEEPLING_TEST_USER_DATA_DIR: profilePath },
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

type Theme = 'light' | 'dark'
type Size = { width: number; height: number }

const captureOneTask = async (window: Page, title: string) => {
  await window.getByLabel('What do you want to keep?').fill(title)
  await window.getByRole('button', { name: 'Add Task' }).click()
  await expect(window.getByText(title)).toBeVisible()
}

const assertReachablePrimaryControls = async (window: Page) => {
  // The same reachability predicate `accessibility.spec.ts`'s 200% reflow
  // case uses: this codebase's established pattern for "every primary
  // control remains reachable" is visibility of the primary interactive
  // controls by role/label, not a literal Tab-key traversal loop. Replicated
  // verbatim here rather than inventing a different (and potentially weaker
  // or stronger) predicate.
  await expect(window.getByLabel('What do you want to keep?')).toBeVisible()
  await expect(window.getByRole('button', { name: 'Add Task' })).toBeVisible()
  await expect(window.getByRole('button', { name: 'Inbox', exact: true })).toBeVisible()
}

const runCase = (title: string, size: Size, theme: Theme) => {
  test(title, { tag: '@windowed' }, async () => {
    const profilePath = allocateDisposableProfile(`appearance-matrix-${size.width}x${size.height}-${theme}`)
    const { application, window } = await launch(profilePath)
    try {
      // Resize FIRST, then read the size back and assert it landed BEFORE
      // asserting anything about layout -- an assertion made against a
      // window that never resized would be vacuous.
      await application.evaluate(
        ({ BrowserWindow }, target) => {
          BrowserWindow.getAllWindows()[0]?.setContentSize(target.width, target.height)
        },
        size,
      )
      const actualSize = await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.getContentSize())
      expect(actualSize).toEqual([size.width, size.height])

      await window.emulateMedia({ colorScheme: theme })
      // Emulating a colorScheme change alone does not force a layout pass
      // in every Electron/Chromium version; give the renderer one tick to
      // settle before measuring anything.
      await window.waitForTimeout(100)

      await expect(window.getByRole('navigation')).toBeVisible()
      await expect(window.getByRole('form', { name: 'Add task' })).toBeVisible()
      await captureOneTask(window, `Case proof ${size.width}x${size.height} ${theme}`)

      const overflow = await window.evaluate(() => ({
        clientWidth: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
      }))
      expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth)

      await assertReachablePrimaryControls(window)
    } finally {
      await application.close()
    }
  })
}

// Title written out as a literal string (not built via interpolation) so
// `grep -F` against THIS SOURCE FILE can find it verbatim, and so the
// literal window size `1024x700` is present in the file for Task 3's
// UI-SPEC evidence table to cite by name.
runCase(
  'appearance matrix: 1024x700 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 700, width: 1024 },
  'light',
)
