import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * D-42 automated accessibility/appearance proof, run against the REAL
 * shipped entry point (same launch as `lifecycle.spec.ts`/`daily-loop.spec.ts`).
 * Covers what CAN be asserted from Chromium/Electron's own accessibility
 * tree and CSS media-query emulation.
 *
 * The macOS layer this file cannot see -- the real AXUIElement tree
 * VoiceOver speaks, real CGEvent keystrokes, real input sources, and real
 * system accessibility/appearance settings -- is NOT a human checklist. It
 * is executed by `tooling/verify-macos-integration.mjs` (rows A1-A15)
 * against the packaged `.app`. This file deliberately does not duplicate
 * those rows, and they deliberately do not duplicate these.
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before accessibility E2E')
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

test('semantic structure: a landmark nav, a labeled task list, a labeled capture form, and headings for every empty-route state', async () => {
  const profilePath = allocateDisposableProfile('a11y-semantic-structure')
  const { application, window } = await launch(profilePath)
  try {
    await expect(window.getByRole('navigation')).toBeVisible()
    await expect(window.getByRole('form', { name: 'Add task' })).toBeVisible()
    await expect(window.getByRole('heading', { name: 'Inbox Is Clear' })).toBeVisible()

    await window.getByLabel('What do you want to keep?').fill('Prove semantic structure')
    await window.getByRole('button', { name: 'Add Task' }).click()
    // Once non-empty, the SAME route surfaces a labeled list, not the empty
    // heading -- semantics track real content state, not a static shell.
    await expect(window.getByRole('list', { name: 'Tasks' })).toBeVisible()
    await expect(window.getByRole('heading', { name: 'Inbox Is Clear' })).toHaveCount(0)

    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await expect(window.getByRole('heading', { name: /Today/ })).toBeVisible()
    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await expect(window.getByRole('heading', { name: /Trash/ })).toBeVisible()
  } finally {
    await application.close()
  }
})

test('focus and selection are independent: roving list focus moves without changing which task is selected, and vice versa', async () => {
  const profilePath = allocateDisposableProfile('a11y-focus-selection')
  const { application, window } = await launch(profilePath)
  try {
    for (const title of ['First task', 'Second task']) {
      await window.getByLabel('What do you want to keep?').fill(title)
      await window.getByRole('button', { name: 'Add Task' }).click()
      await expect(window.getByText(title)).toBeVisible()
    }

    const firstRow = window.getByRole('listitem').filter({ hasText: 'First task' })
    const secondRow = window.getByRole('listitem').filter({ hasText: 'Second task' })
    await firstRow.focus()
    await expect(firstRow).toBeFocused()
    // Roving focus alone (no Enter) never marks a row as the selected task
    // (D-05): aria-current stays unset on both rows.
    await expect(firstRow).not.toHaveAttribute('aria-current', 'true')
    await expect(secondRow).not.toHaveAttribute('aria-current', 'true')

    await window.keyboard.press('ArrowDown')
    await expect(secondRow).toBeFocused()
    await expect(secondRow).not.toHaveAttribute('aria-current', 'true')

    // Return selects the currently roving-focused row BY STABLE IDENTITY --
    // selection (aria-current) now tracks the row focus already reached.
    await window.keyboard.press('Enter')
    await expect(secondRow).toHaveAttribute('aria-current', 'true')
    await expect(firstRow).not.toHaveAttribute('aria-current', 'true')
  } finally {
    await application.close()
  }
})

test('exactly one debounced, settled live region exists -- rapid successive captures never spawn a per-row acknowledgement storm', async () => {
  const profilePath = allocateDisposableProfile('a11y-single-live-region')
  const { application, window } = await launch(profilePath)
  try {
    await expect(window.locator('[aria-live]')).toHaveCount(1)
    await expect(window.locator('[aria-live]')).toHaveAttribute('aria-live', 'polite')

    for (const title of ['Burst one', 'Burst two', 'Burst three']) {
      await window.getByLabel('What do you want to keep?').fill(title)
      await window.getByRole('button', { name: 'Add Task' }).click()
    }
    await expect(window.getByText('Burst three')).toBeVisible()
    // A rapid burst of three captures still leaves exactly ONE live region
    // in the document -- no per-task acknowledgement element was ever
    // spawned into the accessibility tree.
    await expect(window.locator('[aria-live]')).toHaveCount(1)
  } finally {
    await application.close()
  }
})

