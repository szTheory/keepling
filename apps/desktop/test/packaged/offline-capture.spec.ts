import { readFileSync } from 'node:fs'
import { test, expect, _electron as electron, type ElectronApplication } from '@playwright/test'

type PackageManifest = {
  applicationDigestSha256: string
  embeddedVersions: Record<string, string>
  executablePath: string
  sourceRevision: string
}

const manifestPath = process.env.KEEPLING_PACKAGE_MANIFEST
if (!manifestPath) throw new Error('KEEPLING_PACKAGE_MANIFEST is required for packaged tests')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as PackageManifest
const profilePath = process.env.KEEPLING_TEST_USER_DATA_DIR
if (!profilePath) throw new Error('KEEPLING_TEST_USER_DATA_DIR is required for packaged tests')

const launch = (syncMode: 'offline' | 'acknowledge') => electron.launch({
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

const hardKill = async (application: ElectronApplication) => {
  const process = application.process()
  process.kill('SIGKILL')
  await new Promise<void>((resolve) => process.once('exit', () => resolve()))
}

test('offline capture survives hard kill and exact acknowledgement', async () => {
  const first = await launch('offline')
  const firstWindow = await first.firstWindow()
  await expect(firstWindow.getByRole('heading', { name: 'Inbox' })).toBeVisible()
  await firstWindow.getByLabel('Task title').fill('Survive a hard kill')
  await firstWindow.getByRole('button', { name: 'Save task' }).click()
  await expect(firstWindow.getByRole('status')).toHaveText('Saved on this Mac')
  await expect(firstWindow.getByText('Survive a hard kill')).toHaveCount(1)
  await hardKill(first)

  const second = await launch('acknowledge')
  try {
    const secondWindow = await second.firstWindow()
    await expect(secondWindow.getByText('Survive a hard kill')).toHaveCount(1)
    await expect(secondWindow.getByText('Synced')).toHaveCount(1)
    const runtime = await second.evaluate(({ app }) => ({
      isPackaged: app.isPackaged,
      versions: process.versions,
    }))
    expect(runtime.isPackaged).toBe(true)
    expect(runtime.versions.electron).toBe(manifest.embeddedVersions.electron)
    console.log(
      `PACKAGED_OFFLINE_CAPTURE passed=1 digest=${manifest.applicationDigestSha256} revision=${manifest.sourceRevision} executable=${manifest.executablePath}`,
    )
  } finally {
    await second.close()
  }
})
