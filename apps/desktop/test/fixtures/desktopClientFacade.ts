import type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  EditInput,
  RecoveryAvailabilityView,
  TaskOutcome,
  UnresolvedRefusalView,
  WorkspaceConflictView,
  WorkspaceRoute,
  WorkspaceSnapshotView,
  WorkspaceTaskView,
} from '../../../../packages/web-ui/src/ClientFacade.ts'

/**
 * Deterministic desktop-facade fixture (D-26/D-27). It proves the shared
 * `packages/web-ui` Workspace/CaptureForm/TaskList/TaskEditor/
 * ConflictResolver/SyncRecovery presentation renders and behaves correctly
 * against a facade that never imports fetch, browser session state, or
 * platform APIs -- only named semantic operations, matching what the real
 * Electron renderer's preload-backed adapter exposes.
 *
 * This fixture is test-only: it is deterministic (no timers, no randomness
 * beyond an injectable ID generator) and lives outside `packages/web-ui` so
 * production shared presentation never imports it.
 */
type DesktopClientFacadeOptions = {
  nextId?: () => string
  seedConflict?: WorkspaceConflictView
  seedRoute?: WorkspaceRoute
  seedTasks?: readonly WorkspaceTaskView[]
  seedUnresolvedRefusals?: readonly UnresolvedRefusalView[]
}

type UndoEntry =
  | { kind: 'lifecycle'; previous: WorkspaceTaskView; taskId: string }
  | { kind: 'edit'; previous: { notes: string; title: string }; taskId: string }

