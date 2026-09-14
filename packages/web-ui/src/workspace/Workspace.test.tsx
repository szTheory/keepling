import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createRef } from 'react'
import { describe, expect, it, vi } from 'vitest'

import type { ClientFacade, WorkspaceSnapshotView } from '../ClientFacade'
import Workspace, { type WorkspaceHandle } from './Workspace'

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

/**
 * Window 101 closure. The dirty-state guard must hold for a navigation
 * command that arrives BEFORE React has finished mirroring the editor's
 * dirty flag into `Workspace` state.
 *
 * The mirror is two async hops long: `TaskEditor` computes `dirty` during
 * render, reports it from a PASSIVE effect (`onDirtyChange`), which sets
 * `Workspace`'s `dirty` state, which re-renders `Workspace`, which finally
 * rebuilds the `WorkspaceHandle` whose `guardedSetRoute` closes over that
 * value. A `go-today`/`go-inbox`/`new-task` command delivered from the main
 * process inside that gap reads `dirty === false`, skips the dialog, and
 * navigates away from an edit the person never saved -- silent data loss,
 * not merely a test failure.
 *
 * This reproduces that interleaving DETERMINISTICALLY rather than by racing:
 * the input event is dispatched outside `act`, so React flushes the discrete
 * update (render + layout effects, which is where `useImperativeHandle` runs)
 * but has NOT yet run the passive effect that reports dirtiness upward. The
 * command is then delivered synchronously, in that exact gap.
 *
 * FOUND as a Playwright flake -- guarded-navigation.spec.ts:78 and :135, the
 * two cases that press a key immediately after dirtying the editor, failing
 * with "element(s) not found" waiting for the dialog. Both reproduce here
 * without any timing dependency at all.
 */
describe('Workspace dirty guard -- a command arriving before the dirty mirror settles (window 101)', () => {
  const dirtyTask = {
    completedAt: null,
    id: 'task-1',
    notes: '',
    planned: false,
    syncStatus: 'synced',
    title: 'Call dentist',
    trashedAt: null,
  } as unknown as WorkspaceSnapshotView['tasks'][number]

  /**
   * Dispatches a real input event WITHOUT `act`, so React's passive effects
   * stay queued -- the whole point of the test. React's own act warning is
   * suppressed for exactly this span because the un-acted interleaving IS
   * the condition under test, not an accident.
   */
  const typeWithoutFlushingPassiveEffects = (field: HTMLInputElement, value: string) => {
    const actEnvironment = (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT
    ;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = false
    try {
      const nativeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set
      nativeSetter?.call(field, value)
      field.dispatchEvent(new Event('input', { bubbles: true }))
    } finally {
      ;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = actEnvironment
    }
  }

  it('opens the discard dialog instead of navigating, and does not move the route', async () => {
    const facade = makeFacade({ ...baseSnapshot, selectedTaskId: 'task-1', tasks: [dirtyTask] })
    const handleRef = createRef<WorkspaceHandle>()
    render(<Workspace facade={facade} ref={handleRef} />)

    const titleField = document.getElementById('task-editor-title') as HTMLInputElement
    expect(titleField).toHaveValue('Call dentist')

    typeWithoutFlushingPassiveEffects(titleField, 'Call dentist, unsaved')
    // Delivered in the gap: the editor has rendered dirty, but Workspace has
    // not yet been told. This is the keystroke in guarded-navigation.spec.ts.
    handleRef.current?.guardedSetRoute('today')

    expect(await screen.findByRole('alertdialog', { name: 'Discard unsaved changes?' })).toBeVisible()
    expect(facade.setRoute).not.toHaveBeenCalled()
  })

  it('still navigates immediately when the editor is genuinely clean', async () => {
    const facade = makeFacade({ ...baseSnapshot, selectedTaskId: 'task-1', tasks: [dirtyTask] })
    const handleRef = createRef<WorkspaceHandle>()
    render(<Workspace facade={facade} ref={handleRef} />)

    handleRef.current?.guardedSetRoute('today')

    await waitFor(() => expect(facade.setRoute).toHaveBeenCalledWith('today'))
    expect(screen.queryByRole('alertdialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument()
  })
})
