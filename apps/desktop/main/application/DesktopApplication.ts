import { createHash } from 'node:crypto'

import {
  deriveDesktopPresentation,
  type DesktopPresentation,
  type DesktopPresentationInput,
} from './presentation.ts'

type SyncStatus = 'saved_on_this_mac' | 'synced'
type SyncOutcome = 'accepted' | 'already_satisfied' | 'rejected' | 'stale' | 'conflict'

type WorkspaceTask = {
  id: string
  syncStatus: SyncStatus
  title: string
  completedAt?: string | null
  notes?: string
  planned?: boolean
  trashedAt?: string | null
}

type WorkspaceSnapshot = {
  tasks: WorkspaceTask[]
}

type EditTaskCommand = {
  notes: string
  taskId: string
  title: string
}

type LifecycleKind = 'complete' | 'reopen' | 'restore' | 'trash'

type LifecycleCommand = {
  kind: LifecycleKind
  taskId: string
}

type MoveTodayCommand = {
  planned: boolean
  taskId: string
}

type ConflictRecord = {
  conflictId: string
  current: string
  mine: string
  taskId: string
}

type CaptureCommand = {
  title: string
}

type PendingMutation = {
  acceptedAt: string
  commandBytes: string
  fingerprint: string
  mutationId: string
  taskId: string
  title: string
}

type SyncSnapshot = { id: string; revision?: number; title?: string; [key: string]: unknown }

type SyncMutation = {
  acceptedAt: string
  commandBytes: string
  dependencies: string[]
  effect: { entityId: string; snapshot: SyncSnapshot }
  fingerprint: string
  mutationId: string
  resourceKeys: string[]
}

type PullPage = { changes: Array<{ entityId: string; snapshot: SyncSnapshot }>; cursor: string | null }

type SyncState = { cursor: string | null; outbox: string[]; readyPushes: string[] }
type SyncNamespace = {
  accountSubject: string
  generation: string
  issuer: string
  origin: string
  serverInstance: string
}

type LocalAcceptance = {
  fingerprint: string
  mutationId: string
  snapshot: WorkspaceSnapshot
  status: 'local_saved'
}

type SyncAcknowledgement = {
  fingerprint: string
  mutationId: string
  outcome: SyncOutcome
  snapshot: SyncSnapshot
}

interface LocalStorePort {
  acceptCapture(mutation: PendingMutation): Promise<LocalAcceptance>
  acceptMutation?(mutation: SyncMutation): Promise<unknown> | unknown
  bindNamespace?(namespace: SyncNamespace): Promise<boolean> | boolean
  acknowledge(acknowledgement: SyncAcknowledgement): Promise<WorkspaceSnapshot>
  acknowledgeSync?(acknowledgement: SyncAcknowledgement): Promise<void> | void
  applyPull?(page: PullPage): Promise<void> | void
  /** Local-only durable task edit (D-03: commit-first, never claims "Synced"). */
  editTask?(command: EditTaskCommand): Promise<WorkspaceSnapshot> | WorkspaceSnapshot
  /** Local-only durable lifecycle transition (complete/reopen/trash/restore). */
  applyLifecycle?(command: LifecycleCommand): Promise<WorkspaceSnapshot> | WorkspaceSnapshot
  /** Local-only durable Today placement. */
  applyMoveToday?(command: MoveTodayCommand): Promise<WorkspaceSnapshot> | WorkspaceSnapshot
  /** Reverses the latest recorded local edit/lifecycle action, if any. */
  undoLastLocalAction?(): Promise<{ applied: boolean; snapshot: WorkspaceSnapshot }> | { applied: boolean; snapshot: WorkspaceSnapshot }
  /** Lists open sync conflicts awaiting a mine/current choice. */
  listConflicts?(): Promise<ConflictRecord[]> | ConflictRecord[]
  /** Commits the chosen field value for a sync conflict and clears it. */
  resolveConflict?(input: { choice: 'current' | 'mine'; conflictId: string }): Promise<WorkspaceSnapshot> | WorkspaceSnapshot
  pendingMutations(): Promise<PendingMutation[]>
  readyMutations?(): Promise<SyncMutation[]> | SyncMutation[]
  setSyncFence?(reason: string | null): Promise<void> | void
  snapshot(): Promise<WorkspaceSnapshot>
  syncState?(): Promise<SyncState> | SyncState
  close(): Promise<void>
}