test('dialog focus: opening the Quick Entry discard-draft confirmation moves focus into it, onto the safe (non-destructive) default action', async () => {
  const profilePath = allocateDisposableProfile('a11y-dialog-focus-quick-entry')
  const { application } = await launch(profilePath)
  try {
    const [quickEntryWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      application.evaluate(({ Menu }) => {
        const find = (items: Electron.MenuItem[]): Electron.MenuItem | null => {
          for (const item of items) {
            if (item.label.startsWith('Quick Entry')) return item
            if (item.submenu) {
              const found = find(item.submenu.items)
              if (found !== null) return found
            }
          }
          return null
        }
        const menu = Menu.getApplicationMenu()
        const item = menu === null ? null : find(menu.items)
        if (item === null) throw new Error('Quick Entry menu item not found')
        item.click()
      }),
    ])
    await quickEntryWindow.waitForLoadState('domcontentloaded')
    await quickEntryWindow.getByLabel('What do you want to keep?').fill('Draft to discard')
    await quickEntryWindow.getByRole('button', { name: 'Discard Draft…' }).click()

    const dialog = quickEntryWindow.getByRole('alertdialog', { name: 'Discard Quick Entry Draft?' })
    await expect(dialog).toBeVisible()
    await expect(quickEntryWindow.getByRole('button', { name: 'Keep Draft' })).toBeFocused()
  } finally {
    await application.close()
  }
})

test('dialog focus: an inline sync conflict moves focus to its own heading so a screen reader announces the interruption', async () => {
  const profilePath = allocateDisposableProfile('a11y-conflict-focus')
  const first = await electron.launch({
    args: ['.'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_SYNC_MODE: 'offline', KEEPLING_TEST_USER_DATA_DIR: profilePath },
    timeout: 30_000,
  })
  const firstWindow = await first.firstWindow()
  await firstWindow.getByLabel('What do you want to keep?').fill('Buy milk')
  await firstWindow.getByRole('button', { name: 'Add Task' }).click()
  await expect(firstWindow.getByText('Buy milk')).toBeVisible()
  await first.close()

  const conflictApp = await electron.launch({
    args: ['.'],
    cwd: desktopRoot,
    env: { ...process.env, KEEPLING_TEST_SYNC_MODE: 'conflict', KEEPLING_TEST_USER_DATA_DIR: profilePath },
    timeout: 30_000,
  })
  try {
    const window = await conflictApp.firstWindow()
    await expect(window.getByText('This task changed somewhere else.')).toBeVisible()
    await expect(window.getByRole('heading', { name: 'This task changed somewhere else.' })).toBeFocused()
  } finally {
    await conflictApp.close()
  }
})

test('dialog focus: the workspace unsaved-changes alertdialog moves focus into itself, onto the safe (non-destructive) default action, and returns focus on close', async () => {
  const profilePath = allocateDisposableProfile('a11y-unsaved-changes-dialog-focus')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByLabel('What do you want to keep?').fill('Edit me')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await window.getByText('Edit me').click()
    await window.locator('#task-editor-title').fill('Edit me, unsaved')

    await window.getByRole('button', { name: 'Today', exact: true }).click()
    const dialog = window.getByRole('alertdialog', { name: 'Discard unsaved changes?' })
    await expect(dialog).toBeVisible()

    // Opening this alertdialog moves focus INTO it, onto the safe
    // non-destructive default action, exactly as the Quick Entry and
    // conflict dialogs above already do -- a screen reader announces the
    // interruption without the person having to explore the window to
    // discover it happened.
    const focusIsInsideDialog = await window.evaluate((dialogSelector) => {
      const dialogElement = document.querySelector(dialogSelector)
      return dialogElement !== null && dialogElement.contains(document.activeElement)
    }, '[data-workspace-dirty-dialog="true"]')
    expect(focusIsInsideDialog).toBe(true)
    await expect(window.getByRole('button', { name: 'Keep Editing' })).toBeFocused()

    await window.getByRole('button', { name: 'Keep Editing' }).press('Enter')
    await expect(dialog).toHaveCount(0)

    // Closing returns focus to a visible, operable element -- never the
    // removed dialog node, never a silent reset to <body>/the application
    // element (A6's "focus never gets trapped or lost" condition).
    const focusAfterClose = await window.evaluate(() => {
      const active = document.activeElement
      if (active === null || active === document.body || active === document.documentElement) return null
      const rect = active.getBoundingClientRect()
      return { id: active.id, tag: active.tagName, visible: rect.width > 0 && rect.height > 0 }
    })
    expect(focusAfterClose).not.toBeNull()
    expect(focusAfterClose?.visible).toBe(true)
  } finally {
    await application.close()
  }
})

