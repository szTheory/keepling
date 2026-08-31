import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import ActivityList from '@/features/activity/ActivityList'

const taskId = '018d8b40-2f10-7b1a-9d71-263f4af77001'
const mutationId = '018d8b40-2f10-7b1a-9d71-263f4af77002'

const item = {
  accepted_at: '2026-08-31T01:16:00.000000Z',
  activity_id: 2,
  actor: { label: 'You', principal: 'account_owner', type: 'user' },
  changes: [
    {
      field: 'notes',
      kind: 'text',
      new: 'plain <script>window.activityRan = true</script>',
      old: 'Old notes',
    },
    {
      field: 'tags',
      kind: 'organizations',
      new: [
        {
          archived: true,
          id: '018d8b40-2f10-7b1a-9d71-263f4af77003',
          name: '<img src=x onerror="window.tagRan = true">',
        },
      ],
      old: [],
    },
  ],
  client_kind: 'web',
  from_revision: 1,
  mutation_id: mutationId,
  outcome: 'accepted',
  recovery_state: 'not_available',
  to_revision: 2,
  type: 'task_details_updated',
  undone_activity_id: null,
  version: 1,
} as const

const captured = {
  accepted_at: '2026-08-31T01:15:00.000000Z',
  activity_id: 1,
  actor: { label: 'You', principal: 'account_owner', type: 'user' },
  changes: [
    { field: 'title', kind: 'text', new: 'Call dentist', old: null },
  ],
  client_kind: 'web',
  from_revision: null,
  mutation_id: '018d8b40-2f10-7b1a-9d71-263f4af77004',
  outcome: 'accepted',
  recovery_state: 'not_available',
  to_revision: 1,
  type: 'task_captured',
  undone_activity_id: null,
  version: 1,
} as const

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const page = (items: readonly unknown[], nextCursor: string | null) => ({
  account_timezone: 'America/New_York',
  items,
  next_cursor: nextCursor,
})

const activitySentence = (sentence: string) =>
  screen.getByText((_, element) => element?.tagName === 'P' && element.textContent === sentence)

afterEach(() => {
  vi.unstubAllGlobals()
  window.history.replaceState({}, '', '/')
})

