import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import Workspace from '../../../../packages/web-ui/src/workspace/Workspace.tsx'
import type { UndoAvailability } from '@/api/keepling'
import { createBrowserClientFacade } from './browserClientFacade'

/**
 * Proves the browser-owned ClientFacade adapter preserves exact-submission
 * and session behavior (retry-safe mutation identity, the same
 * `keepling:task-acknowledged` / `keepling:undo-available` window events)
 * while exposing only the named `ClientFacade` operations to shared
 * presentation (D-26/D-27).
 */

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' }, status })

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('browserClientFacade', () => {
  it('does not fetch the Inbox until a snapshot is actually requested', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    createBrowserClientFacade('csrf')

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('loads the Inbox lazily and captures a task through the exact submission path', async () => {
    const acknowledgement = {
      mutation_id: 'mutation-1',
      outcome: 'accepted',
      resolved_conflict_id: null,
      revision: 1,
      snapshot: {
        captured_at: '2026-09-02T00:00:00Z',
        completed_at: null,
        deadline_on: null,
        id: 'task-1',
        inbox_state: 'inbox',
        notes: '',
        planned_on: null,
        project: null,
        revision: 1,
        tags: [],
        title: 'Call dentist',
        trashed_at: null,
      },
      task_id: 'task-1',
      undo: null,
      warnings: [],
    }

    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path.endsWith('/api/v1/inbox')) return jsonResponse({ tasks: [] })
      if (path.endsWith('/api/v1/commands/capture-task')) return jsonResponse(acknowledgement)
      throw new Error(`unexpected fetch: ${path} ${JSON.stringify(init)}`)
    })
    vi.stubGlobal('fetch', fetchMock)

    const acknowledgedEvents: unknown[] = []
    window.addEventListener('keepling:task-acknowledged', (event) => {
      acknowledgedEvents.push((event as CustomEvent).detail)
    })

    const facade = createBrowserClientFacade('csrf-token')
    const snapshots: Array<ReturnType<typeof facade.getSnapshot>> = []
    facade.subscribe((snapshot) => snapshots.push(snapshot))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith('/api/v1/inbox', expect.anything()))

    const outcome = await facade.captureTask({ addToToday: false, title: 'Call dentist' })

    expect(outcome).toEqual({
      kind: 'accepted',
      task: {
        completedAt: null,
        id: 'task-1',
        notes: '',
        planned: false,
        syncStatus: 'synced',
        title: 'Call dentist',
        trashedAt: null,
      },
    })
    expect(facade.getSnapshot().tasks.map((task) => task.title)).toEqual(['Call dentist'])
    expect(acknowledgedEvents).toHaveLength(1)

    const [, captureInit] = fetchMock.mock.calls.find(([requestInput]) =>
      String(requestInput).endsWith('/api/v1/commands/capture-task'),
    )!
    expect(JSON.parse(String(captureInit?.body))).toMatchObject({
      title: 'Call dentist',
    })
  })

  it('forwards recovery availability without ever calling fetch', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const facade = createBrowserClientFacade('csrf-token')
    const seen: unknown[] = []
    const unsubscribe = facade.subscribeRecovery((availability) => seen.push(availability))

    const availability: UndoAvailability = {
      expiresAt: '2026-09-02T00:05:00Z',
      handle: 'undo-handle',
      label: 'Undo Trash',
    }
    window.dispatchEvent(new CustomEvent('keepling:undo-available', { detail: availability }))

    expect(seen).toEqual([availability])
    expect(facade.getRecoveryAvailability()).toEqual(availability)
    expect(fetchMock).not.toHaveBeenCalled()

    unsubscribe()
  })

  it('renders the shared Workspace presentation through the browser adapter and captures a task', async () => {
    const acknowledgement = {
      mutation_id: 'mutation-2',
      outcome: 'accepted',
      resolved_conflict_id: null,
      revision: 1,
      snapshot: {
        captured_at: '2026-09-02T00:00:00Z',
        completed_at: null,
        deadline_on: null,
        id: 'task-2',
        inbox_state: 'inbox',
        notes: '',
        planned_on: null,
        project: null,
        revision: 1,
        tags: [],
        title: 'Water plants',
        trashed_at: null,
      },
      task_id: 'task-2',
      undo: null,
      warnings: [],
    }
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input)
      if (path.endsWith('/api/v1/inbox')) return jsonResponse({ tasks: [] })
      if (path.endsWith('/api/v1/commands/capture-task')) return jsonResponse(acknowledgement)
      throw new Error(`unexpected fetch: ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)

    const facade = createBrowserClientFacade('csrf-token')
    render(<Workspace facade={facade} />)

    const user = userEvent.setup()
    await user.type(screen.getByLabelText('What do you want to keep?'), 'Water plants')
    await user.click(screen.getByRole('button', { name: 'Add Task' }))

    await waitFor(() => expect(screen.getByText('Water plants')).toBeInTheDocument())
    expect(screen.getByText('Synced')).toBeInTheDocument()
  })
})