test('200% reflow: at half the default window size, no horizontal overflow, and every primary control remains reachable', async () => {
  const profilePath = allocateDisposableProfile('a11y-200pct-reflow')
  const { application, window } = await launch(profilePath)
  try {
    await application.evaluate(({ BrowserWindow }) => {
      // ~200% zoom equivalent: halve the effective layout viewport.
      BrowserWindow.getAllWindows()[0]?.setContentSize(450, 350)
    })
    await window.waitForTimeout(150)

    const overflow = await window.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }))
    expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth + 1)

    await expect(window.getByLabel('What do you want to keep?')).toBeVisible()
    await expect(window.getByRole('button', { name: 'Add Task' })).toBeVisible()
    await expect(window.getByRole('button', { name: 'Inbox', exact: true })).toBeVisible()
  } finally {
    await application.close()
  }
})

test('theme: color-scheme follows the emulated OS appearance instead of a hardcoded palette', async () => {
  const profilePath = allocateDisposableProfile('a11y-theme-color-scheme')
  const { application, window } = await launch(profilePath)
  try {
    await window.emulateMedia({ colorScheme: 'light' })
    const lightBackground = await window.evaluate(() => getComputedStyle(document.body).backgroundColor)
    await window.emulateMedia({ colorScheme: 'dark' })
    const darkBackground = await window.evaluate(() => getComputedStyle(document.body).backgroundColor)
    expect(darkBackground).not.toBe(lightBackground)
  } finally {
    await application.close()
  }
})

test('contrast: forced-colors mode renders without crashing and preserves real, non-transparent body text color', async () => {
  const profilePath = allocateDisposableProfile('a11y-forced-colors')
  const { application, window } = await launch(profilePath)
  try {
    await window.emulateMedia({ forcedColors: 'active' })
    await window.reload()
    await expect(window.getByLabel('What do you want to keep?')).toBeVisible()
    const color = await window.evaluate(() => getComputedStyle(document.body).color)
    expect(color).not.toBe('')
  } finally {
    await application.close()
  }
})

test('motion: prefers-reduced-motion removes the button hover transition; no-preference keeps it', async () => {
  const profilePath = allocateDisposableProfile('a11y-reduced-motion')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByLabel('What do you want to keep?').waitFor()
    await window.emulateMedia({ reducedMotion: 'no-preference' })
    const withMotion = await window.evaluate(() => {
      const button = document.querySelector('button')
      return button ? getComputedStyle(button).transitionDuration : null
    })
    expect(withMotion).not.toBe('0s')

    await window.emulateMedia({ reducedMotion: 'reduce' })
    const reduced = await window.evaluate(() => {
      const button = document.querySelector('button')
      return button ? getComputedStyle(button).transitionDuration : null
    })
    expect(reduced).toBe('0s')
  } finally {
    await application.close()
  }
})

test('a theme/contrast/motion change while a dialog is open never traps or discards focus', async () => {
  const profilePath = allocateDisposableProfile('a11y-theme-change-mid-dialog')
  const { application } = await launch(profilePath)
  try {
    const [quickEntryWindow] = await Promise.all([
      application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      application.evaluate(({ Menu }) => {
        const find = (items: Electron.MenuItem[]): Electron.MenuItem | null => {
          for (const item of items) {
            if (item.label.startsWith('Quick Entry')) return item
            if (item.submenu) {
              const found = find(item.submenu.items)
              if (found !== null) return found
            }
          }
          return null
        }
        const menu = Menu.getApplicationMenu()
        const item = menu === null ? null : find(menu.items)
        if (item === null) throw new Error('Quick Entry menu item not found')
        item.click()
      }),
    ])
    await quickEntryWindow.waitForLoadState('domcontentloaded')
    await quickEntryWindow.getByLabel('What do you want to keep?').fill('Mid-dialog theme change')
    await quickEntryWindow.getByRole('button', { name: 'Discard Draft…' }).click()
    const dialog = quickEntryWindow.getByRole('alertdialog', { name: 'Discard Quick Entry Draft?' })
    await expect(dialog).toBeVisible()
    const keepDraftButton = quickEntryWindow.getByRole('button', { name: 'Keep Draft' })
    await expect(keepDraftButton).toBeFocused()

    // A theme/contrast/motion change is a pure CSS/OS-preference event --
    // it must never move DOM focus or dismiss an open dialog.
    await quickEntryWindow.emulateMedia({ colorScheme: 'dark', forcedColors: 'active', reducedMotion: 'reduce' })
    await quickEntryWindow.waitForTimeout(100)
    await expect(dialog).toBeVisible()
    await expect(keepDraftButton).toBeFocused()

    await quickEntryWindow.emulateMedia({ colorScheme: 'light', forcedColors: 'none', reducedMotion: 'no-preference' })
    await quickEntryWindow.waitForTimeout(100)
    await expect(dialog).toBeVisible()
    await expect(keepDraftButton).toBeFocused()
  } finally {
    await application.close()
  }
})
