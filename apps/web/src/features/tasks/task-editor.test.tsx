import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import TaskEditor from '@/features/tasks/TaskEditor'

const task = {
  captured_at: '2026-08-30T20:00:00Z',
  id: '018d8b40-2f10-7b1a-9d71-263f4af77001',
  inbox_state: 'inbox',
  notes: 'Ask about Tuesday',
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

afterEach(() => {
  vi.unstubAllGlobals()
  window.history.replaceState({}, '', '/')
})

describe('canonical task editor', () => {
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
