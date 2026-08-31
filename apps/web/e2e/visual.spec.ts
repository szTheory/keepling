import { expect, test, type Page, type TestInfo } from '@playwright/test'

const viewports = [320, 768, 1024, 1440] as const
const themes = ['light', 'dark'] as const

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

const record = async (
  testInfo: TestInfo,
  marker: 'UI-BACKSTOP-LONG-TEXT' | 'UI-BACKSTOP-OVERFLOW',
  facts: unknown,
) => {
  testInfo.annotations.push({ description: JSON.stringify(facts), type: marker })
  await testInfo.attach(`${marker}.json`, {
    body: Buffer.from(JSON.stringify({ marker, facts }, null, 2)),
    contentType: 'application/json',
  })
}

test('@visual-contract UI-BACKSTOP-OVERFLOW proves reflow, themes, focus, and motion independently', async ({
  baseURL,
  page,
}, testInfo) => {
  await authenticate(page, baseURL)
  const title = `Overflow proof ${'calm dependable task '.repeat(8)}`.slice(0, 200)
  const row = await capture(page, title)
  const observations: Array<Record<string, unknown>> = []

  for (const width of viewports) {
    await page.setViewportSize({ height: 900, width })
    for (const theme of themes) {
      await page.evaluate((nextTheme) => {
        document.documentElement.classList.toggle('dark', nextTheme === 'dark')
        document.documentElement.classList.toggle('light', nextTheme === 'light')
      }, theme)
      await expect(row).toBeVisible()
      const dimensions = await page.evaluate(() => ({
        clientWidth: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
      }))
      expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth)
      const name = `overflow-${String(width)}-${theme}.png`
      await testInfo.attach(name, {
        body: await page.screenshot({ animations: 'disabled', fullPage: true }),
        contentType: 'image/png',
      })
      observations.push({ dimensions, theme, width })
    }
  }

  await page.setViewportSize({ height: 900, width: 640 })
  await page.evaluate(() => {
    document.documentElement.style.zoom = '2'
  })
  const zoomed = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }))
  expect(zoomed.scrollWidth).toBeLessThanOrEqual(zoomed.clientWidth)
  await page.evaluate(() => {
    document.documentElement.style.zoom = ''
  })

  await page.emulateMedia({ forcedColors: 'active' })
  const focusTarget = page.getByLabel('What do you want to keep?')
  await focusTarget.focus()
  await focusTarget.press('Tab')
  await page.keyboard.press('Shift+Tab')
  await expect(focusTarget).toBeFocused()
  expect(await page.evaluate(() => matchMedia('(forced-colors: active)').matches)).toBe(true)
  expect(await focusTarget.evaluate((element) => getComputedStyle(element).outlineStyle)).not.toBe('none')
  await page.emulateMedia({ forcedColors: 'none', reducedMotion: 'reduce' })
  const reducedDuration = await focusTarget.evaluate((element) => getComputedStyle(element).transitionDuration)
  expect(['0s', '0.00001s', '1e-05s', '0.1s']).toContain(reducedDuration)

  await record(testInfo, 'UI-BACKSTOP-OVERFLOW', {
    forcedColors: 'focus outline retained',
    observations,
    reducedMotion: reducedDuration,
    zoom200: zoomed,
  })
})

test('@visual-contract UI-BACKSTOP-LONG-TEXT proves content and controls remain readable independently', async ({
  baseURL,
  page,
}, testInfo) => {
  await authenticate(page, baseURL)
  const title = `Long title ${'trusted plain text '.repeat(12)}`.slice(0, 200)
  const notes = 'Long note content. '.repeat(625).slice(0, 10_000)
  const row = await capture(page, title)

  await row.getByRole('link').click()
  await expect(page.getByRole('heading', { name: 'Edit task' })).toBeVisible()
  await page.getByLabel('Notes').fill(notes)
  await page.getByRole('button', { name: 'Save changes' }).click()
  await expect(page.getByText('Task saved.')).toBeVisible()
  await expect(page.getByLabel('Notes')).toHaveValue(notes)

  const organizationName = `Project ${'with a deliberately long readable name '.repeat(6)}`.slice(0, 200)
  await page.goto('/projects')
  await page.getByLabel('New project name').fill(organizationName)
  await page.getByRole('button', { name: 'Create project' }).click()
  await expect(page.getByRole('textbox', { name: `Rename ${organizationName}` })).toHaveValue(
    organizationName,
  )
  const archiveAction = page.getByRole('button', { name: `Archive ${organizationName}` })
  await expect(archiveAction).toBeVisible()

  await page.goto('/settings/sessions')
  const sessionLabel = `Browser ${'with an intentionally descriptive label '.repeat(3)}`.slice(0, 120)
  const labelInput = page.getByRole('textbox', { name: /^Label for / }).first()
  await labelInput.fill(sessionLabel)
  await page.getByRole('button', { name: /^Save label for / }).first().click()
  await expect(page.getByRole('textbox', { name: `Label for ${sessionLabel}` })).toHaveValue(
    sessionLabel,
  )

  await page.setViewportSize({ height: 900, width: 320 })
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }))
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth)
  const longControl = page.getByRole('button', { name: 'Log out this browser' })
  await expect(longControl).toBeVisible()
  expect(await longControl.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true)

  await testInfo.attach('long-text-320.png', {
    body: await page.screenshot({ animations: 'disabled', fullPage: true }),
    contentType: 'image/png',
  })
  await record(testInfo, 'UI-BACKSTOP-LONG-TEXT', {
    actionCopy: 'long organization archive action remained reachable',
    dimensions,
    notesLength: notes.length,
    organizationLength: organizationName.length,
    sessionLabelLength: sessionLabel.length,
    titleLength: title.length,
  })
})
