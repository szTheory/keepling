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

const deferred = <Value,>() => {
  let resolve!: (value: Value) => void
  const promise = new Promise<Value>((resolvePromise) => {
    resolve = resolvePromise
  })
  return { promise, resolve }
}

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
  lookupConflict?: (mutationId: string) => Promise<Response> | Response,
) => {
  let originalMutationId = ''
  const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input)
    if (path === `/api/v1/tasks/${task.id}`) return Promise.resolve(jsonResponse(task))
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
    if (path.startsWith('/api/v1/mutations/') && lookupConflict) {
      return Promise.resolve(lookupConflict(path.slice('/api/v1/mutations/'.length)))
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
  it('freezes the dispatched selection until its deferred response settles', async () => {
    const response = deferred<Response>()
    const bodies: string[] = []
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      bodies.push(String(init?.body))
      return response.promise
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const onKeepEditing = vi.fn()
    const user = userEvent.setup()

    render(
      <ConflictResolver
        conflict={{
          fields: conflictProblem().conflict.fields as TaskConflict['fields'],
          id: conflictProblem().conflict.id,
          latestRevision: 2,
        }}
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onKeepEditing={onKeepEditing}
        taskId={task.id}
      />,
    )

    const mine = screen.getByRole('button', { name: 'Use mine for Title' })
    const current = screen.getByRole('button', { name: 'Use current for Title' })
    const keepEditing = screen.getByRole('button', { name: 'Keep editing' })
    const save = screen.getByRole('button', { name: 'Save resolution' })

    await user.click(mine)
    await user.click(save)

    expect(mine).toBeDisabled()
    expect(current).toBeDisabled()
    expect(keepEditing).toBeDisabled()
    expect(save).toBeDisabled()
    await user.click(current)
    await user.click(keepEditing)
    await user.click(save)
    expect(mine).toHaveAttribute('aria-pressed', 'true')
    expect(current).toHaveAttribute('aria-pressed', 'false')
    expect(onKeepEditing).not.toHaveBeenCalled()
    expect(bodies).toHaveLength(1)

    const request = JSON.parse(bodies[0] ?? '{}') as { mutation_id: string }
    response.resolve(jsonResponse(acknowledgement(request.mutation_id)))

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledOnce())
    expect(onAcknowledged).toHaveBeenCalledWith(
      expect.objectContaining({ snapshot: expect.objectContaining({ title: 'My title' }) }),
    )
    expect(bodies).toHaveLength(1)
  })

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

  it('checks a before-acceptance resolution receipt before replaying exact bytes', async () => {
    let attempts = 0
    const { fetchMock } = installEditorFetch(
      () => {
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
      },
      () => jsonResponse(
        {
          code: 'mutation_not_found',
          detail: 'No receipt exists.',
          recovery_action: 'retry_original_mutation',
          retryable: false,
          status: 404,
          title: 'Mutation not found',
          type: '/problems/mutation_not_found',
        },
        404,
      ),
    )
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
    expect(screen.getByRole('button', { name: 'Use mine for Title' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Use current for Title' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Keep editing' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Save resolution' })).toBeDisabled()

    const firstBody = String(
      fetchMock.mock.calls.filter(
        ([url]) => String(url) === '/api/v1/commands/resolve-task-conflict',
      )[0]?.[1]?.body,
    )
    await user.click(screen.getByRole('button', { name: 'Check again' }))
    expect(
      fetchMock.mock.calls.some(([url]) => String(url).startsWith('/api/v1/mutations/')),
    ).toBe(true)
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

  it('settles an after-commit resolution from lookup without resending', async () => {
    const bodies: string[] = []
    let stored: ReturnType<typeof acknowledgement> | null = null
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path === '/api/v1/commands/resolve-task-conflict') {
        const body = String(init?.body)
        bodies.push(body)
        const request = JSON.parse(body) as { mutation_id: string }
        stored = acknowledgement(request.mutation_id)
        throw new TypeError('response lost after commit')
      }
      if (path.startsWith('/api/v1/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <ConflictResolver
        conflict={{
          fields: conflictProblem().conflict.fields as TaskConflict['fields'],
          id: conflictProblem().conflict.id,
          latestRevision: 2,
        }}
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onKeepEditing={() => undefined}
        taskId={task.id}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Use mine for Title' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledOnce())
    expect(bodies).toHaveLength(1)
    const mutationId = (JSON.parse(bodies[0] ?? '{}') as { mutation_id: string }).mutation_id
    expect(fetchMock.mock.calls[1]?.[0]).toBe(`/api/v1/mutations/${mutationId}`)
  })

  it('marks authentication after dispatch submitted-unknown and resumes with receipt lookup', async () => {
    const bodies: string[] = []
    let stored: ReturnType<typeof acknowledgement> | null = null
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path === '/api/v1/commands/resolve-task-conflict') {
        const body = String(init?.body)
        bodies.push(body)
        const request = JSON.parse(body) as { mutation_id: string }
        stored = acknowledgement(request.mutation_id)
        return jsonResponse(
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
      }
      if (path.startsWith('/api/v1/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(
      <ConflictResolver
        conflict={{
          fields: conflictProblem().conflict.fields as TaskConflict['fields'],
          id: conflictProblem().conflict.id,
          latestRevision: 2,
        }}
        csrfToken="expired-csrf"
        onAcknowledged={onAcknowledged}
        onAuthenticationRequired={onAuthenticationRequired}
        onKeepEditing={() => undefined}
        taskId={task.id}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Use mine for Title' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    expect(screen.getByRole('button', { name: 'Use mine for Title' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Use current for Title' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Keep editing' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Save resolution' })).toBeDisabled()
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string; mutationId: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'sign_in', kind: 'submitted-unknown' })
    await resume('new-csrf')

    await waitFor(() => expect(onAcknowledged).toHaveBeenCalledOnce())
    expect(bodies).toHaveLength(1)
    expect(fetchMock.mock.calls[1]?.[0]).toBe(`/api/v1/mutations/${intent.mutationId}`)
  })

  it('does not settle an acknowledgement whose resolved conflict identity changed', async () => {
    const wrongConflictId = '99999999-9999-4999-8999-999999999999'
    let mutationId = ''
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const path = String(input)
      if (path === '/api/v1/commands/resolve-task-conflict') {
        mutationId = (JSON.parse(String(init?.body)) as { mutation_id: string }).mutation_id
      }
      if (
        path === '/api/v1/commands/resolve-task-conflict' ||
        path === `/api/v1/mutations/${mutationId}`
      ) {
        return jsonResponse({
          ...acknowledgement(mutationId),
          resolved_conflict_id: wrongConflictId,
        })
      }
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAcknowledged = vi.fn()
    const user = userEvent.setup()

    render(
      <ConflictResolver
        conflict={{
          fields: conflictProblem().conflict.fields as TaskConflict['fields'],
          id: conflictProblem().conflict.id,
          latestRevision: 2,
        }}
        csrfToken="csrf"
        onAcknowledged={onAcknowledged}
        onKeepEditing={() => undefined}
        taskId={task.id}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Use mine for Title' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    expect(await screen.findByText('Checking whether your resolution was saved…')).toBeVisible()
    expect(onAcknowledged).not.toHaveBeenCalled()
  })
})
