import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { join } from 'node:path'
import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test'

import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * Exact packaged daily-loop proof (D-42..D-48, MAC-01..05, QUAL-03/04,
 * SRV-02). Runs against the SAME copied `.app` `tooling/package-desktop.mjs`
 * produced -- selected only via the manifest, never rebuilt, never a
 * dev-server or source-tree load. Extends `offline-capture.spec.ts`'s
 * proof (hard kill, one exact reconnect, second-instance profile
 * ownership) with: (a) opening a database that already carries a RETAINED
 * migration lineage and pre-existing data from a "prior session", (b) the
 * full local daily-loop shape (capture -> edit -> complete -> reopen ->
 * Today -> trash -> restore), and (c) a Quick Entry draft that survives a
 * hard kill and relaunch of the packaged app.
 */

type PackageManifest = {
  applicationDigestSha256: string
  embeddedVersions: Record<string, string>
  executablePath: string
  sourceRevision: string
}

const manifestPath = process.env.KEEPLING_PACKAGE_MANIFEST
if (!manifestPath) throw new Error('KEEPLING_PACKAGE_MANIFEST is required for packaged tests')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as PackageManifest
const profileRoot = process.env.KEEPLING_TEST_USER_DATA_DIR
if (!profileRoot) throw new Error('KEEPLING_TEST_USER_DATA_DIR is required for packaged tests')
const migrationPath = new URL('../../migrations/0001_initial.sql', import.meta.url)

const allocateProfile = (lane: string): string => {
  const profilePath = join(profileRoot, `daily-loop-${lane.replaceAll(/[^a-z0-9-]/gi, '-')}`)
  mkdirSync(profilePath, { recursive: true })
  return profilePath
}

const launch = async (
  profilePath: string,
  syncMode: 'offline' | 'acknowledge',
): Promise<{ application: ElectronApplication; window: Page }> => {
  const application = await electron.launch({
    args: [`--user-data-dir=${profilePath}`],
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_SYNC_MODE: syncMode,
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    executablePath: manifest.executablePath,
    timeout: 30_000,
  })
  const window = await application.firstWindow()
  return { application, window }
}

const hardKill = async (application: ElectronApplication): Promise<void> => {
  const nodeProcess = application.process()
  nodeProcess.kill('SIGKILL')
  await new Promise<void>((resolve) => nodeProcess.once('exit', () => resolve()))
}

/** Builds a "retained" namespace.sqlite3 -- schema already migrated and one task already committed -- as if from a prior session, BEFORE the packaged app ever opens this profile. */
const seedRetainedFixture = (profilePath: string, taskId: string, title: string): void => {
  const databasePath = join(profilePath, 'namespace.sqlite3')
  const commandBytes = JSON.stringify({ mutation_id: `${taskId}-mutation`, task_id: taskId, title, type: 'capture_task', version: 1 })
  const store = new NodeSqliteLocalStore({
    databasePath,
    migrationPath,
  })
  store.acceptCapture({
    acceptedAt: '2026-08-01T09:00:00.000Z',
    commandBytes,
    fingerprint: createHash('sha256').update(commandBytes).digest('hex'),
    mutationId: `${taskId}-mutation`,
    taskId,
    title,
  })
  store.close()
}

test('the packaged app opens a retained (already-migrated) database from a prior session without reapplying the migration, and the pre-existing task remains visible', async () => {
  const profilePath = allocateProfile('retained-migration')
  seedRetainedFixture(profilePath, 'retained-task-1', 'Renew the passport before the trip')

  const { application, window } = await launch(profilePath, 'offline')
  try {
    await expect(window.getByText('Renew the passport before the trip')).toBeVisible()

    // Capture a SECOND task in the same session to prove the retained store
    // is still fully writable, not merely readable.
    await window.getByLabel('What do you want to keep?').fill('Book the dentist')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Book the dentist')).toBeVisible()
  } finally {
    await application.close()
  }

  // The migration ledger records EXACTLY ONE row for version 1 -- opening a
  // retained database never re-inserts a duplicate migration record.
  const databasePath = join(profilePath, 'namespace.sqlite3')
  const ledgerDb = new DatabaseSync(databasePath, { defensive: true, timeout: 2_500 })
  const ledger = ledgerDb.prepare('SELECT version FROM schema_migrations').all() as Array<{ version: number }>
  const taskRows = ledgerDb.prepare('SELECT title FROM visible_projection ORDER BY title').all() as Array<{ title: string }>
  ledgerDb.close()
  expect(ledger).toHaveLength(1)
  expect(taskRows.map((row) => row.title)).toEqual(['Book the dentist', 'Renew the passport before the trip'])
})