interface SyncPort {
  acknowledge?(mutation: PendingMutation): Promise<SyncAcknowledgement | null>
  pull?(cursor: string | null, limit: 50): Promise<PullPage>
  push?(commandBytes: string): Promise<SyncAcknowledgement | null>
}

interface CredentialPort {
  load(): Promise<string | null>
  store(value: string): Promise<void>
  clear(): Promise<void>
}

interface ClockPort {
  now(): string
}

interface IdentityPort {
  randomId(): string
}

type DesktopApplicationOptions = {
  clock: ClockPort
  credentials?: CredentialPort
  identity: IdentityPort
  localStore: LocalStorePort
  sync: SyncPort
}

const SYNC_LIMITS = { maximumBackoffMs: 60_000, pull: 50, push: 25 } as const

const computeSyncBackoff = (attempt: number, jitter: () => number): number => {
  const boundedAttempt = Math.max(0, Math.min(attempt, 10))
  const base = Math.min(1_000 * (2 ** boundedAttempt), SYNC_LIMITS.maximumBackoffMs)
  const boundedJitter = Math.max(0, Math.min(jitter(), 1))
  return Math.min(Math.round(base * (0.75 + boundedJitter * 0.5)), SYNC_LIMITS.maximumBackoffMs)
}

class DesktopApplication {
  readonly #clock: ClockPort
  readonly #credentials: CredentialPort | undefined
  readonly #identity: IdentityPort
  readonly #localStore: LocalStorePort
  readonly #sync: SyncPort
  readonly #presentationSubscribers = new Set<(presentation: DesktopPresentation) => void>()
  #currentPresentation = deriveDesktopPresentation({ kind: 'opening' }, 0)
  #presentationSequence = 0

  constructor(options: DesktopApplicationOptions) {
    this.#clock = options.clock
    this.#credentials = options.credentials
    this.#identity = options.identity
    this.#localStore = options.localStore
    this.#sync = options.sync
  }

  async capture(command: CaptureCommand): Promise<LocalAcceptance> {
    const title = command.title.trim()
    if (title.length === 0 || [...title].length > 512) {
      throw new Error('task title must contain between 1 and 512 Unicode scalar values')
    }

    const mutationId = this.#identity.randomId()
    const taskId = this.#identity.randomId()
    const commandBytes = JSON.stringify({
      mutation_id: mutationId,
      task_id: taskId,
      title,
      type: 'capture_task',
    })
    const mutation: PendingMutation = {
      acceptedAt: this.#clock.now(),
      commandBytes,
      fingerprint: createHash('sha256').update(commandBytes).digest('hex'),
      mutationId,
      taskId,
      title,
    }

    // This await is the D-03 boundary. The store may only resolve after COMMIT.
    try {
      const acceptance = await this.#localStore.acceptCapture(mutation)
      this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
      return acceptance
    } catch (error) {
      this.publishPresentation({ kind: 'local_save_failure' })
      throw error
    }
  }

  async snapshot(): Promise<WorkspaceSnapshot> {
    return this.#localStore.snapshot()
  }

