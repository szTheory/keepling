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

const faultHeaders = (route: Route) => ({
  ...route.request().headers(),
  'x-keepling-test-fault': 'authentication_before_acceptance',
  'x-keepling-test-fault-token': faultToken,
})

test('@modal-keyboard dirty editing and capture authentication use the exact safe contracts', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill('Modal keyboard task')
  await page.getByRole('button', { name: 'Add task' }).click()
  await page.getByRole('link', { name: 'Modal keyboard task' }).click()

  const notes = page.getByLabel('Notes')
  await notes.fill('Draft stays here')
  const trigger = page.getByRole('button', { name: 'Cancel editing' })
  await trigger.focus()
  await trigger.press('Enter')

  const dialog = page.getByRole('alertdialog', { name: 'Discard unsaved changes?' })
  await expect(dialog).toContainText('These edits haven’t been saved.')
  await expect(dialog.getByRole('button', { name: 'Save changes' })).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Discard changes' })).toBeVisible()
  const keepEditing = dialog.getByRole('button', { name: 'Keep editing' })
  await expect(keepEditing).toBeFocused()

  await page.keyboard.press('Shift+Tab')
  await expect(dialog.getByRole('button', { name: 'Discard changes' })).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(keepEditing).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(trigger).toBeFocused()
  await expect(notes).toHaveValue('Draft stays here')

  await page.goto('/')
  await page.route('**/api/v1/commands/capture-task', async (route) => {
    await route.continue({ headers: faultHeaders(route) })
  })
  const capture = page.getByLabel('What do you want to keep?')
  await capture.fill('Authentication keeps capture text')
  await page.getByRole('button', { name: 'Add task' }).click()

  await expect(
    page.getByText('Sign in again to finish saving. Your changes are still here.'),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in and continue' })).toBeVisible()
  await expect(capture).toHaveValue('Authentication keeps capture text')
})

test('@modal-keyboard session confirmation contains focus and distinguishes logout', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  await page.goto('/settings/sessions')

  const revoke = page.getByRole('button', { name: /^Revoke / }).first()
  await revoke.click()
  const revokeDialog = page.getByRole('alertdialog')
  await expect(revokeDialog).toContainText('Keepling on that device will need to sign in again.')
  const keepActive = revokeDialog.getByRole('button', { name: 'Keep session active' })
  await expect(keepActive).toBeFocused()
  await page.keyboard.press('Shift+Tab')
  await expect(revokeDialog.getByRole('button', { name: 'Revoke session' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(revoke).toBeFocused()

  const logout = page.getByRole('button', { name: 'Log out this browser' })
  await logout.click()
  const logoutDialog = page.getByRole('alertdialog', { name: 'Log out this browser?' })
  await expect(logoutDialog).toContainText('The current browser will sign out.')
  await expect(logoutDialog.getByRole('button', { name: 'Keep editing' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(logout).toBeFocused()
})
