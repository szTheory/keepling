import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { readdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { allocateDisposableProfile } from '../../playwright.config.ts'

/**
 * Shipped-entry-point proof for every gap this plan (03-13, GAP-1) closes:
 * O-15 (credential adapter wired into bootstrap), O-12 (removeLocalData
 * reachable end to end), and O-11 (D-06 renderer-semantic restoration).
 * O-1 is a recorded decision, not a behavior -- see
 * `apps/web/src/app/WorkspaceShell.tsx` and this plan's SUMMARY.
 *
 * EVERY test in this file launches the REAL SHIPPED entry point
 * (`electron.launch({ args: ['.'] })`, i.e. `dist/main/index.cjs` via
 * `package.json#main`) against the REAL `main/index.ts#bootstrap()` --
 * never `test/fixtures/wired-app-harness.ts`. This is the exact pattern
 * `test/e2e/lifecycle.spec.ts` already established closing O-9.
 */

const desktopRoot = fileURLToPath(new URL('../../', import.meta.url))

test.beforeAll(() => {
  const result = spawnSync('pnpm', ['run', 'build'], { cwd: desktopRoot, stdio: 'inherit' })
  if (result.status !== 0) throw new Error('desktop build failed before gap-closure E2E')
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

const captureTask = async (window: Page, title: string): Promise<void> => {
  await window.getByLabel('What do you want to keep?').fill(title)
  await window.getByRole('button', { name: 'Add Task' }).click()
  await expect(window.getByText(title)).toBeVisible()
}

test.describe('O-15: bootstrap() constructs the real SafeStorageCredentialAdapter, not a no-op', () => {
  test('a stored credential is real safeStorage ciphertext on disk, and sign-out clears it -- proven against the ADAPTER bootstrap() actually wired in', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o15')
    // O-15 evidence requires the test-only introspection seam added
    // directly to the real `bootstrap()` (gated behind this env var, never
    // active otherwise -- see main/index.ts). No __testHarness reference
    // entry point is used.
    const { application } = await launch(profilePath, { KEEPLING_TEST_EXPOSE_INTERNALS: '1' })
    try {
      const credentialPath = join(profilePath, 'credential.enc')
      expect(existsSync(credentialPath)).toBe(false)

      // Proves the object bootstrap() constructed IS the real adapter class
      // (not e.g. a plain object shaped like one).
      const constructorName = await application.evaluate(() => {
        const globalScope = globalThis as unknown as { __keeplingTestCredentials?: { constructor: { name: string } } }
        return globalScope.__keeplingTestCredentials?.constructor.name ?? null
      })
      expect(constructorName).toBe('SafeStorageCredentialAdapter')

      // Store a credential through the REAL adapter bootstrap() wired into
      // DesktopApplication -- the exact instance, not a mock.
      await application.evaluate(async () => {
        const globalScope = globalThis as unknown as { __keeplingTestCredentials?: { store: (value: string) => Promise<void> } }
        await globalScope.__keeplingTestCredentials?.store('super-secret-refresh-token-value')
      })

      expect(existsSync(credentialPath)).toBe(true)
      const onDisk = readFileSync(credentialPath)
      // Real safeStorage ciphertext, never the plaintext value (privacy;
      // this is what distinguishes "adapter is wired" from "adapter is
      // dead code" -- a dead adapter could never produce this file at all).
      expect(onDisk.length).toBeGreaterThan(0)
      expect(onDisk.toString('utf8')).not.toContain('super-secret-refresh-token-value')

      // Sign-out (D-23) fences local intent and clears credentials BEFORE
      // best-effort remote revocation -- exercised here through the SAME
      // wired DesktopApplication instance, proving the credential clear
      // path is not merely unit-tested but actually reachable from the
      // object bootstrap() built.
      await application.evaluate(async () => {
        const globalScope = globalThis as unknown as {
          __keeplingTestDesktopApplication?: { signOut: (revoke: () => Promise<void>) => Promise<void> }
        }
        await globalScope.__keeplingTestDesktopApplication?.signOut(async () => {})
      })

      expect(existsSync(credentialPath)).toBe(false)
    } finally {
      await application.close()
    }
  })

  test('KEEPLING_TEST_EXPOSE_INTERNALS is OFF by default -- no test-only global leaks into an ordinary launch', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o15-off')
    const { application } = await launch(profilePath)
    try {
      const exposed = await application.evaluate(() =>
        Object.prototype.hasOwnProperty.call(globalThis, '__keeplingTestCredentials'),
      )
      expect(exposed).toBe(false)
    } finally {
      await application.close()
    }
  })
})

test.describe('O-12: removeLocalData is reachable end to end and stays structurally unable to reach the server', () => {
  test('the second confirmation fence blocks local-only intent, then a confirmed removal actually deletes the local store files', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o12')
    const { application, window } = await launch(profilePath)
    try {
      await captureTask(window, 'Local-only pending task')

      // First call WITHOUT the second confirmation: a pending local
      // mutation exists (offline sync mode never acknowledges), so this
      // MUST refuse and report bounded counts -- reachable through the
      // named preload contract exactly as a real renderer script would
      // call it (window.keepling is the real contextBridge-exposed API).
      const blocked = await window.evaluate(() => window.keepling.removeLocalData({ confirmRemoveAnyway: false }))
      expect(blocked).toMatchObject({ kind: 'blocked_pending_intent' })
      expect((blocked as { pendingCount: number }).pendingCount).toBeGreaterThanOrEqual(1)

      // The local store files must still be present -- refusal had no
      // effect.
      const beforeRemoval = await readdir(profilePath)
      expect(beforeRemoval.some((entry) => entry.startsWith('namespace.sqlite3'))).toBe(true)

      // Second call WITH the exact confirmation actually removes.
      const removed = await window.evaluate(() => window.keepling.removeLocalData({ confirmRemoveAnyway: true }))
      expect(removed).toEqual({ kind: 'removed' })

      const afterRemoval = await readdir(profilePath)
      expect(afterRemoval.some((entry) => entry.startsWith('namespace.sqlite3'))).toBe(false)
    } finally {
      await application.close()
    }
  })

  test('a hostile extra field on the real preload bridge is rejected before it ever reaches main -- no privileged effect', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o12-hostile')
    const { application, window } = await launch(profilePath)
    try {
      const rejected = await window.evaluate(async () => {
        try {
          // Deliberately hostile: a sync/network-shaped extra field the
          // strict schema must reject (request is typed `unknown`).
          await window.keepling.removeLocalData({ confirmRemoveAnyway: true, syncFirst: true })
          return false
        } catch {
          return true
        }
      })
      expect(rejected).toBe(true)

      // The local store MUST still be intact -- the rejected call had no
      // privileged effect at all, not merely "an error was thrown".
      const entries = await readdir(profilePath)
      expect(entries.some((entry) => entry.startsWith('namespace.sqlite3'))).toBe(true)
    } finally {
      await application.close()
    }
  })
})

