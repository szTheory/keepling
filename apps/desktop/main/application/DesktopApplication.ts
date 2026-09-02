import { createHash } from 'node:crypto'

type SyncStatus = 'saved_on_this_mac' | 'synced'
type SyncOutcome = 'accepted' | 'already_satisfied' | 'rejected' | 'stale' | 'conflict'

type WorkspaceTask = {
  id: string
  syncStatus: SyncStatus
  title: string
}

type WorkspaceSnapshot = {
  tasks: WorkspaceTask[]
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

type PullPage = { changes: Array<{ entityId: string; snapshot: SyncSnapshot }>; cursor: string }

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
  readonly #identity: IdentityPort
  readonly #localStore: LocalStorePort
  readonly #sync: SyncPort

  constructor(options: DesktopApplicationOptions) {
    this.#clock = options.clock
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
    return this.#localStore.acceptCapture(mutation)
  }

  async snapshot(): Promise<WorkspaceSnapshot> {
    return this.#localStore.snapshot()
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
  CredentialPort,
  DesktopApplicationOptions,
  LocalAcceptance,
  LocalStorePort,
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
