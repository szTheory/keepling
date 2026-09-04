import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import type { AddressInfo } from 'node:net'
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

/**
 * O-30 / MAC-04: shipped-entry-point proof that the `offline` row actually
 * reaches a person.
 *
 * O-20's lesson is that code exercised only by fixtures is not proven code,
 * so none of this uses `test/fixtures/wired-app-harness.ts`. Every case
 * below launches the REAL `dist/main/index.cjs`, lets the REAL `bootstrap()`
 * construct the REAL `KeeplingSyncAdapter` against a REAL server address
 * (`KEEPLING_TEST_SYNC_MODE` is deliberately NOT set, so the offline test
 * stub is out of the picture entirely), and reads the row off the REAL
 * rendered window -- the same pixels a user looks at.
 *
 * The narrow `KEEPLING_TEST_EXPOSE_INTERNALS` seam is used only to TRIGGER a
 * pass, which in ordinary use is triggered by a signed-in session's
 * scheduler. What the pass then does -- which HTTP call it makes, how the
 * failure is classified, which row is published, what the window shows -- is
 * entirely production code.
 */
const launchRealSync = async (
  profilePath: string,
): Promise<{ application: ElectronApplication; window: Page }> => {
  const env: Record<string, string> = {
    ...(process.env as Record<string, string>),
    KEEPLING_TEST_EXPOSE_INTERNALS: '1',
    KEEPLING_TEST_USER_DATA_DIR: profilePath,
  }
  // The real adapter, not the inline stub: `main/index.ts` selects the stub
  // whenever this variable is DEFINED, empty string included.
  delete env.KEEPLING_TEST_SYNC_MODE
  const application = await electron.launch({ args: ['.'], cwd: desktopRoot, env, timeout: 30_000 })
  const window = await application.firstWindow()
  return { application, window }
}

/** Seeds a signed-in session so a pass gets as far as the network. Uses the REAL credential adapter bootstrap() wired in. */
const seedCredentials = async (application: ElectronApplication, origin: string): Promise<void> => {
  await application.evaluate(async ({}, serverOrigin: string) => {
    const globalScope = globalThis as unknown as {
      __keeplingTestCredentials?: { store: (value: string) => Promise<void> }
    }
    await globalScope.__keeplingTestCredentials?.store(JSON.stringify({
      accessToken: 'seeded-access-token',
      namespace: {
        accountSubject: 'subject-offline-proof',
        generation: '1',
        issuer: serverOrigin,
        origin: serverOrigin,
        serverInstance: 'instance-offline-proof',
      },
      refreshToken: 'seeded-refresh-token',
    }))
  }, origin)
}

/** Runs one REAL synchronization pass and swallows its rejection, exactly as the shipped scheduler does. */
const runOneSyncPass = async (application: ElectronApplication): Promise<void> => {
  await application.evaluate(async () => {
    const globalScope = globalThis as unknown as {
      __keeplingTestDesktopApplication?: { runSyncPass: () => Promise<unknown> }
    }
    await globalScope.__keeplingTestDesktopApplication?.runSyncPass().catch(() => undefined)
  })
}

const OFFLINE_COPY = 'Offline — showing tasks saved on this Mac'
const RETRYABLE_COPY = 'Couldn’t reach the server. Your changes stay on this Mac.'

/** Binds and immediately releases a loopback port, so connecting to it is a real ECONNREFUSED rather than a hang. */
const allocateClosedPort = async (): Promise<number> => {
  const server = createServer()
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const port = (server.address() as AddressInfo).port
  await new Promise<void>((resolve) => server.close(() => resolve()))
  return port
}

test.describe('O-30: the offline row is real, distinguishes unreachable from rejected, and reaches the window', () => {
  test('a configured server this Mac cannot reach shows the offline row -- not the retryable-failure row', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o30-unreachable')
    const port = await allocateClosedPort()
    const origin = `http://127.0.0.1:${port}`
    writeFileSync(join(profilePath, 'server.json'), JSON.stringify({ baseUrl: `${origin}/` }))

    const { application, window } = await launchRealSync(profilePath)
    try {
      await seedCredentials(application, origin)
      await captureTask(window, 'Kept while the server is unreachable')
      await runOneSyncPass(application)

      // Positive read FIRST: the status surface really rendered and really
      // states the offline copy. Only then is the negation meaningful.
      const row = window.locator('#sync-status-row')
      const copy = row.locator('[data-sync-copy]')
      await expect(copy).toHaveText(OFFLINE_COPY)
      await expect(row).toHaveAttribute('data-sync-status', 'offline')
      await expect(window.getByText(RETRYABLE_COPY)).toHaveCount(0)

      // The user's task is still right there on this Mac -- the whole point
      // of the copy.
      await expect(window.getByText('Kept while the server is unreachable')).toBeVisible()
    } finally {
      await application.close()
    }
  })

  test('a server that ANSWERS badly still shows the retryable-failure row -- an answered request is never called offline', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o30-rejected')
    const server = createServer((_request, response) => {
      response.writeHead(500, { 'content-type': 'application/problem+json' })
      response.end(JSON.stringify({ code: 'internal_error' }))
    })
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    writeFileSync(join(profilePath, 'server.json'), JSON.stringify({ baseUrl: `${origin}/` }))

    const { application, window } = await launchRealSync(profilePath)
    try {
      await seedCredentials(application, origin)
      await captureTask(window, 'Kept while the server rejects')
      await runOneSyncPass(application)

      const row = window.locator('#sync-status-row')
      const copy = row.locator('[data-sync-copy]')
      await expect(copy).toHaveText(RETRYABLE_COPY)
      await expect(row).toHaveAttribute('data-sync-status', 'retryable_failure')
      await expect(window.getByText(OFFLINE_COPY)).toHaveCount(0)
    } finally {
      await application.close()
      await new Promise<void>((resolve) => server.close(() => resolve()))
    }
  })

  test('an app with NO server configured never publishes a row implying its data is synchronized', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o30-unconfigured')
    const { application, window } = await launchRealSync(profilePath)
    try {
      await captureTask(window, 'Kept with no server at all')
      await runOneSyncPass(application)

      const row = window.locator('#sync-status-row')
      const copy = row.locator('[data-sync-copy]')
      await expect(copy).toHaveText(OFFLINE_COPY)
      await expect(row).toHaveAttribute('data-sync-status', 'offline')

      // Guarded negations: the row above proved the surface rendered, so
      // these read a real string, never an empty one.
      const rowText = (await row.textContent()) ?? ''
      expect(rowText.length).toBeGreaterThan(0)
      expect(rowText).not.toMatch(/synced|up to date|everything/i)
    } finally {
      await application.close()
    }
  })
})

