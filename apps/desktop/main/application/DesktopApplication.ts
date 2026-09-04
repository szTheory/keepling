import { createHash } from 'node:crypto'

import {
  GRACE_PERIOD_MS,
  deriveDesktopPresentation,
  type DesktopPresentation,
  type DesktopPresentationInput,
} from './presentation.ts'
import { removeLocalNamespaceData, type RemoveLocalDataOutcome } from '../recovery/remove-local-data.ts'
import { isSyncUnreachable } from './sync-reachability.ts'

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

/**
 * Quick Entry draft (D-03/D-11): explicitly NOT a task change and never
 * claims "Saved on this Mac". Persisted separately from task mutations so it
 * survives Escape/Command-W hide and utility-window recreation; only an
 * explicit discard clears it.
 */
type QuickEntryDraft = {
  addToToday: boolean
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

type SyncState = {
  cursor: string | null
  /**
   * The instant the server last actually answered this Mac, or null/absent
   * when it never has. Persisted by the local store so a relaunch can still
   * read it -- the `offline` row is only honest if this has a real source
   * (O-30).
   */
  lastSuccessfulContact?: string | null
  outbox: string[]
  readyPushes: string[]
}
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
  /** D-24 whole-unit removal of this namespace's closed local file inventory. MUST run only after `close()`. */
  removeLocalFiles?(): Promise<{ remaining: string[]; removed: string[] }> | { remaining: string[]; removed: string[] }
  /** Persists the Quick Entry draft (D-11); not a task change, no outbox row. */
  saveDraft?(draft: QuickEntryDraft): Promise<void> | void
  /** Reads back the persisted Quick Entry draft, or null when there is none. */
  getDraft?(): Promise<QuickEntryDraft | null> | QuickEntryDraft | null
  /** Removes the persisted Quick Entry draft (only on explicit Discard Draft). */
  clearDraft?(): Promise<void> | void
  /** Reads the persisted configurable Quick Entry global-shortcut accelerator. */
  getShortcutPreference?(): Promise<string | null> | string | null
  /** Persists a newly chosen Quick Entry global-shortcut accelerator. */
  setShortcutPreference?(accelerator: string): Promise<void> | void
  pendingMutations(): Promise<PendingMutation[]>
  readyMutations?(): Promise<SyncMutation[]> | SyncMutation[]
  /**
   * Durably records that the server answered at this instant (O-30). Read
   * back through `syncState().lastSuccessfulContact`. Best-effort: this is a
   * presentation source, never a correctness step, so a failure to record it
   * must not fail a synchronization pass.
   */
  recordSuccessfulContact?(at: string): Promise<void> | void
  setSyncFence?(reason: string | null): Promise<void> | void
  snapshot(): Promise<WorkspaceSnapshot>
  syncState?(): Promise<SyncState> | SyncState
  close(): Promise<void>
}

