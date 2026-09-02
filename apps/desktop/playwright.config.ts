import { mkdtempSync, mkdirSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { isAbsolute, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'
import { defineConfig } from '@playwright/test'

const profileRoot = mkdtempSync(join(tmpdir(), 'keepling-desktop-tests-'))
const forbiddenUserDataDir = resolve(homedir(), 'Library', 'Application Support', 'Keepling')

export const assertDisposableProfile = (profilePath: string) => {
  const candidate = resolve(profilePath)
  const fromTestRoot = relative(profileRoot, candidate)
  if (
    candidate === forbiddenUserDataDir ||
    fromTestRoot === '' ||
    fromTestRoot === '..' ||
    fromTestRoot.startsWith(`..${sep}`) ||
    isAbsolute(fromTestRoot)
  ) {
    throw new Error('Electron tests refused a non-disposable Keepling profile')
  }
  return candidate
}

export const allocateDisposableProfile = (lane: string) => {
  const safeLane = lane.replaceAll(/[^a-z0-9-]/gi, '-')
  const profilePath = assertDisposableProfile(join(profileRoot, `${safeLane}-${process.pid}`))
  mkdirSync(profilePath, { recursive: false })
  return profilePath
}

process.env.KEEPLING_TEST_PROFILE_ROOT = profileRoot
process.env.KEEPLING_FORBIDDEN_USER_DATA_DIR = forbiddenUserDataDir
process.once('exit', () => rmSync(profileRoot, { force: true, recursive: true }))

export default defineConfig({
  expect: { timeout: 10_000 },
  forbidOnly: true,
  fullyParallel: false,
  outputDir: './test-results/playwright',
  reporter: process.env.CI ? 'github' : 'list',
  retries: process.env.CI ? 1 : 0,
  testDir: './test',
  timeout: 60_000,
  use: {
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
  },
  workers: 1,
  projects: [
    {
      name: 'electron',
      testMatch: ['e2e/**/*.spec.ts'],
    },
    {
      name: 'packaged',
      testMatch: ['packaged/**/*.spec.ts'],
    },
  ],
})
