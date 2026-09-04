import type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  EditInput,
  RecoveryAvailabilityView,
  TaskOutcome,
  WorkspaceConflictView,
  WorkspaceLayoutState,
  WorkspaceRoute,
  WorkspaceSnapshotView,
  WorkspaceTaskView,
} from '../../../packages/web-ui/src/ClientFacade.ts'

type PreloadTask = Awaited<ReturnType<typeof window.keepling.snapshot>>['tasks'][number]
type PreloadConflict = Awaited<ReturnType<typeof window.keepling.listConflicts>>[number]

/**
 * The production Electron renderer's ClientFacade adapter. It wraps the
 * narrow `window.keepling` preload bridge (D-26/D-27) and never touches
 * Electron/IPC objects directly outside this file -- the shared
 * `packages/web-ui` Workspace presentation calls only these named
 * operations.
 */
const mapTask = (task: PreloadTask): WorkspaceTaskView => ({
  completedAt: task.completedAt ?? null,
  id: task.id,
  notes: task.notes ?? '',
  planned: task.planned ?? false,
  syncStatus: task.syncStatus,
  title: task.title,
  trashedAt: task.trashedAt ?? null,
})

const mapConflict = (conflict: PreloadConflict): WorkspaceConflictView => ({
  current: conflict.current,
  field: 'title',
  id: conflict.conflictId,
  mine: conflict.mine,
  taskId: conflict.taskId,
})

