import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
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

    // O-51 / D-52. Undo of a mutation the server never received.
    //
    // 03-23 made every undo require a SERVER-ISSUED handle, which is right
    // for a mutation the server has acknowledged and wrong for one it has
    // never seen: this profile has no reachable server, so nothing is ever
    // acknowledged, no handle ever exists, and Command-Z was dead -- while
    // MAC-01 names undo as a supported Mac operation.
    //
    // What makes the local undo safe is NOT "the command is still in the
    // outbox". A row sits there unchanged while its POST is in flight. It
    // is the transmission state migration 0002 added: the restore command
    // is `queued`, meaning its bytes were never handed to the transport, so
    // dropping it cannot leave the server holding something this Mac
    // deleted. The refusal path is still proved -- against a command that
    // HAS been transmitted -- in the real-stack lane, which is the only
    // place a real transmission happens.
    await window.getByRole('button', { name: 'Undo Restore' }).click()
    // The undo took effect: the task is back in Trash, where the restore
    // had taken it from.
    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await expect(window.getByText('Call dentist about cleaning')).toBeVisible()
    // And nothing claims a refusal happened.
    await expect(window.locator('#sync-status-row')).not.toHaveAttribute('data-sync-status', 'undo_unavailable')
    await window.getByRole('button', { name: 'Inbox', exact: true }).click()
  } finally {
    await application.close()
  }
})

/**
 * How many SERVER-issued undo capabilities this profile has retained, and
 * what its outbox holds -- read out of the app's own SQLite file, read-only.
 * The same idiom the real-stack lane uses: wait for a durable fact, never
 * for a duration (O-24/O-32).
 */
const readStore = (profilePath: string): { handles: number; queuedTypes: string[] } => {
  const path = join(profilePath, 'namespace.sqlite3')
  if (!existsSync(path)) return { handles: 0, queuedTypes: [] }
  const database = new DatabaseSync(path, { readOnly: true })
  try {
    const handles = database
      .prepare(`SELECT COUNT(*) AS total FROM namespace_metadata WHERE key LIKE 'undo_handle:%'`)
      .get() as { total: number }
    const queued = database
      .prepare(`SELECT immutable_commands.command_bytes AS bytes
                FROM outbox JOIN immutable_commands USING (mutation_id) ORDER BY outbox.sequence`)
      .all() as Array<{ bytes: string }>
    return {
      handles: handles.total,
      queuedTypes: queued.map(({ bytes }) => (JSON.parse(bytes) as { type: string }).type),
    }
  } finally {
    database.close()
  }
}

/**
 * O-45: the undo that DOES reconcile, through the shipped window.
 *
 * `KEEPLING_TEST_SYNC_MODE=acknowledge` plays a server that accepts and
 * issues a compensation capability, which is what a real server does
 * (`CommandStore#issue_undo`). That the capability is a fixture here is the
 * whole reason the real-stack lane exists and forbids this mode.
 *
 * TWO defects in the previous version of this test are fixed here rather
 * than worked around, both found in 03-24:
 *
 *  1. It polled `getByRole('button', { name: 'Complete' })`, and Playwright
 *     matches an accessible name by SUBSTRING unless told otherwise -- so
 *     the "Undo Complete" button it had just clicked satisfied the
 *     assertion. The test could not fail. Every locator below is `exact`.
 *  2. It expected the handle to arrive during the session, but in this mode
 *     no synchronization pass ever runs after bootstrap
 *     (`scheduleSyncPass` returns immediately with no configured adapter),
 *     so no acknowledgement -- and no capability -- could arrive at all.
 *     The completion is now acknowledged by the bootstrap reconcile of a
 *     RELAUNCH, which is the same shape the conflict test below uses.
 *
 * Since 03-24 the wait for the handle is also what keeps this test about
 * the handle. An undo pressed before an acknowledgement lands is now a
 * legitimate local drop of a never-transmitted command (O-51/D-52), and
 * would reverse the completion with no server capability involved.
 */
test('undo reconciles once the server has issued a compensation capability', async () => {
  const profilePath = allocateDisposableProfile('daily-loop-undo')
  const first = await launch('acknowledge', profilePath)
  await first.window.getByLabel('What do you want to keep?').fill('Book the ferry')
  await first.window.getByRole('button', { name: 'Add Task' }).click()
  await expect(first.window.getByText('Book the ferry')).toBeVisible()
  await first.window.getByText('Book the ferry').click()
  await first.window.getByRole('button', { name: 'Complete', exact: true }).click()
  await expect(first.window.getByRole('button', { name: 'Reopen', exact: true })).toBeVisible()
  await first.application.close()

  // The relaunch's bootstrap reconcile is what asks the server about the
  // pending commands, so this is where the capability is issued and
  // retained.
  const { application, window } = await launch('acknowledge', profilePath)
  try {
    await expect.poll(() => readStore(profilePath).handles, { timeout: 60_000 }).toBeGreaterThan(0)
    // Nothing is queued any more: every command was settled, so a local
    // drop is impossible and the press below can only take the handle path.
    expect(readStore(profilePath).queuedTypes).toEqual([])

    // D-06 restores the previously selected task, so the relaunched window
    // already opens on the detail this undo acts from.
    await expect(window.getByRole('heading', { name: 'Book the ferry' })).toBeVisible()
    // Command-Z, not the "Undo Complete" button: that button is a
    // session-local affordance published when the action is performed, and
    // this action was performed in the PREVIOUS session. The keystroke is
    // what a person actually presses here, and it reaches the same
    // main-process undo through the renderer's keyboard map.
    await window.keyboard.press('Meta+z')
    await expect(window.getByRole('button', { name: 'Complete', exact: true })).toBeVisible({ timeout: 30_000 })
    // The revert is not local-only: a real compensation command is queued
    // for the server, carrying the capability the server itself issued.
    await expect.poll(() => readStore(profilePath).queuedTypes, { timeout: 30_000 }).toEqual(['undo_task'])
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

    await window.getByRole('radio', { name: 'Use mine' }).click()
    await window.getByRole('button', { name: 'Save resolution' }).click()
    await expect(window.getByText('This task changed somewhere else.')).toHaveCount(0)
    await expect(window.getByText('Buy milk', { exact: true })).toBeVisible()
  } finally {
    await application.close()
  }
})
