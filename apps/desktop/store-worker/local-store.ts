import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { DatabaseSync } from 'node:sqlite'

import type {
  LocalAcceptance,
  PendingMutation,
  PullPage,
  SyncAcknowledgement,
  SyncMutation,
  SyncNamespace,
  SyncSnapshot,
  SyncState,
  WorkspaceSnapshot,
} from '../main/application/DesktopApplication.ts'

type LocalStoreOptions = {
  databasePath: string
  migrationPath: string | URL
}

type ProjectionRow = { sync_status: 'saved_on_this_mac' | 'synced'; task_id: string; title: string }
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

  constructor(options: LocalStoreOptions) {
    mkdirSync(dirname(options.databasePath), { recursive: true })
    this.#database = new DatabaseSync(options.databasePath, {
      allowExtension: false,
      defensive: true,
      timeout: 2_500,
    })
    this.#database.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;')
    this.#applyMigration(options.migrationPath)
    this.#verifyInvariants()
  }

  acceptCapture(mutation: PendingMutation): LocalAcceptance {
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
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
    }
  }

  applyPull(page: PullPage): void {
    if (!page.cursor || page.changes.length > 50) throw new Error('invalid bounded pull page')
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
      this.#database.prepare('UPDATE sync_cursor SET cursor = ? WHERE singleton = 1').run(page.cursor)
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

  syncState(): SyncState {
    const cursor = this.#database.prepare('SELECT cursor FROM sync_cursor WHERE singleton = 1').get() as { cursor: string | null }
    const outbox = this.#database.prepare('SELECT mutation_id FROM outbox ORDER BY sequence').all() as Array<{ mutation_id: string }>
    return {
      cursor: cursor.cursor,
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
      this.#database.prepare(`
        INSERT INTO canonical_shadow(entity_id, snapshot_json) VALUES (?, ?)
        ON CONFLICT(entity_id) DO UPDATE SET snapshot_json = excluded.snapshot_json
      `).run(pending.task_id, snapshotJson)
      this.#upsertProjection(pending.task_id, acknowledgement.snapshot, 'synced')
      this.#database.prepare(`
        UPDATE mutation_journal SET outcome = ?, terminal_snapshot_json = ? WHERE mutation_id = ?
      `).run(acknowledgement.outcome, snapshotJson, acknowledgement.mutationId)
      this.#database.prepare('DELETE FROM outbox WHERE mutation_id = ?').run(acknowledgement.mutationId)
      if (acknowledgement.outcome === 'conflict') {
        this.#database.prepare(`
          INSERT INTO conflicts(conflict_id, mutation_id, details_json) VALUES (?, ?, ?)
          ON CONFLICT(conflict_id) DO UPDATE SET details_json = excluded.details_json
        `).run(`conflict:${acknowledgement.mutationId}`, acknowledgement.mutationId, snapshotJson)
      }
      this.#replayVisible()
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
      SELECT task_id, title, sync_status FROM visible_projection ORDER BY rowid
    `).all() as ProjectionRow[]
    return {
      tasks: rows.map((row) => ({ id: row.task_id, syncStatus: row.sync_status, title: row.title })),
    }
  }

  close(): void {
    this.#database.close()
  }

  #applyMigration(migrationPath: string | URL): void {
    const migration = readFileSync(migrationPath, 'utf8')
    const checksum = createHash('sha256').update(migration).digest('hex')
    const hasLedger = this.#database.prepare(`
      SELECT 1 AS present FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations'
    `).get() !== undefined

    if (hasLedger) {
      const applied = this.#database.prepare(`
        SELECT checksum FROM schema_migrations WHERE version = 1
      `).get() as { checksum: string } | undefined
      if (applied?.checksum !== checksum) throw new Error('migration checksum mismatch for version 1')
      return
    }

    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#database.exec(migration)
      this.#database.prepare(`
        INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (1, ?, ?)
      `).run(checksum, new Date().toISOString())
      this.#database.exec('COMMIT')
    } catch (error) {
      this.#database.exec('ROLLBACK')
      throw error
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
      command.type !== 'capture_task'
    ) {
      throw new Error('immutable command bytes do not match mutation fields')
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

export { NodeSqliteLocalStore }
export type { LocalStoreOptions }
