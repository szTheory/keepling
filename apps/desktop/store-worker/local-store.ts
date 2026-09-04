import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DatabaseSync } from 'node:sqlite'

import type {
  ConflictRecord,
  EditTaskCommand,
  LifecycleCommand,
  LocalAcceptance,
  MoveTodayCommand,
  PendingMutation,
  PullPage,
  QuickEntryDraft,
  SyncAcknowledgement,
  SyncMutation,
  SyncNamespace,
  SyncSnapshot,
  SyncState,
  WorkspaceSnapshot,
} from '../main/application/DesktopApplication.ts'
import type { OutboundBasis } from '../main/application/outbound-commands.ts'

/**
 * Why an undo of a never-transmitted mutation was or was not performed
 * (O-51). Closed, and deliberately more precise than a boolean: the caller
 * has to tell a person something true about a refusal.
 */
type UndoDropReason = 'blocked' | 'dropped' | 'nothing_to_undo' | 'transmitted' | 'unknown'

/** The SERVER-issued undo capability, retained verbatim (O-45). */
type RetainedUndo = { expiresAt: string; handle: string; label: string }

/**
 * The last local action a person could undo, and whether the server ever
 * issued a capability to undo it with (O-45). `availability: null` means the
 * acknowledgement carrying a handle has not arrived -- there is nothing to
 * send, and nothing here may invent one.
 */
type UndoTarget = {
  availability: RetainedUndo | null
  mutationId: string | null
  previous: { notes: string; title: string }
  taskId: string
}

const QUICK_ENTRY_DRAFT_KEY = 'quick_entry_draft'
const QUICK_ENTRY_SHORTCUT_KEY = 'quick_entry_shortcut'

/**
 * O-45. The server-issued undo capability for one accepted mutation, keyed
 * by that mutation's identity.
 *
 * Stored in the existing `namespace_metadata` key/value table, which is the
 * same idiom the Quick Entry draft, the sync fence, the bound namespace and
 * the last successful contact already use. NOT a new table, for a reason
 * that is a property of this store rather than a preference: there is
 * exactly ONE migration and `#applyMigration` refuses to open a database
 * whose recorded checksum for version 1 disagrees with the file on disk.
 * Editing `0001_initial.sql` would therefore fault every EXISTING local
 * store into `migration_checksum_drift` -- the closed "Keepling can't open
 * the tasks saved on this Mac" recovery state -- for every person who had
 * already run the app. Building a migration-2 mechanism to avoid that is
 * real work with its own failure modes and is not this change's to do.
 *
 * A retained handle is a CAPABILITY, not task state, so it deliberately
 * never enters `canonical_shadow`, `immutable_commands` or the projection.
 */
const UNDO_HANDLE_PREFIX = 'undo_handle:'

type LocalStoreOptions = {
  databasePath: string
  migrationPath: string | URL
}

/**
 * Closed, storage-neutral fault classification (D-22/D-37/D-38, T-KPL03-05-04).
 * Never expands beyond this vocabulary -- the recovery shell exposes exactly
 * one generic "Local store unavailable" state (UI-SPEC) regardless of which
 * code applies, so this only needs to be stable enough for diagnostics and
 * for tests to assert real SQLite/filesystem faults land in the right
 * bucket. `unknown` is the safe default for anything unrecognized -- it
 * still routes to the SAME closed recovery state, never a silent reset.
 */
type StoreFailureCode =
  | 'busy'
  | 'corruption'
  | 'disk_full'
  | 'integrity_failure'
  | 'migration_checksum_drift'
  | 'permission_denied'
  | 'read_only'
  | 'unknown'

const classifyStoreFailure = (error: unknown): StoreFailureCode => {
  const message = (error instanceof Error ? error.message : String(error)).toLowerCase()
  if (message.includes('checksum mismatch')) return 'migration_checksum_drift'
  if (message.includes('invariant check failed')) return 'integrity_failure'
  if (message.includes('malformed') || message.includes('not a database') || message.includes('corrupt')) return 'corruption'
  if (message.includes('disk') && (message.includes('full') || message.includes('space'))) return 'disk_full'
  if (message.includes('enospc') || message.includes('no space left')) return 'disk_full'
  if (message.includes('readonly') || message.includes('read-only') || message.includes('read only')) return 'read_only'
  if (
    message.includes('permission denied') ||
    message.includes('eacces') ||
    message.includes('eperm') ||
    message.includes('unable to open database file')
  ) return 'permission_denied'
  if (message.includes('locked') || message.includes('busy')) return 'busy'
  return 'unknown'
}

/**
 * Pure, instance-free derivation of the exact durable file inventory for a
 * namespace's local store (D-38: database, WAL, and SHM are one unit; a
 * stray `-journal` can exist after an interrupted rollback-journal-mode
 * fallback). Exported standalone -- not only an instance method -- so
 * whole-unit removal (D-24) is reachable even when the store failed to
 * OPEN in the first place (corruption, checksum drift, permission denial):
 * "Remove data from this Mac" must still be able to find and delete its own
 * files without first requiring a healthy `NodeSqliteLocalStore` instance.
 */
const deriveLocalFilePaths = (databasePath: string): string[] => [
  databasePath, `${databasePath}-wal`, `${databasePath}-shm`, `${databasePath}-journal`,
]

/**
 * D-24/D-38 whole-unit removal. MUST be called only after the database
 * connection (if any) is closed -- this never unlinks a live database, it
 * only deletes an already-closed file inventory. Each path is attempted
 * independently so one failure (e.g. an external process holding a handle)
 * does not abort attempts on the rest, and every attempt is reported so the
 * caller can verify absence and offer a retry rather than claim silent
 * success.
 */
const removeLocalFilesAt = (databasePath: string): { remaining: string[]; removed: string[] } => {
  const removed: string[] = []
  const remaining: string[] = []
  for (const path of deriveLocalFilePaths(databasePath)) {
    try {
      if (existsSync(path)) rmSync(path, { force: true })
      if (existsSync(path)) remaining.push(path)
      else removed.push(path)
    } catch {
      remaining.push(path)
    }
  }
  return { remaining, removed }
}

type ProjectionRow = {
  completed_at: string | null
  notes: string
  planned: number
  sync_status: 'saved_on_this_mac' | 'synced'
  task_id: string
  title: string
  trashed_at: string | null
}
type MutationRow = {
  accepted_at: string
  command_bytes: string
  fingerprint: string
  mutation_id: string
  task_id: string
  title: string
  resource_keys_json?: string
  effect_snapshot_json?: string
}

class NodeSqliteLocalStore {
  readonly #database: DatabaseSync
  readonly #databasePath: string