describe('task activity', () => {
  it('resumes the exact expired initial read without collapsing into a generic error', async () => {
    const authenticationProblem = {
      code: 'authentication_required',
      detail: 'Sign in again.',
      recovery_action: 'sign_in',
      retryable: true,
      status: 401,
      title: 'Authentication required',
      type: '/problems/authentication_required',
    }
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(authenticationProblem, 401))
      .mockResolvedValueOnce(jsonResponse(page([item], null)))
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()

    render(
      <ActivityList
        onAuthenticationRequired={onAuthenticationRequired}
        taskId={taskId}
      />,
    )

    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string; mutationId: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'sign_in', kind: 'read' })
    await resume('rotated-csrf')

    await waitFor(() => expect(activitySentence('You updated task details.')).toBeVisible())
    expect(screen.queryByText('Couldn’t load activity. Your tasks weren’t changed.')).not.toBeInTheDocument()
  })

  it('resumes the exact expired cursor read while retaining the last accepted page', async () => {
    const authenticationProblem = {
      code: 'authentication_required',
      detail: 'Sign in again.',
      recovery_action: 'reauthenticate',
      retryable: true,
      status: 401,
      title: 'Authentication required',
      type: '/problems/authentication_required',
    }
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page([item], 'retained-cursor')))
      .mockResolvedValueOnce(jsonResponse(authenticationProblem, 401))
      .mockResolvedValueOnce(jsonResponse(page([captured], null)))
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(
      <ActivityList
        onAuthenticationRequired={onAuthenticationRequired}
        taskId={taskId}
      />,
    )

    await user.click(await screen.findByRole('button', { name: 'Load earlier activity' }))
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    expect(activitySentence('You updated task details.')).toBeVisible()
    const [, resume] = onAuthenticationRequired.mock.calls[0] as [
      unknown,
      (csrfToken: string) => Promise<void>,
    ]
    await resume('rotated-csrf')

    await waitFor(() => expect(activitySentence('You captured this task.')).toBeVisible())
    expect(fetchMock).toHaveBeenNthCalledWith(
      3,
      `/api/v1/tasks/${taskId}/activity?limit=20&cursor=retained-cursor`,
      expect.objectContaining({ credentials: 'same-origin' }),
    )
  })

  it('renders hostile changes as compact plain text with exact zoned time and disclosures', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse(page([item], null))))
    const user = userEvent.setup()

    render(<ActivityList taskId={taskId} />)

    expect(await screen.findByRole('heading', { name: 'Activity' })).toBeVisible()
    expect(activitySentence('You updated task details.')).toBeVisible()
    expect(screen.getByText('Accepted')).toBeVisible()

    const time = screen.getByText(/Aug 30, 2026.*EDT/)
    expect(time).toHaveAttribute('datetime', item.accepted_at)

    const change = screen.getByText('Show change').closest('details')
    expect(change).not.toHaveAttribute('open')
    expect(within(change as HTMLElement).getByText(item.changes[0].new)).toBeInTheDocument()
    expect(screen.getByText(item.changes[1].new[0].name)).toBeInTheDocument()
    expect(screen.getByText('Archived')).toBeVisible()
    expect(document.querySelector('img')).toBeNull()
    expect(document.querySelector('script')).toBeNull()

    const technical = screen.getByText('Technical details').closest('details')
    expect(technical).not.toHaveAttribute('open')
    await user.click(screen.getByText('Technical details'))
    expect(technical).toHaveAttribute('open')
    expect(within(technical as HTMLElement).getByText('Revision 1 → 2')).toBeInTheDocument()
    expect(within(technical as HTMLElement).getByText(mutationId)).toBeInTheDocument()
    expect(
      within(technical as HTMLElement).getByRole('button', { name: 'Copy mutation ID' }),
    ).toBeVisible()
    expect(document.body).not.toHaveTextContent('undo_handle')
  })

  it('loads earlier activity explicitly and focuses the first appended item', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page([item], 'signed-cursor')))
      .mockResolvedValueOnce(jsonResponse(page([captured], null)))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<ActivityList taskId={taskId} />)

    await user.click(await screen.findByRole('button', { name: 'Load earlier activity' }))

    await waitFor(() =>
      expect(activitySentence('You captured this task.').closest('li')).toHaveFocus(),
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      `/api/v1/tasks/${taskId}/activity?limit=20&cursor=signed-cursor`,
      expect.objectContaining({ credentials: 'same-origin' }),
    )
    expect(screen.queryByRole('button', { name: 'Load earlier activity' })).not.toBeInTheDocument()
  })

  it('distinguishes loading, authoritative empty, failure, and stale pagination', async () => {
    let resolveInitial: ((response: Response) => void) | undefined
    const initialFetch = vi.fn(
      () =>
        new Promise<Response>((resolve) => {
          resolveInitial = resolve
        }),
    )
    vi.stubGlobal('fetch', initialFetch)

    const loading = render(<ActivityList taskId={taskId} />)
    expect(screen.getByRole('status')).toHaveTextContent('Loading activity…')
    expect(screen.queryByText('No activity yet')).not.toBeInTheDocument()
    resolveInitial?.(jsonResponse(page([], null)))
    expect(await screen.findByText('No activity yet')).toBeVisible()
    expect(screen.getByText('Accepted changes to this task will appear here.')).toBeVisible()
    loading.unmount()

    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')))
    const failed = render(<ActivityList taskId={taskId} />)
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Couldn’t load activity. Your tasks weren’t changed.',
    )
    expect(screen.getByRole('button', { name: 'Retry loading activity' })).toBeVisible()
    failed.unmount()

    const staleProblem = {
      code: 'activity_cursor_stale',
      detail: 'This task changed before earlier activity could load.',
      recovery_action: 'refresh_activity',
      retryable: false,
      status: 409,
      title: 'Task activity changed',
      type: '/problems/activity_cursor_stale',
    }
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValueOnce(jsonResponse(page([item], 'signed-cursor')))
        .mockResolvedValueOnce(jsonResponse(staleProblem, 409)),
    )
    const user = userEvent.setup()
    render(<ActivityList taskId={taskId} />)
    await user.click(await screen.findByRole('button', { name: 'Load earlier activity' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'This view changed before more items could load.',
    )
    expect(screen.getByRole('button', { name: 'Refresh view' })).toBeVisible()
    expect(activitySentence('You updated task details.')).toBeVisible()
  })

  it('composes history into the canonical task route', async () => {
    const task = {
      captured_at: '2026-08-30T20:00:00Z',
      id: taskId,
      inbox_state: 'inbox',
      notes: '',
      project: null,
      revision: 2,
      tags: [],
      title: 'Call dentist',
    }
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const path = String(input)
        if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
        if (path === `/api/v1/tasks/${taskId}/activity?limit=20`) {
          return jsonResponse(page([item], null))
        }
        throw new Error(`Unexpected request ${path}`)
      }),
    )
    window.history.replaceState({}, '', `/tasks/${taskId}`)

    render(<AppRoutes authenticated csrfToken="csrf" />)

    expect(await screen.findByRole('heading', { name: 'Edit task' })).toBeVisible()
    expect(await screen.findByRole('heading', { name: 'Activity' })).toBeVisible()
    expect(activitySentence('You updated task details.')).toBeVisible()
  })
})
