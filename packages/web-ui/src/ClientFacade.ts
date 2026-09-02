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
type WorkspaceRoute = 'inbox' | 'today' | 'trash'

type WorkspaceTaskView = {
  readonly completedAt: string | null
  readonly id: string
  readonly notes: string
  readonly planned: boolean
  readonly syncStatus: WorkspaceSyncStatus
  readonly title: string
  readonly trashedAt: string | null
}

/** A single conflicting field: what this Mac holds versus what the server holds. */
type WorkspaceConflictView = {
  readonly current: string
  readonly field: 'title'
  readonly id: string
  readonly mine: string
  readonly taskId: string
}

type WorkspaceSnapshotView = {
  readonly conflict: WorkspaceConflictView | null
  readonly route: WorkspaceRoute
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

type EditInput = {
  readonly notes: string
  readonly title: string
}

/** Outcome of a named lifecycle/edit/undo/resolution operation. */
type TaskOutcome =
  | { readonly kind: 'accepted' }
  | { readonly kind: 'rejected'; readonly message: string }

type RecoveryAvailabilityView = {
  readonly expiresAt: string
  readonly handle: string
  readonly label: string
} | null

/**
 * The platform-free semantic presentation contract (D-26/D-27).
 *
 * `getSnapshot`/`subscribe` expose the workspace task list, route, and
 * conflict presence; `captureTask`, `editTask`, `completeTask`, `reopenTask`,
 * `trashTask`, `restoreTask`, `moveToday`, `undoLastChange`, and
 * `resolveConflict` are the named task/lifecycle operations; `selectTask` and
 * `setRoute` are the named navigation operations; `getRecoveryAvailability`/
 * `subscribeRecovery` is the named recovery operation. Every method name
 * describes what the user is doing, never a transport or storage detail.
 */
interface ClientFacade {
  /** Named task operation: commits a new task through this platform's durable path. */
  captureTask(input: CaptureInput): Promise<CaptureOutcome>
  /** Named lifecycle operation: marks a task complete through the durable path. */
  completeTask(taskId: string): Promise<TaskOutcome>
  /** Named task operation: commits edited title/notes through the durable path. */
  editTask(taskId: string, input: EditInput): Promise<TaskOutcome>
  /** Current recovery/undo availability, or null when nothing is recoverable. */
  getRecoveryAvailability(): RecoveryAvailabilityView
  /** Current workspace snapshot without waiting for a subscription tick. */
  getSnapshot(): WorkspaceSnapshotView
  /** Named navigation operation: places or removes a task from Today. */
  moveToday(taskId: string, planned: boolean): Promise<TaskOutcome>
  /** Named lifecycle operation: reopens a completed task through the durable path. */
  reopenTask(taskId: string): Promise<TaskOutcome>
  /** Named conflict operation: commits the chosen field value (mine or current). */
  resolveConflict(choice: 'current' | 'mine'): Promise<TaskOutcome>
  /** Named lifecycle operation: restores a trashed task through the durable path. */
  restoreTask(taskId: string): Promise<TaskOutcome>
  /** Named navigation operation: moves stable selection by task identity, not DOM position (D-05). */
  selectTask(taskId: string | null): void
  /** Named navigation operation: switches the active workspace destination (Inbox/Today/Trash). */
  setRoute(route: WorkspaceRoute): void
  /** Subscribes to workspace snapshot changes; returns an unsubscribe function. */
  subscribe(listener: (snapshot: WorkspaceSnapshotView) => void): () => void
  /** Subscribes to recovery/undo availability changes; returns an unsubscribe function. */
  subscribeRecovery(listener: (availability: RecoveryAvailabilityView) => void): () => void
  /** Named lifecycle operation: moves a task to Trash through the durable path. */
  trashTask(taskId: string): Promise<TaskOutcome>
  /** Named recovery operation: reverses the latest supported local change. */
  undoLastChange(): Promise<TaskOutcome>
}

export type {
  CaptureInput,
  CaptureOutcome,
  ClientFacade,
  EditInput,
  RecoveryAvailabilityView,
  TaskOutcome,
  WorkspaceConflictView,
  WorkspaceRoute,
  WorkspaceSnapshotView,
  WorkspaceSyncStatus,
  WorkspaceTaskView,
}
