import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { DatabaseSync } from 'node:sqlite'

import type {
  LocalAcceptance,
  PendingMutation,
  SyncAcknowledgement,
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
        INSERT INTO immutable_commands(mutation_id, task_id, command_bytes, fingerprint, accepted_at)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        mutation.mutationId,
        mutation.taskId,
        mutation.commandBytes,
        mutation.fingerprint,
        mutation.acceptedAt,
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
      this.#database.prepare(`
        UPDATE visible_projection SET title = ?, sync_status = 'synced' WHERE task_id = ?
      `).run(acknowledgement.snapshot.title, pending.task_id)
      this.#database.prepare(`
        UPDATE mutation_journal SET outcome = ?, terminal_snapshot_json = ? WHERE mutation_id = ?
      `).run(acknowledgement.outcome, snapshotJson, acknowledgement.mutationId)
      this.#database.prepare('DELETE FROM outbox WHERE mutation_id = ?').run(acknowledgement.mutationId)
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
