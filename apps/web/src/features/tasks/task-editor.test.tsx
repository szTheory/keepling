import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import QuickCapture from '@/features/capture/QuickCapture'
import TaskEditor from '@/features/tasks/TaskEditor'

const task = {
  captured_at: '2026-08-30T20:00:00Z',
  deadline_on: '2026-09-02',
  id: '018d8b40-2f10-7b1a-9d71-263f4af77001',
  inbox_state: 'inbox',
  notes: 'Ask about Tuesday',
  planned_on: '2026-08-31',
  revision: 3,
  title: 'Call dentist',
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const acknowledgement = (overrides: Partial<typeof task> = {}) => {
  const snapshot = { ...task, ...overrides }
  return {
    mutation_id: 'mutation-from-request',
    outcome: 'accepted',
    revision: snapshot.revision,
    snapshot,
    task_id: snapshot.id,
    warnings: [],
  }
}

const inboxResponse = () => jsonResponse({ tasks: [task] })

const activityResponse = () =>
  jsonResponse({
    account_timezone: 'America/New_York',
    items: [],
    next_cursor: null,
  })

afterEach(() => {
  vi.unstubAllGlobals()
  window.history.replaceState({}, '', '/')
})

describe('canonical task editor', () => {
  it('keeps Inbox explicit and plans an opted-in capture only after exact capture acknowledgement', async () => {
    let resolvePlan: ((response: Response) => void) | undefined
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === '/api/v1/commands/capture-task') {
        const request = JSON.parse(String(init?.body)) as Record<string, string>
        return Promise.resolve(
          jsonResponse({
            ...acknowledgement({
              deadline_on: null,
              notes: '',
              planned_on: null,
              revision: 1,
              title: request.title,
            }),
            mutation_id: request.mutation_id,
            task_id: request.task_id,
          }, 201),
        )
      }
      if (String(input) === '/api/v1/commands/plan-for-today') {
        return new Promise<Response>((resolve) => {
          resolvePlan = resolve
        })
      }
      throw new Error(`Unexpected request ${String(input)} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onCaptured = vi.fn()
    const user = userEvent.setup()

    render(<QuickCapture csrfToken="csrf" onCaptured={onCaptured} />)

    expect(screen.getByText('Destination: Inbox')).toBeVisible()
    await user.type(screen.getByLabelText('What do you want to keep?'), 'Plan this deliberately')
    await user.click(screen.getByRole('checkbox', { name: 'Add to Today' }))
    await user.click(screen.getByRole('button', { name: 'Add task' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const captureRequest = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body)) as Record<
      string,
      unknown
    >
    const planRequest = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<
      string,
      unknown
    >

    expect(planRequest).toMatchObject({
      base_planned_on: null,
      expected_revision: 1,
      task_id: captureRequest.task_id,
      version: 1,
    })
    expect(planRequest).not.toHaveProperty('planned_on')
    expect(onCaptured).not.toHaveBeenCalled()
    expect(screen.getByLabelText('What do you want to keep?')).toHaveValue(
      'Plan this deliberately',
    )

    resolvePlan?.(
      jsonResponse({
        ...acknowledgement({
          deadline_on: null,
          notes: '',
          planned_on: '2026-08-31',
          revision: 2,
          title: 'Plan this deliberately',
        }),
        mutation_id: planRequest.mutation_id,
        task_id: captureRequest.task_id,
      }),
    )

    await waitFor(() => expect(onCaptured).toHaveBeenCalledOnce())
    expect(screen.getByLabelText('What do you want to keep?')).toHaveValue('')
    expect(screen.getByRole('checkbox', { name: 'Add to Today' })).not.toBeChecked()
  })

  it('edits planned date and deadline separately with account-zone help and the locked warning', async () => {
    let resolveDates: ((response: Response) => void) | undefined
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === '/api/v1/inbox') return Promise.resolve(inboxResponse())
      if (String(input).startsWith(`/api/v1/tasks/${task.id}/activity?`)) {
        return Promise.resolve(activityResponse())
      }
      if (String(input) === '/api/v1/commands/edit-task-dates') {
        return new Promise<Response>((resolve) => {
          resolveDates = resolve
        })
      }
      throw new Error(`Unexpected request ${String(input)} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <TaskEditor
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onNavigate={vi.fn()}
        taskId={task.id}
      />,
    )

    const planned = await screen.findByLabelText('Planned date')
    const deadline = screen.getByLabelText('Deadline')
    expect(planned).toHaveValue('2026-08-31')
    expect(deadline).toHaveValue('2026-09-02')
    expect(screen.getByText('Dates use America/New_York')).toBeVisible()

    await user.clear(planned)
    await user.type(planned, '2026-09-03')
    expect(
      screen.getByText('Planned date is after the deadline. Both dates will be saved.'),
    ).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Save changes' }))

    const request = JSON.parse(
      String(fetchMock.mock.calls.find(([url]) => String(url) === '/api/v1/commands/edit-task-dates')?.[1]?.body),
    ) as Record<string, unknown>
    expect(request).toMatchObject({
      base_values: { planned_on: '2026-08-31' },
      expected_revision: 3,
      fields: { planned_on: '2026-09-03' },
      task_id: task.id,
      version: 1,
    })
    expect(onAcknowledged).not.toHaveBeenCalled()

    resolveDates?.(
      jsonResponse({
        ...acknowledgement({ planned_on: '2026-09-03', revision: 4 }),
        mutation_id: request.mutation_id,
        warnings: [
          {
            code: 'planned_after_deadline',
            message: 'Planned date is after the deadline. Both dates will be saved.',
          },
        ],
      }),
    )

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledOnce())
    expect(planned).toHaveValue('2026-09-03')
    expect(deadline).toHaveValue('2026-09-02')
  })

  it('preserves invalid civil-date text and focuses it without submitting', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      if (String(input) === '/api/v1/inbox') return Promise.resolve(inboxResponse())
      if (String(input).startsWith(`/api/v1/tasks/${task.id}/activity?`)) {
        return Promise.resolve(activityResponse())
      }
      throw new Error(`Unexpected request ${String(input)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<TaskEditor csrfToken="csrf" onNavigate={vi.fn()} taskId={task.id} />)

    const planned = await screen.findByLabelText('Planned date')
    await user.clear(planned)
    await user.type(planned, '2026-02-30')
    await user.click(screen.getByRole('button', { name: 'Save changes' }))

    expect(planned).toHaveValue('2026-02-30')
    expect(planned).toHaveFocus()
    expect(screen.getByText('Enter a valid planned date in YYYY-MM-DD format.')).toBeVisible()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('sends only touched notes with their base value and never saves on blur', async () => {
    let resolveSave: ((response: Response) => void) | undefined
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === '/api/v1/inbox') return Promise.resolve(inboxResponse())
      if (String(input) === '/api/v1/commands/edit-task') {
        return new Promise<Response>((resolve) => {
          resolveSave = resolve
        })
      }
      throw new Error(`Unexpected request ${String(input)} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <TaskEditor
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onNavigate={vi.fn()}
        taskId={task.id}
      />,
    )

    const notes = await screen.findByLabelText('Notes')
    await user.clear(notes)
    await user.type(notes, 'Ask about Wednesday')
    await user.tab()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    const request = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>
    expect(request).toMatchObject({
      base_values: { notes: 'Ask about Tuesday' },
      expected_revision: 3,
      fields: { notes: 'Ask about Wednesday' },
      task_id: task.id,
      version: 1,
    })
    expect(request).not.toHaveProperty('title')
    expect(request.base_values).not.toHaveProperty('title')
    expect(onAcknowledged).not.toHaveBeenCalled()
    expect(notes).toHaveValue('Ask about Wednesday')

    const mutationId = request.mutation_id as string
    resolveSave?.(
      jsonResponse(
        {
          ...acknowledgement({ notes: 'Ask about Wednesday', revision: 4 }),
          mutation_id: mutationId,
        },
      ),
    )

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledOnce())
    expect(screen.getByRole('status')).toHaveTextContent('Task saved.')
  })

  it('waits for exact acknowledgement before Save & move leaves Inbox', async () => {
    let resolveClarify: ((response: Response) => void) | undefined
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === '/api/v1/inbox') return Promise.resolve(inboxResponse())
      if (String(input) === '/api/v1/commands/clarify-task') {
        return new Promise<Response>((resolve) => {
          resolveClarify = resolve
        })
      }
      throw new Error(`Unexpected request ${String(input)} ${String(init?.method)}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onNavigate = vi.fn()
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <TaskEditor
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onNavigate={onNavigate}
        taskId={task.id}
      />,
    )

    await screen.findByDisplayValue('Call dentist')
    await user.click(screen.getByRole('button', { name: 'Save & move out of Inbox' }))
    expect(onNavigate).not.toHaveBeenCalled()
    expect(onAcknowledged).not.toHaveBeenCalled()

    const request = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as Record<string, unknown>
    const mutationId = request.mutation_id as string
    resolveClarify?.(
      jsonResponse({
        ...acknowledgement({ inbox_state: 'clarified', revision: 4 }),
        mutation_id: mutationId,
      }),
    )

    await waitFor(() => expect(onNavigate).toHaveBeenCalledWith('/'))
    expect(onAcknowledged).toHaveBeenCalledWith(
      expect.objectContaining({ snapshot: expect.objectContaining({ inboxState: 'clarified' }) }),
    )
  })

  it('preserves every field, links the summary, and focuses the first invalid field', async () => {
    const fetchMock = vi.fn().mockResolvedValue(inboxResponse())
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(
      <TaskEditor csrfToken="csrf" onNavigate={vi.fn()} taskId={task.id} />,
    )

    const title = await screen.findByLabelText('Title')
    const notes = screen.getByLabelText('Notes')
    await user.clear(title)
    await user.clear(notes)
    await user.type(notes, 'Keep this notes draft')
    fireEvent.keyDown(notes, { ctrlKey: true, key: 'Enter' })

    expect(await screen.findByRole('alert')).toHaveTextContent('Review the highlighted fields')
    expect(screen.getByRole('link', { name: 'Enter a task title.' })).toHaveAttribute(
      'href',
      '#task-editor-title',
    )
    expect(title).toHaveFocus()
    expect(notes).toHaveValue('Keep this notes draft')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('offers Save, Discard, and Stay for dirty navigation and scopes beforeunload', async () => {
    const fetchMock = vi.fn().mockResolvedValue(inboxResponse())
    vi.stubGlobal('fetch', fetchMock)
    const onNavigate = vi.fn()
    const user = userEvent.setup()

    render(<TaskEditor csrfToken="csrf" onNavigate={onNavigate} taskId={task.id} />)

    const notes = await screen.findByLabelText('Notes')
    await user.type(notes, ' updated')

    const beforeUnload = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(beforeUnload)
    expect(beforeUnload.defaultPrevented).toBe(true)

    fireEvent.keyDown(notes, { key: 'Escape' })
    expect(screen.getByRole('alertdialog')).toHaveTextContent('You have unsaved changes.')
    expect(screen.getByRole('button', { name: 'Stay here' })).toHaveFocus()
    expect(screen.getByRole('button', { name: 'Save changes' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Discard changes' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Stay here' }))
    expect(onNavigate).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Cancel editing' }))
    await user.click(screen.getByRole('button', { name: 'Discard changes' }))
    expect(onNavigate).toHaveBeenCalledWith('/')
  })

  it('routes the same editor component at the canonical task URL', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(inboxResponse()))
    window.history.replaceState({}, '', `/tasks/${task.id}`)

    render(<AppRoutes authenticated csrfToken="csrf" />)

    expect(await screen.findByRole('heading', { name: 'Edit task' })).toBeVisible()
    expect(screen.getByDisplayValue('Call dentist')).toBeVisible()
  })

  it('renders task title and notes as plain text without creating hostile markup', async () => {
    const hostileTask = {
      ...task,
      notes: '<script>window.taskNotesRan = true</script>',
      title: '<img src=x onerror="window.taskTitleRan = true">',
    }
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ tasks: [hostileTask] })))

    render(<TaskEditor csrfToken="csrf" taskId={task.id} />)

    expect(await screen.findByLabelText('Title')).toHaveValue(hostileTask.title)
    expect(screen.getByLabelText('Notes')).toHaveValue(hostileTask.notes)
    expect(document.querySelector('img')).toBeNull()
    expect(document.querySelector('script')).toBeNull()
  })
})