test('the packaged app completes capture, edit, complete/reopen, Today placement, and trash/restore through the exact copied executable', async () => {
  const profilePath = allocateProfile('full-loop')
  const { application, window } = await launch(profilePath, 'offline')
  try {
    await window.getByLabel('What do you want to keep?').fill('Call the vet')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Call the vet')).toBeVisible()
    await expect(window.getByText('Saved on this Mac').first()).toBeVisible()

    await window.getByText('Call the vet').click()
    const titleField = window.locator('#task-editor-title')
    await titleField.fill('Call the vet about the checkup')
    await window.keyboard.press('Meta+s')
    await expect(window.getByRole('heading', { name: 'Call the vet about the checkup' })).toBeVisible()

    await window.getByRole('button', { name: 'Complete' }).click()
    await expect(window.getByRole('button', { name: 'Reopen' })).toBeVisible()
    await window.getByRole('button', { name: 'Reopen' }).click()
    await expect(window.getByRole('button', { name: 'Complete' })).toBeVisible()

    await window.getByRole('button', { name: 'Add to Today' }).click()
    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await expect(window.getByText('Call the vet about the checkup')).toBeVisible()
    // Today and Inbox are disjoint routes (a planned task leaves the Inbox
    // list) -- remove it from Today before expecting it back in Inbox.
    await window.getByText('Call the vet about the checkup').click()
    await window.getByRole('button', { name: 'Remove from Today' }).click()

    await window.getByRole('button', { name: 'Inbox', exact: true }).click()
    await window.getByText('Call the vet about the checkup').click()
    await window.getByRole('button', { name: 'Move to Trash' }).click()
    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await window.getByText('Call the vet about the checkup').click()
    await window.getByRole('button', { name: 'Restore' }).click()
    await window.getByRole('button', { name: 'Inbox', exact: true }).click()
    await expect(window.getByText('Call the vet about the checkup')).toBeVisible()
    console.log('PACKAGED_DAILY_LOOP_FULL passed=1')
  } finally {
    await application.close()
  }
})

test('an offline capture and a durable Quick Entry draft both survive a hard kill and a relaunch of the packaged app, then reconcile with exactly one reconnect', async () => {
  const profilePath = allocateProfile('hard-kill-draft-reconnect')
  const first = await launch(profilePath, 'offline')
  await first.window.getByLabel('What do you want to keep?').fill('Survive a hard kill')
  await first.window.getByRole('button', { name: 'Add Task' }).click()
  await expect(first.window.getByText('Survive a hard kill')).toBeVisible()
  await expect(first.window.getByText('Saved on this Mac').first()).toBeVisible()

  // Open Quick Entry through the real native menu (same wiring O-9 proved
  // at the unpackaged shipped entry point) and leave a nonempty draft
  // WITHOUT submitting it.
  const [quickEntryWindow] = await Promise.all([
    first.application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
    first.application.evaluate(({ Menu }) => {
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
      if (item === null) throw new Error('Quick Entry menu item not found in the packaged application menu')
      item.click()
    }),
  ])
  await quickEntryWindow.waitForLoadState('domcontentloaded')
  await quickEntryWindow.getByLabel('What do you want to keep?').fill('Ping the accountant')
  // Draft persistence is debounced (see renderer/quick-entry.tsx) -- wait
  // past the debounce window before the hard kill.
  await quickEntryWindow.waitForTimeout(400)

  await hardKill(first.application)

  const relaunch = await launch(profilePath, 'acknowledge')
  try {
    // The offline capture committed before the kill is retained.
    await expect(relaunch.window.getByText('Survive a hard kill')).toHaveCount(1)
    // The bounded pull-before-push pass at startup performs exactly ONE
    // reconnect reconciliation and settles the exact acknowledged identity
    // -- the SAME assertion `offline-capture.spec.ts` proves for its own
    // fixture, repeated here against a database that also carries the
    // durable Quick Entry draft below.
    await expect(relaunch.window.getByText('Synced')).toHaveCount(1)

    const [reopenedQuickEntry] = await Promise.all([
      relaunch.application.waitForEvent('window', { predicate: (page) => page.url().includes('view=quick-entry') }),
      relaunch.application.evaluate(({ Menu }) => {
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
        if (item === null) throw new Error('Quick Entry menu item not found after relaunch')
        item.click()
      }),
    ])
    await reopenedQuickEntry.waitForLoadState('domcontentloaded')
    // The draft was never submitted -- it survives the hard kill AND the
    // relaunch because it is durably stored by the worker/SQLite store, not
    // renderer/process memory.
    await expect(reopenedQuickEntry.getByLabel('What do you want to keep?')).toHaveValue('Ping the accountant')
    console.log(
      `PACKAGED_DAILY_LOOP_RECONNECT passed=1 digest=${manifest.applicationDigestSha256} revision=${manifest.sourceRevision}`,
    )
  } finally {
    await relaunch.application.close()
  }
})
