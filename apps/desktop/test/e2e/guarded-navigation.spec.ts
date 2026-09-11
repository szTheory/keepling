import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Task 3 (O-22) proof: every keyboard navigation command in
 * `DesktopShell.tsx` that would change route or selected task
 * (`new-task`/Cmd-N, `go-inbox`/Cmd-1, `go-today`/Cmd-2) must go through the
 * SAME dirty-state guard `Workspace.tsx`'s `attemptNavigation` already
 * applies to mouse navigation, instead of calling
 * `facade.setRoute`/`facade.selectTask` directly. This file drives the real
 * shipped Electron app (built from the same dist/{main,preload,renderer,
 * worker} outputs a packaged build uses), never IPC/store internals
 * directly, matching the launch pattern already established by
 * `accessibility.spec.ts`/`daily-loop.spec.ts`.
 */
const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before guarded-navigation E2E')
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

/** Captures a task, opens it, and edits its title WITHOUT saving -- a dirty editor. */
const makeDirty = async (window: Page, title: string) => {
  await window.getByLabel('What do you want to keep?').fill(title)
  await window.getByRole('button', { name: 'Add Task' }).click()
  await expect(window.getByText(title)).toBeVisible()
  await window.getByText(title).click()
  const titleField = window.locator('#task-editor-title')
  await expect(titleField).toHaveValue(title)
  await titleField.fill(`${title}, unsaved`)
  return titleField
}

const dialog = (window: Page) => window.getByRole('alertdialog', { name: 'Discard unsaved changes?' })

test('clean editor: Cmd-1, Cmd-2, and Cmd-N navigate immediately with no dialog', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-clean')
  const { application, window } = await launch(profilePath)
  try {
    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await expect(window.getByRole('heading', { name: 'Nothing Planned for Today' })).toBeVisible()

    await window.keyboard.press('Meta+1')
    await expect(dialog(window)).toHaveCount(0)
    await expect(window.getByLabel('What do you want to keep?')).toBeVisible()

    await window.keyboard.press('Meta+2')
    await expect(dialog(window)).toHaveCount(0)
    await expect(window.getByRole('heading', { name: 'Nothing Planned for Today' })).toBeVisible()

    await window.keyboard.press('Meta+n')
    await expect(dialog(window)).toHaveCount(0)
    await expect(window.getByLabel('What do you want to keep?')).toBeFocused()
  } finally {
    await application.close()
  }
})

test('dirty editor: Cmd-N opens the discard dialog instead of navigating', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-dirty-new-task')
  const { application, window } = await launch(profilePath)
  try {
    await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+n')
    await expect(dialog(window)).toBeVisible()
  } finally {
    await application.close()
  }
})

test('dirty editor: Cmd-1 (go-inbox) opens the discard dialog instead of navigating', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-dirty-go-inbox')
  const { application, window } = await launch(profilePath)
  try {
    await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+1')
    await expect(dialog(window)).toBeVisible()
  } finally {
    await application.close()
  }
})

test('dirty editor: Cmd-2 (go-today) opens the discard dialog instead of navigating', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-dirty-go-today')
  const { application, window } = await launch(profilePath)
  try {
    await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+2')
    await expect(dialog(window)).toBeVisible()
  } finally {
    await application.close()
  }
})

test('keyboard-initiated Keep Editing cancels navigation, matching the mouse-initiated outcome', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-keep-editing')
  const { application, window } = await launch(profilePath)
  try {
    const titleField = await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+2')
    await expect(dialog(window)).toBeVisible()

    await window.getByRole('button', { name: 'Keep Editing' }).click()
    await expect(dialog(window)).toHaveCount(0)
    // Navigation was abandoned -- the dirty draft and the Inbox route are
    // both exactly as they were before the keystroke, the same outcome the
    // mouse-driven "Discard unsaved changes?" Keep Editing path already
    // proves (accessibility.spec.ts "dialog focus" case).
    await expect(titleField).toHaveValue('Call dentist, unsaved')
    await expect(window.getByRole('heading', { name: 'Call dentist' })).toBeVisible()
  } finally {
    await application.close()
  }
})

test('keyboard-initiated Discard Changes discards and completes navigation, matching the mouse-initiated outcome', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-discard')
  const { application, window } = await launch(profilePath)
  try {
    await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+2')
    await expect(dialog(window)).toBeVisible()

    await window.getByRole('button', { name: 'Discard Changes' }).click()
    await expect(dialog(window)).toHaveCount(0)
    // The originally-requested navigation (go-today) completed after the
    // dialog resolved, and the unsaved edit was discarded -- exactly what
    // the existing mouse-driven Discard Changes path already does.
    await expect(window.getByRole('heading', { name: 'Nothing Planned for Today' })).toBeVisible()
  } finally {
    await application.close()
  }
})

test('keyboard-initiated Save Changes saves and completes navigation, matching the mouse-initiated outcome', async () => {
  const profilePath = allocateDisposableProfile('guarded-nav-save')
  const { application, window } = await launch(profilePath)
  try {
    await makeDirty(window, 'Call dentist')
    await window.keyboard.press('Meta+1')
    const openDialog = dialog(window)
    await expect(openDialog).toBeVisible()

    await openDialog.getByRole('button', { name: 'Save Changes' }).click()
    await expect(dialog(window)).toHaveCount(0)
    // The edit was saved (not lost) AND the originally-requested navigation
    // (go-inbox) completed -- exactly what the existing mouse-driven Save
    // Changes path already does.
    await expect(window.getByText('Call dentist, unsaved')).toBeVisible()
    await expect(window.getByLabel('What do you want to keep?')).toBeVisible()
  } finally {
    await application.close()
  }
})
