import {
  KeeplingApiError,
  getInbox,
  prepareCaptureTask,
  submitPreparedTaskCommand,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type UndoAvailability,
} from '@/api/keepling'
import type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  RecoveryAvailabilityView,
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
 */

const mapTask = (task: BrowserTask): WorkspaceTaskView => ({
  id: task.id,
  notes: task.notes,
  syncStatus: 'synced',
  title: task.title,
})

const createBrowserClientFacade = (csrfToken: string): ClientFacade => {
  let tasks: WorkspaceTaskView[] = []
  let selectedTaskId: string | null = null
  let recovery: RecoveryAvailabilityView = null
  let initialized = false

  const snapshotListeners = new Set<(snapshot: WorkspaceSnapshotView) => void>()
  const recoveryListeners = new Set<(availability: RecoveryAvailabilityView) => void>()

  const currentSnapshot = (): WorkspaceSnapshotView => ({ selectedTaskId, tasks })

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
      tasks = inboxTasks.map(mapTask)
      publishSnapshot()
    })
  }

  const upsertFromAcknowledgement = (acknowledgement: CaptureAcknowledgement) => {
    const withoutCurrent = tasks.filter((task) => task.id !== acknowledgement.taskId)
    tasks =
      acknowledgement.snapshot.inboxState === 'inbox'
        ? [mapTask(acknowledgement.snapshot), ...withoutCurrent]
        : withoutCurrent
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
    getRecoveryAvailability: () => recovery,
    getSnapshot: () => {
      ensureInitialized()
      return currentSnapshot()
    },
    selectTask: (taskId: string | null) => {
      selectedTaskId = taskId
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
  }
}

export { createBrowserClientFacade }
