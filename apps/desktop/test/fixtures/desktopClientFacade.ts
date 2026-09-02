import type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  RecoveryAvailabilityView,
  WorkspaceSnapshotView,
  WorkspaceTaskView,
} from '../../../../packages/web-ui/src/ClientFacade.ts'

/**
 * Deterministic desktop-facade fixture (D-26/D-27). It proves the shared
 * `packages/web-ui` Workspace/CaptureForm/TaskList presentation renders
 * identically against a facade that never imports fetch, browser session
 * state, or platform APIs -- only named semantic operations, matching what
 * the real Electron renderer's preload-backed adapter will expose.
 *
 * This fixture is test-only: it is deterministic (no timers, no randomness
 * beyond an injectable ID generator) and lives outside `packages/web-ui` so
 * production shared presentation never imports it.
 */
type DesktopClientFacadeOptions = {
  nextId?: () => string
  seedTasks?: readonly WorkspaceTaskView[]
}

const createDesktopClientFacade = (options: DesktopClientFacadeOptions = {}): ClientFacade => {
  let tasks: WorkspaceTaskView[] = [...(options.seedTasks ?? [])]
  let selectedTaskId: string | null = null
  let recovery: RecoveryAvailabilityView = null
  let sequence = 0
  const nextId = options.nextId ?? (() => `desktop-fixture-task-${++sequence}`)

  const snapshotListeners = new Set<(snapshot: WorkspaceSnapshotView) => void>()
  const recoveryListeners = new Set<(availability: RecoveryAvailabilityView) => void>()

  const currentSnapshot = (): WorkspaceSnapshotView => ({ selectedTaskId, tasks })

  const publishSnapshot = () => {
    const snapshot = currentSnapshot()
    for (const listener of snapshotListeners) listener(snapshot)
  }

  return {
    captureTask: (input: CaptureInput): Promise<CaptureOutcome> => {
      const title = input.title.trim()
      if (title.length === 0) {
        return Promise.resolve({ kind: 'rejected', message: 'task title must not be empty' })
      }

      // Mirrors the real desktop trust boundary (D-03): local acceptance is
      // durable before it is reported synced.
      const task: WorkspaceTaskView = { id: nextId(), notes: '', syncStatus: 'saved_on_this_mac', title }
      tasks = [task, ...tasks]
      publishSnapshot()
      return Promise.resolve({ kind: 'accepted', task })
    },
    getRecoveryAvailability: () => recovery,
    getSnapshot: currentSnapshot,
    selectTask: (taskId: string | null) => {
      selectedTaskId = taskId
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
  }
}

export { createDesktopClientFacade }
