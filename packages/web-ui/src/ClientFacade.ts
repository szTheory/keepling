/**
 * ClientFacade is the ONLY seam shared presentation may call through (D-26/D-27,
 * docs/architecture/REPOSITORY.md "Shared React UI -> narrow ClientFacade").
 *
 * A platform adapter (browser or Electron renderer) implements this interface by
 * wrapping its own transport, session, IPC, or persistence concerns. Shared
 * presentation never imports fetch, cookies, history, IPC, Electron objects,
 * SQLite records, or credentials directly -- it only calls named semantic
 * operations exposed here.
 *
 * These are renderer view models (D-30): distinct from generated wire DTOs,
 * browser session models, and desktop SQLite records. Each adapter maps its own
 * platform truth into these closed shapes.
 */

type WorkspaceSyncStatus = 'draft' | 'saved_on_this_mac' | 'synced'

type WorkspaceTaskView = {
  readonly id: string
  readonly notes: string
  readonly syncStatus: WorkspaceSyncStatus
  readonly title: string
}

type WorkspaceSnapshotView = {
  readonly selectedTaskId: string | null
  readonly tasks: readonly WorkspaceTaskView[]
}

type CaptureInput = {
  readonly addToToday: boolean
  readonly title: string
}

type CaptureOutcome =
  | { readonly kind: 'accepted'; readonly task: WorkspaceTaskView }
  | { readonly kind: 'rejected'; readonly message: string }

type RecoveryAvailabilityView = {
  readonly expiresAt: string
  readonly handle: string
  readonly label: string
} | null

/**
 * The platform-free semantic presentation contract (D-26/D-27).
 *
 * `getSnapshot`/`subscribe` expose the workspace task list; `captureTask` and
 * `selectTask` are the named task/navigation operations this extraction proves;
 * `getRecoveryAvailability`/`subscribeRecovery` are the named recovery
 * operation. Every method name describes what the user is doing, never a
 * transport or storage detail.
 */
interface ClientFacade {
  /** Named task operation: commits a new task through this platform's durable path. */
  captureTask(input: CaptureInput): Promise<CaptureOutcome>
  /** Current recovery/undo availability, or null when nothing is recoverable. */
  getRecoveryAvailability(): RecoveryAvailabilityView
  /** Current workspace snapshot without waiting for a subscription tick. */
  getSnapshot(): WorkspaceSnapshotView
  /** Named navigation operation: moves stable selection by task identity, not DOM position (D-05). */
  selectTask(taskId: string | null): void
  /** Subscribes to workspace snapshot changes; returns an unsubscribe function. */
  subscribe(listener: (snapshot: WorkspaceSnapshotView) => void): () => void
  /** Subscribes to recovery/undo availability changes; returns an unsubscribe function. */
  subscribeRecovery(listener: (availability: RecoveryAvailabilityView) => void): () => void
}

export type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  RecoveryAvailabilityView,
  WorkspaceSnapshotView,
  WorkspaceSyncStatus,
  WorkspaceTaskView,
}
