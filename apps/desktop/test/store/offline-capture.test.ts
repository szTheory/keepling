import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'

import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-offline-capture-'))
  roots.push(root)
  return {
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  }
}

const mutation = {
  acceptedAt: '2026-09-02T12:00:00.000Z',
  commandBytes: '{"mutation_id":"mutation-store","task_id":"task-store","title":"Survive relaunch","type":"capture_task"}',
  fingerprint: '3d0e9b4de22bda0fbe46695da1a512900c389b2630e44afc5ac0cdaab2d8465e',
  mutationId: 'mutation-store',
  taskId: 'task-store',
  title: 'Survive relaunch',
} as const

describe('NodeSqliteLocalStore', () => {
  it('atomically restores projection and immutable outbox after close and reopen', () => {
    const paths = fixture()
    const first = new NodeSqliteLocalStore(paths)
    expect(first.acceptCapture(mutation).status).toBe('local_saved')
    first.close()

    const reopened = new NodeSqliteLocalStore(paths)
    expect(reopened.snapshot()).toEqual({
      tasks: [{ id: 'task-store', syncStatus: 'saved_on_this_mac', title: 'Survive relaunch' }],
    })
    expect(reopened.pendingMutations()).toEqual([mutation])
    reopened.close()
  })

  it('refuses migration checksum drift without resetting retained state', () => {
    const paths = fixture()
    const store = new NodeSqliteLocalStore(paths)
    store.acceptCapture(mutation)
    store.close()

    const changedMigration = join(new URL('.', paths.migrationPath).pathname, 'changed.sql')
    writeFileSync(changedMigration, `${readFileSync(paths.migrationPath, 'utf8')}\n-- drift\n`)
    expect(() => new NodeSqliteLocalStore({ ...paths, migrationPath: changedMigration })).toThrow(
      /migration checksum mismatch/,
    )

    const retained = new NodeSqliteLocalStore(paths)
    expect(retained.snapshot().tasks).toHaveLength(1)
    retained.close()
  })
})
