import { createHash } from 'node:crypto'

type SyncStatus = 'saved_on_this_mac' | 'synced'

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

type LocalAcceptance = {
  fingerprint: string
  mutationId: string
  snapshot: WorkspaceSnapshot
  status: 'local_saved'
}

type SyncAcknowledgement = {
  fingerprint: string
  mutationId: string
  outcome: 'accepted' | 'already_satisfied'
  snapshot: { id: string; title: string }
}

interface LocalStorePort {
  acceptCapture(mutation: PendingMutation): Promise<LocalAcceptance>
  acknowledge(acknowledgement: SyncAcknowledgement): Promise<WorkspaceSnapshot>
  pendingMutations(): Promise<PendingMutation[]>
  snapshot(): Promise<WorkspaceSnapshot>
  close(): Promise<void>
}

interface SyncPort {
  acknowledge(mutation: PendingMutation): Promise<SyncAcknowledgement | null>
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
      const acknowledgement = await this.#sync.acknowledge(mutation)
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

  async close(): Promise<void> {
    await this.#localStore.close()
  }
}

export { DesktopApplication }
export type {
  CaptureCommand,
  CredentialPort,
  DesktopApplicationOptions,
  LocalAcceptance,
  LocalStorePort,
  PendingMutation,
  SyncAcknowledgement,
  SyncPort,
  WorkspaceSnapshot,
  WorkspaceTask,
}
