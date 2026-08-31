import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppShell from '@/app/AppShell'
import { AuthProvider, useAuth } from '@/app/AuthProvider'
import AppRoutes from '@/app/routes'
import Reauthenticate, { type InterruptedIntent } from '@/features/auth/Reauthenticate'
import QuickCapture from '@/features/capture/QuickCapture'

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
  it('drains continuations registered and replaced while a drain is active', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse({ csrf_token: 'initial-csrf', status: 'authenticated' }),
      ),
    )
    let releaseFirst!: () => void
    const firstResume = vi.fn(
      () => new Promise<void>((resolve) => {
        releaseFirst = resolve
      }),
    )
    const differentResume = vi.fn().mockResolvedValue(undefined)
    const replacementResume = vi.fn().mockResolvedValue(undefined)
    const firstIntent = {
      authentication: 'sign_in',
      kind: 'read',
      mutationId: 'read:first',
    } satisfies InterruptedIntent
    const differentIntent = {
      authentication: 'sign_in',
      kind: 'read',
      mutationId: 'read:different',
    } satisfies InterruptedIntent

    function Harness() {
      const auth = useAuth()
      return (
        <>
          <button onClick={() => auth.beginReauthentication(firstIntent, firstResume)} type="button">
            Register first
          </button>
          <button
            onClick={() => void auth.completeReauthentication(firstIntent, 'rotated-csrf')}
            type="button"
          >
            Complete authentication
          </button>
          <button
            onClick={() => {
              auth.beginReauthentication(differentIntent, differentResume)
              auth.beginReauthentication(firstIntent, replacementResume)
            }}
            type="button"
          >
            Register during drain
          </button>
          <output>{auth.interruption?.mutationId ?? 'settled'}</output>
        </>
      )
    }

    const user = userEvent.setup()
    render(<AuthProvider><Harness /></AuthProvider>)
    await user.click(screen.getByRole('button', { name: 'Register first' }))
    await user.click(screen.getByRole('button', { name: 'Complete authentication' }))
    await waitFor(() => expect(firstResume).toHaveBeenCalledOnce())
    await user.click(screen.getByRole('button', { name: 'Register during drain' }))
    releaseFirst()

    await waitFor(() => expect(differentResume).toHaveBeenCalledOnce())
    await waitFor(() => expect(replacementResume).toHaveBeenCalledOnce())
    expect(firstResume).toHaveBeenCalledOnce()
    await waitFor(() => expect(screen.getByText('settled')).toBeVisible())
  })

  it('drains keyed continuations once and keeps a failed resume visibly retryable', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse({ csrf_token: 'initial-csrf', status: 'authenticated' }),
      ),
    )
    const firstResume = vi.fn().mockResolvedValue(undefined)
    const secondResume = vi
      .fn()
      .mockRejectedValueOnce(new Error('activity refresh failed'))
      .mockResolvedValueOnce(undefined)
    const firstIntent = {
      authentication: 'sign_in',
      kind: 'read',
      mutationId: 'read:first',
    } satisfies InterruptedIntent
    const secondIntent = {
      authentication: 'sign_in',
      kind: 'read',
      mutationId: 'read:second',
    } satisfies InterruptedIntent

    function Harness() {
      const auth = useAuth()
      return (
        <>
          <button
            onClick={() => {
              auth.beginReauthentication(firstIntent, firstResume)
              auth.beginReauthentication(firstIntent, firstResume)
              auth.beginReauthentication(secondIntent, secondResume)
            }}
            type="button"
          >
            Register interruptions
          </button>
          <button
            onClick={() => void auth.completeReauthentication(firstIntent, 'rotated-csrf')}
            type="button"
          >
            Complete authentication
          </button>
          <AppRoutes
            authenticated
            authenticatedContent={<p>Retained routed work</p>}
            continuationError={auth.continuationError}
            csrfToken={auth.state.kind === 'authenticated' ? auth.state.csrfToken : 'initial-csrf'}
            interruption={auth.interruption}
            onReauthenticated={auth.completeReauthentication}
            onRetryContinuations={auth.retryContinuations}
          />
        </>
      )
    }

    const user = userEvent.setup()
    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>,
    )

    await user.click(screen.getByRole('button', { name: 'Register interruptions' }))
    await user.click(screen.getByRole('button', { name: 'Complete authentication' }))

    await waitFor(() => expect(firstResume).toHaveBeenCalledOnce())
    expect(firstResume).toHaveBeenCalledWith('rotated-csrf')
    expect(secondResume).toHaveBeenCalledOnce()
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Couldn’t finish restoring everything. Your work is still here.',
    )

    await user.click(screen.getByRole('button', { name: 'Try continuing again' }))

    await waitFor(() => expect(secondResume).toHaveBeenCalledTimes(2))
    expect(firstResume).toHaveBeenCalledOnce()
    await waitFor(() =>
      expect(screen.queryByText('Couldn’t finish restoring everything. Your work is still here.')).not.toBeInTheDocument(),
    )
  })

  it('returns the exact submitted-unknown intent after password reauthentication', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ csrf_token: 'new-csrf', status: 'recently_authenticated' }),
    )
    vi.stubGlobal('fetch', fetchMock)
    const interruption = {
      authentication: 'reauthenticate',
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
      'Sign in again. Keepling will check the original change before continuing.',
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

  it('uses the real login flow for an invalid session while retaining mounted work', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ csrf_token: 'new-session-csrf', status: 'authenticated' }),
    )
    vi.stubGlobal('fetch', fetchMock)
    const interruption = {
      authentication: 'sign_in',
      kind: 'submitted-unknown',
      mutationId: 'retained-mutation',
    } satisfies InterruptedIntent
    const onReauthenticated = vi.fn()
    const user = userEvent.setup()

    render(
      <AppRoutes
        authenticated
        authenticatedContent={<p>Retained exact submission</p>}
        csrfToken="expired-csrf"
        interruption={interruption}
        onReauthenticated={onReauthenticated}
      />,
    )

    expect(screen.getByText('Retained exact submission')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Sign in to continue' })).toBeVisible()
    await user.type(screen.getByLabelText('Password'), 'account password')
    await user.type(screen.getByLabelText('Session label'), 'Restored browser')
    await user.click(screen.getByRole('button', { name: 'Sign in and continue' }))

    await waitFor(() =>
      expect(onReauthenticated).toHaveBeenCalledWith(interruption, 'new-session-csrf'),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/login',
      expect.objectContaining({ method: 'POST' }),
    )
  })
})