test.describe('O-42: an authored recovery action is a live remedy, not a label', () => {
  test('the retryable-failure row offers Retry, and pressing it runs a REAL synchronization pass', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o42-retry')
    let requestCount = 0
    const server = createServer((_request, response) => {
      requestCount += 1
      response.writeHead(500, { 'content-type': 'application/problem+json' })
      response.end(JSON.stringify({ code: 'internal_error' }))
    })
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    writeFileSync(join(profilePath, 'server.json'), JSON.stringify({ baseUrl: `${origin}/` }))

    const { application, window } = await launchRealSync(profilePath)
    try {
      await seedCredentials(application, origin)
      await captureTask(window, 'Kept while the server answers badly')
      await runOneSyncPass(application)

      const retry = window.locator('#sync-status-row button[data-recovery-action="retry"]')
      await expect(retry).toHaveText('Retry')
      const before = requestCount
      await retry.click()
      // The button reached the network, through the shipped IPC surface and
      // the real adapter. Before O-42 nothing downstream read the action at
      // all, so this count could never move.
      await expect.poll(() => requestCount, { timeout: 30_000 }).toBeGreaterThan(before)
      await expect(window.locator('#sync-status-row')).toHaveAttribute('data-sync-status', 'retryable_failure')
    } finally {
      await application.close()
      await new Promise<void>((resolve) => server.close(() => resolve()))
    }
  })

  test('the Export action writes a real file containing the tasks saved on this Mac', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o42-export')
    const { application, window } = await launchRealSync(profilePath)
    try {
      await captureTask(window, 'Exportable while fenced')
      // Reach the real main-process capability the Export action dispatches
      // to, through the same handler a click reaches.
      const outcome = await window.evaluate(async () =>
        (window as unknown as { keepling: { exportLocalData: () => Promise<unknown> } }).keepling.exportLocalData(),
      ) as { kind: string; path: string; taskCount: number }
      expect(outcome.kind).toBe('exported')
      expect(outcome.taskCount).toBeGreaterThan(0)
      expect(existsSync(outcome.path)).toBe(true)
      const exported = JSON.parse(readFileSync(outcome.path, 'utf8')) as {
        pendingCommands: Array<{ type?: string }>
        tasks: Array<{ title: string }>
      }
      expect(exported.tasks.map((task) => task.title)).toContain('Exportable while fenced')
      // The unsent intent travels with it -- otherwise "export before you
      // remove" would still lose what has not reached a server.
      expect(exported.pendingCommands.some((command) => command.type === 'capture_task')).toBe(true)
    } finally {
      await application.close()
    }
  })
})

test.describe('O-31(a): the Quick Entry window shows synchronization state', () => {
  test('capturing through Quick Entry while the server is unreachable says so, in that window', async () => {
    const profilePath = allocateDisposableProfile('gap-closure-o31a')
    const port = await allocateClosedPort()
    const origin = `http://127.0.0.1:${String(port)}`
    writeFileSync(join(profilePath, 'server.json'), JSON.stringify({ baseUrl: `${origin}/` }))

    const { application, window } = await launchRealSync(profilePath)
    try {
      await seedCredentials(application, origin)
      await expect(window.getByRole('heading', { name: 'Inbox' })).toBeVisible()

      const [quickEntry] = await Promise.all([
        application.waitForEvent('window', {
          predicate: (page: Page) => page.url().includes('view=quick-entry'),
        }),
        application.evaluate(({ Menu }) => {
          const find = (items: Electron.MenuItem[]): Electron.MenuItem | null => {
            for (const item of items) {
              if (item.label.startsWith('Quick Entry')) return item
              const nested = item.submenu ? find(item.submenu.items) : null
              if (nested) return nested
            }
            return null
          }
          const item = find(Menu.getApplicationMenu()?.items ?? [])
          if (!item) throw new Error('Quick Entry menu item not found')
          item.click()
        }),
      ])
      await quickEntry.waitForLoadState('domcontentloaded')

      // The window really loaded the NARROW utility bridge, not the main
      // one -- which is exactly why this needed a new channel rather than a
      // component mount.
      expect(await quickEntry.evaluate(() => 'keepling' in window)).toBe(false)
      expect(await quickEntry.evaluate(() => 'keeplingUtility' in window)).toBe(true)

      await runOneSyncPass(application)
      const copy = quickEntry.locator('#utility-sync-status-row [data-sync-copy]')
      await expect(copy).toHaveText(OFFLINE_COPY, { timeout: 30_000 })
      await expect(quickEntry.locator('#utility-sync-status-row')).toHaveAttribute('data-sync-status', 'offline')
      // Read-only: no remedy crosses this bridge.
      await expect(quickEntry.locator('#utility-sync-status-row button')).toHaveCount(0)
    } finally {
      await application.close()
    }
  })
})
