/// <reference types="node" />

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import tokens from '../../../../packages/design-tokens/tokens.json'
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
  it('opens semantic primary navigation in a modal drawer and restores trigger focus', async () => {
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/today')
    render(<AppShell csrfToken="csrf" onLoggedOut={vi.fn()} />)

    const trigger = screen.getByRole('button', { name: 'Open navigation' })
    await user.click(trigger)

    const navigation = screen.getByRole('navigation', { name: 'Primary navigation' })
    for (const label of [
      'Inbox',
      'Today',
      'Upcoming',
      'Projects',
      'Tags',
      'Completed',
      'Trash',
      'Sessions',
    ]) {
      expect(within(navigation).getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(within(navigation).getByRole('link', { name: 'Today' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    await waitFor(() => {
      expect(within(navigation).getByRole('link', { name: 'Inbox' })).toHaveFocus()
    })

    await user.tab({ shift: true })
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Close navigation' })).toHaveFocus()
    })
    await user.keyboard('{Escape}')
    expect(trigger).toHaveFocus()
  })

  it('keeps DTCG source and generated CSS in exact semantic sync', () => {
    const generatedTokens = repositoryFile('packages/design-tokens/css.css')
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
    expect(generatedTokens).toContain('--keepling-layout-nav: 224px;')
    expect(generatedTokens).toContain('--keepling-color-canvas: #f7f2e8;')
    expect(generatedTokens).toContain('--keepling-dark-color-accent: #d29abf;')
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
    expect(css).toContain('@media (min-width: 1024px)')
    expect(css).toContain('@media (min-width: 1064px)')
    expect(css).toContain('outline: 2px solid var(--ring)')
    expect(css).toContain('min-width: 0')
    expect(css).toContain('overflow-x: hidden')
  })
})
