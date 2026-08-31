import { expect, test } from '@playwright/test'

test('@skeleton captures one authenticated task and reloads it from PostgreSQL', async ({
  baseURL,
  page,
}) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')

  const loginResponse = await page.request.post('/api/v1/test/session', {
    headers: {
      origin: new URL(baseURL).origin,
    },
  })

  expect(loginResponse.ok()).toBe(true)

  await page.goto('/')

  const title = 'Keep the exact capture acknowledgement'
  const capture = page.getByLabel('What do you want to keep?')

  await expect(page.getByRole('heading', { exact: true, name: 'Inbox' })).toBeVisible()
  await expect(page.getByText('Destination: Inbox')).toBeVisible()
  await capture.fill(title)

  const captureResponsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith('/api/v1/commands/capture-task') &&
      response.request().method() === 'POST',
  )

  await page.getByRole('button', { name: 'Add task' }).click()

  const captureResponse = await captureResponsePromise
  const request = captureResponse.request().postDataJSON() as { mutation_id: string }
  const acknowledgement = (await captureResponse.json()) as { mutation_id: string }

  expect(captureResponse.ok()).toBe(true)
  expect(acknowledgement.mutation_id).toBe(request.mutation_id)
  await expect(capture).toHaveValue('')
  await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()

  await page.reload()

  await expect(page.getByRole('listitem').filter({ hasText: title })).toBeVisible()
})
