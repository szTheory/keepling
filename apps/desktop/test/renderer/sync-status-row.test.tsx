import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { deriveDesktopPresentation, type DesktopPresentationInput } from '../../main/application/presentation.ts'
import SyncStatusRow from '../../renderer/SyncStatusRow.tsx'

/**
 * O-42: no authored recovery action may cross IPC and die unread.
 *
 * The action list under test is not hand-written here -- it is derived by
 * running the SHIPPED `deriveDesktopPresentation` over every presentation
 * input that has a production construction site, and collecting the codes
 * it actually authors. So an action added to `presentation.ts` tomorrow is
 * covered by these cases the moment it exists, rather than the day someone
 * remembers to extend a list. That is the difference between a test and a
 * transcription.
 */

const productionInputs: DesktopPresentationInput[] = [
  { kind: 'opening' },
  { kind: 'updating', startedAt: 0 },
  { kind: 'offline' },
  { kind: 'retryable_failure', pendingCount: 2 },
  { kind: 'local_saved', pendingCount: 1 },
  { affectedCount: 1, kind: 'rejected' },
  { affectedCount: 1, kind: 'conflict' },
  { kind: 'authentication_required' },
  { kind: 'namespace_mismatch', pendingCount: 3 },
  { kind: 'local_save_failure' },
  { kind: 'store_unavailable' },
]

const authoredCodes = [
  ...new Set(
    productionInputs.flatMap((input) =>
      // `updating` resolves to a quiet `healthy` row inside the grace
      // period, so it is derived past it to reach its real actions.
      deriveDesktopPresentation(input, 1, 10_000).summary.actions.map((action) => action.code),
    ),
  ),
].sort()

type Bridge = Record<string, ReturnType<typeof vi.fn>> & { subscribePresentation: ReturnType<typeof vi.fn> }

const installBridge = (): { bridge: Bridge; publish: (input: DesktopPresentationInput) => void } => {
  let subscriber: ((presentation: unknown) => void) | null = null
  let sequence = 0
  const bridge = {
    beginSignIn: vi.fn(async () => ({ state: 'authorizing' })),
    exportLocalData: vi.fn(async () => ({ kind: 'exported', path: '/tmp/Keepling-export.json', taskCount: 4 })),
    listConflicts: vi.fn(async () => []),
    removeLocalData: vi.fn(async () => ({ conflictedCount: 0, kind: 'blocked_pending_intent', pendingCount: 2 })),
    retrySync: vi.fn(async () => ({ kind: 'ran', pulled: 0, settled: 1 })),
    snapshot: vi.fn(async () => ({ tasks: [] })),
    subscribePresentation: vi.fn((next: (presentation: unknown) => void) => {
      subscriber = next
      return () => {
        subscriber = null
      }
    }),
  } as unknown as Bridge
  ;(globalThis as unknown as { window: { keepling: unknown } }).window.keepling = bridge
  return {
    bridge,
    publish: (input) => {
      sequence += 1
      subscriber?.(deriveDesktopPresentation(input, sequence, 10_000))
    },
  }
}