describe('session administration', () => {
  it('continues an expired session-list read through sign-in', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse(problem('authentication_required', 'Sign in again.', 401), 401),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          sessions: [
            {
              client_kind: 'web',
              coarse_activity: 'active_now',
              created_at: '2026-08-30T18:00:00Z',
              current: true,
              id: 'session-current',
              label: 'Recovered browser',
            },
          ],
        }),
      )
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/settings/sessions')
    const onAuthenticationRequired = vi.fn()

    render(
      <AppShell
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        onLoggedOut={() => undefined}
      />,
    )

    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'sign_in', kind: 'read' })
    await resume('new-csrf')
    expect(await screen.findByDisplayValue('Recovered browser')).toBeInTheDocument()
  })

  it('reauthenticates a revoke and completes the original administration action', async () => {
    const deleteTokens: string[] = []
    let deleteCount = 0
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path === '/api/v1/sessions' && init?.method === undefined) {
        return jsonResponse({
          sessions: [
            {
              client_kind: 'iphone',
              coarse_activity: 'today',
              created_at: '2026-08-29T16:00:00Z',
              current: false,
              id: 'session-other',
              label: 'Phone',
            },
          ],
        })
      }
      if (path.endsWith('/session-other') && init?.method === 'DELETE') {
        deleteTokens.push(new Headers(init.headers).get('x-csrf-token') ?? '')
        deleteCount += 1
        return deleteCount === 1
          ? jsonResponse(
              problem(
                'recent_authentication_required',
                'Reauthenticate before revoking this session.',
                401,
              ),
              401,
            )
          : jsonResponse({ status: 'session_revoked' })
      }
      throw new Error(`Unexpected request: ${path} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/settings/sessions')
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(
      <AppShell
        csrfToken="old-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        onLoggedOut={() => undefined}
      />,
    )

    await user.click(await screen.findByRole('button', { name: 'Revoke Phone' }))
    await user.click(screen.getByRole('button', { name: 'Revoke session' }))
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'reauthenticate', kind: 'action' })
    expect(screen.getByRole('alertdialog')).toBeInTheDocument()

    await resume('recent-csrf')

    await waitFor(() => expect(screen.queryByText('Phone')).not.toBeInTheDocument())
    expect(deleteTokens).toEqual(['old-csrf', 'recent-csrf'])
  })

  it('routes Settings/Sessions with editable labels and exact revocation choices', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === '/api/v1/sessions' && init?.method === undefined) {
        return jsonResponse({
          sessions: [
            {
              client_kind: 'web',
              coarse_activity: 'active_now',
              created_at: '2026-08-30T18:00:00Z',
              current: true,
              id: 'session-current',
              label: 'Home browser',
            },
            {
              client_kind: 'iphone',
              coarse_activity: 'today',
              created_at: '2026-08-29T16:00:00Z',
              current: false,
              id: 'session-other',
              label: 'Phone',
            },
          ],
        })
      }
      if (path.endsWith('/session-other') && init?.method === 'PATCH') {
        return jsonResponse({ label: 'Travel phone', status: 'session_updated' })
      }
      if (path.endsWith('/session-other') && init?.method === 'DELETE') {
        return jsonResponse({ status: 'session_revoked' })
      }
      if (path === '/api/v1/logout') return jsonResponse({ status: 'signed_out' })
      throw new Error(`Unexpected request: ${path} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    window.history.replaceState({}, '', '/settings/sessions')
    const onLoggedOut = vi.fn()
    const user = userEvent.setup()

    render(<AppShell csrfToken="csrf" hasDirtyWork onLoggedOut={onLoggedOut} />)

    expect(await screen.findByRole('heading', { name: 'Sessions' })).toBeVisible()
    expect(screen.getByText('Current browser')).toBeVisible()
    expect(screen.getByText('Web')).toBeVisible()
    expect(screen.getByText('Active now')).toBeVisible()
    expect(screen.getByText('iPhone')).toBeVisible()
    expect(screen.getByText('Today', { selector: 'dd' })).toBeVisible()
    expect(screen.getAllByRole('time')).toHaveLength(2)

    const label = screen.getByLabelText('Label for Phone')
    await user.clear(label)
    await user.type(label, 'Travel phone')
    await user.click(screen.getByRole('button', { name: 'Save label for Phone' }))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/sessions/session-other',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    )

    await user.click(screen.getByRole('button', { name: 'Revoke Travel phone' }))
    expect(screen.getByRole('alertdialog')).toHaveTextContent(
      'Revoke Travel phone? Keepling on that device will need to sign in again.',
    )
    expect(screen.getByRole('button', { name: 'Keep session active' })).toHaveFocus()
    await user.click(screen.getByRole('button', { name: 'Revoke session' }))
    await waitFor(() => expect(screen.queryByDisplayValue('Travel phone')).not.toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Log out this browser' }))
    expect(screen.getByRole('alertdialog')).toHaveTextContent(
      'Log out and discard unsaved changes? Saved tasks will remain in Keepling.',
    )
    expect(screen.getByRole('button', { name: 'Stay here' })).toHaveFocus()
    await user.click(screen.getByRole('button', { name: 'Discard changes and log out' }))
    await waitFor(() => expect(onLoggedOut).toHaveBeenCalledOnce())
  })
})

