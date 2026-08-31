import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
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

    moveResponse.resolve(jsonResponse({ order_revision: 8 }))

    await waitFor(() => {
      expect(within(list).getAllByRole('link').map((link) => link.textContent)).toEqual([
        'Send invoice',
        'Call dentist',
      ])
    })
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
