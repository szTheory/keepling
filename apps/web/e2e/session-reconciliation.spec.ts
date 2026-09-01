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

const afterCommitHeaders = (route: Route) => ({
  ...route.request().headers(),
  'x-keepling-test-fault': 'after_commit',
  'x-keepling-test-fault-token': faultToken,
})

test('@session-reconciliation @uat-accessibility converges rename, revoke, and logout after committed responses are lost', async ({
  baseURL,
  browser,
  page,
}) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')

  await authenticate(page, baseURL)
  const otherContext = await browser.newContext()
  const otherPage = await otherContext.newPage()
  const otherAuthentication = await authenticate(otherPage, baseURL)
  const inventoryResponse = await otherPage.request.get('/api/v1/sessions')
  expect(inventoryResponse.ok()).toBe(true)
  const inventory = (await inventoryResponse.json()) as {
    sessions: Array<{ current: boolean; id: string }>
  }
  const otherCurrent = inventory.sessions.find((session) => session.current)
  expect(otherCurrent).toBeTruthy()

  const targetLabel = 'Recovery target'
  const named = await otherPage.request.patch(`/api/v1/sessions/${otherCurrent!.id}`, {
    data: { label: targetLabel, version: 1 },
    headers: {
      origin: new URL(baseURL).origin,
      'x-csrf-token': otherAuthentication.csrf_token,
    },
  })
  expect(named.ok()).toBe(true)

  const sessionMutations: Array<{ method: string; path: string }> = []
  const armedSessionMethods = new Set(['PATCH', 'DELETE'])
  await page.route('**/api/v1/sessions/*', async (route) => {
    const method = route.request().method()
    sessionMutations.push({ method, path: new URL(route.request().url()).pathname })
    if (armedSessionMethods.delete(method)) {
      await route.continue({ headers: afterCommitHeaders(route) })
    } else {
      await route.continue()
    }
  })

  const logoutRequests: string[] = []
  let logoutArmed = true
  await page.route('**/api/v1/logout', async (route) => {
    logoutRequests.push(route.request().postData() ?? '')
    if (logoutArmed) {
      logoutArmed = false
      await route.continue({ headers: afterCommitHeaders(route) })
    } else {
      await route.continue()
    }
  })

  await page.goto('/settings/sessions')
  const targetInput = page.getByRole('textbox', {
    exact: true,
    name: `Label for ${targetLabel}`,
  })
  await expect(targetInput).toHaveValue(targetLabel)

  const acceptedLabel = 'After commit renamed'
  await targetInput.fill(acceptedLabel)
  await page.getByRole('button', { name: `Save label for ${targetLabel}` }).click()

  await expect(
    page.getByRole('textbox', { exact: true, name: `Label for ${acceptedLabel}` }),
  ).toHaveValue(acceptedLabel)
  await expect(
    page.getByText(`Session label changed to ${acceptedLabel}.`, { exact: true }),
  ).toHaveText(`Session label changed to ${acceptedLabel}.`)
  expect(sessionMutations.filter(({ method }) => method === 'PATCH')).toHaveLength(1)

  await page.getByRole('button', { name: `Revoke ${acceptedLabel}` }).click()
  await page.getByRole('button', { name: 'Revoke session' }).click()

  await expect(
    page.getByRole('textbox', { exact: true, name: `Label for ${acceptedLabel}` }),
  ).not.toBeVisible()
  await expect(page.getByText(`${acceptedLabel} revoked.`, { exact: true })).toHaveText(
    `${acceptedLabel} revoked.`,
  )
  expect(sessionMutations.filter(({ method }) => method === 'DELETE')).toHaveLength(1)

  const serverInventory = await page.request.get('/api/v1/sessions')
  expect(serverInventory.ok()).toBe(true)
  const remaining = (await serverInventory.json()) as {
    sessions: Array<{ id: string; label: string }>
  }
  expect(remaining.sessions.some(({ id }) => id === otherCurrent!.id)).toBe(false)

  await page.getByRole('button', { name: 'Log out this browser' }).click()
  await page.getByRole('button', { exact: true, name: 'Log out' }).click()

  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
  expect(logoutRequests).toHaveLength(1)

  await otherContext.close()
})