test.describe('O-11: D-06 renderer-semantic restoration survives a real relaunch', () => {
  test('destination, surviving selection, and a recoverable (unsaved) draft all restore after closing and reopening the same profile', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o11-restore')
    const first = await launch(profilePath)
    try {
      await captureTask(first.window, 'Restore Target Task')
      await captureTask(first.window, 'Other Task')

      await first.window.getByText('Restore Target Task').click()
      await expect(first.window.locator('#workspace-detail-title')).toHaveText('Restore Target Task')

      // A recoverable draft (D-03: no durability claim) -- edited but never
      // saved.
      const notesField = first.window.locator('#task-editor-notes')
      await notesField.fill('unsaved recovered draft text')
      await expect(first.window.locator('[data-workspace-dirty="true"]')).toBeVisible()

      // Give the fire-and-forget persist IPC call a moment to land on disk
      // before the relaunch -- this is UI-convenience persistence (D-03/
      // D-21), not a durability boundary, so a bounded wait here is
      // appropriate (mirrors createFileWindowStatePort's own contract).
      await first.window.waitForTimeout(500)
    } finally {
      await first.application.close()
    }

    const second = await launch(profilePath)
    try {
      // Destination + surviving selection restored.
      await expect(second.window.locator('#workspace-detail-title')).toHaveText('Restore Target Task')
      // The recoverable draft restored -- and still shows as UNSAVED, never
      // silently promoted to a durability claim.
      await expect(second.window.locator('#task-editor-notes')).toHaveValue('unsaved recovered draft text')
      await expect(second.window.locator('[data-workspace-dirty="true"]')).toBeVisible()
    } finally {
      await second.application.close()
    }
  })

  test('a selection that no longer exists at relaunch degrades safely -- never restores a dangling selection', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o11-dangling')
    const first = await launch(profilePath)
    try {
      await captureTask(first.window, 'Trashed Before Relaunch')
      await first.window.getByText('Trashed Before Relaunch').click()
      await expect(first.window.locator('#workspace-detail-title')).toHaveText('Trashed Before Relaunch')
      await first.window.getByRole('button', { name: 'Move to Trash' }).click()
      // Trashing removes the task from the Inbox route view -- Workspace's
      // own existing safety effect already clears the dangling selection
      // client-side; confirm the detail pane reflects that before closing.
      await expect(first.window.getByText('Choose a Task')).toBeVisible()
      await first.window.waitForTimeout(500)
    } finally {
      await first.application.close()
    }

    const second = await launch(profilePath)
    try {
      // No selection restores -- the detail pane shows the empty state,
      // never a dangling reference to the trashed task.
      await expect(second.window.getByText('Choose a Task')).toBeVisible()
    } finally {
      await second.application.close()
    }
  })
})
