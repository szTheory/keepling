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
    // Scoped to the detail heading, not a bare getByText: the list row now
    // also re-renders with the saved title while the editor stays open, so
    // an unscoped getByText matches both simultaneously (strict-mode
    // violation) once list-refresh and editor-save land in the same tick.
    await expect(window.getByRole('heading', { name: 'Call dentist about cleaning' })).toBeVisible()
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

    // O-45. This step USED to assert that undo reversed the restore. It no
    // longer can, and the change is deliberate rather than a regression that
    // slipped through.
    //
    // `POST /commands/undo-task` takes a SERVER-ISSUED handle. This profile
    // runs with `KEEPLING_TEST_SYNC_MODE=offline`, so no acknowledgement ever
    // arrives, so no handle was ever issued for the restore. The old
    // behaviour reversed the projection and enqueued nothing -- an undo
    // durable on this Mac and invisible to the server forever, which is
    // exactly the defect O-45 filed. Refusing is the honest answer, and the
    // person is TOLD rather than left with a silently-diverged Mac.
    //
    // The COST is real and is recorded rather than hidden: on a Mac with no
    // server configured, no mutation is ever acknowledged, so undo is
    // unavailable there entirely. The successful path is proved in the test
    // below and, against real Phoenix, in the real-stack lane.
    const refusal = 'This change hasn’t reached the server yet, so it can’t be undone. Nothing was changed.'
    await window.getByRole('button', { name: 'Undo Restore' }).click()
    // Both surfaces a person might be looking at say the SAME thing: the
    // main-owned status row and the recovery strip's live region. Being told
    // two different stories about one refusal would be worse than silence.
    await expect(window.locator('#sync-status-row [data-sync-copy]')).toHaveText(refusal)
    await expect(window.locator('#sync-status-row')).toHaveAttribute('data-sync-status', 'undo_unavailable')
    await expect(window.getByLabel('Latest recovery action').getByText(refusal)).toBeVisible()
    // Nothing was changed: the task is still restored, not back in Trash.
    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await expect(window.getByText('Call dentist about cleaning')).toHaveCount(0)
  } finally {
    await application.close()
  }
})

/**
 * O-45: the undo that DOES reconcile, through the shipped window.
 *
 * The revert on screen is itself the proof that the durable undo command was
 * enqueued: `NodeSqliteLocalStore#undoLastLocalAction` refuses to touch the
 * projection at all unless it is handed an undo command, and the projection
 * revert and the outbox insert share one transaction. So a reverted row
 * cannot exist without a queued `undo_task`.
 *
 * `KEEPLING_TEST_SYNC_MODE=acknowledge` plays a server that accepts and
 * issues a compensation capability, which is what a real server does
 * (`CommandStore#issue_undo`). That the capability is a fixture here is the
 * whole reason the real-stack lane exists and forbids this mode.
 */
test('undo reconciles once the server has issued a compensation capability', async () => {
  const profilePath = allocateDisposableProfile('daily-loop-undo')
  const { application, window } = await launch('acknowledge', profilePath)
  try {
    await window.getByLabel('What do you want to keep?').fill('Book the ferry')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Book the ferry')).toBeVisible()

    await window.getByText('Book the ferry').click()
    await window.getByRole('button', { name: 'Complete' }).click()
    await expect(window.getByRole('button', { name: 'Reopen' })).toBeVisible()

    // The acknowledgement carrying the handle arrives on a synchronization
    // pass, so this waits for the capability rather than sleeping and hoping.
    await expect
      .poll(
        async () => {
          await window.getByRole('button', { name: 'Undo Complete' }).click()
          return window.getByRole('button', { name: 'Complete' }).count()
        },
        { intervals: [500], timeout: 60_000 },
      )
      .toBe(1)
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
