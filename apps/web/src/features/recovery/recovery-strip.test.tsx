import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import AppShell from '@/app/AppShell'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryStrip from '@/features/recovery/RecoveryStrip'

const availability = (overrides: Partial<{ expiresAt: string; handle: string; label: string }> = {}) => ({
  expiresAt: '2026-09-01T12:00:00.000000Z',
  handle: 'abcdefghijklmnopqrstuvwxyzABCDEFG0123456789_-',
  label: 'Undo completion',
  ...overrides,
})

const taskSnapshot = {
  captured_at: '2026-08-31T11:00:00.000000Z',
  completed_at: null,
  deadline_on: null,
  id: '11111111-1111-4111-8111-111111111111',
  inbox_state: 'inbox',
  notes: '',
  planned_on: null,
  project: null,
  revision: 3,
  tags: [],
  title: 'Recovered task',
  trashed_at: null,
}

const jsonResponse = (body: unknown, status = 200) =>
  Promise.resolve(
    new Response(JSON.stringify(body), {
      headers: { 'content-type': 'application/json' },
      status,
    }),
  )

describe('persistent semantic recovery', () => {
  beforeEach(() => {
    window.history.replaceState({}, '', '/')
    vi.restoreAllMocks()
  })

  it('keeps only the latest precise action across route changes without rendering its handle', () => {
    render(
      <AppShell
        csrfToken="csrf"
        inboxContent={<main id="main-content">Inbox</main>}
        onLoggedOut={vi.fn()}
      />,
    )

    fireEvent(
      window,
      new CustomEvent('keepling:undo-available', {
        detail: availability({ label: 'Undo task edit' }),
      }),
    )
    fireEvent(
      window,
      new CustomEvent('keepling:undo-available', {
        detail: availability({ handle: 'ZYXwvutsrqponmlkjihgfedcba9876543210_-ABCDE', label: 'Undo Trash' }),
      }),
    )

    expect(screen.getByText('Undo Trash')).toBeVisible()
    expect(screen.queryByText('Undo task edit')).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent('ZYXwvutsrqponmlkjihgfedcba9876543210_-ABCDE')

    window.history.pushState({}, '', '/settings/sessions')
    window.dispatchEvent(new PopStateEvent('popstate'))

    expect(screen.getByText('Undo Trash')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Undo Trash' })).toBeVisible()
  })

  it('retries an uncertain undo with the exact original mutation identity and reconciles acknowledgement', async () => {
    const user = userEvent.setup()
    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      .mockImplementationOnce(() => jsonResponse({ code: 'service_unavailable', title: 'Unavailable' }, 503))
      .mockImplementationOnce((_input, init) => {
        const request = JSON.parse(String(init?.body)) as Record<string, unknown>
        return jsonResponse({
          mutation_id: request.mutation_id,
          outcome: 'accepted',
          revision: 3,
          snapshot: taskSnapshot,
          task_id: taskSnapshot.id,
          warnings: [],
        })
      })

    render(<RecoveryStrip availability={availability()} csrfToken="csrf" onSettled={vi.fn()} />)

    await user.click(screen.getByRole('button', { name: 'Undo completion' }))
    expect(await screen.findByText('Checking whether undo was applied…')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const first = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body)) as Record<string, unknown>
    const second = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>

    expect(second.mutation_id).toBe(first.mutation_id)
    expect(second.handle).toBe(first.handle)
    expect(await screen.findByText('Change undone.')).toBeVisible()
    expect(document.body).not.toHaveTextContent(availability().handle)
  })

  it.each([
    ['undo_expired', 'expired', 'Undo expired. Nothing was changed.'],
    ['undo_stale', 'stale', 'This task changed after that action. Nothing was changed.'],
    ['undo_already_applied', 'already_applied', 'That change was already undone.'],
    ['undo_unknown', 'unknown', 'This undo is unavailable. Nothing was changed.'],
  ])('renders explicit %s no-change state', async (code, outcome, copy) => {
    const user = userEvent.setup()

    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) => {
      const request = JSON.parse(String(init?.body)) as Record<string, unknown>
      return jsonResponse(
        {
          code,
          mutation_id: request.mutation_id,
          outcome,
          recovery_action: null,
          retryable: false,
          title: 'No change',
        },
        outcome === 'unknown' ? 404 : 200,
      )
    })

    render(<RecoveryStrip availability={availability()} csrfToken="csrf" onSettled={vi.fn()} />)
    await user.click(screen.getByRole('button', { name: 'Undo completion' }))

    expect(await screen.findByText(copy)).toBeVisible()
  })

  it('does not intercept native text editing Cmd/Ctrl-Z', () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
    render(<RecoveryStrip availability={availability()} csrfToken="csrf" onSettled={vi.fn()} />)

    const input = document.createElement('textarea')
    document.body.append(input)
    input.focus()

    const macUndo = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'z', metaKey: true })
    const otherUndo = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ctrlKey: true, key: 'z' })
    input.dispatchEvent(macUndo)
    input.dispatchEvent(otherUndo)

    expect(macUndo.defaultPrevented).toBe(false)
    expect(otherUndo.defaultPrevented).toBe(false)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(document.activeElement).toBe(input)
  })

  it('continues the exact undo through reauthentication with rotated CSRF state', async () => {
    const user = userEvent.setup()
    const onAuthenticationRequired = vi.fn()

    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      .mockImplementationOnce(() =>
        jsonResponse(
          {
            code: 'authentication_required',
            recovery_action: 'sign_in',
            retryable: true,
            status: 401,
            title: 'Authentication required',
            type: '/problems/authentication_required',
          },
          401,
        ),
      )
      .mockImplementationOnce((_input, init) => {
        const request = JSON.parse(String(init?.body)) as Record<string, unknown>
        return jsonResponse({
          mutation_id: request.mutation_id,
          outcome: 'accepted',
          revision: 3,
          snapshot: taskSnapshot,
          task_id: taskSnapshot.id,
          warnings: [],
        })
      })

    render(
      <RecoveryStrip
        availability={availability()}
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        onSettled={vi.fn()}
      />,
    )
    await user.click(screen.getByRole('button', { name: 'Undo completion' }))

    expect(await screen.findByText('Sign in to continue undo. Nothing was changed.')).toBeVisible()
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())

    const firstRequest = String(fetchMock.mock.calls[0]?.[1]?.body)
    const firstIdentity = JSON.parse(firstRequest) as { mutation_id: string }
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      InterruptedIntent,
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toEqual({
      authentication: 'sign_in',
      kind: 'not-submitted',
      mutationId: firstIdentity.mutation_id,
    })

    await resume('rotated-csrf')

    expect(String(fetchMock.mock.calls[1]?.[1]?.body)).toBe(firstRequest)
    expect(fetchMock.mock.calls[1]?.[1]?.headers).toMatchObject({
      'x-csrf-token': 'rotated-csrf',
    })
    expect(await screen.findByText('Change undone.')).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Sign in' })).not.toBeInTheDocument()
  })

  it('keeps authentication-required explicit when no continuation host is available', async () => {
    const user = userEvent.setup()

    vi.spyOn(globalThis, 'fetch').mockImplementation(() =>
      jsonResponse(
        {
          code: 'authentication_required',
          recovery_action: 'sign_in',
          retryable: true,
          status: 401,
          title: 'Authentication required',
          type: '/problems/authentication_required',
        },
        401,
      ),
    )

    render(<RecoveryStrip availability={availability()} csrfToken="csrf" onSettled={vi.fn()} />)
    await user.click(screen.getByRole('button', { name: 'Undo completion' }))

    expect(await screen.findByText('Sign in to continue undo. Nothing was changed.')).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Sign in' })).not.toBeInTheDocument()
  })
})