describe('recovery actions reaching a person (O-42)', () => {
  let container: HTMLDivElement
  let root: Root

  beforeEach(() => {
    container = document.createElement('div')
    document.body.append(container)
    root = createRoot(container)
  })

  afterEach(() => {
    act(() => root.unmount())
    container.remove()
  })

  const buttons = () => Array.from(container.querySelectorAll<HTMLButtonElement>('button'))

  it('every state that authors actions renders them, verbatim, in order', () => {
    const { publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))

    for (const input of productionInputs) {
      const expected = deriveDesktopPresentation(input, 1, 10_000).summary
      if (expected.copy === null) continue
      act(() => publish(input))
      expect(buttons().map((button) => button.dataset.recoveryAction)).toEqual(
        expected.actions.map((action) => action.code),
      )
      expect(buttons().map((button) => button.textContent)).toEqual(
        expected.actions.map((action) => action.label),
      )
    }
  })

  it('renders nothing at all for a quiet row', () => {
    const { publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ kind: 'healthy' }))
    expect(container.querySelector('#sync-status-row')).toBeNull()
  })

  it.each(authoredCodes)('the %s action reaches a real capability', async (code) => {
    const { bridge, publish } = installBridge()
    const recovery = document.createElement('div')
    recovery.id = 'sync-recovery-region'
    recovery.tabIndex = -1
    document.body.append(recovery)
    act(() => root.render(<SyncStatusRow />))

    const input = productionInputs.find((candidate) =>
      deriveDesktopPresentation(candidate, 1, 10_000).summary.actions.some((action) => action.code === code),
    )!
    act(() => publish(input))
    const button = buttons().find((candidate) => candidate.dataset.recoveryAction === code)!
    expect(button, `no button rendered for ${code}`).toBeDefined()

    await act(async () => {
      button.click()
      await Promise.resolve()
    })

    // Every code either reaches a named main-process capability or moves
    // focus to the recovery region. A code that did neither would be a
    // button that looks live and is not -- the O-42 defect itself.
    const reachedMain = [
      bridge.beginSignIn,
      bridge.exportLocalData,
      bridge.listConflicts,
      bridge.removeLocalData,
      bridge.retrySync,
      bridge.snapshot,
    ].some((spy) => spy.mock.calls.length > 0)
    expect(reachedMain || document.activeElement === recovery, `${code} did nothing`).toBe(true)
    recovery.remove()
  })

  it('signs in through the system browser, never by collecting anything here', async () => {
    const { bridge, publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ kind: 'authentication_required' }))

    // No credential-entry field may exist in any Electron renderer.
    expect(container.querySelectorAll('input')).toHaveLength(0)
    await act(async () => {
      buttons()[0]!.click()
      await Promise.resolve()
    })
    expect(bridge.beginSignIn).toHaveBeenCalledWith()
  })

  it('never confirms an irreversible removal from a single press', async () => {
    const { bridge, publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ kind: 'namespace_mismatch', pendingCount: 2 }))

    await act(async () => {
      buttons().find((button) => button.dataset.recoveryAction === 'remove_local_data')!.click()
      await Promise.resolve()
    })
    expect(bridge.removeLocalData).toHaveBeenCalledWith({ confirmRemoveAnyway: false })
    expect(container.querySelector('[data-recovery-result]')?.textContent).toContain(
      '2 changes have not reached a server yet',
    )
  })

  it('exports before offering removal, and says where the file went', async () => {
    const { bridge, publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ kind: 'namespace_mismatch', pendingCount: 2 }))

    await act(async () => {
      buttons().find((button) => button.dataset.recoveryAction === 'export')!.click()
      await Promise.resolve()
    })
    expect(bridge.exportLocalData).toHaveBeenCalledWith()
    expect(container.querySelector('[data-recovery-result]')?.textContent).toContain(
      'Exported 4 tasks to /tmp/Keepling-export.json',
    )
  })

  it('refreshes from the server when a conflict has no mine/current chooser', async () => {
    const { bridge, publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ affectedCount: 1, kind: 'conflict' }))

    await act(async () => {
      buttons()[0]!.click()
      await Promise.resolve()
      await Promise.resolve()
    })
    expect(bridge.listConflicts).toHaveBeenCalled()
    expect(bridge.retrySync).toHaveBeenCalled()
  })

  it('is not a second live region', () => {
    // The workspace contract pins exactly one announcer
    // (test/e2e/accessibility.spec.ts:112). A second one would interrupt
    // whatever someone is typing on every background sync change.
    const { publish } = installBridge()
    act(() => root.render(<SyncStatusRow />))
    act(() => publish({ kind: 'retryable_failure', pendingCount: 1 }))
    expect(container.querySelectorAll('[aria-live], [role="status"], [role="alert"]')).toHaveLength(0)
  })
})