interface SyncPort {
  acknowledge?(mutation: PendingMutation): Promise<SyncAcknowledgement | null>
  /**
   * Whether a server is configured at all (O-30). `false` means there is
   * nothing to be offline FROM: the app is working exactly as intended and
   * its data is safe locally, but it is not synchronized and must never
   * publish a row implying that it is. Absent means "unknown", which is
   * treated as configured -- a port that cannot answer this question is
   * never assumed to be serverless.
   */
  configured?(): boolean
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
    // The durable, retried-verbatim intent (D-03). Its shape is the
    // contract's `CaptureTaskCommand` -- mutation_id, task_id, title,
    // version -- plus the optional `type` discriminator, and it is fixed
    // here because these exact bytes are what a real server receives.
    //
    // `version` was missing until O-34 pointed this client at real Phoenix
    // for the first time and the server refused the body 400
    // invalid_command. `type` stays IN the bytes because an outbox that
    // survives a relaunch has nothing else to route by, and re-serializing
    // on retry is forbidden; the server verifies it against the endpoint
    // and never routes on it (KeeplingWeb.CommandDiscriminator).
    const commandBytes = JSON.stringify({
      mutation_id: mutationId,
      task_id: taskId,
      title,
      type: 'capture_task',
      version: 1,
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
    // D-22: a broken local store must NEVER present a false empty workspace.
    // Publish the closed `store_unavailable` recovery state and reject --
    // never resolve with `{ tasks: [] }` on failure.
    try {
      const snapshot = await this.#localStore.snapshot()
      return snapshot
    } catch (error) {
      this.publishPresentation({ kind: 'store_unavailable' })
      throw error
    }
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

  /**
   * Quick Entry draft persistence (D-03/D-11). This is deliberately NOT a
   * task mutation: no immutable command, no outbox row, no presentation
   * publish -- a draft never claims durability beyond "kept while Keepling
   * is running", which the main-owned store honors across window hide and
   * recreation.
   */
  async saveDraft(draft: QuickEntryDraft): Promise<void> {
    if (!this.#localStore.saveDraft) throw new Error('Quick Entry draft storage is unavailable')
    const title = draft.title
    if ([...title].length > 512) throw new Error('draft title must not exceed 512 Unicode scalar values')
    await this.#localStore.saveDraft({ addToToday: draft.addToToday, title })
  }

  async getDraft(): Promise<QuickEntryDraft | null> {
    if (!this.#localStore.getDraft) return null
    return this.#localStore.getDraft()
  }

  async clearDraft(): Promise<void> {
    if (!this.#localStore.clearDraft) throw new Error('Quick Entry draft storage is unavailable')
    await this.#localStore.clearDraft()
  }

  async getShortcutPreference(): Promise<string | null> {
    if (!this.#localStore.getShortcutPreference) return null
    return this.#localStore.getShortcutPreference()
  }

  async setShortcutPreference(accelerator: string): Promise<void> {
    if (!this.#localStore.setShortcutPreference) throw new Error('shortcut preference storage is unavailable')
    if (accelerator.trim().length === 0) throw new Error('shortcut accelerator must not be empty')
    await this.#localStore.setShortcutPreference(accelerator)
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
    // D-22: a store-open/query failure at startup must degrade to the
    // closed `store_unavailable` recovery state, never an unhandled
    // rejection out of `bootstrap()` -- this is the FIRST call the desktop
    // entry point makes against the local store, so it must be the most
    // defensive one.
    let pending: PendingMutation[]
    try {
      pending = await this.#localStore.pendingMutations()
    } catch (error) {
      this.publishPresentation({ kind: 'store_unavailable' })
      return { settled: 0 }
    }
    let settled = 0
    for (const mutation of pending) {
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

  /**
   * D-24 "Remove data from this Mac…" -- separate from sign out and server
   * deletion. Delegates the actual serialized fence/close/delete/verify
   * sequence to the pure `removeLocalNamespaceData` state machine so it can
   * be exercised without a live worker/Electron process; this method's job
   * is only to supply the real ports (local store, credentials) and publish
   * the resulting presentation state. NEVER accepts or constructs a server
   * deletion request -- no sync/network port is passed to the removal
   * function at all, so calling it structurally cannot reach the server.
   */
  async removeLocalData(input: { confirmRemoveAnyway: boolean }): Promise<RemoveLocalDataOutcome> {
    return removeLocalNamespaceData({
      confirmRemoveAnyway: input.confirmRemoveAnyway,
      credentials: this.#credentials,
      localStore: this.#localStore,
    })
  }

  /**
   * O-19 / MAC-04: a synchronization pass is one of the five states a person
   * must be able to INSPECT without reading logs. This publishes the
   * `updating` row for the duration of the pass and clears it on EVERY exit
   * path -- success, partial settlement, and failure.
   *
   * Two properties this deliberately preserves:
   *
   *  - It makes NO durability claim. `updating` says "Updating…", never
   *    "Synced"; a mutation is only settled by an acknowledgement matching
   *    its mutation identity AND fingerprint exactly (D-03), and anything
   *    still in the outbox afterwards lands on "Saved on this Mac".
   *  - It never clobbers a more specific row published DURING the pass
   *    (conflict, namespace mismatch, authentication required). The
   *    terminal publish is guarded on the presentation sequence, so a pass
   *    that surfaced a real interruption leaves that interruption on
   *    screen.
   *
   * The delayed re-publish exists because `deriveDesktopPresentation`
   * resolves `updating` to a quiet `healthy` row inside GRACE_PERIOD_MS
   * (anti-flicker). A pass that finishes quickly is therefore invisible by
   * design; a pass that outlives the grace period re-publishes itself so it
   * actually becomes "Updating…" on screen. This is a presentation hint
   * only -- no correctness step depends on it (D-18).
   */
  async runSyncPass(): Promise<{ pulled: number; settled: number }> {
    if (!this.#sync.pull || !this.#sync.push || !this.#localStore.applyPull || !this.#localStore.readyMutations) {
      const result = await this.reconcile()
      return { pulled: 0, settled: result.settled }
    }

    // O-30: no server configured. `healthy` here would be a quiet row a
    // person reads as "everything is synchronized", which is simply untrue
    // -- there is no server to have synchronized with. `local_saved` ("Sync
    // when you're back online") is equally wrong: it promises a sync that
    // nothing is arranged to perform. `offline` -- "Offline — showing tasks
    // saved on this Mac" -- is the one row whose copy a person would read as
    // true here, and its `lastSuccessfulContact` is honestly null because
    // this app has never contacted anything.
    if (this.#sync.configured?.() === false) {
      this.publishPresentation({
        kind: 'offline',
        lastSuccessfulContact: (await this.#readLastSuccessfulContact()) ?? undefined,
      })
      return { pulled: 0, settled: 0 }
    }

    const startedAt = Date.now()
    let ownedSequence = this.publishPresentation({ kind: 'updating', startedAt }).sequence
    const graceTimer = setTimeout(() => {
      if (this.#currentPresentation.sequence !== ownedSequence) return
      ownedSequence = this.publishPresentation({ kind: 'updating', startedAt }).sequence
    }, GRACE_PERIOD_MS)
    ;(graceTimer as { unref?: () => void }).unref?.()

    // `undefined` until the ready set is actually known, so a failure before
    // that point publishes an honest count-less row rather than a made-up 0.
    let pending: number | undefined
    const settle = (input: DesktopPresentationInput): void => {
      clearTimeout(graceTimer)
      if (this.#currentPresentation.sequence !== ownedSequence) return
      this.publishPresentation(input)
    }

    // Read before the pass so a failure mid-pass can report the REAL prior
    // contact rather than inventing one. Stays null when the server has
    // never answered this Mac.
    let lastSuccessfulContact: string | null = null

    try {
      const state = await this.#localStore.syncState?.()
      lastSuccessfulContact = state?.lastSuccessfulContact ?? null
      const page = await this.#sync.pull(state?.cursor ?? null, SYNC_LIMITS.pull)
      // The server answered. That is a real contact regardless of whether
      // the answer turns out to be well-formed below, and it is what gives
      // the offline row an honest source next time. Best-effort (D-18): a
      // local store that cannot record this must not fail the pass or
      // downgrade a genuine success into a retryable failure.
      try {
        await this.#localStore.recordSuccessfulContact?.(this.#clock.now())
      } catch {
        // Presentation hint only -- never a correctness step.
      }
      if (page.changes.length > SYNC_LIMITS.pull) throw new Error('sync pull exceeded bounded page size')
      await this.#localStore.applyPull(page)

      const ready = (await this.#localStore.readyMutations()).slice(0, SYNC_LIMITS.push)
      pending = ready.length
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
      const remaining = ready.length - settled
      settle(remaining > 0 ? { kind: 'local_saved', pendingCount: remaining } : { kind: 'healthy' })
      return { pulled: page.changes.length, settled }
    } catch (error) {
      // O-30: a server that never answered is OFFLINE; a server that
      // answered and the answer was a problem stays RETRYABLE. The tag comes
      // from the transport, the only layer that knows whether bytes came
      // back -- never from sniffing message text.
      if (isSyncUnreachable(error)) {
        settle({ kind: 'offline', lastSuccessfulContact: lastSuccessfulContact ?? undefined })
      } else {
        settle({ kind: 'retryable_failure', pendingCount: pending })
      }
      throw error
    }
  }

  async #readLastSuccessfulContact(): Promise<string | null> {
    try {
      return (await this.#localStore.syncState?.())?.lastSuccessfulContact ?? null
    } catch {
      // An unreadable local store never fabricates a contact instant.
      return null
    }
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
  QuickEntryDraft,
  RemoveLocalDataOutcome,
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