const createDesktopClientFacade = (options: DesktopClientFacadeOptions = {}): ClientFacade => {
  let tasks: WorkspaceTaskView[] = [...(options.seedTasks ?? [])]
  let route: WorkspaceRoute = options.seedRoute ?? 'inbox'
  let selectedTaskId: string | null = null
  let conflict: WorkspaceConflictView | null = options.seedConflict ?? null
  let recovery: RecoveryAvailabilityView = null
  let lastUndo: UndoEntry | null = null
  let sequence = 0
  const nextId = options.nextId ?? (() => `desktop-fixture-task-${++sequence}`)

  const snapshotListeners = new Set<(snapshot: WorkspaceSnapshotView) => void>()
  const recoveryListeners = new Set<(availability: RecoveryAvailabilityView) => void>()

  const currentSnapshot = (): WorkspaceSnapshotView => ({
    conflict,
    route,
    selectedTaskId,
    tasks,
    unresolvedRefusals: options.seedUnresolvedRefusals ?? [],
  })

  const publishSnapshot = () => {
    const snapshot = currentSnapshot()
    for (const listener of snapshotListeners) listener(snapshot)
  }

  const publishRecovery = (label: string, handle: string) => {
    recovery = { expiresAt: '2026-01-01T00:00:00Z', handle, label }
    for (const listener of recoveryListeners) listener(recovery)
  }

  const clearRecovery = () => {
    recovery = null
    for (const listener of recoveryListeners) listener(recovery)
  }

  const findTask = (taskId: string): WorkspaceTaskView | undefined =>
    tasks.find((task) => task.id === taskId)

  const patchTask = (taskId: string, patch: Partial<WorkspaceTaskView>) => {
    tasks = tasks.map((task) => (task.id === taskId ? { ...task, ...patch } : task))
  }

  return {
    captureTask: (input: CaptureInput): Promise<CaptureOutcome> => {
      const title = input.title.trim()
      if (title.length === 0) {
        return Promise.resolve({ kind: 'rejected', message: 'task title must not be empty' })
      }

      // Mirrors the real desktop trust boundary (D-03): local acceptance is
      // durable before it is reported synced.
      const task: WorkspaceTaskView = {
        completedAt: null,
        id: nextId(),
        notes: '',
        planned: input.addToToday,
        syncStatus: 'saved_on_this_mac',
        title,
        trashedAt: null,
      }
      tasks = [task, ...tasks]
      publishSnapshot()
      return Promise.resolve({ kind: 'accepted', task })
    },
    completeTask: (taskId: string): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      lastUndo = { kind: 'lifecycle', previous, taskId }
      patchTask(taskId, { completedAt: '2026-01-01T00:00:00Z' })
      publishSnapshot()
      publishRecovery('Undo Complete', `undo-complete-${taskId}`)
      return Promise.resolve({ kind: 'accepted' })
    },
    editTask: (taskId: string, input: EditInput): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      if (input.title.trim().length === 0) {
        return Promise.resolve({ kind: 'rejected', message: 'task title must not be empty' })
      }
      lastUndo = { kind: 'edit', previous: { notes: previous.notes, title: previous.title }, taskId }
      patchTask(taskId, { notes: input.notes, title: input.title.trim() })
      publishSnapshot()
      publishRecovery('Undo Edit', `undo-edit-${taskId}`)
      return Promise.resolve({ kind: 'accepted' })
    },
    getRecoveryAvailability: () => recovery,
    getSnapshot: currentSnapshot,
    moveToday: (taskId: string, planned: boolean): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      lastUndo = { kind: 'lifecycle', previous, taskId }
      patchTask(taskId, { planned })
      publishSnapshot()
      return Promise.resolve({ kind: 'accepted' })
    },
    reopenTask: (taskId: string): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      lastUndo = { kind: 'lifecycle', previous, taskId }
      patchTask(taskId, { completedAt: null })
      publishSnapshot()
      publishRecovery('Undo Reopen', `undo-reopen-${taskId}`)
      return Promise.resolve({ kind: 'accepted' })
    },
    resolveConflict: (choices): Promise<TaskOutcome> => {
      if (conflict === null) return Promise.resolve({ kind: 'rejected', message: 'No conflict to resolve.' })
      const titleField = conflict.fields.find((field) => field.field === 'title')
      const choice = choices.title
      if (titleField !== undefined && choice !== undefined) {
        const resolvedTitle = choice === 'mine' ? titleField.mine : titleField.current
        patchTask(conflict.taskId, { syncStatus: 'synced', title: resolvedTitle ?? '' })
      }
      conflict = null
      publishSnapshot()
      return Promise.resolve({ kind: 'accepted' })
    },
    restoreTask: (taskId: string): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      lastUndo = { kind: 'lifecycle', previous, taskId }
      patchTask(taskId, { trashedAt: null })
      publishSnapshot()
      publishRecovery('Undo Restore', `undo-restore-${taskId}`)
      return Promise.resolve({ kind: 'accepted' })
    },
    selectTask: (taskId: string | null) => {
      selectedTaskId = taskId
      publishSnapshot()
    },
    setRoute: (nextRoute: WorkspaceRoute) => {
      route = nextRoute
      selectedTaskId = null
      publishSnapshot()
    },
    subscribe: (listener) => {
      snapshotListeners.add(listener)
      return () => snapshotListeners.delete(listener)
    },
    subscribeRecovery: (listener) => {
      recoveryListeners.add(listener)
      return () => recoveryListeners.delete(listener)
    },
    trashTask: (taskId: string): Promise<TaskOutcome> => {
      const previous = findTask(taskId)
      if (!previous) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      lastUndo = { kind: 'lifecycle', previous, taskId }
      patchTask(taskId, { trashedAt: '2026-01-01T00:00:00Z' })
      publishSnapshot()
      publishRecovery('Undo Trash', `undo-trash-${taskId}`)
      return Promise.resolve({ kind: 'accepted' })
    },
    undoLastChange: (): Promise<TaskOutcome> => {
      if (lastUndo === null) return Promise.resolve({ kind: 'rejected', message: 'Nothing to undo.' })
      if (lastUndo.kind === 'lifecycle') {
        patchTask(lastUndo.taskId, lastUndo.previous)
      } else {
        patchTask(lastUndo.taskId, { notes: lastUndo.previous.notes, title: lastUndo.previous.title })
      }
      lastUndo = null
      clearRecovery()
      publishSnapshot()
      return Promise.resolve({ kind: 'accepted' })
    },
  }
}

export { createDesktopClientFacade }
