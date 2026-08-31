import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import TrashList from '@/features/lists/TrashList'

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

const task = (overrides: Record<string, unknown> = {}) => ({
  captured_at: '2026-08-31T04:00:00.000000Z',
  completed_at: null,
  deadline_on: null,
  id: '11111111-1111-4111-8111-111111111111',
  inbox_state: 'inbox',
  notes: '',
  planned_on: null,
  project: null,
  revision: 4,
  tags: [],
  title: 'Call dentist',
  trashed_at: '2026-08-31T13:00:00.000000Z',
  ...overrides,
})

const acknowledgement = (
  mutationId: string,
  taskId = '11111111-1111-4111-8111-111111111111',
  destinations: readonly string[] = ['Inbox'],
) => ({
  destinations,
  mutation_id: mutationId,
  outcome: 'accepted',
  revision: 5,
  snapshot: task({ id: taskId, revision: 5, trashed_at: null }),
  task_id: taskId,
  warnings: [],
})

afterEach(() => {
  vi.restoreAllMocks()
  window.history.replaceState({}, '', '/')
})

describe('Trash route and acknowledged restore', () => {
  it('does not show empty before an authoritative zero result', async () => {
    const response = deferred<Response>()
    vi.stubGlobal('fetch', vi.fn(() => response.promise))

    render(<TrashList csrfToken="csrf" />)

    expect(screen.getByRole('status')).toHaveTextContent('Loading Trash…')
    expect(screen.queryByText('Trash is empty')).not.toBeInTheDocument()

    response.resolve(jsonResponse({ tasks: [] }))

    expect(await screen.findByText('Trash is empty')).toBeInTheDocument()
    expect(screen.getByText('Tasks moved to Trash stay recoverable here.')).toBeInTheDocument()
  })

  it('routes authenticated Trash through its generated facade', async () => {
    vi.stubGlobal('fetch', vi.fn(() => Promise.resolve(jsonResponse({ tasks: [] }))))
    window.history.replaceState({}, '', '/trash')

    render(<AppRoutes authenticated csrfToken="csrf" />)

    expect(await screen.findByRole('heading', { level: 1, name: 'Trash' })).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledWith('/api/v1/trash', expect.objectContaining({ credentials: 'same-origin' }))
  })

  it('keeps the row pending, removes it after exact acknowledgement, announces destinations, and focuses next', async () => {
    const restoreResponse = deferred<Response>()
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          tasks: [
            task(),
            task({ id: '22222222-2222-4222-8222-222222222222', title: 'Send invoice' }),
          ],
        }),
      )
      .mockImplementationOnce(() => restoreResponse.promise)
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/trash')

    render(<TrashList csrfToken="csrf" />)

    const list = await screen.findByRole('list', { name: 'Trash tasks' })
    await user.click(within(list).getByRole('button', { name: 'Restore “Call dentist”' }))

    expect(within(list).getByText('Call dentist')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Restoring “Call dentist”' })).toBeDisabled()

    const request = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body))
    expect(request).toMatchObject({ expected_revision: 4, task_id: task().id, version: 1 })
    expect(request.mutation_id).toMatch(/^[0-9a-f-]{36}$/)

    restoreResponse.resolve(jsonResponse(acknowledgement(request.mutation_id, task().id, ['Inbox', 'Today'])))

    await waitFor(() => expect(within(list).queryByText('Call dentist')).not.toBeInTheDocument())
    expect(screen.getByText('Task restored to Inbox and Today.')).toBeInTheDocument()
    expect(window.location.pathname).toBe('/trash')
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Restore “Send invoice”' })).toHaveFocus(),
    )
  })

  it('treats a mismatched or lost response as unknown and retries the exact submission', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ tasks: [task()] }))
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body))
        return jsonResponse(acknowledgement(request.mutation_id, '99999999-9999-4999-8999-999999999999'))
      })
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body))
        return jsonResponse(acknowledgement(request.mutation_id))
      })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TrashList csrfToken="csrf" />)
    await user.click(await screen.findByRole('button', { name: 'Restore “Call dentist”' }))

    expect(await screen.findByText('Checking whether your change was saved…')).toBeInTheDocument()
    expect(screen.getByText('Call dentist')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(screen.queryByText('Call dentist')).not.toBeInTheDocument())
    expect(fetchMock.mock.calls[1]?.[1]?.body).toBe(fetchMock.mock.calls[2]?.[1]?.body)
  })

  it.each([
    ['authentication_required', 401, 'Sign in again to finish saving. Your changes are still here.', 'Sign in and continue'],
    ['task_trash_conflict', 409, 'This task changed somewhere else. Refresh Trash before restoring it.', 'Refresh Trash'],
    ['unexpected_problem', 422, 'Couldn’t restore this task. Nothing was changed.', 'Retry restore'],
  ])('retains the row in the %s state', async (code, status, message, action) => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn<typeof fetch>()
        .mockResolvedValueOnce(jsonResponse({ tasks: [task()] }))
        .mockResolvedValueOnce(
          jsonResponse(
            {
              code,
              detail: 'Restore was not accepted.',
              recovery_action: code === 'task_trash_conflict' ? 'refresh_task' : 'retry',
              retryable: false,
              status,
              title: 'Restore failed',
              type: `/problems/${code}`,
            },
            status,
          ),
        ),
    )
    const user = userEvent.setup()

    render(<TrashList csrfToken="csrf" />)
    await user.click(await screen.findByRole('button', { name: 'Restore “Call dentist”' }))

    expect(await screen.findByText(message)).toBeInTheDocument()
    expect(screen.getByText('Call dentist')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: action })).toBeInTheDocument()
  })

  it('focuses the Trash heading after restoring the final row', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ tasks: [task()] }))
      .mockImplementationOnce(async (_input, init) => {
        const request = JSON.parse(String(init?.body))
        return jsonResponse(acknowledgement(request.mutation_id))
      })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TrashList csrfToken="csrf" />)
    await user.click(await screen.findByRole('button', { name: 'Restore “Call dentist”' }))

    await waitFor(() => expect(screen.getByRole('heading', { level: 1, name: 'Trash' })).toHaveFocus())
  })
})