  async editTask(command: EditTaskCommand): Promise<WorkspaceSnapshot> {
    const title = command.title.trim()
    if (title.length === 0 || [...title].length > 512) {
      throw new Error('task title must contain between 1 and 512 Unicode scalar values')
    }
    if (!this.#localStore.editTask) throw new Error('task editing is unavailable')
    // D-03 boundary: durable commit before "Saved on this Mac" is reported.
    const snapshot = await this.#localStore.editTask({ ...command, title })
    this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
    return snapshot
  }

  async applyLifecycle(command: LifecycleCommand): Promise<WorkspaceSnapshot> {
    if (!this.#localStore.applyLifecycle) throw new Error('task lifecycle actions are unavailable')
    const snapshot = await this.#localStore.applyLifecycle(command)
    this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
    return snapshot
  }

  async moveToday(command: MoveTodayCommand): Promise<WorkspaceSnapshot> {
    if (!this.#localStore.applyMoveToday) throw new Error('Today placement is unavailable')
    const snapshot = await this.#localStore.applyMoveToday(command)
    this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
    return snapshot
  }

  async undoLastLocalAction(): Promise<{ applied: boolean; snapshot: WorkspaceSnapshot }> {
    if (!this.#localStore.undoLastLocalAction) throw new Error('undo is unavailable')
    const result = await this.#localStore.undoLastLocalAction()
    if (result.applied) this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
    return result
  }

  async listConflicts(): Promise<ConflictRecord[]> {
    if (!this.#localStore.listConflicts) return []
    return this.#localStore.listConflicts()
  }

  async resolveConflict(input: { choice: 'current' | 'mine'; conflictId: string }): Promise<WorkspaceSnapshot> {
    if (!this.#localStore.resolveConflict) throw new Error('conflict resolution is unavailable')
    const snapshot = await this.#localStore.resolveConflict(input)
    this.publishPresentation({ kind: 'local_saved', pendingCount: 1 })
    return snapshot
  }

  async activateNamespace(namespace: SyncNamespace): Promise<boolean> {
    if (!this.#localStore.bindNamespace) throw new Error('namespace binding is unavailable')
    const bound = await this.#localStore.bindNamespace(namespace)
    if (!bound) this.publishPresentation({ kind: 'namespace_mismatch' })
    return bound
  }

  async signOut(revoke: () => Promise<void>): Promise<void> {
    await this.#localStore.setSyncFence?.('signed_out')
    await this.#credentials?.clear()
    try {
      await revoke()
    } catch {
      // Revocation is best-effort after the local namespace is already fenced.
    }
  }

  presentationSnapshot(): DesktopPresentation {
    return this.#currentPresentation
  }

  publishPresentation(input: DesktopPresentationInput): DesktopPresentation {
    this.#currentPresentation = deriveDesktopPresentation(input, ++this.#presentationSequence)
    for (const subscriber of this.#presentationSubscribers) subscriber(this.#currentPresentation)
    return this.#currentPresentation
  }

  subscribePresentation(subscriber: (presentation: DesktopPresentation) => void): () => void {
    this.#presentationSubscribers.add(subscriber)
    return () => this.#presentationSubscribers.delete(subscriber)
  }

  async reconcile(): Promise<{ settled: number }> {
    let settled = 0
    for (const mutation of await this.#localStore.pendingMutations()) {
      const acknowledgement = await this.#sync.acknowledge?.(mutation) ?? null
      if (
        acknowledgement === null ||
        acknowledgement.mutationId !== mutation.mutationId ||
        acknowledgement.fingerprint !== mutation.fingerprint
      ) {
        continue
      }
      await this.#localStore.acknowledge(acknowledgement)
      settled += 1
    }
    return { settled }
  }


  async runSyncPass(): Promise<{ pulled: number; settled: number }> {
    if (!this.#sync.pull || !this.#sync.push || !this.#localStore.applyPull || !this.#localStore.readyMutations) {
      const result = await this.reconcile()
      return { pulled: 0, settled: result.settled }
    }

    const state = await this.#localStore.syncState?.()
    const page = await this.#sync.pull(state?.cursor ?? null, SYNC_LIMITS.pull)
    if (page.changes.length > SYNC_LIMITS.pull) throw new Error('sync pull exceeded bounded page size')
    await this.#localStore.applyPull(page)

    const ready = (await this.#localStore.readyMutations()).slice(0, SYNC_LIMITS.push)
    let settled = 0
    for (const mutation of ready) {
      const acknowledgement = await this.#sync.push(mutation.commandBytes)
      if (
        acknowledgement === null ||
        acknowledgement.mutationId !== mutation.mutationId ||
        acknowledgement.fingerprint !== mutation.fingerprint
      ) continue
      await (this.#localStore.acknowledgeSync?.(acknowledgement)
        ?? this.#localStore.acknowledge(acknowledgement))
      settled += 1
    }
    return { pulled: page.changes.length, settled }
  }

  async close(): Promise<void> {
    await this.#localStore.close()
  }
}

export { DesktopApplication, SYNC_LIMITS, computeSyncBackoff }
export type {
  CaptureCommand,
  ConflictRecord,
  CredentialPort,
  DesktopApplicationOptions,
  EditTaskCommand,
  LifecycleCommand,
  LifecycleKind,
  LocalAcceptance,
  LocalStorePort,
  MoveTodayCommand,
  PendingMutation,
  PullPage,
  SyncMutation,
  SyncNamespace,
  SyncAcknowledgement,
  SyncOutcome,
  SyncPort,
  SyncSnapshot,
  SyncState,
  WorkspaceSnapshot,
  WorkspaceTask,
}
