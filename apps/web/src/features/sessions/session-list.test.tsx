import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import SessionList from '@/features/sessions/SessionList'

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const problem = (code = 'service_unavailable', status = 503) => ({
  code,
  recovery_action: 'check_again',
  retryable: true,
  status,
  title: 'Request could not be completed',
  type: `https://keepling.test/problems/${code}`,
})

const currentSession = {
  client_kind: 'web',
  coarse_activity: 'active_now',
  created_at: '2026-08-30T18:00:00Z',
  current: true,
  id: 'session-current',
  label: 'Home browser',
}

const otherSession = {
  client_kind: 'iphone',
  coarse_activity: 'today',
  created_at: '2026-08-29T16:00:00Z',
  current: false,
  id: 'session-other',
  label: 'Phone',
}

const sessionsResponse = (sessions = [currentSession, otherSession]) =>
  jsonResponse({ sessions })

afterEach(() => vi.unstubAllGlobals())

describe('uncertain session administration', () => {
  it('proves an after-commit rename from the authoritative inventory without retrying the write', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(
        sessionsResponse([currentSession, { ...otherSession, label: 'Travel phone' }]),
      )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={vi.fn()} />)

    const label = await screen.findByLabelText('Label for Phone')
    await user.clear(label)
    await user.type(label, 'Travel phone')
    await user.click(screen.getByRole('button', { name: 'Save label for Phone' }))

    expect(await screen.findByText('Session label changed to Travel phone.')).toBeVisible()
    expect(screen.getByLabelText('Label for Travel phone')).toHaveValue('Travel phone')
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === 'PATCH')).toHaveLength(1)
  })

  it('reports an uncertain rename as unchanged only after inventory proves the old label', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(sessionsResponse())
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={vi.fn()} />)

    const label = await screen.findByLabelText('Label for Phone')
    await user.clear(label)
    await user.type(label, 'Travel phone')
    await user.click(screen.getByRole('button', { name: 'Save label for Phone' }))

    expect(await screen.findByText('Phone was not renamed. The existing label is unchanged.')).toBeVisible()
    expect(screen.getByLabelText('Label for Phone')).toHaveValue('Phone')
  })

  it('keeps an unreadable rename explicitly unknown and Check again repeats only the read', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockRejectedValueOnce(new TypeError('inventory unavailable'))
      .mockResolvedValueOnce(
        sessionsResponse([currentSession, { ...otherSession, label: 'Travel phone' }]),
      )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={vi.fn()} />)

    const label = await screen.findByLabelText('Label for Phone')
    await user.clear(label)
    await user.type(label, 'Travel phone')
    await user.click(screen.getByRole('button', { name: 'Save label for Phone' }))

    expect(
      await screen.findByText('Keepling could not confirm whether Phone was renamed.'),
    ).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Check rename again' }))

    expect(await screen.findByText('Session label changed to Travel phone.')).toBeVisible()
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === 'PATCH')).toHaveLength(1)
  })

  it('proves an after-commit revocation from absence without retrying DELETE', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(sessionsResponse([currentSession]))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={vi.fn()} />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Phone' }))
    await user.click(screen.getByRole('button', { name: 'Revoke session' }))

    expect(await screen.findByText('Phone revoked.')).toBeVisible()
    expect(screen.queryByLabelText('Label for Phone')).not.toBeInTheDocument()
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === 'DELETE')).toHaveLength(1)
  })

  it('reports an uncertain revocation as active only after inventory proves presence', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(sessionsResponse())
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={vi.fn()} />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Phone' }))
    await user.click(screen.getByRole('button', { name: 'Revoke session' }))

    expect(await screen.findByText('Phone remains active.')).toBeVisible()
    expect(screen.getByLabelText('Label for Phone')).toBeVisible()
  })

  it('proves current-session logout only when the authenticated probe says the session is gone', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(jsonResponse(problem('authentication_required', 401), 401))
    vi.stubGlobal('fetch', fetchMock)
    const onLoggedOut = vi.fn()
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={onLoggedOut} />)

    await user.click(await screen.findByRole('button', { name: 'Log out this browser' }))
    await user.click(screen.getByRole('button', { name: 'Log out' }))

    await waitFor(() => expect(onLoggedOut).toHaveBeenCalledOnce())
    expect(fetchMock.mock.calls.filter(([input]) => String(input) === '/api/v1/logout')).toHaveLength(1)
  })

  it('reports current-session logout as still signed in only after an authenticated probe', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(jsonResponse({ csrf_token: 'still-authenticated' }))
    vi.stubGlobal('fetch', fetchMock)
    const onLoggedOut = vi.fn()
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={onLoggedOut} />)

    await user.click(await screen.findByRole('button', { name: 'Log out this browser' }))
    await user.click(screen.getByRole('button', { name: 'Log out' }))

    expect(await screen.findByText('This browser is still signed in.')).toBeVisible()
    expect(onLoggedOut).not.toHaveBeenCalled()
  })

  it('keeps an unreadable logout unknown and Check again repeats only the authentication probe', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(sessionsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockRejectedValueOnce(new TypeError('session probe unavailable'))
      .mockResolvedValueOnce(jsonResponse(problem('authentication_required', 401), 401))
    vi.stubGlobal('fetch', fetchMock)
    const onLoggedOut = vi.fn()
    const user = userEvent.setup()

    render(<SessionList csrfToken="csrf" hasDirtyWork={false} onLoggedOut={onLoggedOut} />)

    await user.click(await screen.findByRole('button', { name: 'Log out this browser' }))
    await user.click(screen.getByRole('button', { name: 'Log out' }))

    expect(
      await screen.findByText('Keepling could not confirm whether this browser was logged out.'),
    ).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Check logout again' }))

    await waitFor(() => expect(onLoggedOut).toHaveBeenCalledOnce())
    expect(fetchMock.mock.calls.filter(([input]) => String(input) === '/api/v1/logout')).toHaveLength(1)
  })
})
