import { describe, expect, it } from 'vitest'

import {
  deriveDesktopPresentation,
  sanitizeDesktopDiagnostic,
  type DesktopPresentationInput,
} from '../../main/application/presentation.ts'
import { desktopPresentationSchema } from '../../preload/contracts.ts'

const now = Date.parse('2026-09-02T12:10:00.000Z')

const fixtures: Array<{
  actionCodes: string[]
  copy: string | null
  input: DesktopPresentationInput
  kind: string
}> = [
  { actionCodes: [], copy: null, input: { kind: 'healthy', lastSuccessfulContact: '10 minutes ago' }, kind: 'healthy' },
  { actionCodes: [], copy: 'Opening your tasks…', input: { kind: 'opening' }, kind: 'opening' },
  { actionCodes: [], copy: 'Preparing your tasks for offline use…', input: { kind: 'preparing' }, kind: 'preparing' },
  { actionCodes: [], copy: null, input: { kind: 'updating', startedAt: now - 2_999 }, kind: 'healthy' },
  { actionCodes: ['inspect'], copy: 'Updating…', input: { kind: 'updating', startedAt: now - 3_000 }, kind: 'updating' },
  { actionCodes: [], copy: 'Offline — showing tasks saved on this Mac', input: { kind: 'offline', lastSuccessfulContact: '10 minutes ago' }, kind: 'offline' },
  { actionCodes: ['retry'], copy: 'Couldn’t reach the server. Your changes stay on this Mac.', input: { kind: 'retryable_failure', pendingCount: 4 }, kind: 'retryable_failure' },
  { actionCodes: [], copy: 'Saved on this Mac. Sync when you’re back online', input: { kind: 'local_saved', pendingCount: 1 }, kind: 'local_saved' },
  { actionCodes: ['check_again'], copy: 'Checking whether this change was accepted…', input: { kind: 'uncertain', pendingCount: 1 }, kind: 'uncertain' },
  { actionCodes: ['review'], copy: 'The server didn’t accept this change. Your version is still on this Mac.', input: { kind: 'rejected', affectedCount: 1 }, kind: 'rejected' },
  { actionCodes: ['review_conflict'], copy: 'This task changed somewhere else. Choose what to keep. Other tasks can continue.', input: { kind: 'conflict', affectedCount: 2 }, kind: 'conflict' },
  { actionCodes: ['sign_in'], copy: 'Sign in to continue syncing. Changes remain safe on this Mac.', input: { kind: 'authentication_required', pendingCount: 3 }, kind: 'authentication_required' },
  { actionCodes: ['inspect', 'export', 'remove_local_data'], copy: 'These changes belong to a different account or server and won’t be sent here.', input: { kind: 'namespace_mismatch', pendingCount: 2 }, kind: 'namespace_mismatch' },
  { actionCodes: ['retry_save'], copy: 'Couldn’t save this change on this Mac. Keep this window open and try again.', input: { kind: 'local_save_failure' }, kind: 'local_save_failure' },
  { actionCodes: ['retry_opening', 'show_recovery_options'], copy: 'Keepling can’t open the tasks saved on this Mac. Your data was not replaced or removed.', input: { kind: 'store_unavailable' }, kind: 'store_unavailable' },
]

describe('desktop recovery presentation', () => {
  for (const [index, fixture] of fixtures.entries()) {
    it(`publishes exact closed row ${fixture.kind} without renderer inference`, () => {
      const presentation = deriveDesktopPresentation(fixture.input, index + 1, now)
      expect(desktopPresentationSchema.parse(presentation)).toEqual(presentation)
      expect(presentation.sequence).toBe(index + 1)
      expect(presentation.summary.kind).toBe(fixture.kind)
      expect(presentation.summary.copy).toBe(fixture.copy)
      expect(presentation.summary.actions.map((action) => action.code)).toEqual(fixture.actionCodes)
      expect(presentation.surfaces.shell).toEqual(presentation.summary)
      expect(presentation.surfaces.row).toEqual(presentation.summary)
      expect(presentation.surfaces.panel).toEqual(presentation.summary)
      expect(JSON.stringify(presentation)).not.toMatch(/outbox|cursor|fingerprint|sqlite|ipc|transport/i)
      expect(JSON.stringify(presentation)).not.toContain('Everything synced')
    })
  }

  it('bounds counts and admits only privacy-safe diagnostics', () => {
    const presentation = deriveDesktopPresentation({ kind: 'authentication_required', pendingCount: 99_999 }, 20, now)
    expect(presentation.summary.count).toBe(99)
    expect(() => sanitizeDesktopDiagnostic({ operation: 'sync_pass', outcome: 'retryable_failure', processRole: 'main', timingMs: 12_345 })).not.toThrow()
    for (const forbidden of ['title', 'notes', 'token', 'cursor', 'fingerprint', 'serverUrl', 'databasePath', 'identifier']) {
      expect(() => sanitizeDesktopDiagnostic({ operation: 'sync_pass', outcome: 'ready', processRole: 'main', [forbidden]: 'private' })).toThrow()
    }
  })
})
