import { describe, expect, it } from 'vitest'

import {
  DesktopApplication,
  type LocalAcceptance,
  type LocalStorePort,
  type PendingMutation,
  type QuickEntryDraft,
  type SyncAcknowledgement,
  type WorkspaceSnapshot,
} from '../../main/application/DesktopApplication.ts'

const emptySnapshot = (): WorkspaceSnapshot => ({ tasks: [] })

/**
 * A minimal LocalStorePort double that supports draft/shortcut methods,
 * proving DesktopApplication delegates correctly (D-03/D-09/D-11) and
 * never publishes a "Saved on this Mac" presentation update for a draft --
 * a draft carries no durability claim of its own.
 */
class DraftAwareStore implements LocalStorePort {
  draft: QuickEntryDraft | null = null
  shortcut: string | null = null

  async acceptCapture(): Promise<LocalAcceptance> {
    throw new Error('not exercised in this test')
  }

  async acknowledge(): Promise<WorkspaceSnapshot> {
    return emptySnapshot()
  }

  async pendingMutations(): Promise<PendingMutation[]> {
    return []
  }

  async snapshot(): Promise<WorkspaceSnapshot> {
    return emptySnapshot()
  }

  async saveDraft(draft: QuickEntryDraft): Promise<void> {
    this.draft = draft
  }

  async getDraft(): Promise<QuickEntryDraft | null> {
    return this.draft
  }

  async clearDraft(): Promise<void> {
    this.draft = null
  }

  async getShortcutPreference(): Promise<string | null> {
    return this.shortcut
  }

  async setShortcutPreference(accelerator: string): Promise<void> {
    this.shortcut = accelerator
  }

  async close(): Promise<void> {}
}

const buildApplication = (store: LocalStorePort) =>
  new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    identity: { randomId: () => 'unused-id' },
    localStore: store,
    sync: { acknowledge: async () => null },
  })

describe('DesktopApplication quick entry draft', () => {
  it('has no draft until one is saved', async () => {
    const application = buildApplication(new DraftAwareStore())
    expect(await application.getDraft()).toBeNull()
  })

  it('saves and returns a nonempty draft without publishing a "Saved on this Mac" presentation', async () => {
    const store = new DraftAwareStore()
    const application = buildApplication(store)
    await application.saveDraft({ addToToday: true, title: 'Call dentist' })
    expect(await application.getDraft()).toEqual({ addToToday: true, title: 'Call dentist' })
    expect(application.presentationSnapshot().summary.kind).toBe('opening')
  })

  it('rejects a draft title over 512 Unicode scalar values before reaching the store', async () => {
    const store = new DraftAwareStore()
    const application = buildApplication(store)
    await expect(application.saveDraft({ addToToday: false, title: 'x'.repeat(513) })).rejects.toThrow()
    expect(store.draft).toBeNull()
  })

  it('clears the draft only when explicitly asked', async () => {
    const store = new DraftAwareStore()
    const application = buildApplication(store)
    await application.saveDraft({ addToToday: false, title: 'Ephemeral' })
    await application.clearDraft()
    expect(await application.getDraft()).toBeNull()
  })

  it('throws when the local store has no draft support at all', async () => {
    class NoDraftStore implements LocalStorePort {
      async acceptCapture(): Promise<LocalAcceptance> {
        throw new Error('unused')
      }

      async acknowledge(): Promise<WorkspaceSnapshot> {
        return emptySnapshot()
      }

      async pendingMutations(): Promise<PendingMutation[]> {
        return []
      }

      async snapshot(): Promise<WorkspaceSnapshot> {
        return emptySnapshot()
      }

      async close(): Promise<void> {}
    }
    const application = buildApplication(new NoDraftStore())
    await expect(application.saveDraft({ addToToday: false, title: 'x' })).rejects.toThrow()
    expect(await application.getDraft()).toBeNull()
    await expect(application.clearDraft()).rejects.toThrow()
  })
})

describe('DesktopApplication quick entry shortcut preference', () => {
  it('persists and reads back a rebound accelerator', async () => {
    const application = buildApplication(new DraftAwareStore())
    expect(await application.getShortcutPreference()).toBeNull()
    await application.setShortcutPreference('Control+Alt+K')
    expect(await application.getShortcutPreference()).toBe('Control+Alt+K')
  })

  it('rejects an empty accelerator', async () => {
    const application = buildApplication(new DraftAwareStore())
    await expect(application.setShortcutPreference('')).rejects.toThrow()
  })
})