const createDesktopClientFacade = (): ClientFacade => {
  let tasks: WorkspaceTaskView[] = []
  let route: WorkspaceRoute = 'inbox'
  let selectedTaskId: string | null = null
  let conflict: WorkspaceConflictView | null = null
  let recovery: RecoveryAvailabilityView = null

  const snapshotListeners = new Set<(snapshot: WorkspaceSnapshotView) => void>()
  const recoveryListeners = new Set<(availability: RecoveryAvailabilityView) => void>()

  const currentSnapshot = (): WorkspaceSnapshotView => ({ conflict, route, selectedTaskId, tasks })

  const publishSnapshot = () => {
    const snapshot = currentSnapshot()
    for (const listener of snapshotListeners) listener(snapshot)
  }

  const refreshConflicts = async () => {
    const conflicts = await window.keepling.listConflicts()
    conflict = conflicts.length > 0 ? mapConflict(conflicts[0]!) : null
  }

  const refresh = async () => {
    const snapshot = await window.keepling.snapshot()
    tasks = snapshot.tasks.map(mapTask)
    await refreshConflicts()
    publishSnapshot()
  }

  void refresh()

  // Plan 03-04: a task captured through Quick Entry (a separate resident
  // utility window/IPC surface) commits through the SAME main-owned
  // `DesktopApplication`, which already publishes a presentation update on
  // every local commit (`publishPresentation({ kind: 'local_saved' })`).
  // Refetching the snapshot on that signal is what makes "Its durable task
  // appears immediately in Keepling" (D-11) true for the main window
  // without a manual reload, and costs nothing extra for ordinary
  // in-window edits (they already call `refresh()` themselves).
  window.keepling.subscribePresentation(() => {
    void refresh()
  })

  /**
   * KNOWN LIMIT, recorded rather than papered over (O-45). The shared
   * `RecoveryAvailabilityView` carries `expiresAt` and `handle`, and NEITHER
   * is rendered -- `SyncRecovery` reads only `label`. The real
   * server-issued handle deliberately does NOT come here: it is an
   * account-bound capability and a renderer must never hold one. So these
   * two fields stay local placeholders; the AUTHORITY on whether an undo
   * can happen is main, which refuses and says why.
   */
  const publishRecovery = (label: string) => {
    recovery = { expiresAt: new Date(Date.now() + 5 * 60_000).toISOString(), handle: 'local-undo', label }
    for (const listener of recoveryListeners) listener(recovery)
  }

  const clearRecovery = () => {
    recovery = null
    for (const listener of recoveryListeners) listener(recovery)
  }

  const runResult = async (
    result: Promise<{ tasks: readonly PreloadTask[] }>,
    recoveryLabel?: string,
  ): Promise<TaskOutcome> => {
    try {
      const snapshot = await result
      tasks = snapshot.tasks.map(mapTask)
      await refreshConflicts()
      publishSnapshot()
      if (recoveryLabel) publishRecovery(recoveryLabel)
      return { kind: 'accepted' }
    } catch (error) {
      return { kind: 'rejected', message: error instanceof Error ? error.message : 'Nothing was changed.' }
    }
  }

  return {
    // O-11 gap closure (D-06): a real (not stubbed) main-owned round trip
    // through the named preload contract added by this plan -- the exact
    // "extend ClientFacade with named semantic restoration operations and
    // persist the snapshot through the existing main-owned window-state
    // port" the plan action calls for (a small self-contained sibling port
    // in `main/index.ts`, since `lifecycle.ts` is outside this plan's
    // authorized file scope; see 03-13-SUMMARY.md).
    persistWorkspaceLayout: (state: WorkspaceLayoutState) => {
      window.keepling.persistWorkspaceLayout(state)
    },
    restoreWorkspaceLayout: () => window.keepling.restoreWorkspaceLayout(),
    captureTask: async (input: CaptureInput): Promise<CaptureOutcome> => {
      try {
        const acceptance = await window.keepling.capture({ title: input.title })
        tasks = acceptance.snapshot.tasks.map(mapTask)
        let task = tasks.find((candidate) => candidate.title === input.title.trim()) ?? tasks[0]!
        if (input.addToToday && task) {
          const outcome = await runResult(window.keepling.moveToday({ planned: true, taskId: task.id }))
          if (outcome.kind === 'accepted') task = tasks.find((candidate) => candidate.id === task.id) ?? task
        } else {
          publishSnapshot()
        }
        return { kind: 'accepted', task }
      } catch (error) {
        return {
          kind: 'rejected',
          message: error instanceof Error ? error.message : 'Couldn’t add this task. Nothing was changed.',
        }
      }
    },
    completeTask: (taskId: string) =>
      runResult(window.keepling.lifecycleTask({ kind: 'complete', taskId }), 'Undo Complete'),
    editTask: (taskId: string, input: EditInput) =>
      runResult(window.keepling.editTask({ ...input, taskId }), 'Undo Edit'),
    getRecoveryAvailability: () => recovery,
    getSnapshot: currentSnapshot,
    moveToday: (taskId: string, planned: boolean) =>
      runResult(window.keepling.moveToday({ planned, taskId }), planned ? 'Undo Add to Today' : 'Undo Remove from Today'),
    reopenTask: (taskId: string) =>
      runResult(window.keepling.lifecycleTask({ kind: 'reopen', taskId }), 'Undo Reopen'),
    resolveConflict: async (choice: 'current' | 'mine') => {
      if (conflict === null) return { kind: 'rejected', message: 'No conflict to resolve.' }
      return runResult(window.keepling.resolveConflict({ choice, conflictId: conflict.id }))
    },
    restoreTask: (taskId: string) =>
      runResult(window.keepling.lifecycleTask({ kind: 'restore', taskId }), 'Undo Restore'),
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
    trashTask: (taskId: string) => runResult(window.keepling.lifecycleTask({ kind: 'trash', taskId })),
    /**
     * O-45. An undo now either reaches the server or is REFUSED, and the
     * refusal says which. The copy is the same wording main publishes on
     * the status row, because a person may see either surface and being
     * told two different things about one refusal is worse than being told
     * nothing. `SyncRecovery` renders this in its `role="status"` region.
     */
    undoLastChange: async () => {
      const result = await window.keepling.undoLastAction()
      if (!result.applied) {
        if (result.reason === 'unsent') {
          return {
            kind: 'rejected',
            message: 'This change hasn’t reached the server yet, so it can’t be undone. Nothing was changed.',
          }
        }
        if (result.reason === 'expired') {
          return { kind: 'rejected', message: 'This change can no longer be undone. Nothing was changed.' }
        }
        return { kind: 'rejected', message: 'Nothing to undo.' }
      }
      tasks = result.snapshot.tasks.map(mapTask)
      await refreshConflicts()
      clearRecovery()
      publishSnapshot()
      return { kind: 'accepted' }
    },
  }
}

export { createDesktopClientFacade }
