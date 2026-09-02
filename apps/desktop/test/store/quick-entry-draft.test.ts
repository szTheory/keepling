import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'

import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

/**
 * Quick Entry draft and shortcut-preference persistence (D-03/D-09/D-11).
 * A draft is deliberately NOT a task mutation -- these tests assert it
 * survives close/reopen (utility-window recreation and app relaunch) without
 * ever appearing in immutable_commands/outbox, and that only an explicit
 * clearDraft() removes it.
 */
const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-quick-entry-draft-'))
  roots.push(root)
  return {
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath: new URL('../../migrations/0001_initial.sql', import.meta.url),
  }
}

describe('NodeSqliteLocalStore quick entry draft', () => {
  it('has no draft by default', () => {
    const store = new NodeSqliteLocalStore(fixture())
    expect(store.getDraft()).toBeNull()
    store.close()
  })

  it('persists a nonempty draft across close and reopen (survives utility-window recreation)', () => {
    const paths = fixture()
    const first = new NodeSqliteLocalStore(paths)
    first.saveDraft({ addToToday: true, title: 'Call dentist' })
    first.close()

    const reopened = new NodeSqliteLocalStore(paths)
    expect(reopened.getDraft()).toEqual({ addToToday: true, title: 'Call dentist' })
    reopened.close()
  })

  it('overwrites the previous draft rather than accumulating history', () => {
    const store = new NodeSqliteLocalStore(fixture())
    store.saveDraft({ addToToday: false, title: 'First draft' })
    store.saveDraft({ addToToday: true, title: 'Second draft' })
    expect(store.getDraft()).toEqual({ addToToday: true, title: 'Second draft' })
    store.close()
  })

  it('only removes the draft on explicit clearDraft (Discard Draft)', () => {
    const store = new NodeSqliteLocalStore(fixture())
    store.saveDraft({ addToToday: false, title: 'Ephemeral' })
    expect(store.getDraft()).not.toBeNull()
    store.clearDraft()
    expect(store.getDraft()).toBeNull()
    store.close()
  })

  it('never appears as a task mutation: capture is unaffected by an open draft', () => {
    const store = new NodeSqliteLocalStore(fixture())
    store.saveDraft({ addToToday: false, title: 'Draft only, never a task' })
    const snapshot = store.snapshot()
    expect(snapshot.tasks).toHaveLength(0)
    store.close()
  })

  it('rejects a draft title over 512 Unicode scalar values', () => {
    const store = new NodeSqliteLocalStore(fixture())
    expect(() => store.saveDraft({ addToToday: false, title: 'x'.repeat(513) })).toThrow()
    store.close()
  })
})

describe('NodeSqliteLocalStore quick entry shortcut preference', () => {
  it('has no configured preference by default (falls back to the D-10 default elsewhere)', () => {
    const store = new NodeSqliteLocalStore(fixture())
    expect(store.getShortcutPreference()).toBeNull()
    store.close()
  })

  it('persists a rebound shortcut across close and reopen', () => {
    const paths = fixture()
    const first = new NodeSqliteLocalStore(paths)
    first.setShortcutPreference('Control+Alt+K')
    first.close()

    const reopened = new NodeSqliteLocalStore(paths)
    expect(reopened.getShortcutPreference()).toBe('Control+Alt+K')
    reopened.close()
  })

  it('rejects an empty accelerator', () => {
    const store = new NodeSqliteLocalStore(fixture())
    expect(() => store.setShortcutPreference('')).toThrow()
    store.close()
  })
})
