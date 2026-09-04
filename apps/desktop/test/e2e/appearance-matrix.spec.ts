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

/**
 * The five window CONTENT sizes 03-UI-SPEC.md line 334 names -- read as
 * content size (the renderer's own viewport), not outer window size
 * including titlebar chrome. `setContentSize`/`getContentSize` operate on
 * content size directly, and the spec's own "minimum bounds are 680x520px"
 * language in the Main Window Contract is stated the same way. This
 * interpretation is recorded here per this plan's own planner_assumptions
 * rather than guessed silently.
 */

/**
 * Below 1024px content width the shipped shell (`Workspace.tsx`
 * `resolveBreakpoint`) is the 'compact' breakpoint: it shows exactly ONE of
 * the list or detail region at a time (D-04, "Below 1024px, show one routed
 * surface at a time"), matching `desktop.css`'s single-column
 * `main[data-workspace-breakpoint] { grid-template-columns: 1fr; }`. At
 * 1024px and above (`compact-wide`/`persistent`), BOTH regions render
 * simultaneously inside the fixed `320px 1fr` grid
 * (`main[data-workspace-breakpoint='compact-wide'|'persistent']`).
 *
 * So "does the fixed grid collapse a region to nothing" is only a
 * meaningful question at sizes where both regions actually coexist in the
 * DOM. At 680x520 (the only 'compact' size in this matrix) there is no
 * simultaneous list+detail case to measure -- asserting "both non-zero
 * width" there would either be vacuously true (only one exists, so its
 * sibling selector matches nothing and any `count() === 0` check trivially
 * "passes") or would have to click a task into existence first, changing the
 * routed surface being measured. Instead, at 680x520 this file asserts the
 * ONE region the compact breakpoint actually shows (the list, since no task
 * is selected) is non-zero width -- the real failure mode a single-column
 * `1fr` grid could exhibit.
 */
const isSimultaneousRegionSize = (size: Size): boolean => size.width >= 1024

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

      if (isSimultaneousRegionSize(size)) {
        const [listWidth, detailWidth] = await Promise.all([
          window.locator('[data-workspace-region="list"]').evaluate((element) => element.getBoundingClientRect().width),
          window.locator('[data-workspace-region="detail"]').evaluate((element) => element.getBoundingClientRect().width),
        ])
        expect(listWidth).toBeGreaterThan(0)
        expect(detailWidth).toBeGreaterThan(0)
      } else {
        const listWidth = await window
          .locator('[data-workspace-region="list"]')
          .evaluate((element) => element.getBoundingClientRect().width)
        expect(listWidth).toBeGreaterThan(0)
        await expect(window.locator('[data-workspace-region="detail"]')).toHaveCount(0)
      }
    } finally {
      await application.close()
    }
  })
}

// Titles are written out as literal strings (not built via interpolation)
// so `grep -F`/`grep -o` against THIS SOURCE FILE -- exactly what
// 03-27-PLAN.md's acceptance criteria and 03-UI-SPEC.md's evidence table
// both do -- can find each one verbatim, and so the required-count checks
// (10 cases, 10 distinct size/theme pairs, all five literal sizes) are
// checking real enumerated text rather than a template that only produces
// those strings at runtime.
runCase(
  'appearance matrix: 680x520 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 520, width: 680 },
  'light',
)
runCase(
  'appearance matrix: 680x520 dark -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 520, width: 680 },
  'dark',
)
runCase(
  'appearance matrix: 1024x700 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 700, width: 1024 },
  'light',
)
runCase(
  'appearance matrix: 1024x700 dark -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 700, width: 1024 },
  'dark',
)
runCase(
  'appearance matrix: 1064x700 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 700, width: 1064 },
  'light',
)
runCase(
  'appearance matrix: 1064x700 dark -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 700, width: 1064 },
  'dark',
)
runCase(
  'appearance matrix: 1180x780 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 780, width: 1180 },
  'light',
)
runCase(
  'appearance matrix: 1180x780 dark -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 780, width: 1180 },
  'dark',
)
runCase(
  'appearance matrix: 1440x900 light -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 900, width: 1440 },
  'light',
)
runCase(
  'appearance matrix: 1440x900 dark -- no window-level horizontal overflow and every primary control remains reachable',
  { height: 900, width: 1440 },
  'dark',
)
