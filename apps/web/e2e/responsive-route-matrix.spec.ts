import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'

const authenticate = async (page: Page, baseURL: string | undefined) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  const response = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(response.ok()).toBe(true)
}

const capture = async (page: Page, title: string) => {
  await page.goto('/')
  await page.getByLabel('What do you want to keep?').fill(title)
  await page.getByRole('button', { name: 'Add task' }).click()
  const row = page.getByRole('listitem').filter({ hasText: title })
  await expect(row).toBeVisible()
  return row
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
    await expect(page.getByRole('button', { name: 'Close navigation' })).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(trigger).toBeFocused()
    await expect(page).toHaveURL(/\/$/)

    await trigger.press('Enter')
    await navigation.getByRole('link', { name: 'Today' }).focus()
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/today$/)
    await expect(page.getByRole('heading', { exact: true, name: 'Today' })).toBeVisible()

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

test('@responsive-route-matrix preserves the amended 1024 and 1064 workspace boundaries', async ({
  baseURL,
  page,
}) => {
  await authenticate(page, baseURL)
  const row = await capture(page, 'Boundary workspace task')

  for (const width of [1024, 1064] as const) {
    await page.setViewportSize({ height: 900, width })
    await row.getByRole('link').click()

    const navigation = page.locator('[data-workspace-region="navigation"]')
    const list = page.locator('[data-workspace-region="list"]')
    const detail = page.locator('[data-workspace-region="detail"]')
    const dimensions = await Promise.all([
      navigation.boundingBox(),
      list.boundingBox(),
      detail.boundingBox(),
    ])

    expect(dimensions[1]?.width).toBeGreaterThanOrEqual(360)
    expect(dimensions[2]?.width).toBeGreaterThanOrEqual(480)
    if (width === 1024) {
      await expect(page.getByRole('button', { name: 'Open navigation' })).toBeVisible()
      await expect(navigation).toBeHidden()
    } else {
      await expect(page.getByRole('button', { name: 'Open navigation' })).toBeHidden()
      await expect(navigation).toBeVisible()
      expect(dimensions[0]?.width).toBe(224)
    }

    const overflow = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }))
    expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth)
    await page.goto('/')
  }
})
