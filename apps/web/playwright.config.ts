import { randomBytes } from 'node:crypto'
import process from 'node:process'
import { defineConfig, devices } from '@playwright/test'

const host = '127.0.0.1'
const publicPort = process.env.KEEPLING_E2E_PORT ?? '4173'
const baseURL = `http://${host}:${publicPort}`
const testFaultToken =
  process.env.KEEPLING_TEST_FAULT_TOKEN ?? randomBytes(32).toString('hex')

process.env.KEEPLING_TEST_FAULT_TOKEN = testFaultToken

export default defineConfig({
  testDir: './e2e',
  testMatch: ['**/*.spec.ts', '**/support/stack.ts'],
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  outputDir: './test-results',
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'exec node --experimental-strip-types ./e2e/support/stack.ts',
    env: {
      ...process.env,
      KEEPLING_E2E_HOST: host,
      KEEPLING_E2E_PORT: publicPort,
      KEEPLING_TEST_FAULT_TOKEN: testFaultToken,
    },
    gracefulShutdown: {
      signal: 'SIGTERM',
      timeout: 8_000,
    },
    reuseExistingServer: false,
    timeout: 120_000,
    url: `${baseURL}/`,
  },
})
