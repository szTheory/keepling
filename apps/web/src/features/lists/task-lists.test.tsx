import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import TaskList from '@/features/lists/TaskList'
import TodayList from '@/features/lists/TodayList'
import UpcomingList from '@/features/lists/UpcomingList'

type Deferred<T> = {
  promise: Promise<T>
  reject: (reason?: unknown) => void
  resolve: (value: T) => void
}

const deferred = <T,>(): Deferred<T> => {
  let resolve!: (value: T) => void
  let reject!: (reason?: unknown) => void
  const promise = new Promise<T>((accept, decline) => {
    resolve = accept
    reject = decline
  })
  return { promise, reject, resolve }
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const item = (overrides: Record<string, unknown> = {}) => ({
  captured_at: '2026-08-31T04:00:00.000000Z',
  deadline_on: null,
  id: '11111111-1111-4111-8111-111111111111',
  planned_on: '2026-08-31',
  reasons: ['planned_today'],
  revision: 1,
  section: 'today',
  title: 'Call dentist',
  ...overrides,
})

const page = (items: readonly unknown[], overrides: Record<string, unknown> = {}) => ({
  account_day: '2026-08-31',
  account_timezone: 'America/New_York',
  items,
  next_cursor: null,
  order_revision: null,
  view: 'inbox',
  ...overrides,
})

afterEach(() => {
  vi.restoreAllMocks()
  window.history.replaceState({}, '', '/')
})

describe('routed task lists', () => {
  it('enters sign-in continuation for an expired list read and completes the original read', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
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
      .mockResolvedValueOnce(jsonResponse(page([item()], { view: 'today' })))
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()

    render(
      <TaskList
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        view="today"
      />,
    )

    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'sign_in', kind: 'read' })

    await resume('new-csrf')

    expect(await screen.findByRole('link', { name: 'Call dentist' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('does not render Today empty copy until an authoritative zero result arrives', async () => {
    const response = deferred<Response>()
    vi.stubGlobal('fetch', vi.fn(() => response.promise))

    render(<TodayList csrfToken="csrf" />)

    expect(screen.getByRole('status')).toHaveTextContent('Loading Today…')
    expect(screen.queryByText('Nothing for Today')).not.toBeInTheDocument()

    response.resolve(jsonResponse(page([], { order_revision: 4, view: 'today' })))

    expect(await screen.findByText('Nothing for Today')).toBeInTheDocument()
    expect(screen.getByText(/choose an existing task to make it part of today/i)).toBeInTheDocument()
  })

  it('keeps acknowledged Today order visible until a semantic move is acknowledged', async () => {
    const moveResponse = deferred<Response>()
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse(
          page(
            [
              item(),
              item({
                id: '22222222-2222-4222-8222-222222222222',
                planned_on: null,
                deadline_on: '2026-08-31',
                reasons: ['deadline_today'],
                title: 'Send invoice',
              }),
            ],
            { order_revision: 7, view: 'today' },
          ),
        ),
      )
      .mockImplementationOnce(() => moveResponse.promise)
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TodayList csrfToken="csrf" />)

    const list = await screen.findByRole('list', { name: 'Today tasks' })
    expect(within(list).getAllByRole('link').map((link) => link.textContent)).toEqual([
      'Call dentist',
      'Send invoice',
    ])
    expect(screen.getByText('Planned today')).toBeInTheDocument()
    expect(screen.getByText('Deadline today')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Move later “Call dentist”' }))

    expect(screen.getByText('Moving…')).toBeInTheDocument()
    for (const button of screen.getAllByRole('button', { name: /Move (earlier|later)/ })) {
      expect(button).toBeDisabled()
    }
    expect(screen.getByRole('button', { name: 'Complete “Call dentist”' })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Complete “Call dentist”' }))
    expect(
      fetchMock.mock.calls.filter(([url]) => String(url) === '/api/v1/commands/complete-task'),
    ).toHaveLength(0)
    expect(within(list).getAllByRole('link').map((link) => link.textContent)).toEqual([
      'Call dentist',
      'Send invoice',
    ])

    const request = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body))
    expect(request).toMatchObject({
      direction: 'later',
      expected_order_revision: 7,
      task_id: '11111111-1111-4111-8111-111111111111',
      version: 1,
    })
    expect(request.mutation_id).toMatch(/^[0-9a-f-]{36}$/)

    moveResponse.resolve(
      jsonResponse({
        mutation_id: request.mutation_id,
        order_revision: 8,
        task_id: request.task_id,
      }),
    )

    await waitFor(() => {
      expect(within(list).getAllByRole('link').map((link) => link.textContent)).toEqual([
        'Send invoice',
        'Call dentist',
      ])
    })
    for (const button of screen.getAllByRole('button', { name: /Move (earlier|later)/ })) {
      expect(button).toBeEnabled()
    }
  })

  it('refreshes authoritative rows and cursor after moving across a loaded Today boundary', async () => {
    const first = item()
    const boundary = item({
      id: '22222222-2222-4222-8222-222222222222',
      title: 'Boundary task',
    })
    const hiddenAdjacent = item({
      id: '33333333-3333-4333-8333-333333333333',
      title: 'Previously hidden task',
    })
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse(
          page([first, boundary], {
            next_cursor: 'old-order-cursor',
            order_revision: 7,
            view: 'today',
          }),
        ),
      )
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body)) as {
          mutation_id: string
          task_id: string
        }
        return jsonResponse({
          mutation_id: request.mutation_id,
          order_revision: 8,
          task_id: request.task_id,
        })
      })
      .mockResolvedValueOnce(
        jsonResponse(
          page([first, hiddenAdjacent], {
            next_cursor: 'new-order-cursor',
            order_revision: 8,
            view: 'today',
          }),
        ),
      )
      .mockResolvedValueOnce(
        jsonResponse(
          page([boundary], {
            next_cursor: null,
            order_revision: 8,
            view: 'today',
          }),
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TodayList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Move later “Boundary task”' }))
    expect(await screen.findByRole('link', { name: 'Previously hidden task' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Boundary task' })).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Load more tasks' }))

    expect(await screen.findByRole('link', { name: 'Boundary task' })).toBeInTheDocument()
    expect(String(fetchMock.mock.calls[3]?.[0])).toContain('cursor=new-order-cursor')
    expect(String(fetchMock.mock.calls[3]?.[0])).not.toContain('old-order-cursor')
  })

  it('retains accepted rows on stale pagination and focuses the first appended row', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(page([item()], { next_cursor: 'opaque-page-1' })))
      .mockResolvedValueOnce(
        jsonResponse(
          {
            code: 'task_view_cursor_stale',
            detail: 'This view changed before more items could load.',
            recovery_action: 'refresh_view',
            retryable: false,
            status: 409,
            title: 'Task view changed',
            type: '/problems/task_view_cursor_stale',
          },
          409,
        ),
      )
      .mockResolvedValueOnce(
        jsonResponse(
          page([
            item(),
            item({ id: '22222222-2222-4222-8222-222222222222', title: 'Buy stamps' }),
          ]),
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TaskList view="inbox" />)

    expect(await screen.findByRole('link', { name: 'Call dentist' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Load more tasks' }))

    expect(await screen.findByText('This view changed before more items could load.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Call dentist' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Refresh view' }))

    const appended = await screen.findByRole('link', { name: 'Buy stamps' })
    await waitFor(() => expect(appended).toHaveFocus())
  })

  it('globally locks Today moves and looks up the original identity after response loss', async () => {
    let stored: { mutation_id: string; order_revision: number; task_id: string } | null = null
    const commandBodies: string[] = []
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path.startsWith('/api/v1/today?')) {
        return jsonResponse(
          page(
            [
              item(),
              item({ id: '22222222-2222-4222-8222-222222222222', title: 'Send invoice' }),
            ],
            { order_revision: 3, view: 'today' },
          ),
        )
      }
      if (path === '/api/v1/commands/move-today-task') {
        const body = String(init?.body)
        commandBodies.push(body)
        const request = JSON.parse(body) as { mutation_id: string; task_id: string }
        stored = {
          mutation_id: request.mutation_id,
          order_revision: 4,
          task_id: request.task_id,
        }
        throw new TypeError('response lost')
      }
      if (path.startsWith('/api/v1/today/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TodayList csrfToken="csrf" />)
    await screen.findByRole('link', { name: 'Call dentist' })
    await user.click(screen.getByRole('button', { name: 'Move later “Call dentist”' }))

    expect(await screen.findByText('Checking whether your change was saved…')).toBeInTheDocument()
    const moveButtons = screen.getAllByRole('button', { name: /Move (earlier|later)/ })
    expect(moveButtons).not.toHaveLength(0)
    for (const button of moveButtons) expect(button).toBeDisabled()

    screen.getByRole('button', { name: 'Move earlier “Send invoice”' }).click()
    expect(commandBodies).toHaveLength(1)

    const originalMutationId = (
      JSON.parse(commandBodies[0] ?? '{}') as { mutation_id: string }
    ).mutation_id
    await user.click(screen.getByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3))
    expect(commandBodies).toHaveLength(1)
    expect(fetchMock.mock.calls[2]?.[0]).toBe(
      `/api/v1/today/mutations/${originalMutationId}`,
    )
  })

  it('retains an after-commit authentication response until exact Today reconciliation', async () => {
    const bodies: string[] = []
    let stored: { mutation_id: string; order_revision: number; task_id: string } | null = null
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path.startsWith('/api/v1/today?')) {
        return jsonResponse(
          page(
            [
              item(),
              item({ id: '22222222-2222-4222-8222-222222222222', title: 'Send invoice' }),
            ],
            { order_revision: 3, view: 'today' },
          ),
        )
      }
      if (path === '/api/v1/commands/move-today-task') {
        const body = String(init?.body)
        bodies.push(body)
        const request = JSON.parse(body) as { mutation_id: string; task_id: string }
        stored ??= {
          mutation_id: request.mutation_id,
          order_revision: 4,
          task_id: request.task_id,
        }
        return bodies.length === 1
          ? jsonResponse(
              {
                code: 'authentication_required',
                recovery_action: 'sign_in',
                retryable: true,
                status: 401,
                title: 'Authentication required',
                type: '/problems/authentication_required',
              },
              401,
            )
          : jsonResponse(stored)
      }
      if (path.startsWith('/api/v1/today/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(
      <TaskList
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        view="today"
      />,
    )
    await screen.findByRole('link', { name: 'Call dentist' })
    await user.click(screen.getByRole('button', { name: 'Move later “Call dentist”' }))
    const continueButton = await screen.findByRole('button', { name: 'Sign in and continue' })
    for (const button of screen.getAllByRole('button', { name: /Move (earlier|later)/ })) {
      expect(button).toBeDisabled()
    }
    await user.click(continueButton)
    const [, resume] = onAuthenticationRequired.mock.calls[0] as [unknown, (csrf: string) => Promise<void>]
    await resume('new-session-csrf')

    await waitFor(() => expect(screen.getByText('Today order updated.')).toBeInTheDocument())
    expect(bodies).toHaveLength(1)
    for (const button of screen.getAllByRole('button', { name: /Move (earlier|later)/ })) {
      expect(button).toBeEnabled()
    }
  })

  it('routes authenticated Today, Upcoming, and Completed views through their facades', async () => {
    vi.stubGlobal('fetch', vi.fn(() => Promise.resolve(jsonResponse(page([])))))

    for (const [pathname, heading] of [
      ['/today', 'Today'],
      ['/upcoming', 'Upcoming'],
      ['/completed', 'Completed'],
    ] as const) {
      window.history.replaceState({}, '', pathname)
      const rendered = render(<AppRoutes authenticated csrfToken="csrf" />)
      expect(await screen.findByRole('heading', { level: 1, name: heading })).toBeInTheDocument()
      rendered.unmount()
    }
  })

  it('renders Upcoming reasons as visible text and exposes no reorder controls', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() =>
        Promise.resolve(
          jsonResponse(
            page(
              [
                item({
                  group_on: '2026-09-02',
                  planned_on: '2026-08-31',
                  deadline_on: '2026-09-02',
                  reasons: ['planned_today', 'deadline_future'],
                  upcoming_reason: 'deadline',
                }),
              ],
              { view: 'upcoming' },
            ),
          ),
        ),
      ),
    )

    render(<UpcomingList />)

    expect(await screen.findByText('Planned today · Deadline Sep 2')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /move earlier/i })).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'September 2, 2026' })).toBeInTheDocument()
  })
})
