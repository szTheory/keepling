import { randomUUID } from 'node:crypto'

import { expect, test, type Page } from '@playwright/test'

const authenticate = async (page: Page, baseURL: string | undefined) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const response = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(response.ok()).toBe(true)
  return (await response.json()) as { csrf_token: string }
}

const command = (
  page: Page,
  baseURL: string,
  csrfToken: string,
  path: string,
  data: Record<string, unknown>,
) =>
  page.request.post(`/api/v1/commands/${path}`, {
    data,
    headers: {
      origin: new URL(baseURL).origin,
      'x-csrf-token': csrfToken,
    },
  })

test('@phase1-lifecycle traverses the complete real-stack browser lifecycle', async ({
  baseURL,
  page,
}, testInfo) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const { csrf_token: csrfToken } = await authenticate(page, baseURL)
  const originalTitle = 'Phase 1 complete lifecycle'
  const editedTitle = 'Phase 1 lifecycle edited'

  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill(originalTitle)
  await page.getByLabel('Add to Today').check()
  const captureResponsePromise = page.waitForResponse(
    (response) => response.url().endsWith('/commands/capture-task') && response.request().method() === 'POST',
  )
  await page.getByRole('button', { name: 'Add task' }).click()
  const captureResponse = await captureResponsePromise
  const captured = (await captureResponse.json()) as { revision: number; task_id: string }
  expect(captureResponse.status()).toBe(201)
  expect(captured.revision).toBe(1)

  const row = page.getByRole('listitem').filter({ hasText: originalTitle })
  await row.getByRole('link').click()
  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await page.getByLabel('Title').fill(editedTitle)
  await page.getByLabel('Notes').fill('Accepted notes remain inspectable.')
  const editResponsePromise = page.waitForResponse((response) => response.url().endsWith('/commands/edit-task'))
  await page.getByRole('button', { name: 'Save changes' }).click()
  const editResponse = await editResponsePromise
  expect(editResponse.ok()).toBe(true)
  await expect(page.getByText('Task saved.')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Activity' })).toBeVisible()

  const undoResponsePromise = page.waitForResponse((response) => response.url().endsWith('/commands/undo-task'))
  await page.getByRole('button', { name: 'Undo task edit' }).click()
  const undoResponse = await undoResponsePromise
  const undone = (await undoResponse.json()) as { revision: number }
  expect(undoResponse.ok()).toBe(true)
  await expect(page.getByLabel('Title')).toHaveValue(originalTitle)

  const planMutationId = randomUUID()
  const plannedResponse = await command(page, baseURL, csrfToken, 'plan-for-today', {
    base_planned_on: null,
    expected_revision: undone.revision,
    mutation_id: planMutationId,
    task_id: captured.task_id,
    version: 1,
  })
  expect(plannedResponse.ok()).toBe(true)
  const planned = (await plannedResponse.json()) as { revision: number }

  const mismatchResponse = await command(page, baseURL, csrfToken, 'plan-for-today', {
    base_planned_on: null,
    expected_revision: undone.revision,
    mutation_id: planMutationId,
    task_id: captured.task_id,
    version: 1,
  })
  expect(await mismatchResponse.json()).toEqual(await plannedResponse.json())

  const clarifyResponse = await command(page, baseURL, csrfToken, 'clarify-task', {
    base_values: {},
    expected_revision: planned.revision,
    fields: {},
    mutation_id: randomUUID(),
    task_id: captured.task_id,
    version: 1,
  })
  expect(clarifyResponse.ok()).toBe(true)

  await page.goto('/today')
  await expect(page.getByRole('heading', { level: 1, name: 'Today' })).toBeVisible()
  const clarifiedRow = page.getByRole('listitem').filter({ hasText: originalTitle })
  await expect(clarifiedRow).toBeVisible()
  await clarifiedRow.getByRole('link').click()
  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await expect(page.getByLabel('Title')).toHaveValue(originalTitle)

  await page.goto('/today')
  const completeResponsePromise = page.waitForResponse((response) => response.url().endsWith('/commands/complete-task'))
  await page.getByRole('button', { name: `Complete “${originalTitle}”` }).click()
  const completed = (await (await completeResponsePromise).json()) as { revision: number }

  await page.goto('/completed')
  const completedRow = page.getByRole('listitem').filter({ hasText: originalTitle })
  await expect(completedRow).toBeVisible()
  await completedRow.getByRole('link').click()
  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await expect(page.getByLabel('Title')).toHaveValue(originalTitle)

  await page.goto('/completed')
  const reopenResponsePromise = page.waitForResponse((response) => response.url().endsWith('/commands/reopen-task'))
  await page.getByRole('button', { name: `Reopen “${originalTitle}”` }).click()
  const reopened = (await (await reopenResponsePromise).json()) as { revision: number }
  expect(reopened.revision).toBe(completed.revision + 1)

  const trashResponse = await command(page, baseURL, csrfToken, 'trash-task', {
    expected_revision: reopened.revision,
    mutation_id: randomUUID(),
    task_id: captured.task_id,
    version: 1,
  })
  expect(trashResponse.ok()).toBe(true)
  await page.goto('/trash')
  await expect(page.getByRole('heading', { name: 'Trash' })).toBeVisible()
  const restoreResponsePromise = page.waitForResponse((response) => response.url().endsWith('/commands/restore-task'))
  await page.getByRole('button', { name: `Restore “${originalTitle}”` }).click()
  const restored = (await (await restoreResponsePromise).json()) as { revision: number }
  await expect(page.getByText('Trash is empty')).toBeVisible()

  const firstEdit = await command(page, baseURL, csrfToken, 'edit-task', {
    base_values: { title: originalTitle },
    expected_revision: restored.revision,
    fields: { title: editedTitle },
    mutation_id: randomUUID(),
    task_id: captured.task_id,
    version: 1,
  })
  expect(firstEdit.ok()).toBe(true)
  const conflictMutationId = randomUUID()
  const conflictBody = {
    base_values: { title: originalTitle },
    expected_revision: restored.revision,
    fields: { title: 'Competing stale title' },
    mutation_id: conflictMutationId,
    task_id: captured.task_id,
    version: 1,
  }
  const conflict = await command(page, baseURL, csrfToken, 'edit-task', conflictBody)
  expect(conflict.status()).toBe(409)
  const persistedConflict = await conflict.json()
  const conflictReplay = await command(page, baseURL, csrfToken, 'edit-task', conflictBody)
  expect(await conflictReplay.json()).toEqual(persistedConflict)

  const csrfAbuse = await page.request.post('/api/v1/commands/trash-task', {
    data: {
      expected_revision: (await firstEdit.json() as { revision: number }).revision,
      mutation_id: randomUUID(),
      task_id: captured.task_id,
      version: 1,
    },
    headers: { origin: new URL(baseURL).origin },
  })
  expect(csrfAbuse.status()).toBe(403)

  for (const [path, heading] of [
    ['/', 'Inbox'],
    ['/upcoming', 'Upcoming'],
    ['/completed', 'Completed'],
    ['/settings/sessions', 'Sessions'],
  ] as const) {
    await page.goto(path)
    await expect(page.getByRole('heading', { level: 1, name: heading })).toBeVisible()
  }

  await page.goto(`/tasks/${encodeURIComponent(captured.task_id)}`)
  await expect(page.getByRole('heading', { name: 'Activity' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Activity' }).getByRole('list')).toBeVisible()

  testInfo.annotations.push({
    description: 'login/session, capture, editor, undo, Today, complete/reopen, Trash/restore, persisted conflict, CSRF, lists, activity',
    type: 'PHASE1-LIFECYCLE',
  })
})
