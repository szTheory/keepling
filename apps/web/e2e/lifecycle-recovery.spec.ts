import process from 'node:process'

import { expect, test, type Page, type Route } from '@playwright/test'

const faultToken = process.env.KEEPLING_TEST_FAULT_TOKEN

if (!faultToken || faultToken.length < 32) {
  throw new Error('KEEPLING_TEST_FAULT_TOKEN must be a per-run high-entropy value')
}

const authenticate = async (page: Page, baseURL: string | undefined) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const response = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(response.ok()).toBe(true)
  return (await response.json()) as { csrf_token: string }
}

const captureTask = async (page: Page, title: string) => {
  await page.goto('/')
  const capture = page.getByLabel('What do you want to keep?')
  await capture.fill(title)
  await page.getByLabel('Add to Today').check()
  await page.getByRole('button', { name: 'Add task' }).click()
  await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()
  await page.goto('/today')
  await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()
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
  expect(bodies).toHaveLength(2)
  expect(bodies[1]).toBe(bodies[0])
  const replay = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(await replay.json()).toEqual(await stored.json())
})

test('@lifecycle-recovery preserves identity when authentication interrupts before acceptance', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const title = 'Authentication before acceptance'
  await captureTask(page, title)

  let body = ''
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    body = route.request().postData() ?? ''
    await route.continue({ headers: faultHeaders(route, 'authentication_before_acceptance') })
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(
    page.getByText('Sign in again to finish saving. Your changes are still here.'),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()

  const request = JSON.parse(body) as { mutation_id: string }
  const missing = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(missing.status()).toBe(404)
})

test('@lifecycle-recovery preserves the stored identity when authentication interrupts after commit', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const title = 'Authentication after commit'
  await captureTask(page, title)

  let body = ''
  await page.route('**/api/v1/commands/complete-task', async (route) => {
    body = route.request().postData() ?? ''
    await route.continue({ headers: faultHeaders(route, 'authentication_after_commit') })
  })

  await page.getByRole('button', { name: `Complete “${title}”` }).click()
  await expect(
    page.getByText('Sign in again to finish saving. Your changes are still here.'),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()

  const request = JSON.parse(body) as { mutation_id: string }
  const stored = await page.request.get(`/api/v1/mutations/${request.mutation_id}`)
  expect(stored.ok()).toBe(true)
  expect(await stored.json()).toMatchObject({
    mutation_id: request.mutation_id,
    outcome: 'accepted',
  })
})

test('@lifecycle-recovery continues exact undo through reauthentication', async ({
  baseURL,
  page,
}) => {
  const { csrf_token: csrfToken } = await authenticate(page, baseURL)
  await captureTask(page, 'Undo survives reauthentication')

  const bodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/undo-task', async (route) => {
    bodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({
        headers: faultHeaders(route, 'authentication_before_acceptance'),
      })
    } else {
      await route.continue()
    }
  })
  await page.route('**/api/v1/reauthenticate', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      json: { csrf_token: csrfToken, status: 'reauthenticated' },
      status: 200,
    })
  })

  await page.getByRole('button', { name: 'Undo Today planning' }).click()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()
  await page.getByRole('textbox', { exact: true, name: 'Password' }).fill('test-only continuation')
  await page.getByRole('button', { name: 'Sign in and continue' }).click()

  await expect(page.getByText('Change undone.')).toBeVisible()
  expect(bodies).toHaveLength(2)
  expect(bodies[1]).toBe(bodies[0])
})
