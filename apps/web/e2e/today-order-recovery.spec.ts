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
}

const captureForToday = async (page: Page, title: string) => {
  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill(title)
  await page.getByLabel('Add to Today').check()
  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith('/api/v1/commands/capture-task') &&
      response.request().method() === 'POST',
  )
  await page.getByRole('button', { name: 'Add task' }).click()
  const response = await responsePromise
  expect(response.status()).toBe(201)
  return (await response.json()) as { task_id: string }
}

const afterCommitHeaders = (route: Route) => ({
  ...route.request().headers(),
  'x-keepling-test-fault': 'after_commit',
  'x-keepling-test-fault-token': faultToken,
})

type TodayPage = {
  items: Array<{ id: string; section: 'overdue' | 'today'; title: string }>
  order_revision: number
}

test('@today-order-recovery retains the first committed move until exact reconciliation', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const firstTitle = 'Today recovery first'
  const secondTitle = 'Today recovery second'
  const first = await captureForToday(page, firstTitle)
  const second = await captureForToday(page, secondTitle)

  await page.goto('/today')
  await expect(page.getByRole('listitem').filter({ hasText: firstTitle })).toBeVisible()
  await expect(page.getByRole('listitem').filter({ hasText: secondTitle })).toBeVisible()

  const beforeResponse = await page.request.get('/api/v1/today?limit=50')
  expect(beforeResponse.ok()).toBe(true)
  const before = (await beforeResponse.json()) as TodayPage
  const capturedIds = new Set([first.task_id, second.task_id])
  let targetIndex = before.items.findIndex(
    (item, index) =>
      capturedIds.has(item.id) && before.items[index + 1]?.section === item.section,
  )
  let direction: 'earlier' | 'later' = 'later'
  if (targetIndex < 0) {
    targetIndex = before.items.findIndex(
      (item, index) =>
        capturedIds.has(item.id) && before.items[index - 1]?.section === item.section,
    )
    direction = 'earlier'
  }
  expect(targetIndex).toBeGreaterThanOrEqual(0)

  const target = before.items[targetIndex]!
  const adjacentIndex = direction === 'later' ? targetIndex + 1 : targetIndex - 1
  const expectedIds = before.items.map((item) => item.id)
  ;[expectedIds[targetIndex], expectedIds[adjacentIndex]] = [
    expectedIds[adjacentIndex]!,
    expectedIds[targetIndex]!,
  ]

  const commandBodies: string[] = []
  let armed = true
  await page.route('**/api/v1/commands/move-today-task', async (route) => {
    commandBodies.push(route.request().postData() ?? '')
    if (armed) {
      armed = false
      await route.continue({ headers: afterCommitHeaders(route) })
    } else {
      await route.continue()
    }
  })
  const lookupPaths: string[] = []
  await page.route('**/api/v1/today/mutations/**', async (route) => {
    lookupPaths.push(new URL(route.request().url()).pathname)
    await route.continue()
  })

  await page
    .getByRole('button', {
      name: `Move ${direction} “${target.title}”`,
    })
    .click()
  await expect(page.getByText('Checking whether your change was saved…')).toBeVisible()
  const moveButtons = page.getByRole('button', { name: /Move (earlier|later)/ })
  for (let index = 0; index < (await moveButtons.count()); index += 1) {
    await expect(moveButtons.nth(index)).toBeDisabled()
  }

  const replacementTitle = target.id === first.task_id ? secondTitle : firstTitle
  const replacement = page.getByRole('button', {
    name: `Move earlier “${replacementTitle}”`,
  })
  await replacement.evaluate((button: HTMLButtonElement) => {
    button.disabled = false
    button.click()
  })
  expect(commandBodies).toHaveLength(1)

  const original = JSON.parse(commandBodies[0] ?? '{}') as {
    mutation_id: string
    task_id: string
  }
  expect(original.task_id).toBe(target.id)
  const storedResponse = await page.request.get(
    `/api/v1/today/mutations/${original.mutation_id}`,
  )
  expect(storedResponse.ok()).toBe(true)
  const stored = (await storedResponse.json()) as {
    mutation_id: string
    order_revision: number
    task_id: string
  }
  expect(stored).toMatchObject({
    mutation_id: original.mutation_id,
    order_revision: before.order_revision + 1,
    task_id: target.id,
  })

  await page.getByRole('button', { name: 'Check again' }).click()
  await expect(page.getByText('Today order updated.')).toBeVisible()
  expect(commandBodies).toHaveLength(1)
  expect(lookupPaths).toEqual([`/api/v1/today/mutations/${original.mutation_id}`])

  const afterResponse = await page.request.get('/api/v1/today?limit=50')
  expect(afterResponse.ok()).toBe(true)
  const after = (await afterResponse.json()) as TodayPage
  const afterIds = after.items.map((item) => item.id)
  expect(after.order_revision).toBe(stored.order_revision)
  expect(afterIds).toEqual(expectedIds)
  expect(new Set(afterIds).size).toBe(afterIds.length)
  expect(afterIds.filter((id) => id === target.id)).toHaveLength(1)
})
