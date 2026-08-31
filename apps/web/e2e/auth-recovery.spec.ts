import { spawnSync } from 'node:child_process'
import { userInfo } from 'node:os'
import { resolve } from 'node:path'
import process from 'node:process'

import { expect, test } from '@playwright/test'

const repositoryRoot = resolve(import.meta.dirname, '../../..')
const serverRoot = resolve(repositoryRoot, 'apps/server')
const runtimePreflight = resolve(repositoryRoot, 'tooling/runtime-preflight.sh')
const postgresPort = process.env.KEEPLING_E2E_POSTGRES_PORT ?? '55432'
const databaseUrl = `ecto://${encodeURIComponent(userInfo().username)}@127.0.0.1:${postgresPort}/keepling_e2e`

const operatorEnvironment = {
  ...process.env,
  KEEPLING_TEST_DATABASE_URL: databaseUrl,
  MIX_ENV: 'test',
}

const runRuntime = (args: string[], cwd = repositoryRoot) => {
  const result = spawnSync(runtimePreflight, ['--exec', '--', ...args], {
    cwd,
    encoding: 'utf8',
    env: operatorEnvironment,
  })
  if (result.status !== 0) {
    throw new Error(`${result.stdout}\n${result.stderr}`)
  }
  return `${result.stdout}\n${result.stderr}`
}

const issueLink = (task: 'keepling.setup_token' | 'keepling.recover', baseURL: string) => {
  const output = runRuntime(['mix', task, '--base-url', baseURL], serverRoot)
  const link = output.match(/https?:\/\/[^\s]+\/(?:setup|recover)\?token=[^\s]+/)?.[0]
  if (!link) throw new Error(`Operator task did not emit a browser link:\n${output}`)
  return link
}

test('@auth-recovery consumes real setup and recovery links once and administers sessions', async ({
  baseURL,
  browser,
  page,
}) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')

  runRuntime([
    'psql',
    '-h',
    '127.0.0.1',
    '-p',
    postgresPort,
    '-d',
    'keepling_e2e',
    '-v',
    'ON_ERROR_STOP=1',
    '-c',
    'DELETE FROM accounts; UPDATE account_setup SET token_hash = NULL, issued_at = NULL, expires_at = NULL, consumed_at = NULL, disabled_at = NULL;',
  ])

  const setupLink = issueLink('keepling.setup_token', baseURL)
  await page.goto(setupLink)
  await expect(page.getByRole('heading', { name: 'Set up Keepling' })).toBeVisible()
  await page.getByLabel('Password').fill('first operator password')
  await page.getByLabel('Account timezone').fill('America/New_York')
  await page.getByRole('button', { name: 'Create account' }).click()
  await expect(page.getByText('Account created. Sign in to continue.')).toBeVisible()

  await page.goto(setupLink)
  await page.getByLabel('Password').fill('second password')
  await page.getByLabel('Account timezone').fill('America/New_York')
  await page.getByRole('button', { name: 'Create account' }).click()
  await expect(page.getByText('This setup link has already been used. Sign in to continue.')).toBeVisible()

  await page.goto('/login')
  const password = page.getByLabel('Password')
  await expect(password).toHaveAttribute('autocomplete', 'current-password')
  await password.fill('first operator password')
  await page.getByLabel('Session label').fill('Recovery browser')
  await page.getByRole('button', { name: 'Show password' }).click()
  await expect(password).toHaveAttribute('type', 'text')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('heading', { name: 'Inbox' })).toBeVisible()

  const recoveryLink = issueLink('keepling.recover', baseURL)
  await page.goto(recoveryLink)
  await page.getByLabel('New password').fill('replacement operator password')
  await page.getByLabel('Session label').fill('Recovered browser')
  await page.getByRole('button', { name: 'Set new password' }).click()
  await expect(page.getByRole('heading', { name: 'Inbox' })).toBeVisible()

  await page.goto(recoveryLink)
  await page.getByLabel('New password').fill('another replacement')
  await page.getByLabel('Session label').fill('Used recovery')
  await page.getByRole('button', { name: 'Set new password' }).click()
  await expect(page.getByText('This recovery link is invalid, expired, or already used.')).toBeVisible()

  const otherContext = await browser.newContext()
  const otherPage = await otherContext.newPage()
  await otherPage.goto(`${baseURL}/login`)
  await otherPage.getByLabel('Password').fill('replacement operator password')
  await otherPage.getByLabel('Session label').fill('Other browser')
  await otherPage.getByRole('button', { name: 'Sign in' }).click()
  await expect(otherPage.getByRole('heading', { name: 'Inbox' })).toBeVisible()

  await page.goto('/settings/sessions')
  await expect(page.getByRole('heading', { name: 'Sessions' })).toBeVisible()
  await expect(page.getByDisplayValue('Other browser')).toBeVisible()
  await page.getByLabel('Label for Other browser').fill('Travel browser')
  await page.getByRole('button', { name: 'Save label for Other browser' }).click()
  await expect(page.getByDisplayValue('Travel browser')).toBeVisible()
  await page.getByRole('button', { name: 'Revoke Travel browser' }).click()
  await page.getByRole('button', { name: 'Revoke session' }).click()
  await expect(page.getByDisplayValue('Travel browser')).not.toBeVisible()

  await page.getByRole('button', { name: 'Log out this browser' }).click()
  await page.getByRole('button', { name: 'Log out' }).click()
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
  await otherContext.close()
})
