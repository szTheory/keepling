import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import LifecycleActions from '@/features/tasks/LifecycleActions'
import TaskList from '@/features/lists/TaskList'

type Deferred<T> = {
  promise: Promise<T>
  resolve: (value: T) => void
}

const deferred = <T,>(): Deferred<T> => {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((accept) => {
    resolve = accept
  })
  return { promise, resolve }
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const task = {
  capturedAt: '2026-08-31T04:00:00.000000Z',
  deadlineOn: null,
  id: '11111111-1111-4111-8111-111111111111',
  plannedOn: '2026-08-31',
  reasons: ['planned_today'] as const,
  revision: 4,
  section: 'today' as const,
  title: 'Call dentist',
}

const acknowledgement = (mutationId: string) => ({
  mutation_id: mutationId,
  outcome: 'accepted',
  revision: 5,
  snapshot: {
    captured_at: task.capturedAt,
    completed_at: '2026-08-31T12:00:00.000000Z',
    deadline_on: null,
    id: task.id,
    inbox_state: 'inbox',
    notes: '',
    planned_on: task.plannedOn,
    project: null,
    revision: 5,
    tags: [],
    title: task.title,
  },
  task_id: task.id,
  warnings: [],
})

const page = (items: readonly unknown[], view = 'today') => ({
  account_day: '2026-08-31',
  account_timezone: 'America/New_York',
  items,
  next_cursor: null,
  order_revision: view === 'today' ? 3 : null,
  view,
})

const wireItem = (overrides: Record<string, unknown> = {}) => ({
  captured_at: task.capturedAt,
  deadline_on: null,
  id: task.id,
  planned_on: task.plannedOn,
  reasons: ['planned_today'],
  revision: task.revision,
  section: 'today',
  title: task.title,
  ...overrides,
})

afterEach(() => {
  vi.restoreAllMocks()
})

describe('task lifecycle actions', () => {
  it('keeps the task visible until the exact completion acknowledgement arrives', async () => {
    const response = deferred<Response>()
    const fetchMock = vi.fn<typeof fetch>(() => response.promise)
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <div>
        <a href={`/tasks/${task.id}`}>{task.title}</a>
        <LifecycleActions csrfToken="csrf" onAcknowledged={onAcknowledged} task={task} />
      </div>,
    )

    await user.click(screen.getByRole('button', { name: 'Complete “Call dentist”' }))

    expect(screen.getByRole('link', { name: task.title })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Completing “Call dentist”' })).toBeDisabled()
    expect(onAcknowledged).not.toHaveBeenCalled()

    const request = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))
    expect(request).toMatchObject({ expected_revision: 4, task_id: task.id, version: 1 })
    expect(request.mutation_id).toMatch(/^[0-9a-f-]{36}$/)

    response.resolve(jsonResponse(acknowledgement(request.mutation_id)))

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledTimes(1))
    expect(onAcknowledged).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'complete', task: expect.objectContaining({ id: task.id }) }),
    )
  })

  it('checks an unknown outcome before replaying the same mutation identity', async () => {
    let firstBody = ''
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockImplementationOnce(async (_input, init) => {
        firstBody = String(init?.body)
        throw new TypeError('response lost')
      })
      .mockResolvedValueOnce(
        jsonResponse(
          {
            code: 'mutation_not_found',
            recovery_action: 'retry_exact_mutation',
            retryable: true,
            status: 404,
            title: 'Mutation not found',
            type: '/problems/mutation_not_found',
          },
          404,
        ),
      )
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body))
        return jsonResponse(acknowledgement(request.mutation_id))
      })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(<LifecycleActions csrfToken="csrf" onAcknowledged={onAcknowledged} task={task} />)
    await user.click(screen.getByRole('button', { name: 'Complete “Call dentist”' }))

    expect(await screen.findByText('Checking whether your change was saved…')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledTimes(1))
    const request = JSON.parse(firstBody) as { mutation_id: string }
    expect(fetchMock.mock.calls[1]?.[0]).toBe(`/api/v1/mutations/${request.mutation_id}`)
    expect(fetchMock.mock.calls[2]?.[1]?.body).toBe(firstBody)
  })

  it.each([
    ['authentication_required', 401, 'Sign in again. Keepling will check whether your change was saved.'],
    ['task_lifecycle_conflict', 409, 'This task changed somewhere else. Review the current task before trying again.'],
    ['unexpected_problem', 422, 'Couldn’t complete this task. Nothing was changed.'],
  ])('shows an honest %s recovery state', async (code, status, message) => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() =>
        Promise.resolve(
          jsonResponse(
            {
              code,
              detail: 'Lifecycle request was not accepted.',
              recovery_action: code === 'task_lifecycle_conflict' ? 'refresh_task' : 'retry',
              retryable: false,
              status,
              title: 'Lifecycle request failed',
              type: `/problems/${code}`,
            },
            status,
          ),
        ),
      ),
    )
    const user = userEvent.setup()

    render(<LifecycleActions csrfToken="csrf" onAcknowledged={() => undefined} task={task} />)
    await user.click(screen.getByRole('button', { name: 'Complete “Call dentist”' }))

    expect(await screen.findByText(message)).toBeInTheDocument()
  })

  it('uses reopen semantics for a completed task', async () => {
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      const request = JSON.parse(String(init?.body))
      return jsonResponse({
        ...acknowledgement(request.mutation_id),
        snapshot: {
          ...acknowledgement(request.mutation_id).snapshot,
          completed_at: null,
        },
      })
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <LifecycleActions
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        task={{ ...task, completedAt: '2026-08-31T12:00:00.000000Z' }}
      />,
    )
    await user.click(screen.getByRole('button', { name: 'Reopen “Call dentist”' }))

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledTimes(1))
    expect(String(fetchMock.mock.calls[0]?.[0])).toBe('/api/v1/commands/reopen-task')
    expect(onAcknowledged).toHaveBeenCalledWith(expect.objectContaining({ action: 'reopen' }))
  })

  it('moves an acknowledged completion into Completed today and focuses the next task', async () => {
    const completeResponse = deferred<Response>()
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse(page([
          wireItem(),
          wireItem({ id: '22222222-2222-4222-8222-222222222222', title: 'Send invoice' }),
        ])),
      )
      .mockImplementationOnce(() => completeResponse.promise)
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TaskList csrfToken="csrf" view="today" />)
    await screen.findByRole('link', { name: task.title })
    await user.click(screen.getByRole('button', { name: 'Complete “Call dentist”' }))

    expect(screen.getByRole('link', { name: task.title })).toBeInTheDocument()
    const request = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body))
    completeResponse.resolve(jsonResponse(acknowledgement(request.mutation_id)))

    const completed = await screen.findByRole('list', { name: 'Completed today tasks' })
    expect(within(completed).getByRole('link', { name: task.title })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('link', { name: 'Send invoice' })).toHaveFocus())
    expect(screen.getByText('Task completed. Moved to Completed today.')).toBeInTheDocument()
  })

  it('recomputes destinations after reopen instead of predicting membership', async () => {
    const reopened = wireItem({ completed_at: undefined, revision: 6 })
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse(page([wireItem({ completed_at: '2026-08-31T12:00:00.000000Z', completed_on: '2026-08-31' })], 'completed')),
      )
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body))
        return jsonResponse({
          ...acknowledgement(request.mutation_id),
          revision: 6,
          snapshot: { ...acknowledgement(request.mutation_id).snapshot, completed_at: null, revision: 6 },
        })
      })
      .mockResolvedValueOnce(jsonResponse(page([reopened], 'inbox')))
      .mockResolvedValueOnce(jsonResponse(page([reopened], 'today')))
      .mockResolvedValueOnce(jsonResponse(page([], 'upcoming')))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TaskList csrfToken="csrf" view="completed" />)
    await screen.findByRole('button', { name: 'Reopen “Call dentist”' })
    await user.click(screen.getByRole('button', { name: 'Reopen “Call dentist”' }))

    expect(await screen.findByText('Task reopened to Inbox and Today.')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: task.title })).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('heading', { level: 1, name: 'Completed' })).toHaveFocus())
  })
})
