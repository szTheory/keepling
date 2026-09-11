import {
  KeeplingApiError,
  completeTask as apiCompleteTask,
  editTask as apiEditTask,
  getInbox,
  planForToday,
  prepareCaptureTask,
  reopenTask as apiReopenTask,
  resolveTaskConflict,
  restoreTask as apiRestoreTask,
  submitPreparedTaskCommand,
  trashTask as apiTrashTask,
  undoTask,
  unplanTask,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type CommandAcknowledgement,
  type TaskConflict,
  type UndoAvailability,
} from '@/api/keepling'
import type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  EditInput,
  RecoveryAvailabilityView,
  TaskOutcome,
  WorkspaceConflictView,
  WorkspaceRoute,
  WorkspaceSnapshotView,
  WorkspaceTaskView,
} from '../../../../packages/web-ui/src/ClientFacade'

/**
 * Browser-owned ClientFacade adapter (docs/architecture/REPOSITORY.md
 * "Shared React UI -> narrow ClientFacade, never Electron/browser
 * implementation details"). It wraps the existing `@/api/keepling`
 * transport and the same `keepling:task-acknowledged` /
 * `keepling:undo-available` window events the browser app already uses, so
 * exact-submission and session behavior is unchanged -- only the seam
 * shared presentation calls through is new.
 *
 * The Mac client (Electron) is this plan's (03-03) target platform; the
 * browser adapter is extended here only far enough to keep implementing the
 * shared `ClientFacade` interface truthfully. Today/Trash routes stay backed
 * by the already-loaded Inbox list only (no `getTrash`/today endpoints wired
 * yet), and conflict resolution covers the `title` field the server reports.
 */

const mapTask = (task: BrowserTask): WorkspaceTaskView => ({
  completedAt: task.completedAt,
  id: task.id,
  notes: task.notes,
  planned: task.plannedOn !== null,
  syncStatus: 'synced',
  title: task.title,
  trashedAt: task.trashedAt,
})

