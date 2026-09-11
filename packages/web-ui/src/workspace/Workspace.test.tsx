import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import type { ClientFacade, WorkspaceSnapshotView } from '../ClientFacade'
import Workspace from './Workspace'

const baseSnapshot: WorkspaceSnapshotView = {
  conflict: null,
  route: 'inbox',
  selectedTaskId: null,
  tasks: [],
  unresolvedRefusals: [],
}

const makeFacade = (snapshot: WorkspaceSnapshotView): ClientFacade & { setRoute: ReturnType<typeof vi.fn>; selectTask: ReturnType<typeof vi.fn> } => {
  let current = snapshot
  const listeners = new Set<(next: WorkspaceSnapshotView) => void>()
  const setRoute = vi.fn((route: WorkspaceSnapshotView['route']) => {
    current = { ...current, route }
    for (const listener of listeners) listener(current)
  })
  const selectTask = vi.fn((taskId: string | null) => {
    current = { ...current, selectedTaskId: taskId }
    for (const listener of listeners) listener(current)
  })

  return {
    captureTask: vi.fn(),
    completeTask: vi.fn(),
    editTask: vi.fn(),
    getRecoveryAvailability: () => null,
    getSnapshot: () => current,
    moveToday: vi.fn(),
    reopenTask: vi.fn(),
    resolveConflict: vi.fn(),
    restoreTask: vi.fn(),
    selectTask,
    setRoute,
    subscribe: (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    subscribeRecovery: () => () => undefined,
    trashTask: vi.fn(),
    undoLastChange: vi.fn(),
  } as unknown as ClientFacade & { setRoute: typeof setRoute; selectTask: typeof selectTask }
}

describe('Workspace recovery strip -- unresolved refusals (Task 2, O-44)', () => {
  it('surfaces an unresolved refusal for a task not currently viewed, naming the task', () => {
    const facade = makeFacade({
      ...baseSnapshot,
      unresolvedRefusals: [{ route: 'inbox', taskId: 'task-1', taskTitle: 'Book the ferry' }],
    })
    render(<Workspace facade={facade} />)

    expect(screen.getByText('Book the ferry changed while you were away. Review the conflict.', { exact: false })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Review conflict' })).toBeVisible()
  })

  it('navigates to the affected task when the recovery-strip action is activated', async () => {
    const facade = makeFacade({
      ...baseSnapshot,
      route: 'trash',
      unresolvedRefusals: [{ route: 'today', taskId: 'task-1', taskTitle: 'Book the ferry' }],
    })
    const user = userEvent.setup()
    render(<Workspace facade={facade} />)

    await user.click(screen.getByRole('button', { name: 'Review conflict' }))

    expect(facade.setRoute).toHaveBeenCalledWith('today')
    expect(facade.selectTask).toHaveBeenCalledWith('task-1')
  })

  it('renders no entry once a refusal is no longer unresolved', () => {
    const facade = makeFacade({ ...baseSnapshot, unresolvedRefusals: [] })
    render(<Workspace facade={facade} />)

    expect(screen.queryByRole('button', { name: 'Review conflict' })).not.toBeInTheDocument()
    expect(screen.queryByText('changed while you were away', { exact: false })).not.toBeInTheDocument()
  })

  it('surfaces multiple unresolved refusals without displacing the eligible-undo entry', () => {
    const facade: ClientFacade = {
      ...makeFacade({
        ...baseSnapshot,
        unresolvedRefusals: [
          { route: 'inbox', taskId: 'task-1', taskTitle: 'Book the ferry' },
          { route: 'today', taskId: 'task-2', taskTitle: 'Buy milk' },
        ],
      }),
      getRecoveryAvailability: () => ({ expiresAt: '2026-01-01T00:00:00Z', handle: 'undo-1', label: 'Undo Complete' }),
      subscribeRecovery: (listener) => {
        listener({ expiresAt: '2026-01-01T00:00:00Z', handle: 'undo-1', label: 'Undo Complete' })
        return () => undefined
      },
    }
    render(<Workspace facade={facade} />)

    expect(screen.getByRole('button', { name: 'Undo Complete' })).toBeVisible()
    expect(screen.getAllByRole('button', { name: 'Review conflict' })).toHaveLength(2)
    expect(screen.getByText('Book the ferry', { exact: false })).toBeVisible()
    expect(screen.getByText('Buy milk', { exact: false })).toBeVisible()
  })
})
