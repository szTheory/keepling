import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import AppShell from '@/app/AppShell'

vi.mock('@/features/recovery/RecoveryStrip', () => ({
  default: () => <div>Recovery action</div>,
}))

vi.mock('@/features/sessions/SessionList', () => ({
  default: () => <div>Session inventory</div>,
}))

const repositoryFile = (relativePath: string) =>
  readFileSync(resolve(process.cwd(), '../..', relativePath), 'utf8')

describe('approved Phase 1 UI contract', () => {
  it('keeps DTCG source and generated CSS in exact semantic sync', () => {
    const tokens = JSON.parse(repositoryFile('packages/design-tokens/tokens.json')) as {
      layout: Record<string, { $value: string }>
      motion: Record<string, { $value: string }>
      space: Record<string, { $value: string }>
      typography: Record<string, { $value: string }>
    }
    const generated = repositoryFile('packages/design-tokens/css.css')

    expect(Object.values(tokens.space).map(({ $value }) => $value)).toEqual([
      '4px',
      '8px',
      '16px',
      '24px',
      '32px',
      '48px',
      '64px',
    ])
    expect(Object.values(tokens.typography).map(({ $value }) => $value)).toEqual([
      '14px',
      '16px',
      '20px',
      '28px',
    ])
    expect(tokens.layout).toMatchObject({
      detailMin: { $value: '480px' },
      listMax: { $value: '440px' },
      listMin: { $value: '360px' },
      nav: { $value: '224px' },
      target: { $value: '44px' },
    })
    expect(tokens.motion).toMatchObject({
      direct: { $value: '160ms' },
      overlay: { $value: '180ms' },
      reduced: { $value: '100ms' },
    })
    expect(generated).toContain('--keepling-layout-nav: 224px;')
    expect(generated).toContain('--keepling-color-canvas: #f7f2e8;')
    expect(generated).toContain('--keepling-dark-color-accent: #d29abf;')
  })

  it('exposes reachable landmarks, navigation, 44px targets, and one live region', () => {
    window.history.replaceState({}, '', '/settings/sessions')
    render(<AppShell csrfToken="csrf" onLoggedOut={vi.fn()} />)

    expect(screen.getByRole('banner')).toBeInTheDocument()
    const navigation = screen.getByRole('navigation', { name: 'Keepling' })
    for (const label of [
      'Inbox',
      'Today',
      'Upcoming',
      'Completed',
      'Projects',
      'Tags',
      'Trash',
      'Sessions',
    ]) {
      expect(within(navigation).getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(within(navigation).getByRole('link', { name: 'Sessions' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    expect(screen.getByRole('main')).toHaveAttribute('id', 'main-content')
    expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite')

    for (const link of within(navigation).getAllByRole('link')) {
      expect(link).toHaveClass('min-h-[var(--keepling-layout-target)]')
    }
  })

  it('keeps dirty-navigation choice explicit and initially focuses Stay here', async () => {
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/settings/sessions')
    render(<AppShell csrfToken="csrf" hasDirtyWork onLoggedOut={vi.fn()} />)

    await user.click(screen.getByRole('link', { name: 'Inbox' }))

    const dialog = screen.getByRole('alertdialog', { name: 'Unsaved changes' })
    expect(within(dialog).getByRole('button', { name: 'Save changes' })).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Discard changes' })).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Stay here' })).toHaveFocus()
  })

  it('encodes theme, forced-color, zoom/reflow, focus, and reduced-motion contracts', () => {
    const css = `${repositoryFile('packages/design-tokens/css.css')}\n${repositoryFile('apps/web/src/index.css')}`

    expect(css).toContain('@media (prefers-color-scheme: dark)')
    expect(css).toContain('@media (forced-colors: active)')
    expect(css).toContain('@media (prefers-reduced-motion: reduce)')
    expect(css).toContain('@media (max-width: 1023px)')
    expect(css).toContain('outline: 2px solid var(--ring)')
    expect(css).toContain('min-width: 0')
    expect(css).toContain('overflow-x: hidden')
  })
})
