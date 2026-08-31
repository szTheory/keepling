import { spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { userInfo } from 'node:os'
import { resolve } from 'node:path'
import process from 'node:process'

import { expect, test, type Page } from '@playwright/test'

const repositoryRoot = resolve(import.meta.dirname, '../../..')
const runtimePreflight = resolve(repositoryRoot, 'tooling/runtime-preflight.sh')
const postgresPort = process.env.KEEPLING_E2E_POSTGRES_PORT ?? '55432'
const databaseUrl = `ecto://${encodeURIComponent(userInfo().username)}@127.0.0.1:${postgresPort}/keepling_e2e`
const continuationPassword = 'authenticated read continuation password'

const setAccountPassword = () => {
  const environment = {
    ...process.env,
    KEEPLING_TEST_DATABASE_URL: databaseUrl,
    KEEPLING_TEST_SECRET_KEY_BASE:
      process.env.KEEPLING_TEST_SECRET_KEY_BASE ?? randomBytes(64).toString('hex'),
    MIX_ENV: 'test',
  }
  const code = [
    `hash = Argon2.hash_pwd_salt(${JSON.stringify(continuationPassword)})`,
    'Ecto.Adapters.SQL.query!(Keepling.Repo, "UPDATE accounts SET password_hash = $1", [hash])',
  ].join('; ')
  const result = spawnSync(
    runtimePreflight,
    ['--exec', '--', 'sh', '-c', `cd apps/server && mix run -e '${code}'`],
    { cwd: repositoryRoot, encoding: 'utf8', env: environment },
  )
  if (result.status !== 0) throw new Error(`${result.stdout}\n${result.stderr}`)
}

const authenticate = async (page: Page, baseURL: string | undefined) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const response = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(response.ok()).toBe(true)
  return (await response.json()) as { csrf_token: string }
}

const revokeCurrentSession = async (
  page: Page,
  baseURL: string | undefined,
  csrfToken: string,
) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const sessionsResponse = await page.request.get('/api/v1/sessions')
  const sessions = (await sessionsResponse.json()) as {
    sessions: Array<{ current: boolean; id: string }>
  }
  const current = sessions.sessions.find((session) => session.current)
  expect(current).toBeTruthy()
  const revoked = await page.request.delete(`/api/v1/sessions/${current!.id}`, {
    headers: {
      origin: new URL(baseURL).origin,
      'x-csrf-token': csrfToken,
    },
  })
  expect(revoked.ok()).toBe(true)
}

const continueThroughLogin = async (page: Page, label: string) => {
  await expect(page.getByRole('heading', { name: 'Sign in to continue' })).toBeVisible()
  await page.getByRole('textbox', { exact: true, name: 'Password' }).fill(continuationPassword)
  await page.getByLabel('Session label').fill(label)
  await page.locator('form').getByRole('button', { name: 'Sign in and continue' }).click()
  await expect(page.getByRole('heading', { name: 'Sign in to continue' })).not.toBeVisible()
  const sessionResponse = await page.request.get('/api/v1/session')
  expect(sessionResponse.ok()).toBe(true)
  const session = (await sessionResponse.json()) as {
    csrf_token: string
  }
  return session.csrf_token
}

test('@authenticated-read-task @authenticated-read-concurrent restores concurrent task reads after real session expiry', async ({
  baseURL,
  page,
}) => {
  setAccountPassword()
  const { csrf_token: csrfToken } = await authenticate(page, baseURL)
  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill('Read recovery task')
  await page.getByRole('button', { name: 'Add task' }).click()
  const taskLink = page.getByRole('link', { name: 'Read recovery task' })
  await expect(taskLink).toBeVisible()
  const taskPath = await taskLink.getAttribute('href')
  expect(taskPath).toBeTruthy()

  await revokeCurrentSession(page, baseURL, csrfToken)

  await page.evaluate((pathname) => {
    window.history.pushState({}, '', pathname)
    window.dispatchEvent(new PopStateEvent('popstate'))
  }, taskPath)

  await continueThroughLogin(page, 'Recovered task read')

  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await expect(page.getByLabel('Title')).toHaveValue('Read recovery task')
  await expect(page.getByRole('heading', { name: 'Activity' })).toBeVisible()
  expect(new URL(page.url()).pathname).toBe(taskPath)
})

test('@authenticated-read-organizations restores assignment, Projects, and Tags routes', async ({
  baseURL,
  page,
}) => {
  setAccountPassword()
  let { csrf_token: csrfToken } = await authenticate(page, baseURL)
  await page.goto('/')

  for (const [pathname, heading, label] of [
    ['/projects', 'Projects', 'Recovered project read'],
    ['/tags', 'Tags', 'Recovered tag read'],
  ] as const) {
    await revokeCurrentSession(page, baseURL, csrfToken)
    await page.evaluate((nextPath) => {
      window.history.pushState({}, '', nextPath)
      window.dispatchEvent(new PopStateEvent('popstate'))
    }, pathname)
    csrfToken = await continueThroughLogin(page, label)
    await expect(page.getByRole('heading', { name: heading })).toBeVisible()
    expect(new URL(page.url()).pathname).toBe(pathname)
  }

  await page.evaluate(() => {
    window.history.pushState({}, '', '/')
    window.dispatchEvent(new PopStateEvent('popstate'))
  })
  await page.getByLabel('What do you want to keep?').fill('Assignment read recovery task')
  await page.getByRole('button', { name: 'Add task' }).click()
  const taskLink = page.getByRole('link', { name: 'Assignment read recovery task' })
  await expect(taskLink).toBeVisible()
  const taskPath = await taskLink.getAttribute('href')
  expect(taskPath).toBeTruthy()
  const assignmentPath = `${taskPath}/organizations`

  await revokeCurrentSession(page, baseURL, csrfToken)
  await page.evaluate((nextPath) => {
    window.history.pushState({}, '', nextPath)
    window.dispatchEvent(new PopStateEvent('popstate'))
  }, assignmentPath)
  await continueThroughLogin(page, 'Recovered assignment read')

  await expect(page.getByRole('heading', { name: 'Project and tags' })).toBeVisible()
  await expect(page.getByRole('combobox', { name: 'Project' })).toBeVisible()
  expect(new URL(page.url()).pathname).toBe(assignmentPath)
})
