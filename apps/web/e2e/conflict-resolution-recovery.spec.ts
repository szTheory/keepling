import { randomUUID } from 'node:crypto'
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

const editTask = (
  page: Page,
  baseURL: string,
  csrfToken: string,
  data: Record<string, unknown>,
) =>
  page.request.post('/api/v1/commands/edit-task', {
    data,
    headers: {
      origin: new URL(baseURL).origin,
      'x-csrf-token': csrfToken,
    },
  })

const faultHeaders = (route: Route) => ({
  ...route.request().headers(),
  'x-keepling-test-fault': 'after_commit',
  'x-keepling-test-fault-token': faultToken,
})

test('@conflict-resolution-recovery reconciles the original choice after its committed response is lost', async ({
  baseURL,
  page,
}) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const { csrf_token: csrfToken } = await authenticate(page, baseURL)
  const originalTitle = 'Conflict response loss'
  const currentTitle = 'Current accepted title'
  const mineTitle = 'Original mine choice'

  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill(originalTitle)
  const captureResponsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith('/api/v1/commands/capture-task') &&
      response.request().method() === 'POST',
  )
  await page.getByRole('button', { name: 'Add task' }).click()
  const captureResponse = await captureResponsePromise
  expect(captureResponse.status()).toBe(201)
  const captured = (await captureResponse.json()) as { revision: number; task_id: string }

  await page.getByRole('listitem').filter({ hasText: originalTitle }).getByRole('link').click()
  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await page.getByLabel('Title').fill(mineTitle)

  const competingEdit = await editTask(page, baseURL, csrfToken, {
    base_values: { title: originalTitle },
    expected_revision: captured.revision,
    fields: { title: currentTitle },
    mutation_id: randomUUID(),
    task_id: captured.task_id,
    version: 1,
  })
  expect(competingEdit.ok()).toBe(true)
  const competingAcknowledgement = (await competingEdit.json()) as { revision: number }

  await page.getByRole('button', { name: 'Save changes' }).click()
  await expect(
    page.getByRole('heading', { name: 'This task changed somewhere else.' }),
  ).toBeVisible()

  const resolutionBodies: string[] = []
  await page.route('**/api/v1/commands/resolve-task-conflict', async (route) => {
    resolutionBodies.push(route.request().postData() ?? '')
    await route.continue({ headers: faultHeaders(route) })
  })

  const mine = page.getByRole('button', { name: 'Use mine for Title' })
  const current = page.getByRole('button', { name: 'Use current for Title' })
  const keepEditing = page.getByRole('button', { name: 'Keep editing' })
  const save = page.getByRole('button', { name: 'Save resolution' })
  await mine.click()
  await save.click()

  await expect(page.getByText('Checking whether your resolution was saved…')).toBeVisible()
  await expect(mine).toBeDisabled()
  await expect(current).toBeDisabled()
  await expect(keepEditing).toBeDisabled()
  await expect(save).toBeDisabled()
  await current.evaluate((button: HTMLButtonElement) => button.click())
  await keepEditing.evaluate((button: HTMLButtonElement) => button.click())
  await save.evaluate((button: HTMLButtonElement) => button.click())
  await expect(mine).toHaveAttribute('aria-pressed', 'true')
  await expect(current).toHaveAttribute('aria-pressed', 'false')
  expect(resolutionBodies).toHaveLength(1)

  const resolution = JSON.parse(resolutionBodies[0] ?? '{}') as {
    mutation_id: string
    selections: { title: string }
  }
  expect(resolution.selections).toEqual({ title: 'mine' })
  const stored = await page.request.get(`/api/v1/mutations/${resolution.mutation_id}`)
  expect(stored.ok()).toBe(true)
  expect(await stored.json()).toMatchObject({
    mutation_id: resolution.mutation_id,
    outcome: 'accepted',
    revision: competingAcknowledgement.revision + 1,
    snapshot: { title: mineTitle },
  })

  await page.getByRole('button', { name: 'Check again' }).click()

  await expect(page.getByLabel('Title')).toHaveValue(mineTitle)
  await expect(
    page.getByRole('heading', { name: 'This task changed somewhere else.' }),
  ).not.toBeVisible()
  expect(resolutionBodies).toHaveLength(1)
  const canonical = await page.request.get(`/api/v1/tasks/${captured.task_id}`)
  expect(canonical.ok()).toBe(true)
  expect(await canonical.json()).toMatchObject({
    revision: competingAcknowledgement.revision + 1,
    title: mineTitle,
  })
})