const createBrowserClientFacade = (csrfToken: string): ClientFacade => {
  const records = new Map<string, BrowserTask>()
  let route: WorkspaceRoute = 'inbox'
  let selectedTaskId: string | null = null
  let activeConflict: TaskConflict | null = null
  let activeConflictTaskId: string | null = null
  let recovery: RecoveryAvailabilityView = null
  let initialized = false

  const snapshotListeners = new Set<(snapshot: WorkspaceSnapshotView) => void>()
  const recoveryListeners = new Set<(availability: RecoveryAvailabilityView) => void>()

  const conflictView = (): WorkspaceConflictView | null => {
    if (activeConflict === null || activeConflictTaskId === null) return null
    if (activeConflict.fields.length === 0) return null
    return {
      fields: activeConflict.fields.map((field) => ({
        current: field.current,
        field: field.field,
        mine: field.mine,
      })),
      id: activeConflict.id,
      taskId: activeConflictTaskId,
    }
  }

  const currentSnapshot = (): WorkspaceSnapshotView => ({
    conflict: conflictView(),
    route,
    selectedTaskId,
    tasks: [...records.values()].map(mapTask),
    // Browser access is online-first (no local durable refusal ledger) --
    // there is no unattended refusal class for this adapter to surface.
    unresolvedRefusals: [],
  })

  const publishSnapshot = () => {
    const snapshot = currentSnapshot()
    for (const listener of snapshotListeners) listener(snapshot)
  }

  // Load the Inbox only once the workspace slice actually asks for a
  // snapshot. A facade consumer that only wants recovery/undo availability
  // (AppShell today) never triggers this fetch.
  const ensureInitialized = () => {
    if (initialized) return
    initialized = true
    void getInbox().then((inboxTasks) => {
      for (const task of inboxTasks) records.set(task.id, task)
      publishSnapshot()
    })
  }

  const upsertFromAcknowledgement = (acknowledgement: CommandAcknowledgement) => {
    records.set(acknowledgement.taskId, acknowledgement.snapshot)
  }

  const handleTaskAcknowledged = (event: Event) => {
    upsertFromAcknowledgement((event as CustomEvent<CaptureAcknowledgement>).detail)
    publishSnapshot()
  }

  const handleUndoAvailable = (event: Event) => {
    recovery = (event as CustomEvent<UndoAvailability>).detail
    for (const listener of recoveryListeners) listener(recovery)
  }

  window.addEventListener('keepling:task-acknowledged', handleTaskAcknowledged)
  window.addEventListener('keepling:undo-available', handleUndoAvailable)

  const runCommand = async (
    operation: () => Promise<CommandAcknowledgement>,
    taskId: string,
  ): Promise<TaskOutcome> => {
    try {
      const acknowledgement = await operation()
      upsertFromAcknowledgement(acknowledgement)
      activeConflict = null
      activeConflictTaskId = null
      publishSnapshot()
      return { kind: 'accepted' }
    } catch (error) {
      if (error instanceof KeeplingApiError && error.conflict) {
        activeConflict = error.conflict
        activeConflictTaskId = taskId
        publishSnapshot()
      }
      const message =
        error instanceof KeeplingApiError
          ? error.message
          : `Couldn’t update this task (${taskId}). Nothing was changed.`
      return { kind: 'rejected', message }
    }
  }

  return {
    captureTask: async (input: CaptureInput): Promise<CaptureOutcome> => {
      ensureInitialized()
      const submission = {
        mutationId: crypto.randomUUID(),
        taskId: crypto.randomUUID(),
        title: input.title,
      } satisfies CaptureTaskSubmission

      try {
        const acknowledgement = await submitPreparedTaskCommand(
          prepareCaptureTask(submission),
          csrfToken,
        )
        upsertFromAcknowledgement(acknowledgement)
        publishSnapshot()
        window.dispatchEvent(
          new CustomEvent<CaptureAcknowledgement>('keepling:task-acknowledged', {
            detail: acknowledgement,
          }),
        )
        return { kind: 'accepted', task: mapTask(acknowledgement.snapshot) }
      } catch (error) {
        const message =
          error instanceof KeeplingApiError
            ? error.message
            : 'Couldn’t add this task. Nothing was changed.'
        return { kind: 'rejected', message }
      }
    },
    completeTask: (taskId: string) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      return runCommand(
        () =>
          apiCompleteTask(
            { expectedRevision: record.revision, mutationId: crypto.randomUUID(), taskId },
            csrfToken,
          ),
        taskId,
      )
    },
    editTask: (taskId: string, input: EditInput) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      return runCommand(
        () =>
          apiEditTask(
            {
              baseValues: { notes: record.notes, title: record.title },
              expectedRevision: record.revision,
              fields: { notes: input.notes, title: input.title },
              mutationId: crypto.randomUUID(),
              taskId,
            },
            csrfToken,
          ),
        taskId,
      )
    },
    getRecoveryAvailability: () => recovery,
    getSnapshot: () => {
      ensureInitialized()
      return currentSnapshot()
    },
    moveToday: (taskId: string, planned: boolean) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      const submission = {
        basePlannedOn: record.plannedOn,
        expectedRevision: record.revision,
        mutationId: crypto.randomUUID(),
        taskId,
      }
      return runCommand(
        () => (planned ? planForToday(submission, csrfToken) : unplanTask(submission, csrfToken)),
        taskId,
      )
    },
    reopenTask: (taskId: string) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      return runCommand(
        () =>
          apiReopenTask(
            { expectedRevision: record.revision, mutationId: crypto.randomUUID(), taskId },
            csrfToken,
          ),
        taskId,
      )
    },
    resolveConflict: (choices) => {
      const conflict = activeConflict
      const taskId = conflictView()?.taskId
      if (conflict === null || taskId === undefined) {
        return Promise.resolve({ kind: 'rejected', message: 'No conflict to resolve.' })
      }
      return runCommand(
        () =>
          resolveTaskConflict(
            {
              conflictId: conflict.id,
              latestRevision: conflict.latestRevision,
              mutationId: crypto.randomUUID(),
              selections: choices,
              taskId,
            },
            csrfToken,
          ),
        taskId,
      )
    },
    restoreTask: (taskId: string) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      return runCommand(
        () =>
          apiRestoreTask(
            { expectedRevision: record.revision, mutationId: crypto.randomUUID(), taskId },
            csrfToken,
          ),
        taskId,
      )
    },
    selectTask: (taskId: string | null) => {
      selectedTaskId = taskId
      publishSnapshot()
    },
    setRoute: (nextRoute: WorkspaceRoute) => {
      route = nextRoute
      publishSnapshot()
    },
    subscribe: (listener) => {
      ensureInitialized()
      snapshotListeners.add(listener)
      return () => snapshotListeners.delete(listener)
    },
    subscribeRecovery: (listener) => {
      recoveryListeners.add(listener)
      return () => recoveryListeners.delete(listener)
    },
    trashTask: (taskId: string) => {
      const record = records.get(taskId)
      if (!record) return Promise.resolve({ kind: 'rejected', message: 'Task not found.' })
      return runCommand(
        () =>
          apiTrashTask(
            { expectedRevision: record.revision, mutationId: crypto.randomUUID(), taskId },
            csrfToken,
          ),
        taskId,
      )
    },
    undoLastChange: async () => {
      if (recovery === null) return { kind: 'rejected', message: 'Nothing to undo.' }
      const result = await undoTask({ availability: recovery, mutationId: crypto.randomUUID() }, csrfToken)
      if (result.kind === 'acknowledged') {
        upsertFromAcknowledgement(result.acknowledgement)
        recovery = null
        for (const listener of recoveryListeners) listener(recovery)
        publishSnapshot()
        return { kind: 'accepted' }
      }
      return { kind: 'rejected', message: result.result.title }
    },
  }
}

export { createBrowserClientFacade }