  constructor(options: LocalStoreOptions) {
    this.#databasePath = options.databasePath
    mkdirSync(dirname(options.databasePath), { recursive: true })
    this.#database = new DatabaseSync(options.databasePath, {
      allowExtension: false,
      defensive: true,
      timeout: 2_500,
    })
    this.#database.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;')
    this.#applyMigration(options.migrationPath)
    this.#recoverInterruptedTransmissions()
    this.#verifyInvariants()
  }

  acceptCapture(mutation: PendingMutation): LocalAcceptance {
    this.#assertNotFenced()
    this.#validateMutation(mutation)
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#database.prepare(`
        INSERT INTO immutable_commands(
          mutation_id, task_id, command_bytes, fingerprint, accepted_at,
          resource_keys_json, effect_snapshot_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(
        mutation.mutationId,
        mutation.taskId,
        mutation.commandBytes,
        mutation.fingerprint,
        mutation.acceptedAt,
        JSON.stringify([`task:${mutation.taskId}`]),
        JSON.stringify({ id: mutation.taskId, revision: 0, title: mutation.title }),
      )
      this.#database.prepare(`
        INSERT INTO mutation_journal(mutation_id, outcome, terminal_snapshot_json)
        VALUES (?, 'pending', NULL)
      `).run(mutation.mutationId)
      this.#database.prepare(`
        INSERT INTO visible_projection(task_id, title, sync_status)
        VALUES (?, ?, 'saved_on_this_mac')
      `).run(mutation.taskId, mutation.title)
      this.#database.prepare(`
        INSERT INTO outbox(mutation_id, sequence)
        VALUES (?, COALESCE((SELECT MAX(sequence) + 1 FROM outbox), 1))
      `).run(mutation.mutationId)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }

    return {
      fingerprint: mutation.fingerprint,
      mutationId: mutation.mutationId,
      snapshot: this.snapshot(),
      status: 'local_saved',
    }
  }

  acceptMutation(mutation: SyncMutation): void {
    this.#validateSyncMutation(mutation)
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#enqueueOutbound(mutation)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
  }

  /**
   * The ONE durable enqueue (O-41). Callers must already hold a
   * transaction: `acceptMutation` opens its own, and
   * `editTask`/`applyLifecycle`/`applyMoveToday` call this INSIDE the very
   * transaction that writes the local projection, because "a client reports
   * mutation success only after its local projection and durable outbox
   * entry commit atomically" (D-03) is not satisfied by two transactions in
   * a row -- a crash between them loses the outbound intent while the person
   * has already been told the change is safe.
   */
  #enqueueOutbound(mutation: SyncMutation): void {
    this.#database.prepare(`
      INSERT INTO immutable_commands(
        mutation_id, task_id, command_bytes, fingerprint, accepted_at,
        resource_keys_json, effect_snapshot_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      mutation.mutationId,
      mutation.effect.entityId,
      mutation.commandBytes,
      mutation.fingerprint,
      mutation.acceptedAt,
      JSON.stringify(mutation.resourceKeys),
      JSON.stringify(mutation.effect.snapshot),
    )
    this.#database.prepare(`
      INSERT INTO mutation_journal(mutation_id, outcome, terminal_snapshot_json)
      VALUES (?, 'pending', NULL)
    `).run(mutation.mutationId)
    for (const dependency of mutation.dependencies) {
      this.#database.prepare(`
        INSERT INTO mutation_dependencies(mutation_id, dependency_mutation_id) VALUES (?, ?)
      `).run(mutation.mutationId, dependency)
    }
    this.#upsertProjection(mutation.effect.entityId, mutation.effect.snapshot, 'saved_on_this_mac')
    this.#database.prepare(`
      INSERT INTO outbox(mutation_id, sequence)
      VALUES (?, COALESCE((SELECT MAX(sequence) + 1 FROM outbox), 1))
    `).run(mutation.mutationId)
  }

  /**
   * What this client believes the SERVER currently holds for one task
   * (O-41), which is what `base_values`/`base_planned_on`/`expected_revision`
   * must describe.
   *
   * The chain matters. For a task with nothing queued the basis is the
   * canonical shadow -- the last snapshot the server itself supplied. For a
   * task that ALREADY has queued mutations the basis is the effect of the
   * last queued one, because those will be delivered first (they hold an
   * earlier outbox sequence and the same resource key, so `readyMutations`
   * cannot let a later one overtake them). Using the shadow in that case
   * would send the same stale base twice and the server would report a
   * conflict against a value this client had itself just supplied.
   *
   * `expected_revision` has a contract minimum of 1 and a captured task is
   * revision 1 on the server, so an unacknowledged task resolves to 1 rather
   * than to a fabricated higher number. The revision is not the conflict gate
   * for `edit_task` (a three-way field merge is), so a stale revision on an
   * offline edit is safe; for `trash_task`/`restore_task` the server compares
   * it exactly, and a genuine divergence is a genuine conflict.
   */
  taskSyncBasis(taskId: string): OutboundBasis {
    const projection = this.#requireProjectionRow(taskId)
    const queued = this.#database.prepare(`
      SELECT immutable_commands.effect_snapshot_json AS effect_snapshot_json
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE immutable_commands.task_id = ?
      ORDER BY outbox.sequence DESC LIMIT 1
    `).get(taskId) as { effect_snapshot_json: string | null } | undefined
    const shadow = this.#database.prepare(`
      SELECT snapshot_json FROM canonical_shadow WHERE entity_id = ?
    `).get(taskId) as { snapshot_json: string } | undefined

    const queuedSnapshot = queued?.effect_snapshot_json
      ? (JSON.parse(queued.effect_snapshot_json) as SyncSnapshot)
      : null
    const shadowSnapshot = shadow ? (JSON.parse(shadow.snapshot_json) as SyncSnapshot) : null
    const basisSnapshot = queuedSnapshot ?? shadowSnapshot
    const revisionCandidates = [queuedSnapshot?.revision, shadowSnapshot?.revision]
    const expectedRevision = revisionCandidates.find(
      (value): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 1,
    ) ?? 1

    return {
      baseNotes: typeof basisSnapshot?.notes === 'string' ? basisSnapshot.notes : projection.notes,
      basePlannedOn: typeof basisSnapshot?.planned_on === 'string' ? basisSnapshot.planned_on : null,
      baseTitle: typeof basisSnapshot?.title === 'string' ? basisSnapshot.title : projection.title,
      expectedRevision,
    }
  }

  applyPull(page: PullPage): void {
    if (page.changes.length > 50) throw new Error('invalid bounded pull page')
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      for (const change of page.changes) {
        const existing = this.#database.prepare(`
          SELECT snapshot_json FROM canonical_shadow WHERE entity_id = ?
        `).get(change.entityId) as { snapshot_json: string } | undefined
        const existingRevision = existing
          ? ((JSON.parse(existing.snapshot_json) as SyncSnapshot).revision ?? -1)
          : -1
        if ((change.snapshot.revision ?? -1) >= existingRevision) {
          this.#database.prepare(`
            INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
            ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
          `).run(change.entityId, JSON.stringify(change.snapshot))
        }
      }
      if (page.cursor !== null) this.#database.prepare('UPDATE sync_cursor SET cursor = ? WHERE singleton = 1').run(page.cursor)
      this.#replayVisible()
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
  }

  readyMutations(): SyncMutation[] {
    const fenced = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = 'sync_fence'
    `).get() as { value: string } | undefined
    if (fenced) return []

    const rows = this.#database.prepare(`
      SELECT immutable_commands.accepted_at, immutable_commands.command_bytes,
             immutable_commands.fingerprint, immutable_commands.mutation_id,
             immutable_commands.task_id, immutable_commands.resource_keys_json,
             immutable_commands.effect_snapshot_json
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE outbox.state <> 'in_flight'
      ORDER BY outbox.sequence
    `).all() as MutationRow[]
    const mutations = rows.map((row) => this.#rowToSyncMutation(row))
    return mutations.filter((mutation, index) => {
      const dependenciesSatisfied = mutation.dependencies.every((dependency) => {
        const outcome = this.#database.prepare(`
          SELECT outcome FROM mutation_journal WHERE mutation_id = ?
        `).get(dependency) as { outcome: string } | undefined
        return outcome?.outcome === 'accepted' || outcome?.outcome === 'already_satisfied'
      })
      if (!dependenciesSatisfied) return false
      return mutations.slice(0, index).every((earlier) =>
        earlier.resourceKeys.every((key) => !mutation.resourceKeys.includes(key)),
      )
    }).slice(0, 25)
  }

  /**
   * O-51. The moment before this command's bytes are handed to the
   * transport. From here on an undo may NOT drop it: the client cannot know
   * whether the server saw it, and dropping a command the server accepted is
   * the divergence D-52 exists to avoid.
   *
   * The fingerprint is checked against the stored command, so a caller can
   * never mark one row as the transmission of another's bytes. A row that is
   * absent or already in flight is a caller bug and throws -- silently
   * doing nothing here would leave a live request looking never-sent.
   */
  beginTransmission(mutationId: string, fingerprint: string): void {
    const row = this.#database.prepare(`
      SELECT outbox.state AS state, immutable_commands.fingerprint AS fingerprint
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE outbox.mutation_id = ?
    `).get(mutationId) as { fingerprint: string; state: string } | undefined
    if (row === undefined) throw new Error('transmission has no queued command')
    if (row.fingerprint !== fingerprint) throw new Error('transmission fingerprint does not match the queued command')
    if (row.state === 'in_flight') throw new Error('transmission is already in flight')
    this.#database.prepare(`UPDATE outbox SET state = 'in_flight' WHERE mutation_id = ?`).run(mutationId)
  }

  /**
   * O-51. The request ended without an outcome -- the transport failed, or
   * the caller could not match the answer to the command it sent.
   *
   * The row becomes `uncertain`, NEVER `queued`. `fetch` rejecting cannot
   * distinguish "the request never left" from "it left and the answer was
   * lost" (O-47), so this is exactly the ambiguity the drop rule refuses to
   * resolve in the client's favour. It stays pushable, because
   * retransmitting the same immutable bytes under the same mutation
   * identity is what the server's idempotency is for.
   *
   * A row the acknowledgement already removed is not an error: settling and
   * abandoning race by nature, and the settled answer wins.
   */
  abandonTransmission(mutationId: string): void {
    this.#database.prepare(`
      UPDATE outbox SET state = 'uncertain' WHERE mutation_id = ? AND state = 'in_flight'
    `).run(mutationId)
  }

  /**
   * O-51. A process that ended mid-POST leaves `in_flight` rows with no
   * outcome. They are promoted to `uncertain` at the next open -- NOT reset
   * to `queued`, which would silently make a possibly-transmitted command
   * droppable again and reopen the divergence window on every crash.
   *
   * Promotion, not reset: the rows keep their bytes, their sequence and
   * their place in the queue, and are pushed again on the next pass.
   *
   * Two deliberate narrownesses:
   *
   *  - It runs only at schema version 2 or above, because the column it
   *    repairs is what version 2 adds. A store opened against an older
   *    migration set (the fault fixtures do this to BUILD a pre-0002
   *    database) has no interrupted transmissions to recover: nothing could
   *    have marked one.
   *  - It reads before it writes, so opening a READ-ONLY database file with
   *    nothing in flight still succeeds and still fails only on write
   *    (D-22/D-38). When something IS in flight and the file cannot be
   *    written, the open fails loudly instead: a store that cannot record
   *    what it does not know must not be used to answer questions about it.
   */
  #recoverInterruptedTransmissions(): void {
    if (this.#appliedSchemaVersion() < 2) return
    const interrupted = this.#database.prepare(`
      SELECT COUNT(*) AS total FROM outbox WHERE state = 'in_flight'
    `).get() as { total: number }
    if (interrupted.total === 0) return
    this.#database.prepare(`UPDATE outbox SET state = 'uncertain' WHERE state = 'in_flight'`).run()
  }

  #appliedSchemaVersion(): number {
    const row = this.#database.prepare(`
      SELECT MAX(version) AS version FROM schema_migrations
    `).get() as { version: number | null }
    return row.version ?? 0
  }

  /**
   * O-51 / D-52: undo of a mutation the server never received.
   *
   * This is the ONLY path that removes a command from the outbox without an
   * answer from the server, so every reason it can refuse is spelled out
   * rather than collapsed into a boolean:
   *
   *   `dropped`         the command was `queued` -- its bytes were never
   *                     handed to the transport -- so there is nothing to
   *                     reconcile and it is removed outright, in the SAME
   *                     transaction that reverts what a person sees.
   *   `nothing_to_undo` no recorded local action.
   *   `transmitted`     the command is `in_flight` or `uncertain`. The
   *                     server may hold it. Refused.
   *   `blocked`         a LATER queued command shares its resource key, so
   *                     dropping this one would send the successor against
   *                     a base the server never received. Refused.
   *   `unknown`         no outbox row for the recorded action, or an action
   *                     recorded before mutation identity existed. Absent
   *                     state is ambiguous state. Refused.
   *
   * The command rows are deleted rather than tombstoned. Bytes that never
   * left the machine have no counterpart anywhere to reconcile against, and
   * leaving `immutable_commands`/`mutation_journal` behind would keep a
   * `pending` journal entry for a command nothing can ever settle.
   */
  undoUnsentLocalAction(): { applied: boolean; reason: UndoDropReason; snapshot: WorkspaceSnapshot } {
    this.#assertNotFenced()
    const refuse = (reason: UndoDropReason) => ({ applied: false, reason, snapshot: this.snapshot() })
    const action = this.#readLastAction()
    if (action === null) return refuse('nothing_to_undo')
    if (action.mutationId === null) return refuse('unknown')

    const target = this.#database.prepare(`
      SELECT outbox.sequence AS sequence, outbox.state AS state,
             immutable_commands.resource_keys_json AS resource_keys_json
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE outbox.mutation_id = ?
    `).get(action.mutationId) as { resource_keys_json: string; sequence: number; state: string } | undefined
    if (target === undefined) return refuse('unknown')
    if (target.state !== 'queued') return refuse('transmitted')

    const resourceKeys = new Set(JSON.parse(target.resource_keys_json) as string[])
    const successors = this.#database.prepare(`
      SELECT immutable_commands.resource_keys_json AS resource_keys_json
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE outbox.sequence > ?
    `).all(target.sequence) as Array<{ resource_keys_json: string }>
    const blocked = successors.some((successor) =>
      (JSON.parse(successor.resource_keys_json) as string[]).some((key) => resourceKeys.has(key)),
    )
    if (blocked) return refuse('blocked')

    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#database.prepare(`
        UPDATE visible_projection
        SET title = ?, notes = ?, completed_at = ?, trashed_at = ?, planned = ?
        WHERE task_id = ?
      `).run(
        action.previous.title,
        action.previous.notes,
        action.previous.completed_at,
        action.previous.trashed_at,
        action.previous.planned,
        action.taskId,
      )
      // Children first: foreign keys are ON, and the command row is the
      // parent of all three.
      this.#database.prepare('DELETE FROM outbox WHERE mutation_id = ?').run(action.mutationId)
      this.#database.prepare('DELETE FROM mutation_dependencies WHERE mutation_id = ? OR dependency_mutation_id = ?')
        .run(action.mutationId, action.mutationId)
      this.#database.prepare('DELETE FROM conflicts WHERE mutation_id = ?').run(action.mutationId)
      this.#database.prepare('DELETE FROM mutation_journal WHERE mutation_id = ?').run(action.mutationId)
      this.#database.prepare('DELETE FROM immutable_commands WHERE mutation_id = ?').run(action.mutationId)
      this.#database.prepare('DELETE FROM namespace_metadata WHERE key = ?')
        .run(`${UNDO_HANDLE_PREFIX}${action.mutationId}`)
      // One level of undo (O-2): a second press finds nothing rather than
      // walking back through history this store does not keep.
      this.#database.prepare('UPDATE last_local_action SET action_json = NULL WHERE singleton = 1').run()
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return { applied: true, reason: 'dropped', snapshot: this.snapshot() }
  }

  acknowledgeSync(acknowledgement: SyncAcknowledgement): void {
    this.acknowledge(acknowledgement)
  }

  setSyncFence(reason: string | null): void {
    if (reason === null) {
      this.#database.prepare("DELETE FROM namespace_metadata WHERE key = 'sync_fence'").run()
    } else {
      this.#database.prepare(`
        INSERT INTO namespace_metadata(key, value) VALUES ('sync_fence', ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
      `).run(reason)
    }
  }

  bindNamespace(namespace: SyncNamespace): boolean {
    const dimensions = [
      namespace.issuer,
      namespace.origin,
      namespace.serverInstance,
      namespace.accountSubject,
      namespace.generation,
    ]
    if (dimensions.some((value) => value.length === 0)) throw new Error('incomplete synchronization namespace')
    const serialized = JSON.stringify(namespace)
    const existing = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = 'sync_namespace'
    `).get() as { value: string } | undefined
    if (existing && existing.value !== serialized) {
      this.setSyncFence('namespace_mismatch')
      return false
    }
    this.#database.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES ('sync_namespace', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(serialized)
    return true
  }

  /**
   * O-30: records that the server actually answered at this instant, in the
   * same durable `namespace_metadata` table the sync fence and bound
   * namespace already use, so a relaunch can still read it. This is the ONLY
   * writer of the offline row's `lastSuccessfulContact` -- nothing may
   * derive or default it.
   */
  recordSuccessfulContact(at: string): void {
    if (typeof at !== 'string' || at.length === 0) throw new Error('successful contact instant is invalid')
    this.#database.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES ('last_successful_contact', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(at)
  }

  syncState(): SyncState {
    const cursor = this.#database.prepare('SELECT cursor FROM sync_cursor WHERE singleton = 1').get() as { cursor: string | null }
    const outbox = this.#database.prepare('SELECT mutation_id FROM outbox ORDER BY sequence').all() as Array<{ mutation_id: string }>
    const contact = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = 'last_successful_contact'
    `).get() as { value: string } | undefined
    return {
      cursor: cursor.cursor,
      lastSuccessfulContact: contact?.value ?? null,
      outbox: outbox.map((row) => row.mutation_id),
      readyPushes: this.readyMutations().map((mutation) => mutation.mutationId),
    }
  }

  acknowledge(acknowledgement: SyncAcknowledgement): WorkspaceSnapshot {
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      const pending = this.#database.prepare(`
        SELECT immutable_commands.fingerprint, immutable_commands.task_id
        FROM outbox
        JOIN immutable_commands USING (mutation_id)
        WHERE outbox.mutation_id = ?
      `).get(acknowledgement.mutationId) as { fingerprint: string; task_id: string } | undefined

      if (pending === undefined) {
        const terminal = this.#database.prepare(`
          SELECT outcome FROM mutation_journal WHERE mutation_id = ?
        `).get(acknowledgement.mutationId) as { outcome: string } | undefined
        if (terminal?.outcome === acknowledgement.outcome) {
          this.#database.exec('COMMIT')
          return this.snapshot()
        }
        throw new Error('unknown acknowledgement mutation')
      }
      if (pending.fingerprint !== acknowledgement.fingerprint) {
        throw new Error('acknowledgement fingerprint mismatch')
      }

      const snapshotJson = JSON.stringify(acknowledgement.snapshot)
      // O-38. Only an ACCEPTED answer carries a full canonical task snapshot,
      // so only an accepted answer may replace what this Mac believes the
      // server holds.
      //
      // A conflict answer is an RFC 9457 problem carrying just the affected
      // fields' current values, and a rejection carries no task state at
      // all. Writing either into `canonical_shadow` would blank every field
      // the server did not mention, and `#upsertProjection` would then fall
      // back to displaying the task's identifier as its title -- a silent
      // data-shaped lie produced by trying to be helpful. The next real pull
      // brings the true canonical state; until then the local row stands and
      // honestly still reads "Saved on this Mac".
      if (acknowledgement.outcome === 'accepted' || acknowledgement.outcome === 'already_satisfied') {
        this.#database.prepare(`
          INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
          ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
        `).run(pending.task_id, snapshotJson)
        this.#upsertProjection(pending.task_id, acknowledgement.snapshot, 'synced')
      }
      // O-45: the server-issued compensation capability, retained against
      // the mutation it undoes. This is the ONLY writer of an undo handle;
      // nothing derives, extends or repairs one. It is present only for the
      // commands the server can compensate (`Undo.@supported_commands` --
      // notably not `capture_task`), and its absence is an honest "this
      // cannot be undone", never a reason to synthesise something.
      if (acknowledgement.undo !== undefined) {
        this.#retainUndoAvailability(acknowledgement.mutationId, acknowledgement.undo)
      }
      this.#pruneUndoAvailability(new Date().toISOString())
      this.#database.prepare(`
        UPDATE mutation_journal SET outcome = ?, terminal_snapshot_json = ? WHERE mutation_id = ?
      `).run(acknowledgement.outcome, snapshotJson, acknowledgement.mutationId)
      // Terminal for every outcome: the server has decided, and retrying the
      // same immutable bytes cannot change its mind. Leaving a refused
      // command queued is how an outbox fills with commands nothing can ever
      // settle. Note this is ALSO what keeps the ordering rule free of a
      // stuck state -- a later mutation on the same task becomes ready as
      // soon as this one leaves the outbox, whatever the outcome was.
      this.#database.prepare('DELETE FROM outbox WHERE mutation_id = ?').run(acknowledgement.mutationId)
      if (acknowledgement.outcome === 'conflict') {
        const command = this.#database.prepare(`
          SELECT effect_snapshot_json FROM immutable_commands WHERE mutation_id = ?
        `).get(acknowledgement.mutationId) as { effect_snapshot_json: string } | undefined
        const mineSnapshot: SyncSnapshot = command
          ? (JSON.parse(command.effect_snapshot_json) as SyncSnapshot)
          : { id: '' }
        const current = typeof acknowledgement.snapshot.title === 'string' ? acknowledgement.snapshot.title : null
        const mine = typeof mineSnapshot.title === 'string' ? mineSnapshot.title : null
        // A mine/current record is only recorded when the SERVER named a
        // divergent `title`, because that is the only thing the desktop's
        // chooser can honestly present (`ConflictResolver` asks which TITLE
        // to keep). A lifecycle or Trash conflict diverges on
        // `completed_at`/`trashed_at`, and offering those two timestamps
        // under "choose which title" would be a lie in the UI. Those still
        // reach a person as the `conflict` row and its Review Conflict
        // action, which falls back to refreshing from the server -- exactly
        // the `refresh_task` recovery the server itself names. Recorded as a
        // known limit in 03-22-SUMMARY.md.
        if (current !== null && mine !== null) {
          this.#database.prepare(`
            INSERT INTO conflicts(conflict_id, mutation_id, details_json) VALUES (?, ?, ?)
            ON CONFLICT(conflict_id) DO UPDATE SET details_json = excluded.details_json
          `).run(
            `conflict:${acknowledgement.mutationId}`,
            acknowledgement.mutationId,
            JSON.stringify({ current, mine }),
          )
        }
      }
      // The visible projection is a replay of (canonical shadow + outbox).
      // Replaying it after a REFUSAL would reassert the shadow over a change
      // the refused command had already applied locally -- so the person
      // would watch their edit vanish while being told "Your version is
      // still on this Mac", and a diverged row would be relabelled "Synced"
      // on the strength of an answer that settled nothing. The local row
      // stands, still reading "Saved on this Mac", and the conflict record
      // (when the server named a title) holds both versions for the choice.
      //
      // KNOWN LIMIT, recorded in 03-22-SUMMARY.md rather than papered over:
      // the refused command is terminal and is gone from the outbox, so the
      // NEXT pull replays the shadow and the local value is lost. Giving a
      // refused local change a durable home is a product decision this plan
      // did not carry authority to make.
      if (acknowledgement.outcome === 'accepted' || acknowledgement.outcome === 'already_satisfied') {
        this.#replayVisible()
      }
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return this.snapshot()
  }

  pendingMutations(): PendingMutation[] {
    const rows = this.#database.prepare(`
      SELECT immutable_commands.accepted_at, immutable_commands.command_bytes,
             immutable_commands.fingerprint, immutable_commands.mutation_id,
             immutable_commands.task_id, visible_projection.title
      FROM outbox
      JOIN immutable_commands USING (mutation_id)
      JOIN visible_projection ON visible_projection.task_id = immutable_commands.task_id
      ORDER BY outbox.sequence
      LIMIT 25
    `).all() as MutationRow[]
    return rows.map((row) => ({
      acceptedAt: row.accepted_at,
      commandBytes: row.command_bytes,
      fingerprint: row.fingerprint,
      mutationId: row.mutation_id,
      taskId: row.task_id,
      title: row.title,
    }))
  }

  snapshot(): WorkspaceSnapshot {
    const rows = this.#database.prepare(`
      SELECT task_id, title, sync_status, notes, completed_at, trashed_at, planned
      FROM visible_projection ORDER BY rowid
    `).all() as ProjectionRow[]
    return {
      tasks: rows.map((row) => ({
        completedAt: row.completed_at,
        id: row.task_id,
        notes: row.notes,
        planned: row.planned === 1,
        syncStatus: row.sync_status,
        title: row.title,
        trashedAt: row.trashed_at,
      })),
    }
  }

  editTask(command: EditTaskCommand, outbound?: SyncMutation): WorkspaceSnapshot {
    this.#assertNotFenced()
    const title = command.title.trim()
    if (title.length === 0 || [...title].length > 512) throw new Error('invalid task title')
    if ([...command.notes].length > 50_000) throw new Error('invalid task notes')
    if (outbound) this.#validateOutbound(outbound, command.taskId, ['edit_task'])
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      const before = this.#requireProjectionRow(command.taskId)
      this.#recordLastAction(command.taskId, before, outbound?.mutationId ?? null)
      this.#database.prepare(`
        UPDATE visible_projection SET title = ?, notes = ? WHERE task_id = ?
      `).run(title, command.notes, command.taskId)
      // O-41: the outbound intent joins the SAME transaction as the local
      // projection write. Two transactions in a row would satisfy neither
      // D-03 nor the person, who has already been told the change is safe.
      if (outbound) this.#enqueueOutbound(outbound)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return this.snapshot()
  }

  applyLifecycle(command: LifecycleCommand, outbound?: SyncMutation): WorkspaceSnapshot {
    this.#assertNotFenced()
    if (outbound) {
      this.#validateOutbound(outbound, command.taskId, ['complete_task', 'reopen_task', 'restore_task', 'trash_task'])
    }
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      const before = this.#requireProjectionRow(command.taskId)
      this.#recordLastAction(command.taskId, before, outbound?.mutationId ?? null)
      if (command.kind === 'complete') {
        this.#database.prepare(`UPDATE visible_projection SET completed_at = ? WHERE task_id = ?`)
          .run(new Date().toISOString(), command.taskId)
      } else if (command.kind === 'reopen') {
        this.#database.prepare(`UPDATE visible_projection SET completed_at = NULL WHERE task_id = ?`)
          .run(command.taskId)
      } else if (command.kind === 'trash') {
        this.#database.prepare(`UPDATE visible_projection SET trashed_at = ? WHERE task_id = ?`)
          .run(new Date().toISOString(), command.taskId)
      } else {
        this.#database.prepare(`UPDATE visible_projection SET trashed_at = NULL WHERE task_id = ?`)
          .run(command.taskId)
      }
      if (outbound) this.#enqueueOutbound(outbound)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return this.snapshot()
  }

  applyMoveToday(command: MoveTodayCommand, outbound?: SyncMutation): WorkspaceSnapshot {
    this.#assertNotFenced()
    if (outbound) this.#validateOutbound(outbound, command.taskId, ['plan_for_today', 'unplan_task'])
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      const before = this.#requireProjectionRow(command.taskId)
      this.#recordLastAction(command.taskId, before, outbound?.mutationId ?? null)
      this.#database.prepare(`UPDATE visible_projection SET planned = ? WHERE task_id = ?`)
        .run(command.planned ? 1 : 0, command.taskId)
      if (outbound) this.#enqueueOutbound(outbound)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return this.snapshot()
  }

  /**
   * O-45: what the last local action was, and whether the SERVER issued a
   * capability to undo it. `null` means there is nothing to undo at all.
   */
  undoTarget(): UndoTarget | null {
    const action = this.#readLastAction()
    if (action === null) return null
    return {
      availability: action.mutationId === null ? null : this.#readUndoAvailability(action.mutationId),
      mutationId: action.mutationId,
      previous: { notes: action.previous.notes, title: action.previous.title },
      taskId: action.taskId,
    }
  }

  /**
   * Reverses the last local action AND sends it (O-45).
   *
   * `outbound` is REQUIRED. Until this change the projection was reversed
   * and nothing was enqueued, so an undo was durable on this Mac and
   * invisible to the server forever -- the same defect class as O-41, one
   * operation later. Calling this without a durable undo command now
   * changes NOTHING and reports `applied: false`, because silently
   * accepting an undo locally and dropping it is precisely the behaviour
   * being removed. The caller decides what a person is told (an unsent
   * mutation has no handle; an expired handle can no longer be used), and
   * that refusal is surfaced rather than swallowed.
   *
   * The revert and the enqueue share ONE transaction, for the same reason
   * every other mutation does (D-03): a crash between them would leave a
   * person told the undo is safe while the intent to send it is gone.
   *
   * The undo itself is deliberately not recorded as a new undoable action.
   * The handle it consumed is one-shot server side, so a second press must
   * find nothing rather than replay a spent capability.
   */
  undoLastLocalAction(outbound?: SyncMutation): { applied: boolean; snapshot: WorkspaceSnapshot } {
    this.#assertNotFenced()
    if (outbound === undefined) return { applied: false, snapshot: this.snapshot() }
    const action = this.#readLastAction()
    if (action === null) return { applied: false, snapshot: this.snapshot() }
    this.#validateOutboundUndo(outbound, action.taskId)
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#database.prepare(`
        UPDATE visible_projection
        SET title = ?, notes = ?, completed_at = ?, trashed_at = ?, planned = ?
        WHERE task_id = ?
      `).run(
        action.previous.title,
        action.previous.notes,
        action.previous.completed_at,
        action.previous.trashed_at,
        action.previous.planned,
        action.taskId,
      )
      this.#enqueueOutbound(outbound)
      // The projection above is the reverted state; `#enqueueOutbound`
      // upserts the effect over it, and the effect carries the same
      // reverted title, so the row a person sees does not flicker back.
      if (action.mutationId !== null) {
        this.#database.prepare('DELETE FROM namespace_metadata WHERE key = ?')
          .run(`${UNDO_HANDLE_PREFIX}${action.mutationId}`)
      }
      this.#database.prepare(`UPDATE last_local_action SET action_json = NULL WHERE singleton = 1`).run()
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return { applied: true, snapshot: this.snapshot() }
  }

  listConflicts(): ConflictRecord[] {
    const rows = this.#database.prepare(`
      SELECT conflicts.conflict_id, conflicts.details_json, immutable_commands.task_id
      FROM conflicts JOIN immutable_commands USING (mutation_id)
    `).all() as Array<{ conflict_id: string; details_json: string; task_id: string }>
    return rows.map((row) => {
      const details = JSON.parse(row.details_json) as { current: string; mine: string }
      return { conflictId: row.conflict_id, current: details.current, mine: details.mine, taskId: row.task_id }
    })
  }

  resolveConflict(input: { choice: 'current' | 'mine'; conflictId: string }): WorkspaceSnapshot {
    this.#assertNotFenced()
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      const row = this.#database.prepare(`
        SELECT conflicts.details_json, immutable_commands.task_id
        FROM conflicts JOIN immutable_commands USING (mutation_id)
        WHERE conflicts.conflict_id = ?
      `).get(input.conflictId) as { details_json: string; task_id: string } | undefined
      if (row === undefined) throw new Error('conflict not found')
      const details = JSON.parse(row.details_json) as { current: string; mine: string }
      const resolvedTitle = input.choice === 'mine' ? details.mine : details.current
      const status = input.choice === 'mine' ? 'saved_on_this_mac' : 'synced'
      this.#database.prepare(`UPDATE visible_projection SET title = ?, sync_status = ? WHERE task_id = ?`)
        .run(resolvedTitle, status, row.task_id)
      this.#database.prepare(`DELETE FROM conflicts WHERE conflict_id = ?`).run(input.conflictId)
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
    return this.snapshot()
  }

  /**
   * Quick Entry draft persistence (D-03/D-11). Stored in the existing
   * `namespace_metadata` key/value table -- a draft is deliberately NOT a
   * task mutation, so it never touches immutable_commands/outbox/journal.
   * A single UPDATE-then-INSERT-if-absent keeps this durable across window
   * hide/recreation and app restart without a schema change.
   */
  saveDraft(draft: QuickEntryDraft): void {
    if ([...draft.title].length > 512) throw new Error('draft title must not exceed 512 Unicode scalar values')
    this.#database.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(QUICK_ENTRY_DRAFT_KEY, JSON.stringify({ addToToday: draft.addToToday, title: draft.title }))
  }

  getDraft(): QuickEntryDraft | null {
    const row = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = ?
    `).get(QUICK_ENTRY_DRAFT_KEY) as { value: string } | undefined
    if (row === undefined) return null
    return JSON.parse(row.value) as QuickEntryDraft
  }

  clearDraft(): void {
    this.#database.prepare('DELETE FROM namespace_metadata WHERE key = ?').run(QUICK_ENTRY_DRAFT_KEY)
  }

  getShortcutPreference(): string | null {
    const row = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = ?
    `).get(QUICK_ENTRY_SHORTCUT_KEY) as { value: string } | undefined
    return row?.value ?? null
  }

  setShortcutPreference(accelerator: string): void {
    if (accelerator.trim().length === 0) throw new Error('shortcut accelerator must not be empty')
    this.#database.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(QUICK_ENTRY_SHORTCUT_KEY, accelerator)
  }

  #requireProjectionRow(taskId: string): ProjectionRow {
    const row = this.#database.prepare(`
      SELECT task_id, title, sync_status, notes, completed_at, trashed_at, planned
      FROM visible_projection WHERE task_id = ?
    `).get(taskId) as ProjectionRow | undefined
    if (row === undefined) throw new Error('task not found')
    return row
  }

  /**
   * O-45: the recorded action now carries the MUTATION IDENTITY it produced,
   * because that identity is the only thing that can find the server-issued
   * undo handle for it. Rows written before this change have no
   * `mutationId`; they resolve to no availability and are refused, which is
   * the correct answer -- there is no handle for them and one must never be
   * invented.
   */
  #recordLastAction(taskId: string, before: ProjectionRow, mutationId: string | null): void {
    this.#database.prepare(`
      UPDATE last_local_action SET action_json = ? WHERE singleton = 1
    `).run(JSON.stringify({ mutationId, previous: before, taskId }))
  }

  #readLastAction(): { mutationId: string | null; previous: ProjectionRow; taskId: string } | null {
    const stored = this.#database.prepare(`
      SELECT action_json FROM last_local_action WHERE singleton = 1
    `).get() as { action_json: string | null }
    if (stored.action_json === null) return null
    const action = JSON.parse(stored.action_json) as {
      mutationId?: string | null
      previous: ProjectionRow
      taskId: string
    }
    return { mutationId: action.mutationId ?? null, previous: action.previous, taskId: action.taskId }
  }

  #retainUndoAvailability(mutationId: string, undo: RetainedUndo): void {
    this.#database.prepare(`
      INSERT INTO namespace_metadata(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(`${UNDO_HANDLE_PREFIX}${mutationId}`, JSON.stringify(undo))
  }

  #readUndoAvailability(mutationId: string): RetainedUndo | null {
    const row = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = ?
    `).get(`${UNDO_HANDLE_PREFIX}${mutationId}`) as { value: string } | undefined
    return row === undefined ? null : (JSON.parse(row.value) as RetainedUndo)
  }

  /**
   * Handles are one-shot server side and expire (24 hours, `Undo.valid_for_seconds`).
   * Keeping spent or lapsed ones would accumulate dead capabilities in a
   * plaintext store forever, so each write sweeps the ones whose own
   * SERVER-supplied expiry has passed. Nothing here extends or renews one.
   */
  #pruneUndoAvailability(nowIso: string): void {
    const rows = this.#database.prepare(`
      SELECT key, value FROM namespace_metadata WHERE key LIKE ?
    `).all(`${UNDO_HANDLE_PREFIX}%`) as Array<{ key: string; value: string }>
    const now = Date.parse(nowIso)
    if (!Number.isFinite(now)) return
    for (const row of rows) {
      const expiry = Date.parse((JSON.parse(row.value) as RetainedUndo).expiresAt)
      if (!Number.isFinite(expiry) || expiry <= now) {
        this.#database.prepare('DELETE FROM namespace_metadata WHERE key = ?').run(row.key)
      }
    }
  }

  close(): void {
    this.#database.close()
  }

  /** See the standalone `deriveLocalFilePaths` -- kept as an instance convenience. */
  listLocalFilePaths(): string[] {
    return deriveLocalFilePaths(this.#databasePath)
  }

  /**
   * D-24/D-38 whole-unit removal. MUST be called only after `close()` -- see
   * the standalone `removeLocalFilesAt`, which this delegates to.
   */
  removeLocalFiles(): { remaining: string[]; removed: string[] } {
    return removeLocalFilesAt(this.#databasePath)
  }

  #assertNotFenced(): void {
    const fenced = this.#database.prepare(`
      SELECT value FROM namespace_metadata WHERE key = 'sync_fence'
    `).get() as { value: string } | undefined
    if (fenced) throw new Error(`local writes are fenced: ${fenced.value}`)
  }

  /**
   * The migration runner, generalised (O-51). It applies an ORDERED set of
   * migrations and preserves the checksum binding D-37 requires: a version
   * whose recorded checksum disagrees with the file on disk fails loudly and
   * the store does not open. Nothing here repairs, reapplies or rewrites a
   * ledger row.
   *
   * `migrationPath` still names ONE file -- the initial schema -- because
   * every existing caller passes exactly that, and because the fault suite
   * proves drift by pointing the option at a deliberately corrupted copy in
   * a temporary directory. The remaining migrations are its SIBLINGS: any
   * `NNNN_*.sql` beside it, ordered by the version its name carries, with
   * the explicitly named file winning for its own version. So a real install
   * (whose file sits in the shipped `migrations/` directory) picks up every
   * later migration automatically, and a fault fixture pointing at a lone
   * corrupted file still exercises exactly the version it names.
   *
   * The set must be contiguous from 1. A gap means a build shipped without
   * a migration it depends on, and applying what is present would produce a
   * schema no version number describes.
   */
  #collectMigrations(migrationPath: string | URL): Array<{ path: string; version: number }> {
    const initialPath = migrationPath instanceof URL ? fileURLToPath(migrationPath) : migrationPath
    const versionOf = (name: string): number | null => {
      const matched = /^(\d{4})_[A-Za-z0-9_-]+\.sql$/.exec(name)
      return matched === null ? null : Number(matched[1])
    }
    const byVersion = new Map<number, string>()
    for (const entry of readdirSync(dirname(initialPath))) {
      const version = versionOf(entry)
      if (version !== null) byVersion.set(version, join(dirname(initialPath), entry))
    }
    // The explicitly named file is authoritative for its own version, so a
    // fault fixture's corrupted copy is what gets checksummed rather than a
    // pristine sibling of the same name.
    byVersion.set(versionOf(basename(initialPath)) ?? 1, initialPath)
    const ordered = [...byVersion.entries()]
      .map(([version, path]) => ({ path, version }))
      .sort((left, right) => left.version - right.version)
    ordered.forEach((migration, index) => {
      if (migration.version !== index + 1) {
        throw new Error(`migration set is not contiguous: expected version ${index + 1}, found ${migration.version}`)
      }
    })
    return ordered
  }

  #applyMigration(migrationPath: string | URL): void {
    const migrations = this.#collectMigrations(migrationPath)
    const ledgerPresent = (): boolean => this.#database.prepare(`
      SELECT 1 AS present FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations'
    `).get() !== undefined

    for (const migration of migrations) {
      const contents = readFileSync(migration.path, 'utf8')
      const checksum = createHash('sha256').update(contents).digest('hex')
      // Re-read each time: the ledger table is created BY migration 1, so it
      // is absent for the first iteration of a fresh database and present
      // for every one after it.
      if (ledgerPresent()) {
        const applied = this.#database.prepare(`
          SELECT checksum FROM schema_migrations WHERE version = ?
        `).get(migration.version) as { checksum: string } | undefined
        if (applied !== undefined) {
          if (applied.checksum !== checksum) {
            throw new Error(`migration checksum mismatch for version ${String(migration.version)}`)
          }
          continue
        }
      }

      this.#database.exec('BEGIN IMMEDIATE')
      try {
        this.#database.exec(contents)
        this.#database.prepare(`
          INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (?, ?, ?)
        `).run(migration.version, checksum, new Date().toISOString())
        this.#database.exec('COMMIT')
      } catch (error) {
        this.#database.exec('ROLLBACK')
        throw error
      }
    }

    // The other direction, checked only AFTER the known set validates so a
    // drifted file still reports drift: a ledger version this build carries
    // no migration for means the database was migrated by a NEWER Keepling.
    // Opening it anyway would let an older binary write rows a newer
    // schema's constraints were written to govern.
    if (!ledgerPresent()) return
    const ahead = this.#database.prepare(`
      SELECT version FROM schema_migrations WHERE version > ? ORDER BY version LIMIT 1
    `).get(migrations.length) as { version: number } | undefined
    if (ahead !== undefined) {
      throw new Error(
        `database schema version ${String(ahead.version)} is ahead of the ${String(migrations.length)} migrations this build carries`,
      )
    }
  }

  #validateMutation(mutation: PendingMutation): void {
    const fingerprint = createHash('sha256').update(mutation.commandBytes).digest('hex')
    if (fingerprint !== mutation.fingerprint) throw new Error('mutation fingerprint mismatch')
    const command = JSON.parse(mutation.commandBytes) as Record<string, unknown>
    if (
      command.mutation_id !== mutation.mutationId ||
      command.task_id !== mutation.taskId ||
      command.title !== mutation.title ||
      command.type !== 'capture_task' ||
      command.version !== 1
    ) {
      // `version` is checked here and not only at the transport, because
      // bytes the server will refuse must never reach the outbox in the
      // first place: an unpushable command sits there forever, reported as
      // "Saved on this Mac", with nothing ever able to settle it.
      throw new Error('immutable command bytes do not match mutation fields')
    }
  }

  /**
   * O-41 outbound guard, the same discipline `#validateMutation` applies to
   * a capture and for the same reason: bytes a server will refuse must
   * never reach the outbox in the first place. An unpushable command sits
   * there forever, reported as "Saved on this Mac", with nothing ever able
   * to settle it -- which is exactly how the missing `version` (O-34)
   * would have poisoned every queue on every Mac had a real server not
   * finally been pointed at.
   *
   * The type must also be one the CALLER expects. A `trash_task` body
   * arriving through `editTask` is a client bug, and the server would
   * answer 400 on the discriminator anyway; refusing it here keeps the
   * failure loud and local instead of durable and remote.
   */
  #validateOutbound(mutation: SyncMutation, taskId: string, allowedTypes: readonly string[]): void {
    const fingerprint = createHash('sha256').update(mutation.commandBytes).digest('hex')
    const command = JSON.parse(mutation.commandBytes) as Record<string, unknown>
    if (
      fingerprint !== mutation.fingerprint ||
      command.mutation_id !== mutation.mutationId ||
      command.task_id !== taskId ||
      mutation.effect.entityId !== taskId ||
      command.version !== 1 ||
      typeof command.type !== 'string' ||
      !allowedTypes.includes(command.type) ||
      typeof command.expected_revision !== 'number' ||
      !Number.isSafeInteger(command.expected_revision) ||
      command.expected_revision < 1 ||
      mutation.resourceKeys.length === 0 ||
      new Set(mutation.resourceKeys).size !== mutation.resourceKeys.length
    ) {
      throw new Error('outbound command bytes do not match the mutation being recorded')
    }
  }

  /**
   * O-45. `UndoTaskCommand` publishes NO `task_id` and NO
   * `expected_revision` -- the server resolves both from the handle it
   * minted, and `decode_undo` compares the key set exactly, so either extra
   * key is a 400. The guard is therefore its own, and checks the two things
   * that CAN be checked: the bytes are the exact undo shape, and the task
   * this Mac is queueing it against is the task whose action is being
   * undone (which is what makes the `task:<id>` resource key an honest
   * ordering key rather than a label).
   */
  #validateOutboundUndo(mutation: SyncMutation, taskId: string): void {
    const fingerprint = createHash('sha256').update(mutation.commandBytes).digest('hex')
    const command = JSON.parse(mutation.commandBytes) as Record<string, unknown>
    if (
      fingerprint !== mutation.fingerprint ||
      command.mutation_id !== mutation.mutationId ||
      command.type !== 'undo_task' ||
      command.version !== 1 ||
      typeof command.handle !== 'string' ||
      !/^[A-Za-z0-9_-]{43,128}$/.test(command.handle) ||
      Object.keys(command).length !== 4 ||
      mutation.effect.entityId !== taskId ||
      mutation.resourceKeys.length !== 1 ||
      mutation.resourceKeys[0] !== `task:${taskId}`
    ) {
      throw new Error('outbound undo command bytes do not match the action being undone')
    }
  }

  #validateSyncMutation(mutation: SyncMutation): void {
    const fingerprint = createHash('sha256').update(mutation.commandBytes).digest('hex')
    const command = JSON.parse(mutation.commandBytes) as Record<string, unknown>
    if (
      fingerprint !== mutation.fingerprint ||
      command.mutation_id !== mutation.mutationId ||
      mutation.resourceKeys.length === 0 ||
      new Set(mutation.resourceKeys).size !== mutation.resourceKeys.length
    ) throw new Error('invalid immutable synchronization mutation')
    for (const dependency of mutation.dependencies) {
      const found = this.#database.prepare(`
        SELECT 1 AS present FROM mutation_journal WHERE mutation_id = ?
      `).get(dependency)
      if (!found) throw new Error('orphan synchronization dependency')
    }
  }

  #rowToSyncMutation(row: MutationRow): SyncMutation {
    const dependencies = this.#database.prepare(`
      SELECT dependency_mutation_id FROM mutation_dependencies WHERE mutation_id = ?
      ORDER BY dependency_mutation_id
    `).all(row.mutation_id) as Array<{ dependency_mutation_id: string }>
    return {
      acceptedAt: row.accepted_at,
      commandBytes: row.command_bytes,
      dependencies: dependencies.map((entry) => entry.dependency_mutation_id),
      effect: {
        entityId: row.task_id,
        snapshot: JSON.parse(row.effect_snapshot_json ?? '{}') as SyncSnapshot,
      },
      fingerprint: row.fingerprint,
      mutationId: row.mutation_id,
      resourceKeys: JSON.parse(row.resource_keys_json ?? '[]') as string[],
    }
  }

  #upsertProjection(entityId: string, snapshot: SyncSnapshot, status: 'saved_on_this_mac' | 'synced'): void {
    const title = typeof snapshot.title === 'string' && snapshot.title.length > 0 ? snapshot.title : snapshot.id
    this.#database.prepare(`
      INSERT INTO visible_projection(task_id, title, sync_status) VALUES (?, ?, ?)
      ON CONFLICT(task_id) DO UPDATE SET title = excluded.title, sync_status = excluded.sync_status
    `).run(entityId, title, status)
  }

  #replayVisible(): void {
    const shadowRows = this.#database.prepare(`SELECT entity_id, snapshot_json FROM canonical_shadow`).all() as Array<{
      entity_id: string
      snapshot_json: string
    }>
    for (const row of shadowRows) this.#upsertProjection(row.entity_id, JSON.parse(row.snapshot_json) as SyncSnapshot, 'synced')
    const pending = this.readyOutboxInOrder()
    for (const mutation of pending) this.#upsertProjection(mutation.effect.entityId, mutation.effect.snapshot, 'saved_on_this_mac')
  }

  private readyOutboxInOrder(): SyncMutation[] {
    const rows = this.#database.prepare(`
      SELECT immutable_commands.accepted_at, immutable_commands.command_bytes,
             immutable_commands.fingerprint, immutable_commands.mutation_id,
             immutable_commands.task_id, immutable_commands.resource_keys_json,
             immutable_commands.effect_snapshot_json
      FROM outbox JOIN immutable_commands USING (mutation_id) ORDER BY outbox.sequence
    `).all() as MutationRow[]
    return rows.map((row) => this.#rowToSyncMutation(row))
  }

  #verifyInvariants(): void {
    const quickCheck = this.#database.prepare('PRAGMA quick_check').get() as { quick_check: string }
    const foreignKeys = this.#database.prepare('PRAGMA foreign_keys').get() as { foreign_keys: number }
    const journalMode = this.#database.prepare('PRAGMA journal_mode').get() as { journal_mode: string }
    const synchronous = this.#database.prepare('PRAGMA synchronous').get() as { synchronous: number }
    if (
      quickCheck.quick_check !== 'ok' ||
      foreignKeys.foreign_keys !== 1 ||
      journalMode.journal_mode.toLowerCase() !== 'wal' ||
      synchronous.synchronous !== 2
    ) {
      throw new Error('local store invariant check failed')
    }
  }
}

export { classifyStoreFailure, deriveLocalFilePaths, NodeSqliteLocalStore, removeLocalFilesAt }
export type { LocalStoreOptions, RetainedUndo, StoreFailureCode, UndoDropReason, UndoTarget }
