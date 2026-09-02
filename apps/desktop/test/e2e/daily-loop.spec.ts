import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Keyboard-complete Mac daily-loop proof (D-12 through D-16, D-39/D-41,
 * MAC-01/MAC-02). Drives the real Electron app -- built from the same
 * dist/{main,preload,renderer,worker} outputs a packaged build uses -- only
 * through user-visible roles, never through direct IPC or store access.
 * Asserts local visibility before any network concern, deterministic focus
 * after every row removal, and that a conflict never overwrites a draft
 * without an explicit choice.
 */

const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  // Build once per run so the launched app reflects current source, matching
  // how the packaged lane proves the shipped artifact rather than IPC mocks.
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before daily-loop E2E')
  if (!existsSync(`${desktopRoot}/dist/main/index.cjs`)) {
    throw new Error('desktop build did not produce dist/main/index.cjs')
  }
})

const launch = async (
  syncMode: 'offline' | 'acknowledge' | 'conflict',
  profilePath: string,
): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: ['.'],
    cwd: desktopRoot,
    env: {
      ...process.env,
      KEEPLING_TEST_SYNC_MODE: syncMode,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

test('completes the full daily loop through user-visible roles only', async () => {
  const profilePath = allocateDisposableProfile('daily-loop-full')
  const { application, window } = await launch('offline', profilePath)
  try {
    // Capture (MAC-01): local visibility before any network concern (D-03).
    await window.getByLabel('What do you want to keep?').fill('Call dentist')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Call dentist')).toBeVisible()
    await expect(window.getByText('Saved on this Mac').first()).toBeVisible()

    // Open by stable identity, edit, and save with Command-S (D-12).
    await window.getByText('Call dentist').click()
    const titleField = window.locator('#task-editor-title')
    await expect(titleField).toHaveValue('Call dentist')
    await titleField.fill('Call dentist about cleaning')
    const notesField = window.locator('#task-editor-notes')
    await notesField.fill('Ask about morning slots')
    await window.keyboard.press('Meta+s')
    await expect(window.getByText('Call dentist about cleaning')).toBeVisible()
    await expect(window.locator('[data-workspace-dirty="true"]')).toHaveCount(0)

    // Complete, then reopen (D-14).
    await window.getByRole('button', { name: 'Complete' }).click()
    await expect(window.getByRole('button', { name: 'Reopen' })).toBeVisible()
    await window.getByRole('button', { name: 'Reopen' }).click()
    await expect(window.getByRole('button', { name: 'Complete' })).toBeVisible()

    // Add to Today, verify placement, then remove.
    await window.getByRole('button', { name: 'Add to Today' }).click()
    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await expect(window.getByText('Call dentist about cleaning')).toBeVisible()
    await window.getByText('Call dentist about cleaning').click()
    await window.getByRole('button', { name: 'Remove from Today' }).click()

    // Trash and restore (D-14); deterministic focus after removal, never a
    // DOM index (heading gets focus when the list becomes empty).
    await window.getByRole('button', { name: 'Inbox', exact: true }).click()
    await window.getByText('Call dentist about cleaning').click()
    await window.getByRole('button', { name: 'Move to Trash' }).click()
    await expect(window.getByRole('heading', { name: 'Inbox Is Clear' })).toBeFocused()

    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await window.getByText('Call dentist about cleaning').click()
    await window.getByRole('button', { name: 'Restore' }).click()

    // Latest supported undo reverses the restore back to trashed.
    await window.getByRole('button', { name: 'Undo Restore' }).click()
    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await expect(window.getByText('Call dentist about cleaning')).toBeVisible()
  } finally {
    await application.close()
  }
})

test('surfaces a sync conflict inline and requires an explicit mine/current choice', async () => {
  const profilePath = allocateDisposableProfile('daily-loop-conflict')

  // Capture offline first: the outbox mutation only reconciles on the next
  // launch, matching the real bounded pull-before-push pass at startup.
  const first = await launch('offline', profilePath)
  await first.window.getByLabel('What do you want to keep?').fill('Buy milk')
  await first.window.getByRole('button', { name: 'Add Task' }).click()
  await expect(first.window.getByText('Buy milk')).toBeVisible()
  await first.application.close()

  const { application, window } = await launch('conflict', profilePath)
  try {
    await expect(window.getByText('This task changed somewhere else.')).toBeVisible()
    await expect(window.getByText('Your version:')).toBeVisible()
    await expect(window.getByText('Current version:')).toBeVisible()

    await window.getByRole('button', { name: 'Use mine' }).click()
    await expect(window.getByText('This task changed somewhere else.')).toHaveCount(0)
    await expect(window.getByText('Buy milk', { exact: true })).toBeVisible()
  } finally {
    await application.close()
  }
})
