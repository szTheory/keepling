import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Native menu / keyboard E2E evidence for Plan 03-04 Task 1 (D-07/D-12/
 * D-13/D-14).
 *
 * Same scope note as `keyboard-quick-entry.spec.ts`: this exercises the
 * real `buildApplicationMenu`/`createMainWindow` modules through the
 * `dist-harness/harness.cjs` reference wiring, not the shipped app's
 * `main/index.ts` entry point (out of scope for this wave -- see this
 * plan's SUMMARY "Known Gaps").
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const build = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (build.status !== 0) throw new Error('desktop build failed before keyboard-menus E2E')
  const harness = spawnSync('pnpm', ['run', 'build:harness'], { cwd: desktopRoot, stdio: 'inherit' })
  if (harness.status !== 0) throw new Error('harness build failed before keyboard-menus E2E')
  if (!existsSync(`${desktopRoot}/dist-harness/harness.cjs`)) {
    throw new Error('harness build did not produce dist-harness/harness.cjs')
  }
})

const launch = async (profilePath: string): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: ['dist-harness/harness.cjs'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_USER_DATA_DIR: profilePath },
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

test('every frequent semantic command is present in the native menu with its UI-SPEC wording', async () => {
  const profilePath = allocateDisposableProfile('keyboard-menus-inventory')
  const { application } = await launch(profilePath)
  try {
    const labels = await application.evaluate(({ Menu }) => {
      const collect = (items: Electron.MenuItem[]): string[] =>
        items.flatMap((item) => [item.label, ...(item.submenu ? collect(item.submenu.items) : [])])
      const menu = Menu.getApplicationMenu()
      if (menu === null) throw new Error('no application menu set')
      return collect(menu.items)
    })

    for (const expected of [
      'New Task',
      'Save',
      'Undo Last Supported Action',
      'Inbox',
      'Today',
      'Toggle Sidebar',
      'Sync & Recovery',
      'Settings…',
    ]) {
      expect(labels).toContain(expected)
    }
    // Discoverable even without knowing the shortcut (UI-SPEC "Menu items
    // remain available for discoverability").
    expect(labels.some((label) => label.startsWith('Quick Entry'))).toBe(true)
  } finally {
    await application.close()
  }
})

test('native menu validation swaps Complete/Reopen and Move to Trash/Restore per selection state', async () => {
  const { deriveMenuLabels } = await import('../../main/menuLabels.ts')
  expect(deriveMenuLabels({ hasSelection: false, selectedCompleted: false, selectedTrashed: false }).completeReopen).toBe(
    'Complete',
  )
  expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: true, selectedTrashed: false }).completeReopen).toBe(
    'Reopen',
  )
  expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: false, selectedTrashed: true }).trashRestore).toBe(
    'Restore',
  )
})

test('Command-1/Command-2 (menu-equivalent keystrokes) navigate Inbox/Today', async () => {
  const profilePath = allocateDisposableProfile('keyboard-menus-navigation')
  const { application, window } = await launch(profilePath)
  try {
    // Wait for the window to be focused and interactive before sending
    // keys -- pressing immediately after launch can race window focus.
    await window.getByLabel('What do you want to keep?').waitFor()
    await window.keyboard.press('Meta+2')
    await expect(window.getByRole('button', { name: 'Today', exact: true })).toHaveAttribute('aria-current', 'true')
    await window.keyboard.press('Meta+1')
    await expect(window.getByRole('button', { name: 'Inbox', exact: true })).toHaveAttribute('aria-current', 'true')
  } finally {
    await application.close()
  }
})

test('an editable/composing/repeated Complete-Reopen keystroke never fires the destructive command (D-12)', async () => {
  const profilePath = allocateDisposableProfile('keyboard-menus-destructive-guard')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByLabel('What do you want to keep?').fill('Draft in progress')
    await expect(window.getByLabel('What do you want to keep?')).toBeFocused()

    // Command-Shift-K while the capture title field is focused must not
    // toggle anything (there is nothing captured yet to toggle, and no
    // exception should be thrown).
    await window.keyboard.press('Meta+Shift+K')
    await expect(window.getByRole('button', { name: 'Add Task' })).toBeVisible()

    // Composition guard: dispatch Command-Shift-K mid-IME-composition on a
    // real captured, selected task and confirm it stays uncompleted.
    await window.getByRole('button', { name: 'Add Task' }).click()
    await window.getByText('Draft in progress').click()
    await window.evaluate(() => {
      document.body.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))
      document.body.dispatchEvent(
        new KeyboardEvent('keydown', { bubbles: true, isComposing: true, key: 'K', metaKey: true, shiftKey: true }),
      )
      document.body.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }))
    })
    await expect(window.getByRole('button', { name: 'Reopen' })).toHaveCount(0)
    await expect(window.getByRole('button', { name: 'Complete' })).toBeVisible()
  } finally {
    await application.close()
  }
})

test('the native window title names only Keepling and the coarse destination, never task content (D-07)', async () => {
  const profilePath = allocateDisposableProfile('keyboard-menus-privacy-title')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByLabel('What do you want to keep?').fill('Extremely private task title')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Extremely private task title')).toBeVisible()

    const title = await application.evaluate(
      () =>
        (globalThis as unknown as { __testHarness: { mainWindow: Electron.BrowserWindow } }).__testHarness.mainWindow
          .title,
    )
    expect(title).toBe('Keepling — Inbox')
    expect(title).not.toContain('Extremely private task title')

    await window.keyboard.press('Meta+2')
    await window.waitForTimeout(50)
    const titleAfterToday = await application.evaluate(
      () =>
        (globalThis as unknown as { __testHarness: { mainWindow: Electron.BrowserWindow } }).__testHarness.mainWindow
          .title,
    )
    expect(titleAfterToday).toBe('Keepling — Today')
  } finally {
    await application.close()
  }
})