describe('capture authentication recovery', () => {
  it('keeps parsed 5xx capture identity and reconciles the committed receipt before resend', async () => {
    const commandBodies: string[] = []
    let stored: Record<string, unknown> | null = null
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path === '/api/v1/commands/capture-task') {
        const body = String(init?.body)
        commandBodies.push(body)
        const request = JSON.parse(body) as {
          mutation_id: string
          task_id: string
          title: string
        }
        stored = {
          mutation_id: request.mutation_id,
          outcome: 'accepted',
          revision: 1,
          snapshot: {
            captured_at: '2026-08-30T20:00:00Z',
            completed_at: null,
            deadline_on: null,
            id: request.task_id,
            inbox_state: 'inbox',
            notes: '',
            planned_on: null,
            project: null,
            revision: 1,
            tags: [],
            title: request.title,
            trashed_at: null,
          },
          task_id: request.task_id,
          warnings: [],
        }
        return jsonResponse(problem('service_unavailable', 'Response replaced after commit.', 503), 503)
      }
      if (path.startsWith('/api/v1/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onCaptured = vi.fn()
    const user = userEvent.setup()

    render(<QuickCapture csrfToken="csrf" onCaptured={onCaptured} />)

    const draft = screen.getByLabelText('What do you want to keep?')
    await user.type(draft, 'One task after parsed 5xx')
    await user.click(screen.getByRole('button', { name: 'Add task' }))

    expect(await screen.findByText('Checking whether your change was saved…')).toBeVisible()
    expect(draft).toHaveValue('One task after parsed 5xx')
    const identity = JSON.parse(commandBodies[0] ?? '{}') as {
      mutation_id: string
      task_id: string
    }

    await user.click(screen.getByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(onCaptured).toHaveBeenCalledOnce())
    expect(commandBodies).toHaveLength(1)
    expect(fetchMock.mock.calls[1]?.[0]).toBe(`/api/v1/mutations/${identity.mutation_id}`)
    expect(onCaptured).toHaveBeenCalledWith(
      expect.objectContaining({ mutationId: identity.mutation_id, taskId: identity.task_id }),
    )
    expect(draft).toHaveValue('')
  })

  it('replays the exact capture after a before-acceptance disconnect and missing receipt', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const call = fetchMock.mock.calls.length
      if (call === 1) throw new TypeError('connection lost before acceptance')
      if (call === 2) {
        return jsonResponse(problem('mutation_not_found', 'Mutation not found', 404), 404)
      }

      const request = JSON.parse(String(init?.body)) as {
        mutation_id: string
        task_id: string
        title: string
      }
      return jsonResponse(
        {
          mutation_id: request.mutation_id,
          outcome: 'accepted',
          revision: 1,
          snapshot: {
            captured_at: '2026-08-30T20:00:00Z',
            id: request.task_id,
            inbox_state: 'inbox',
            revision: 1,
            title: request.title,
          },
          task_id: request.task_id,
          warnings: [],
        },
        201,
      )
    })
    vi.stubGlobal('fetch', fetchMock)
    const onCaptured = vi.fn()
    const user = userEvent.setup()

    render(<QuickCapture csrfToken="csrf" onCaptured={onCaptured} />)

    await user.type(screen.getByLabelText('What do you want to keep?'), 'Replay exactly once')
    await user.click(screen.getByRole('button', { name: 'Add task' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(onCaptured).toHaveBeenCalledOnce())
    expect(fetchMock).toHaveBeenCalledTimes(3)

    const firstRequest = String(fetchMock.mock.calls[0]?.[1]?.body)
    const replayRequest = String(fetchMock.mock.calls[2]?.[1]?.body)
    expect(replayRequest).toBe(firstRequest)

    const firstIdentity = JSON.parse(firstRequest) as {
      mutation_id: string
      task_id: string
    }
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `/api/v1/mutations/${firstIdentity.mutation_id}`,
    )
    expect(onCaptured).toHaveBeenCalledWith(
      expect.objectContaining({
        mutationId: firstIdentity.mutation_id,
        taskId: firstIdentity.task_id,
      }),
    )
  })

  it('preserves the draft and mutation identity when authentication expires before acceptance', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(problem('authentication_required', 'Sign in again.', 401), 401),
      )
      .mockResolvedValueOnce(
        jsonResponse(problem('mutation_not_found', 'Mutation not found', 404), 404),
      )
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const onCaptured = vi.fn()
    const user = userEvent.setup()

    render(
      <QuickCapture
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        onCaptured={onCaptured}
      />,
    )

    const draft = screen.getByLabelText('What do you want to keep?')
    await user.type(draft, 'Keep this exact draft')
    await user.click(screen.getByRole('button', { name: 'Add task' }))

    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      InterruptedIntent,
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent.kind).toBe('submitted-unknown')
    expect(intent.authentication).toBe('sign_in')
    expect(draft).toHaveValue('Keep this exact draft')
    const firstRequest = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body)) as {
      mutation_id: string
      task_id: string
    }

    fetchMock.mockResolvedValueOnce(
      jsonResponse(
        {
          mutation_id: firstRequest.mutation_id,
          outcome: 'accepted',
          revision: 1,
          snapshot: {
            captured_at: '2026-08-30T20:00:00Z',
            id: firstRequest.task_id,
            inbox_state: 'inbox',
            revision: 1,
            title: 'Keep this exact draft',
          },
          task_id: firstRequest.task_id,
          warnings: [],
        },
        201,
      ),
    )
    await resume('renewed-csrf')

    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `/api/v1/mutations/${firstRequest.mutation_id}`,
    )
    const retryRequest = JSON.parse(String(fetchMock.mock.calls[2]?.[1]?.body)) as {
      mutation_id: string
    }
    expect(retryRequest.mutation_id).toBe(firstRequest.mutation_id)
    expect(fetchMock.mock.calls[2]?.[1]?.body).toBe(fetchMock.mock.calls[0]?.[1]?.body)
    await waitFor(() => expect(onCaptured).toHaveBeenCalledOnce())
  })

  it('reauthenticates an unknown result check without replacing its submitted identity', async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new TypeError('response lost'))
      .mockResolvedValueOnce(
        jsonResponse(problem('authentication_required', 'Sign in again.', 401), 401),
      )
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const onCaptured = vi.fn()
    const user = userEvent.setup()

    render(
      <QuickCapture
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        onCaptured={onCaptured}
      />,
    )

    await user.type(screen.getByLabelText('What do you want to keep?'), 'Unknown delivery')
    await user.click(screen.getByRole('button', { name: 'Add task' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      InterruptedIntent,
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent.kind).toBe('submitted-unknown')
    expect(intent.authentication).toBe('sign_in')
    if (intent.kind !== 'submitted-unknown') throw new Error('Expected submitted-unknown intent')
    expect(fetchMock.mock.calls[1]?.[0]).toBe(`/api/v1/mutations/${intent.mutationId}`)

    const initialRequest = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body)) as {
      mutation_id: string
      task_id: string
    }
    fetchMock.mockResolvedValueOnce(
      jsonResponse(
        {
          mutation_id: initialRequest.mutation_id,
          outcome: 'accepted',
          revision: 1,
          snapshot: {
            captured_at: '2026-08-30T20:00:00Z',
            id: initialRequest.task_id,
            inbox_state: 'inbox',
            revision: 1,
            title: 'Unknown delivery',
          },
          task_id: initialRequest.task_id,
          warnings: [],
        },
        201,
      ),
    )
    await resume('renewed-csrf')

    expect(fetchMock.mock.calls[2]?.[0]).toBe(`/api/v1/mutations/${intent.mutationId}`)
    await waitFor(() => expect(onCaptured).toHaveBeenCalledOnce())
  })
})
