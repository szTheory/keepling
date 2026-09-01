import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'

const authenticate = async (page: Page, baseURL: string | undefined) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const response = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(response.ok()).toBe(true)
}

for (const width of [320, 1024] as const) {
  test(`@responsive-route-matrix ${width}px drawer reaches primary routes by keyboard`, async ({
    baseURL,
    page,
  }) => {
    await authenticate(page, baseURL)
    await page.setViewportSize({ height: 900, width })
    await page.goto('/')

    const trigger = page.getByRole('button', { name: 'Open navigation' })
    await trigger.focus()
    await page.keyboard.press('Enter')

    const navigation = page.getByRole('navigation', { name: 'Primary navigation' })
    await expect(navigation).toBeVisible()
    await expect(navigation.getByRole('link', { name: 'Inbox' })).toBeFocused()
    await expect(navigation.getByRole('link', { name: 'Today' })).not.toHaveAttribute(
      'aria-current',
      'page',
    )

    await page.keyboard.press('Shift+Tab')
    await expect(navigation.getByRole('button', { name: 'Close navigation' })).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(trigger).toBeFocused()
    await expect(page).toHaveURL(/\/$/)

    await trigger.press('Enter')
    await navigation.getByRole('link', { name: 'Today' }).focus()
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/today$/)
    await expect(page.getByRole('heading', { name: 'Today' })).toBeVisible()

    const todayTrigger = page.getByRole('button', { name: 'Open navigation' })
    await todayTrigger.press('Enter')
    await navigation.getByRole('link', { name: 'Sessions' }).focus()
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/settings\/sessions$/)
    await expect(page.getByRole('heading', { name: 'Sessions' })).toBeVisible()

    const accessibility = await new AxeBuilder({ page }).analyze()
    expect(
      accessibility.violations.filter(({ impact }) => impact === 'serious' || impact === 'critical'),
    ).toEqual([])
  })
}
