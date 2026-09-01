import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import type { TaskConflict } from '@/api/keepling'
import ActivityList from '@/features/activity/ActivityList'
import ConflictResolver from '@/features/tasks/ConflictResolver'
import TaskEditor from '@/features/tasks/TaskEditor'

const taskId = '018d8b40-2f10-7b1a-9d71-263f4af77001'
const hostile = '</textarea><img src=x onerror="window.hostileRan=true"><script>window.hostileRan=true</script>javascript:alert(1)'

const jsonResponse = (body: unknown) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json' },
    status: 200,
  })

const task = {
  captured_at: '2026-08-31T01:15:00.000000Z',
  completed_at: null,
  deadline_on: null,
  id: taskId,
  inbox_state: 'inbox',
  notes: hostile,
  planned_on: null,
  project: null,
  revision: 1,
  tags: [],
  title: hostile,
  trashed_at: null,
}

const activity = {
  accepted_at: '2026-08-31T01:16:00.000000Z',
  activity_id: 2,
  actor: { label: 'You', principal: 'account_owner', type: 'user' },
  changes: [{ field: 'notes', kind: 'text', new: hostile, old: 'safe' }],
  client_kind: 'web',
  from_revision: 1,
  mutation_id: '018d8b40-2f10-7b1a-9d71-263f4af77002',
  outcome: 'accepted',
  recovery_state: 'not_available',
  to_revision: 2,
  type: 'task_details_updated',
  undone_activity_id: null,
  version: 1,
}

const expectNoInjectedDom = () => {
  expect(document.querySelector('script')).toBeNull()
  expect(document.querySelector('img')).toBeNull()
  expect(document.querySelector('[onerror]')).toBeNull()
  expect(document.querySelector('[href^="javascript:"]')).toBeNull()
  expect((window as Window & { hostileRan?: boolean }).hostileRan).not.toBe(true)
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  delete (window as Window & { hostileRan?: boolean }).hostileRan
})

describe('hostile canonical content', () => {
  it('keeps task title and notes literal in the routed editor controls', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn((input: RequestInfo | URL) => {
        const path = String(input)
        if (path === `/api/v1/tasks/${taskId}`) return Promise.resolve(jsonResponse(task))
        if (path.startsWith(`/api/v1/tasks/${taskId}/activity?`)) {
          return Promise.resolve(
            jsonResponse({ account_timezone: 'America/New_York', items: [], next_cursor: null }),
          )
        }
        throw new Error(`Unexpected request ${path}`)
      }),
    )

    render(<TaskEditor csrfToken="csrf" taskId={taskId} />)

    expect(await screen.findByLabelText('Title')).toHaveValue(hostile)
    expect(screen.getByLabelText('Notes')).toHaveValue(hostile)
    expectNoInjectedDom()
  })

  it('keeps activity changes literal inside the real disclosure surface', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse({
          account_timezone: 'America/New_York',
          items: [activity],
          next_cursor: null,
        }),
      ),
    )

    render(<ActivityList taskId={taskId} />)

    expect(await screen.findByText(hostile)).toBeInTheDocument()
    expectNoInjectedDom()
  })

  it('keeps mine and current conflict values literal', async () => {
    const conflict: TaskConflict = {
      fields: [{ base: 'safe', current: hostile, field: 'notes', mine: hostile }],
      id: '018d8b40-2f10-7b1a-9d71-263f4af77003',
      latestRevision: 2,
    }

    render(
      <ConflictResolver
        conflict={conflict}
        csrfToken="csrf"
        onAcknowledged={vi.fn()}
        onKeepEditing={vi.fn()}
        taskId={taskId}
      />,
    )

    await waitFor(() => expect(screen.getAllByText(hostile)).toHaveLength(2))
    expectNoInjectedDom()
  })
})
