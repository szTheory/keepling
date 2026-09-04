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

/**
 * Headless E2E BY DEFAULT (`KEEPLING_TEST_HEADLESS=0` to force windowed).
 *
 * The app suppresses window PRESENTATION under this flag (see
 * `apps/desktop/main/windows/headless-presentation.ts`); Playwright keeps
 * driving the renderer over CDP. Specs whose assertions depend on REAL
 * presentation -- `BrowserWindow.isVisible()`, focus, window ordering -- are
 * tagged `@windowed` and are EXCLUDED here rather than weakened to pass.
 *
 * WHY THE DEFAULT FLIPPED (2026-09-04). This was opt-in, on the stated
 * reasoning that "CI has no screen to take over and benefits from the
 * windowed path being exercised". That reasoning was sound when written and
 * is now false: this repository has NO git remote, so
 * `.github/workflows/desktop.yml` has never executed and cannot. The windowed
 * path was therefore being exercised in exactly one place -- a developer's own
 * screen, on every tight loop, which is the cost this flag exists to remove.
 *
 * The coverage that opt-in default was protecting is NOT dropped, it MOVES:
 * `tooling/verify-desktop-phase.mjs` sets `KEEPLING_TEST_HEADLESS=0` on both
 * the `electron-e2e` and `packaged` lanes, so the full windowed suite --
 * `@windowed` specs included -- runs at every gate invocation. Fast loop is
 * headless and scoped; the authoritative run is windowed and complete.
 *
 * If you ever make the gate honour an inherited `KEEPLING_TEST_HEADLESS`,
 * the `@windowed` specs stop running ANYWHERE and their absence is silent.
 * That is the vacuity trap this phase has been removing everywhere else: a
 * check that reports success because it observed nothing. Keep the gate
 * forcing the value.
 */
const headless = process.env.KEEPLING_TEST_HEADLESS !== '0'
// The main process reads this variable directly, so normalise it here rather
// than leaving the renderer-side and main-side notions of "headless" free to
// disagree: an unset variable must mean headless in BOTH.
process.env.KEEPLING_TEST_HEADLESS = headless ? '1' : '0'
console.log(
  headless
    ? 'playwright: headless (default) -- excluding @windowed specs. KEEPLING_TEST_HEADLESS=0 runs them.'
    : 'playwright: windowed (KEEPLING_TEST_HEADLESS=0) -- running the complete suite including @windowed specs.',
)

export default defineConfig({
  expect: { timeout: 10_000 },
  grepInvert: headless ? /@windowed/ : undefined,
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
    /**
     * The real-stack lane is its OWN project, and its specs live in their own
     * directory rather than in `packaged/`, deliberately.
     *
     * It is a packaged-artifact lane like the others, but it is the only one
     * that needs a REAL backend -- Elixir, PostgreSQL, migrations, a seeded
     * database. Folding it into `packaged` would make every existing packaged
     * spec unrunnable without that toolchain, and would hide its case count
     * inside another lane's, so a real-stack run that executed ZERO cases
     * would be invisible. It also keeps `tooling/smoke-desktop-packaged.mjs`'s
     * "every file in test/packaged is a packaged spec" rule true, instead of
     * teaching that script an exception -- an exception list is exactly how a
     * spec stops being run without anyone noticing.
     *
     * Its runner is `tooling/verify-real-stack-desktop.mjs` and its gate lane
     * is `real-stack-sync`.
     */
    {
      name: 'real-stack',
      testMatch: ['real-stack/**/*.spec.ts'],
      timeout: 600_000,
    },
  ],
})
