import { spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { userInfo } from 'node:os'
import { resolve } from 'node:path'
import process from 'node:process'

import { expect, test, type Page, type Route } from '@playwright/test'

const faultToken = process.env.KEEPLING_TEST_FAULT_TOKEN
const repositoryRoot = resolve(import.meta.dirname, '../../..')
const runtimePreflight = resolve(repositoryRoot, 'tooling/runtime-preflight.sh')
const postgresPort = process.env.KEEPLING_E2E_POSTGRES_PORT ?? '55432'
const databaseUrl = `ecto://${encodeURIComponent(userInfo().username)}@127.0.0.1:${postgresPort}/keepling_e2e`
const continuationPassword = 'phase one continuation password'

if (!faultToken || faultToken.length < 32) {
  throw new Error('KEEPLING_TEST_FAULT_TOKEN must be a per-run high-entropy value')
}

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

const captureTask = async (page: Page, title: string, navigateToToday = true) => {
  await page.goto('/')
  const capture = page.getByLabel('What do you want to keep?')
  await capture.fill(title)
  await page.getByLabel('Add to Today').check()
  await page.getByRole('button', { name: 'Add task' }).click()
  await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()
  if (navigateToToday) {
    await page.getByRole('link', { name: 'Today' }).click()
    await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()
  }
}

type FaultMode =
  | 'after_commit'
  | 'authentication_after_commit'
  | 'authentication_before_acceptance'
  | 'before_acceptance'

const faultHeaders = (route: Route, mode: FaultMode) => ({
  ...route.request().headers(),
  'x-keepling-test-fault': mode,
  'x-keepling-test-fault-token': faultToken,
})

test('@lifecycle-recovery retries exact bytes after a before-acceptance disconnect', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const title = 'Before acceptance remains recoverable'
  await captureTask(page, title)

  const bodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({ headers: faultHeaders(route, 'before_acceptance') })
    } else {
      await route.continue()
    }
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(page.getByText('Checking whether your change was saved…')).toBeVisible()

  const request = JSON.parse(bodies[0] ?? '{}') as { mutation_id?: string }
  expect(request.mutation_id).toBeTruthy()
  const missing = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(missing.status()).toBe(404)

  await page.getByRole('button', { name: 'Check again' }).click()

  await expect(page.getByRole('button', { name: `Reopen “${title}”` })).toBeVisible()
  expect(bodies).toHaveLength(2)
  expect(bodies[1]).toBe(bodies[0])
})

test('@lifecycle-recovery reconciles one stored result after an after-commit disconnect', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const title = 'After commit reconciles once'
  await captureTask(page, title)

  const bodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({ headers: faultHeaders(route, 'after_commit') })
    } else {
      await route.continue()
    }
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(page.getByText('Checking whether your change was saved…')).toBeVisible()

  const request = JSON.parse(bodies[0] ?? '{}') as { mutation_id?: string }
  expect(request.mutation_id).toBeTruthy()
  const stored = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(stored.ok()).toBe(true)
  const storedAcknowledgement = (await stored.json()) as {
    mutation_id: string
    outcome: string
  }
  expect(storedAcknowledgement).toMatchObject({
    mutation_id: request.mutation_id,
    outcome: 'accepted',
  })

  await page.getByRole('button', { name: 'Check again' }).click()

  await expect(page.getByRole('button', { name: `Reopen “${title}”` })).toBeVisible()
  expect(bodies).toHaveLength(1)
  const replay = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(await replay.json()).toEqual(await stored.json())
})

test('@lifecycle-recovery preserves identity when authentication interrupts before acceptance', async ({
  baseURL,
  page,
}) => {
  setAccountPassword()
  await authenticate(page, baseURL)
  const title = 'Authentication before acceptance'
  await captureTask(page, title)

  const bodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({ headers: faultHeaders(route, 'authentication_before_acceptance') })
    } else {
      await route.continue()
    }
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(
    page.getByText('Sign in again. Keepling will check whether your change was saved.'),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()

  const request = JSON.parse(bodies[0] ?? '{}') as { mutation_id: string }
  const missing = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(missing.status()).toBe(404)

  await page.getByRole('button', { name: 'Sign in and continue' }).click()
  await page.getByRole('textbox', { exact: true, name: 'Password' }).fill(continuationPassword)
  await page.getByLabel('Session label').fill('Before acceptance continuation')
  await page.locator('form').getByRole('button', { name: 'Sign in and continue' }).click()

  await expect(page.getByRole('button', { name: `Reopen “${title}”` })).toBeVisible()
  expect(bodies).toHaveLength(2)
  expect(bodies[1]).toBe(bodies[0])
})

test('@lifecycle-recovery preserves the stored identity when authentication interrupts after commit', async ({
  baseURL,
  page,
}) => {
  setAccountPassword()
  await authenticate(page, baseURL)
  const title = 'Authentication after commit'
  await captureTask(page, title)

  const bodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({ headers: faultHeaders(route, 'authentication_after_commit') })
    } else {
      await route.continue()
    }
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(
    page.getByText('Sign in again. Keepling will check whether your change was saved.'),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()

  const request = JSON.parse(bodies[0] ?? '{}') as { mutation_id: string }
  const stored = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(stored.ok()).toBe(true)
  expect(await stored.json()).toMatchObject({
    mutation_id: request.mutation_id,
    outcome: 'accepted',
  })

  await page.getByRole('button', { name: 'Sign in and continue' }).click()
  await page.getByRole('textbox', { exact: true, name: 'Password' }).fill(continuationPassword)
  await page.getByLabel('Session label').fill('After commit continuation')
  await page.locator('form').getByRole('button', { name: 'Sign in and continue' }).click()

  await expect(page.getByRole('button', { name: `Reopen “${title}”` })).toBeVisible()
  expect(bodies).toHaveLength(1)
})

test('@lifecycle-recovery continues exact undo through a real login after session revocation', async ({
  baseURL,
  page,
}) => {
  setAccountPassword()
  const { csrf_token: csrfToken } = await authenticate(page, baseURL)
  await captureTask(page, 'Undo survives reauthentication', false)

  const bodies: string[] = []
  await page.route('**/api/v1/commands/undo-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    await route.continue()
  })

  const sessionsResponse = await page.request.get('/api/v1/sessions')
  expect(sessionsResponse.ok()).toBe(true)
  const sessions = (await sessionsResponse.json()) as {
    sessions: Array<{ current: boolean; id: string }>
  }
  const currentSession = sessions.sessions.find((session) => session.current)
  expect(currentSession).toBeTruthy()
  const revoked = await page.request.delete(`/api/v1/sessions/${currentSession!.id}`, {
    headers: {
      origin: new URL(baseURL!).origin,
      'x-csrf-token': csrfToken,
    },
  })
  expect(revoked.ok()).toBe(true)

  await page.getByRole('button', { name: 'Undo Today planning' }).click()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()
  await page.getByRole('textbox', { exact: true, name: 'Password' }).fill(continuationPassword)
  await page.getByLabel('Session label').fill('Continued browser')
  await page.getByRole('button', { name: 'Sign in and continue' }).click()

  await expect(page.getByText('Change undone.')).toBeVisible()
  expect(bodies).toHaveLength(2)
  expect(bodies[1]).toBe(bodies[0])
})
