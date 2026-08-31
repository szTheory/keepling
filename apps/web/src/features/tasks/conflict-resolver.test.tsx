import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import type { TaskConflict } from '@/api/keepling'
import ConflictResolver from '@/features/tasks/ConflictResolver'
import TaskEditor from '@/features/tasks/TaskEditor'

const task = {
  captured_at: '2026-08-30T20:00:00.000000Z',
  completed_at: null,
  deadline_on: null,
  id: '018d8b40-2f10-7b1a-9d71-263f4af77001',
  inbox_state: 'inbox' as const,
  notes: 'Accepted notes',
  planned_on: null,
  project: null,
  revision: 1,
  tags: [],
  title: 'Base title',
  trashed_at: null,
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const activityResponse = () =>
  jsonResponse({ account_timezone: 'America/New_York', items: [], next_cursor: null })

const conflictProblem = () => ({
  affected_fields: ['title'],
  code: 'task_edit_conflict',
  conflict: {
    fields: [
      { base: 'Base title', current: 'Current title', field: 'title', mine: 'My title' },
    ],
    id: '018d8b40-2f10-7b1a-9d71-263f4af77002',
    latest_revision: 2,
  },
  current_revision: 2,
  detail: 'Review the affected fields before saving again.',
  recovery_action: 'review_task_conflict',
  retryable: false,
  status: 409,
  title: 'Task changed elsewhere',
  type: '/problems/task_edit_conflict',
})

const acknowledgement = (mutationId: string, title = 'My title') => ({
  mutation_id: mutationId,
  outcome: 'accepted',
  resolved_conflict_id: conflictProblem().conflict.id,
  revision: 3,
  snapshot: { ...task, notes: 'Keep this draft', revision: 3, title },
  task_id: task.id,
  warnings: [],
})

const installEditorFetch = (
  resolveConflict: (request: Record<string, unknown>) => Promise<Response> | Response,
) => {
  let originalMutationId = ''
  const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input)
    if (path === '/api/v1/inbox') return Promise.resolve(jsonResponse({ tasks: [task] }))
    if (path.startsWith(`/api/v1/tasks/${task.id}/activity?`)) {
      return Promise.resolve(activityResponse())
    }
    if (path === '/api/v1/commands/edit-task') {
      const request = JSON.parse(String(init?.body)) as Record<string, unknown>
      originalMutationId = String(request.mutation_id)
      return Promise.resolve(jsonResponse(conflictProblem(), 409))
    }
    if (path === '/api/v1/commands/resolve-task-conflict') {
      const request = JSON.parse(String(init?.body)) as Record<string, unknown>
      return Promise.resolve(resolveConflict(request))
    }
    throw new Error(`Unexpected request ${path}`)
  })

  vi.stubGlobal('fetch', fetchMock)
  return { fetchMock, getOriginalMutationId: () => originalMutationId }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('inline task conflict resolution', () => {
  it('renders long hostile values as affected plain text with an accessible six-line disclosure', async () => {
    const longMine = Array.from({ length: 8 }, (_, index) => `Mine ${index + 1}`).join('\n')
    const longCurrent = '<img src=x onerror="window.conflictRan=true">\n' + longMine
    const conflict: TaskConflict = {
      fields: [
        { base: 'Old notes', current: longCurrent, field: 'notes', mine: longMine },
      ],
      id: conflictProblem().conflict.id,
      latestRevision: 2,
    }

    render(
      <ConflictResolver
        conflict={conflict}
        csrfToken="csrf"
        onAcknowledged={vi.fn()}
        onKeepEditing={vi.fn()}
        taskId={task.id}
      />,
    )

    const resolver = screen.getByRole('region', { name: 'This task changed somewhere else.' })
    expect(within(resolver).getByText('Your version')).toBeVisible()
    expect(within(resolver).getByText('Current version')).toBeVisible()
    expect(within(resolver).getAllByRole('button', { name: 'Show full value' })).toHaveLength(2)
    expect(document.querySelector('img')).toBeNull()
    expect(
      screen.getByText((_, element) => element?.textContent === longCurrent),
    ).toHaveTextContent('<img src=x onerror=')

    const disclosure = within(resolver).getAllByRole('button', { name: 'Show full value' })[0]
    expect(disclosure).toHaveAttribute('aria-expanded', 'false')
    await userEvent.setup().click(disclosure)
    expect(disclosure).toHaveAttribute('aria-expanded', 'true')
    expect(disclosure).toHaveTextContent('Show less')
  })

  it('keeps nonconflicting drafts and returns focus to the affected field for continued editing', async () => {
    installEditorFetch(() => jsonResponse({}))
    const user = userEvent.setup()

    render(<TaskEditor csrfToken="csrf" taskId={task.id} />)

    const title = await screen.findByLabelText('Title')
    const notes = screen.getByLabelText('Notes')
    await user.clear(title)
    await user.type(title, 'My title')
    await user.clear(notes)
    await user.type(notes, 'Keep this draft')
    await user.click(screen.getByRole('button', { name: 'Save changes' }))

    const heading = await screen.findByRole('heading', {
      name: 'This task changed somewhere else.',
    })
    expect(heading).toHaveFocus()
    expect(screen.getByText('My title')).toBeVisible()
    expect(screen.getByText('Current title')).toBeVisible()
    expect(screen.queryByText('Accepted notes')).not.toBeInTheDocument()
    expect(notes).toHaveValue('Keep this draft')

    await user.click(screen.getByRole('button', { name: 'Keep editing' }))
    expect(title).toHaveFocus()
    expect(notes).toHaveValue('Keep this draft')
    expect(screen.queryByRole('heading', { name: 'This task changed somewhere else.' })).toBeNull()
  })

  it('submits selected values with a fresh identity and reconciles only exact acknowledgement', async () => {
    const { fetchMock, getOriginalMutationId } = installEditorFetch((request) =>
      jsonResponse(acknowledgement(String(request.mutation_id))),
    )
    const user = userEvent.setup()

    render(<TaskEditor csrfToken="csrf" taskId={task.id} />)

    const title = await screen.findByLabelText('Title')
    const notes = screen.getByLabelText('Notes')
    await user.clear(title)
    await user.type(title, 'My title')
    await user.clear(notes)
    await user.type(notes, 'Keep this draft')
    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    await screen.findByRole('heading', { name: 'This task changed somewhere else.' })

    const mine = screen.getByRole('button', { name: 'Use mine for Title' })
    await user.click(mine)
    expect(mine).toHaveAttribute('aria-pressed', 'true')
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))

    const resolutionCall = fetchMock.mock.calls.find(
      ([url]) => String(url) === '/api/v1/commands/resolve-task-conflict',
    )
    const request = JSON.parse(String(resolutionCall?.[1]?.body)) as Record<string, unknown>
    expect(request).toMatchObject({
      conflict_id: conflictProblem().conflict.id,
      latest_revision: 2,
      selections: { title: 'mine' },
      task_id: task.id,
      version: 1,
    })
    expect(request.mutation_id).not.toBe(getOriginalMutationId())

    await waitFor(() => expect(title).toHaveValue('My title'))
    expect(notes).toHaveValue('Keep this draft')
    expect(screen.queryByRole('heading', { name: 'This task changed somewhere else.' })).toBeNull()
    expect(screen.getByRole('button', { name: 'Save changes' })).toHaveFocus()
  })

  it('retries an unknown resolution with the exact body and keeps an honest stale state visible', async () => {
    let attempts = 0
    const { fetchMock } = installEditorFetch(() => {
      attempts += 1
      if (attempts === 1) throw new TypeError('response lost')
      return jsonResponse(
        {
          code: 'task_conflict_stale',
          current_revision: 3,
          detail: 'Review the latest task before resolving the conflict again.',
          recovery_action: 'review_task_conflict',
          retryable: false,
          status: 409,
          title: 'Task changed after the conflict',
          type: '/problems/task_conflict_stale',
        },
        409,
      )
    })
    const user = userEvent.setup()

    render(<TaskEditor csrfToken="csrf" taskId={task.id} />)
    const title = await screen.findByLabelText('Title')
    await user.clear(title)
    await user.type(title, 'My title')
    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    await screen.findByRole('heading', { name: 'This task changed somewhere else.' })
    await user.click(screen.getByRole('button', { name: 'Use current for Title' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))

    expect(await screen.findByRole('status')).toHaveTextContent(
      'Checking whether your resolution was saved…',
    )

    const firstBody = String(
      fetchMock.mock.calls.filter(
        ([url]) => String(url) === '/api/v1/commands/resolve-task-conflict',
      )[0]?.[1]?.body,
    )
    await user.click(screen.getByRole('button', { name: 'Check again' }))
    const resolutionCalls = fetchMock.mock.calls.filter(
      ([url]) => String(url) === '/api/v1/commands/resolve-task-conflict',
    )
    expect(resolutionCalls).toHaveLength(2)
    expect(String(resolutionCalls[1]?.[1]?.body)).toBe(firstBody)
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'This task changed again. Review the latest task before resolving it.',
    )
    expect(screen.getByLabelText('Title')).toHaveValue('My title')
    expect(screen.getByRole('heading', { name: 'This task changed somewhere else.' })).toBeVisible()
  })
})
