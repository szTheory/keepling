import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import Reauthenticate, { type InterruptedIntent } from '@/features/auth/Reauthenticate'

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const problem = (code: string, detail: string, status = 422) => ({
  code,
  detail,
  recovery_action: 'request_new_link',
  retryable: false,
  status,
  title: 'Request could not be completed',
  type: `https://keepling.test/problems/${code}`,
})

afterEach(() => {
  vi.unstubAllGlobals()
  window.history.replaceState({}, '', '/')
})

describe('closed browser authentication', () => {
  it('routes an operator setup token through an explicit valid IANA timezone', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ status: 'setup_complete', timezone: 'America/New_York' }, 201),
    )
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/setup/setup-token')

    const user = userEvent.setup()
    render(<AppRoutes authenticated={false} />)

    await user.type(screen.getByLabelText('Password'), 'correct horse battery staple')
    await user.type(screen.getByLabelText('Account timezone'), 'America/New_York')
    await user.click(screen.getByRole('button', { name: 'Create account' }))

    await expect(screen.findByRole('status')).resolves.toHaveTextContent(
      'Account created. Sign in to continue.',
    )
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/setup',
      expect.objectContaining({
        body: JSON.stringify({
          password: 'correct horse battery staple',
          timezone: 'America/New_York',
          token: 'setup-token',
          version: 1,
        }),
        method: 'POST',
      }),
    )
    expect(screen.queryByRole('link', { name: /register/i })).not.toBeInTheDocument()
  })

  it('keeps setup terminal and validation states explicit without submitting an invalid timezone', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/setup/setup-token')

    const user = userEvent.setup()
    render(<AppRoutes authenticated={false} />)

    await user.type(screen.getByLabelText('Password'), 'long pasted password')
    await user.type(screen.getByLabelText('Account timezone'), 'Eastern-ish')
    await user.click(screen.getByRole('button', { name: 'Create account' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a valid IANA timezone')
    expect(screen.getByLabelText('Account timezone')).toHaveFocus()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('supports password managers, paste, and a named login reveal control', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ csrf_token: 'rotated-csrf', status: 'authenticated' }),
    )
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/login')

    const onAuthenticated = vi.fn()
    const user = userEvent.setup()
    render(<AppRoutes authenticated={false} onAuthenticated={onAuthenticated} />)

    const password = screen.getByLabelText('Password')
    expect(password).toHaveAttribute('autocomplete', 'current-password')
    await user.click(password)
    await user.paste('this password has spaces and punctuation !')
    await user.click(screen.getByRole('button', { name: 'Show password' }))
    expect(password).toHaveAttribute('type', 'text')
    expect(screen.getByRole('button', { name: 'Hide password' })).toBeVisible()
    await user.type(screen.getByLabelText('Session label'), 'Home browser')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    await waitFor(() => expect(onAuthenticated).toHaveBeenCalledWith('rotated-csrf'))
  })

  it('routes recovery tokens and names their one-use terminal state honestly', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(problem('recovery_unavailable', 'Request a new recovery link.'), 422),
    )
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/recover/recovery-token')

    const user = userEvent.setup()
    render(<AppRoutes authenticated={false} />)

    expect(screen.getByLabelText('New password')).toHaveAttribute('autocomplete', 'new-password')
    await user.type(screen.getByLabelText('New password'), 'replacement password')
    await user.type(screen.getByLabelText('Session label'), 'Recovered browser')
    await user.click(screen.getByRole('button', { name: 'Set new password' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'This recovery link is invalid, expired, or already used.',
    )
    expect(screen.getByRole('link', { name: 'Return to sign in' })).toBeVisible()
  })
})

describe('reauthentication interruption', () => {
  it('returns the exact submitted-unknown intent after password reauthentication', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ csrf_token: 'new-csrf', status: 'recently_authenticated' }),
    )
    vi.stubGlobal('fetch', fetchMock)
    const interruption = {
      kind: 'submitted-unknown',
      mutationId: 'original-mutation-identity',
    } satisfies InterruptedIntent
    const onAuthenticated = vi.fn()
    const user = userEvent.setup()

    render(
      <Reauthenticate
        csrfToken="old-csrf"
        interruption={interruption}
        onAuthenticated={onAuthenticated}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent(
      'Sign in again to finish saving. Your changes are still here.',
    )
    expect(screen.getByText('The submitted change will be checked with its original identity.')).toBeVisible()
    expect(screen.getByLabelText('Password')).toHaveFocus()
    await user.type(screen.getByLabelText('Password'), 'reauth password')
    await user.click(screen.getByRole('button', { name: 'Sign in and continue' }))

    await waitFor(() =>
      expect(onAuthenticated).toHaveBeenCalledWith(interruption, 'new-csrf'),
    )
    expect(onAuthenticated.mock.calls[0]?.[0]).toBe(interruption)
  })
})
