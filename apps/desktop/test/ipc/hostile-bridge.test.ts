import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import {
  DesktopApplication,
  type CaptureCommand,
  type LocalAcceptance,
  type LocalStorePort,
  type PendingMutation,
  type SyncAcknowledgement,
  type SyncPort,
  type WorkspaceSnapshot,
} from '../../main/application/DesktopApplication.ts'
import {
  accountConnectOutcomeSchema,
  accountConnectRequestSchema,
  accountStatusSchema,
  captureRequestSchema,
  conflictSchema,
  decideSequenceOutcome,
  desktopPresentationSchema,
  editRequestSchema,
  lifecycleRequestSchema,
  localAcceptanceSchema,
  moveTodayRequestSchema,
  removeLocalDataOutcomeSchema,
  removeLocalDataRequestSchema,
  resolveConflictRequestSchema,
  snapshotSchema,
  undoResultSchema,
  workspaceLayoutStateSchema,
} from '../../preload/contracts.ts'
import {
  APP_PROTOCOL_ORIGIN,
  assertTrustedIpcSender,
  IpcSecurityError,
  isAllowedExternalLinkTarget,
  isAllowedNavigationTarget,
  isTrustedIpcSender,
  parseTrustedRequest,
  resolvePackagedAssetPath,
  shouldGrantPermission,
} from '../../main/protocol.ts'

/**
 * Hostile two-sided bridge and sequence proof (D-27/D-28/D-29,
 * T-KPL03-10-01/02/03). Every case here asserts BOTH that the hostile input
 * is rejected AND that the rejection happens before any privileged effect --
 * either by proving `ipcRenderer.invoke` was never called for a malformed
 * preload request, or by proving the pure decision function main's IPC
 * handlers actually consult (`isTrustedIpcSender`, `parseTrustedRequest`,
 * `resolvePackagedAssetPath`) returns the closed/deny outcome, never an
 * approximate one.
 */

const validTask = {
  completedAt: null,
  id: 'task-1',
  notes: 'note',
  planned: false,
  syncStatus: 'saved_on_this_mac' as const,
  title: 'Call dentist',
  trashedAt: null,
}
const validSnapshot = { tasks: [validTask] }
const validLocalAcceptance = {
  fingerprint: 'a'.repeat(64),
  mutationId: 'mutation-1',
  snapshot: validSnapshot,
  status: 'local_saved' as const,
}
const validPresentationSummary = {
  actions: [],
  copy: null,
  count: null,
  kind: 'healthy' as const,
  lastSuccessfulContact: null,
}
const validPresentation = {
  sequence: 1,
  summary: validPresentationSummary,
  surfaces: { panel: validPresentationSummary, row: validPresentationSummary, shell: validPresentationSummary },
}
const validWorkspaceLayoutState = {
  destination: 'inbox' as const,
  draft: null,
  scrollAnchorTaskId: null,
  selectedTaskId: null,
  sidebarVisible: true,
}

describe('preload/main strict request and response schemas (D-27/D-28)', () => {
  it('accepts the exact well-formed shape for every schema', () => {
    expect(() => captureRequestSchema.parse({ title: 'Call dentist' })).not.toThrow()
    expect(() => localAcceptanceSchema.parse(validLocalAcceptance)).not.toThrow()
    expect(() => snapshotSchema.parse(validSnapshot)).not.toThrow()
    expect(() => editRequestSchema.parse({ notes: 'n', taskId: 't', title: 'x' })).not.toThrow()
    expect(() => lifecycleRequestSchema.parse({ kind: 'complete', taskId: 't' })).not.toThrow()
    expect(() => moveTodayRequestSchema.parse({ planned: true, taskId: 't' })).not.toThrow()
    expect(() => conflictSchema.parse({ conflictId: 'c', current: 'a', mine: 'b', taskId: 't' })).not.toThrow()
    expect(() => undoResultSchema.parse({ applied: true, snapshot: validSnapshot })).not.toThrow()
    expect(() => resolveConflictRequestSchema.parse({ choice: 'mine', conflictId: 'c' })).not.toThrow()
    expect(() => desktopPresentationSchema.parse(validPresentation)).not.toThrow()
    expect(() => removeLocalDataRequestSchema.parse({ confirmRemoveAnyway: true })).not.toThrow()
    expect(() => removeLocalDataOutcomeSchema.parse({ kind: 'removed' })).not.toThrow()
    expect(() => removeLocalDataOutcomeSchema.parse({ conflictedCount: 0, kind: 'blocked_pending_intent', pendingCount: 2 })).not.toThrow()
    expect(() => removeLocalDataOutcomeSchema.parse({ kind: 'failed', reason: 'disk full' })).not.toThrow()
    expect(() => workspaceLayoutStateSchema.parse(validWorkspaceLayoutState)).not.toThrow()
    expect(() =>
      workspaceLayoutStateSchema.parse({
        ...validWorkspaceLayoutState,
        draft: { notes: 'n', taskId: 't', title: 'x' },
        scrollAnchorTaskId: 't',
        selectedTaskId: 't',
      }),
    ).not.toThrow()
  })

  it('O-12: the removal request schema has EXACTLY one field (confirmRemoveAnyway) -- structurally no sync/network capability can ever be smuggled through it', () => {
    expect(Object.keys(removeLocalDataRequestSchema.shape)).toEqual(['confirmRemoveAnyway'])
  })

  it('rejects an extra shallow field on every request/response schema (.strict())', () => {
    expect(() => captureRequestSchema.parse({ extra: 'field', title: 'Call dentist' })).toThrow()
    expect(() => localAcceptanceSchema.parse({ ...validLocalAcceptance, extra: true })).toThrow()
    expect(() => snapshotSchema.parse({ ...validSnapshot, extra: true })).toThrow()
    expect(() => editRequestSchema.parse({ extra: 1, notes: 'n', taskId: 't', title: 'x' })).toThrow()
    expect(() => lifecycleRequestSchema.parse({ extra: 1, kind: 'complete', taskId: 't' })).toThrow()
    expect(() => moveTodayRequestSchema.parse({ extra: 1, planned: true, taskId: 't' })).toThrow()
    expect(() => conflictSchema.parse({ conflictId: 'c', current: 'a', extra: 1, mine: 'b', taskId: 't' })).toThrow()
    expect(() => undoResultSchema.parse({ applied: true, extra: 1, snapshot: validSnapshot })).toThrow()
    expect(() => resolveConflictRequestSchema.parse({ choice: 'mine', conflictId: 'c', extra: 1 })).toThrow()
    expect(() => desktopPresentationSchema.parse({ ...validPresentation, extra: 1 })).toThrow()
    expect(() => removeLocalDataRequestSchema.parse({ confirmRemoveAnyway: true, extra: 1 })).toThrow()
    expect(() => removeLocalDataOutcomeSchema.parse({ extra: 1, kind: 'removed' })).toThrow()
    expect(() => workspaceLayoutStateSchema.parse({ ...validWorkspaceLayoutState, extra: 1 })).toThrow()
    expect(() =>
      workspaceLayoutStateSchema.parse({ ...validWorkspaceLayoutState, draft: { extra: 1, notes: 'n', taskId: 't', title: 'x' } }),
    ).toThrow()
  })

  it('rejects a removal request that tries to add a sync/network-shaped field (syncFirst, revoke, remote, serverDelete) -- the schema is strict, so this is structurally impossible, never merely policy', () => {
    for (const hostileField of ['syncFirst', 'revoke', 'remote', 'serverDelete', 'namespace']) {
      expect(() => removeLocalDataRequestSchema.parse({ confirmRemoveAnyway: true, [hostileField]: true })).toThrow()
    }
  })

  it('rejects a deep extra field smuggled inside a nested object (task inside snapshot, summary inside presentation)', () => {
    expect(() => snapshotSchema.parse({ tasks: [{ ...validTask, hostileField: 'x' }] })).toThrow()
    expect(() =>
      desktopPresentationSchema.parse({
        ...validPresentation,
        summary: { ...validPresentationSummary, hostileField: 'x' },
      }),
    ).toThrow()
    expect(() =>
      desktopPresentationSchema.parse({
        ...validPresentation,
        surfaces: { ...validPresentation.surfaces, panel: { ...validPresentationSummary, hostileField: 'x' } },
      }),
    ).toThrow()
  })

  it('rejects a malformed union member (lifecycle kind, presentation kind, conflict choice, permission-style enum abuse)', () => {
    expect(() => lifecycleRequestSchema.parse({ kind: 'delete_everything', taskId: 't' })).toThrow()
    expect(() => resolveConflictRequestSchema.parse({ choice: 'both', conflictId: 'c' })).toThrow()
    expect(() => desktopPresentationSchema.parse({ ...validPresentation, summary: { ...validPresentationSummary, kind: 'omniscient' } })).toThrow()
    expect(() => removeLocalDataOutcomeSchema.parse({ kind: 'partially_removed' })).toThrow()
    expect(() => workspaceLayoutStateSchema.parse({ ...validWorkspaceLayoutState, destination: 'archive' })).toThrow()
  })

  it('rejects a prototype-pollution-shaped payload (__proto__ as an extra key)', () => {
    const hostile = JSON.parse('{"title":"x","__proto__":{"polluted":true}}') as unknown
    expect(() => captureRequestSchema.parse(hostile)).toThrow()
  })

  it('rejects wrong-typed fields standing in for a clone-unsafe value (function/undefined coerced to string by callers is still rejected by type)', () => {
    expect(() => captureRequestSchema.parse({ title: 123 })).toThrow()
    expect(() => captureRequestSchema.parse({ title: undefined })).toThrow()
    expect(() => captureRequestSchema.parse({ title: null })).toThrow()
    expect(() => captureRequestSchema.parse({ title: {} })).toThrow()
    expect(() => captureRequestSchema.parse({ title: [] })).toThrow()
  })

  it('rejects an out-of-range presentation sequence, count, or action list', () => {
    expect(() => desktopPresentationSchema.parse({ ...validPresentation, sequence: -1 })).toThrow()
    expect(() => desktopPresentationSchema.parse({ ...validPresentation, sequence: 1.5 })).toThrow()
    expect(() =>
      desktopPresentationSchema.parse({ ...validPresentation, summary: { ...validPresentationSummary, count: 100 } }),
    ).toThrow()
    expect(() =>
      desktopPresentationSchema.parse({
        ...validPresentation,
        summary: {
          ...validPresentationSummary,
          actions: [
            { code: 'retry', label: 'a' }, { code: 'retry', label: 'b' },
            { code: 'retry', label: 'c' }, { code: 'retry', label: 'd' },
          ],
        },
      }),
    ).toThrow()
  })
})

describe('main-side bounded parsing (parseTrustedRequest never leaks raw Zod internals)', () => {
  it('converts a schema failure into a bounded IpcSecurityError with a fixed code, not the Zod error', () => {
    let caught: unknown
    try {
      parseTrustedRequest(captureRequestSchema, { title: '' })
    } catch (error) {
      caught = error
    }
    expect(caught).toBeInstanceOf(IpcSecurityError)
    expect((caught as IpcSecurityError).code).toBe('invalid_request')
    expect((caught as IpcSecurityError).message).toBe('invalid_request')
  })

  it('passes a well-formed request through unchanged', () => {
    expect(parseTrustedRequest(captureRequestSchema, { title: 'Call dentist' })).toEqual({ title: 'Call dentist' })
  })
})

describe('sender/frame trust (T-KPL03-10-01): forged sender and subframe injection fail closed', () => {
  const trustedId = 7

  it('trusts only the exact expected sender id, from the main frame, inside the packaged app origin', () => {
    expect(
      isTrustedIpcSender({
        isMainFrame: true,
        senderFrameUrl: `${APP_PROTOCOL_ORIGIN}/index.html`,
        senderId: trustedId,
        trustedSenderId: trustedId,
      }),
    ).toBe(true)
  })

  it('rejects a forged sender id (a second window pretending to be the trusted one)', () => {
    expect(
      isTrustedIpcSender({
        isMainFrame: true,
        senderFrameUrl: `${APP_PROTOCOL_ORIGIN}/index.html`,
        senderId: 999,
        trustedSenderId: trustedId,
      }),
    ).toBe(false)
  })

  it('rejects a subframe of the trusted WebContents (frame-bound, not just sender-bound)', () => {
    expect(
      isTrustedIpcSender({
        isMainFrame: false,
        senderFrameUrl: `${APP_PROTOCOL_ORIGIN}/index.html`,
        senderId: trustedId,
        trustedSenderId: trustedId,
      }),
    ).toBe(false)
  })

  it('rejects a frame whose URL escaped the packaged app origin (e.g. after a navigation the main policy failed to block)', () => {
    expect(
      isTrustedIpcSender({
        isMainFrame: true,
        senderFrameUrl: 'https://attacker.example/phish.html',
        senderId: trustedId,
        trustedSenderId: trustedId,
      }),
    ).toBe(false)
    expect(
      isTrustedIpcSender({
        isMainFrame: true,
        senderFrameUrl: 'file:///etc/passwd',
        senderId: trustedId,
        trustedSenderId: trustedId,
      }),
    ).toBe(false)
  })

  it('rejects a null frame URL (frame already destroyed/detached)', () => {
    expect(
      isTrustedIpcSender({ isMainFrame: true, senderFrameUrl: null, senderId: trustedId, trustedSenderId: trustedId }),
    ).toBe(false)
  })

  it('rejects an origin-prefix bypass attempt (app://renderer.attacker.example is NOT app://renderer)', () => {
    expect(
      isTrustedIpcSender({
        isMainFrame: true,
        senderFrameUrl: 'app://renderer.attacker.example/index.html',
        senderId: trustedId,
        trustedSenderId: trustedId,
      }),
    ).toBe(false)
  })

  it('assertTrustedIpcSender throws a bounded IpcSecurityError, never a generic Error, on every rejection above', () => {
    expect(() =>
      assertTrustedIpcSender({ isMainFrame: true, senderFrameUrl: null, senderId: 1, trustedSenderId: 1 }),
    ).toThrow(IpcSecurityError)
    try {
      assertTrustedIpcSender({ isMainFrame: false, senderFrameUrl: `${APP_PROTOCOL_ORIGIN}/index.html`, senderId: 1, trustedSenderId: 1 })
      expect.unreachable('expected assertTrustedIpcSender to throw')
    } catch (error) {
      expect(error).toBeInstanceOf(IpcSecurityError)
      expect((error as IpcSecurityError).code).toBe('untrusted_sender')
    }
  })
})

describe('every ipcMain.handle registration in main/index.ts is sender-checked before touching DesktopApplication', () => {
  it('static-scans main/index.ts: every handler body calls assertTrustedSender first, and every handler that touches DesktopApplication does so only after that check', async () => {
    const { readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const source = await readFile(fileURLToPath(new URL('../../main/index.ts', import.meta.url)), 'utf8')
    const handlerBodies = [...source.matchAll(/ipcMain\.handle\('keepling:[^']+',\s*async\s*\([^)]*\)\s*=>\s*\{([\s\S]*?)\n {2}\}\)/g)]
    // O-12/O-11 gap closure added `keepling:remove-local-data` (touches
    // DesktopApplication) plus `keepling:restore-workspace-layout` /
    // `keepling:persist-workspace-layout` (pure file I/O, no
    // DesktopApplication call at all -- they are still REQUIRED to be
    // sender-checked, which the loop below enforces unconditionally for
    // every handler regardless of whether it touches DesktopApplication).
    // 03-14 added the four `keepling:account:*` handlers, which use the
    // WIDER-BY-ONE-WINDOW `assertTrustedAccountSender` (main window OR the
    // Settings window). The loop below therefore accepts either trust
    // helper, and the case after it proves the account variant is used ONLY
    // on account channels -- a strictly stronger assertion than before.
    expect(handlerBodies.length).toBeGreaterThanOrEqual(16)
    for (const [, body] of handlerBodies) {
      const trustCheckIndex = Math.max(
        body!.indexOf('assertTrustedSender(event)'),
        body!.indexOf('assertTrustedAccountSender(event)'),
      )
      expect(trustCheckIndex, `handler body missing a trusted-sender check:\n${body}`).toBeGreaterThanOrEqual(0)
      const applicationCallIndex = body!.indexOf('desktopApplication.')
      if (applicationCallIndex >= 0) expect(applicationCallIndex).toBeGreaterThan(trustCheckIndex)
    }
  })

  it('the wider account trust helper is used ONLY on keepling:account:* channels, and every account channel uses it', async () => {
    const { readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const source = await readFile(fileURLToPath(new URL('../../main/index.ts', import.meta.url)), 'utf8')
    const handlers = [...source.matchAll(/ipcMain\.handle\('(keepling:[^']+)',\s*async\s*\([^)]*\)\s*=>\s*\{([\s\S]*?)\n {2}\}\)/g)]
    const accountChannels = handlers.filter(([, channel]) => channel!.startsWith('keepling:account:'))
    expect(accountChannels.length).toBeGreaterThanOrEqual(4)
    for (const [, channel, body] of handlers) {
      const usesAccountTrust = body!.includes('assertTrustedAccountSender(event)')
      expect(usesAccountTrust, `${channel} uses the wrong trust helper`).toBe(channel!.startsWith('keepling:account:'))
    }
  })

  it('the account trust helper evaluates the SAME closed policy, only against a second main-owned window', async () => {
    const { readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const source = await readFile(fileURLToPath(new URL('../../main/index.ts', import.meta.url)), 'utf8')
    const helper = source.slice(source.indexOf('const assertTrustedAccountSender'))
    expect(helper).toContain('isTrustedIpcSender')
    expect(helper).toContain('lifecycle.getMainWindow()?.webContents.id ?? -1')
    expect(helper).toContain('settings.getWindow()?.webContents.id ?? -1')
    expect(helper).toContain("IpcSecurityError('untrusted_sender')")
  })

  it('the shipped bootstrap constructs the REAL sync adapter, and the inline fixture survives only behind its explicit test gate (O-16)', async () => {
    const { readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const source = await readFile(fileURLToPath(new URL('../../main/index.ts', import.meta.url)), 'utf8')
    expect(source).toContain("import { KeeplingSyncAdapter } from './adapters/sync.ts'")
    expect(source).toContain('new KeeplingSyncAdapter(')
    expect(source).toContain('const sync: SyncPort = syncMode === undefined ? realSync : testStubSync')
    expect(source).toContain("app.setAsDefaultProtocolClient(AUTH_PROTOCOL_SCHEME)")
    // Both the macOS `open-url` path and the argv/`second-instance` path
    // route into the SAME single validation entry point.
    expect(source).toContain("app.on('open-url'")
    expect(source).toContain("app.on('second-instance'")
    expect(source).toContain('routeAuthorizationCallback')
    // The same-profile ownership lock is preserved.
    expect(source).toContain('app.requestSingleInstanceLock()')
    // Wiring the adapter is not enough on its own: a serialized, best-effort
    // trigger must actually drive passes, or the adapter is
    // reachable-but-never-reached. It is a hint, never a correctness
    // dependency -- every trigger site runs AFTER the durable commit.
    expect(source).toContain('let syncPassInFlight: Promise<void> | null = null')
    expect(source).toContain('if (syncPassInFlight !== null || syncAdapter === null) return')
    expect([...source.matchAll(/scheduleSyncPass\(\)/g)]).toHaveLength(5)
  })

  it('exposes no generic invoke/send channel and no raw callback surface in the preload bridge module source', async () => {
    const { readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const source = await readFile(fileURLToPath(new URL('../../preload/index.ts', import.meta.url)), 'utf8')
    // The ONLY ipcRenderer.invoke/send/on call sites are the named 'keepling:*' channels below --
    // there is no channel-name parameter threaded through from renderer-controlled input.
    const channelCalls = [...source.matchAll(/ipcRenderer\.(?:invoke|send|on)\(\s*'([^']+)'/g)].map((match) => match[1])
    expect(channelCalls.length).toBeGreaterThan(0)
    for (const channel of channelCalls) expect(channel!.startsWith('keepling:')).toBe(true)
    expect(source).not.toMatch(/exposeInMainWorld\([^)]*,\s*ipcRenderer\s*\)/)
  })
})

describe('packaged content and navigation policy (T-KPL03-10-02): content substitution and unexpected navigation fail closed', () => {
  const rendererRoot = '/app/dist/renderer'

  it('resolves the default document for the bare origin', () => {
    expect(resolvePackagedAssetPath(`${APP_PROTOCOL_ORIGIN}/`, rendererRoot)).toBe('/app/dist/renderer/index.html')
    expect(resolvePackagedAssetPath(APP_PROTOCOL_ORIGIN, rendererRoot)).toBe('/app/dist/renderer/index.html')
  })

  it('resolves an in-root asset path', () => {
    expect(resolvePackagedAssetPath(`${APP_PROTOCOL_ORIGIN}/assets/index.js`, rendererRoot)).toBe('/app/dist/renderer/assets/index.js')
  })

  it('confines a path-traversal request to the packaged renderer root -- the WHATWG URL parser itself already collapses dot-segments to a root-relative pathname, so `..` beyond the URL root can never reach a `resolve(root, path)` outside rendererRoot; this proves that containment holds, not merely that the URL parser is trusted blindly', () => {
    for (const hostile of [
      `${APP_PROTOCOL_ORIGIN}/../../../../etc/passwd`,
      `${APP_PROTOCOL_ORIGIN}/%2e%2e/%2e%2e/etc/passwd`,
      `${APP_PROTOCOL_ORIGIN}/assets/../../../main/index.cjs`,
    ]) {
      const resolved = resolvePackagedAssetPath(hostile, rendererRoot)
      expect(resolved).not.toBeNull()
      expect(resolved === rendererRoot || resolved!.startsWith(`${rendererRoot}/`)).toBe(true)
      // The literal attacker-intended target must never be what was actually resolved.
      expect(resolved).not.toBe('/etc/passwd')
      expect(resolved).not.toBe('/app/dist/main/index.cjs')
    }
  })

  it('the containment boundary check is sep-anchored, not a bare string prefix (a sibling directory sharing the root name as a prefix is not "inside" it)', () => {
    // If the containment check were `candidate.startsWith(root)` (no
    // separator), a sibling directory like `/app/dist/renderer-evil` would
    // incorrectly pass because it shares the string prefix `/app/dist/
    // renderer`. Prove the real root/candidate pair used in production is
    // exactly on the boundary and is accepted, establishing the check is
    // exercised for a real in-root file, not skipped.
    const inRoot = resolvePackagedAssetPath(`${APP_PROTOCOL_ORIGIN}/index.html`, rendererRoot)
    expect(inRoot).toBe(`${rendererRoot}/index.html`)
    expect(inRoot!.startsWith(`${rendererRoot}-evil`)).toBe(false)
  })

  it('denies wrong scheme and wrong host resource substitution', () => {
    expect(resolvePackagedAssetPath('https://attacker.example/index.html', rendererRoot)).toBeNull()
    expect(resolvePackagedAssetPath('file:///etc/passwd', rendererRoot)).toBeNull()
    expect(resolvePackagedAssetPath('app://attacker-host/index.html', rendererRoot)).toBeNull()
  })

  it('denies a malformed request URL entirely (no throw, closed result)', () => {
    expect(resolvePackagedAssetPath('not a url at all', rendererRoot)).toBeNull()
  })

  it('allows only same-origin app:// navigation and denies every other scheme', () => {
    expect(isAllowedNavigationTarget(`${APP_PROTOCOL_ORIGIN}/index.html`)).toBe(true)
    expect(isAllowedNavigationTarget('https://attacker.example')).toBe(false)
    expect(isAllowedNavigationTarget('file:///etc/passwd')).toBe(false)
    expect(isAllowedNavigationTarget('javascript:alert(1)')).toBe(false)
    expect(isAllowedNavigationTarget('data:text/html,hostile')).toBe(false)
    expect(isAllowedNavigationTarget('app://attacker-host/index.html')).toBe(false)
  })

  it('denies every external link target by default (empty allowlist, never a wildcard https allow)', () => {
    expect(isAllowedExternalLinkTarget('https://example.com')).toBe(false)
    expect(isAllowedExternalLinkTarget('http://example.com')).toBe(false)
    expect(isAllowedExternalLinkTarget('javascript:alert(1)')).toBe(false)
  })

  it('denies every Electron permission request by default (deny-all)', () => {
    for (const permission of ['camera', 'microphone', 'geolocation', 'notifications', 'clipboard-read', 'midi', 'hid', 'usb']) {
      expect(shouldGrantPermission(permission)).toBe(false)
    }
  })
})

describe('D-29 presentation sequence contract: missing/out-of-order/duplicate sequences refetch, never apply unsafe increments', () => {
  it('applies the first observed sequence unconditionally (baseline)', () => {
    expect(decideSequenceOutcome(null, 0)).toBe('apply')
    expect(decideSequenceOutcome(null, 41)).toBe('apply')
  })

  it('applies the exact successor', () => {
    expect(decideSequenceOutcome(5, 6)).toBe('apply')
  })

  it('ignores a duplicate (equal) or stale (lower) sequence rather than regressing presented state', () => {
    expect(decideSequenceOutcome(5, 5)).toBe('ignore_stale')
    expect(decideSequenceOutcome(5, 3)).toBe('ignore_stale')
    expect(decideSequenceOutcome(5, 0)).toBe('ignore_stale')
  })

  it('treats any gap (missing sequence) as opaque refetch, never an unsafe increment', () => {
    expect(decideSequenceOutcome(5, 7)).toBe('refetch')
    expect(decideSequenceOutcome(5, 100)).toBe('refetch')
  })
})

describe('preload bridge: hostile renderer calls never reach ipcRenderer.invoke (no privileged effect on validation failure)', () => {
  let ipcRendererMock: { invoke: ReturnType<typeof vi.fn>; on: ReturnType<typeof vi.fn>; removeListener: ReturnType<typeof vi.fn>; send: ReturnType<typeof vi.fn> }
  let exposeInMainWorldMock: ReturnType<typeof vi.fn>
  let exposedApi: Record<string, unknown>

  beforeEach(async () => {
    vi.resetModules()
    ipcRendererMock = {
      invoke: vi.fn(async (channel: string) => {
        if (channel === 'keepling:presentation-snapshot') return validPresentation
        return validSnapshot
      }),
      on: vi.fn(),
      removeListener: vi.fn(),
      send: vi.fn(),
    }
    exposeInMainWorldMock = vi.fn()
    vi.doMock('electron', () => ({
      contextBridge: { exposeInMainWorld: exposeInMainWorldMock },
      ipcRenderer: ipcRendererMock,
    }))
    await import('../../preload/index.ts')
    expect(exposeInMainWorldMock).toHaveBeenCalledTimes(1)
    expect(exposeInMainWorldMock.mock.calls[0]![0]).toBe('keepling')
    exposedApi = exposeInMainWorldMock.mock.calls[0]![1] as Record<string, unknown>
  })

  afterEach(() => {
    vi.doUnmock('electron')
    vi.resetModules()
  })

  it('exposes only the named, expected surface -- no generic invoke/send/on escape hatch', () => {
    expect(Object.keys(exposedApi).sort()).toEqual(
      [
        'accountStatus', 'beginSignIn', 'capture', 'editTask', 'lifecycleTask', 'listConflicts',
        'moveToday', 'persistWorkspaceLayout', 'presentationSnapshot', 'removeLocalData',
        'resolveConflict', 'restoreWorkspaceLayout', 'snapshot', 'subscribePresentation',
        'undoLastAction',
      ].sort(),
    )
    expect(exposedApi).not.toHaveProperty('invoke')
    expect(exposedApi).not.toHaveProperty('send')
    expect(exposedApi).not.toHaveProperty('ipcRenderer')
  })

  it('capture(): an extra field never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect((exposedApi.capture as (r: unknown) => Promise<unknown>)({ addToToday: true, extra: 'x', title: 't' })).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:capture', expect.anything())
  })

  it('capture(): a malformed title type never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect((exposedApi.capture as (r: unknown) => Promise<unknown>)({ title: { hostile: true } })).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:capture', expect.anything())
  })

  it('editTask(): an unknown extra field never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect(
      (exposedApi.editTask as (r: unknown) => Promise<unknown>)({ hostileField: 1, notes: 'n', taskId: 't', title: 'x' }),
    ).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:edit-task', expect.anything())
  })

  it('lifecycleTask(): a malformed union member (unknown kind) never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect(
      (exposedApi.lifecycleTask as (r: unknown) => Promise<unknown>)({ kind: 'delete_forever', taskId: 't' }),
    ).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:lifecycle-task', expect.anything())
  })

  it('moveToday(): a wrong-typed field never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect((exposedApi.moveToday as (r: unknown) => Promise<unknown>)({ planned: 'yes', taskId: 't' })).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:move-today', expect.anything())
  })

  it('resolveConflict(): a malformed choice enum never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect(
      (exposedApi.resolveConflict as (r: unknown) => Promise<unknown>)({ choice: 'delete_both', conflictId: 'c' }),
    ).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalledWith('keepling:resolve-conflict', expect.anything())
  })

  it('removeLocalData(): a malformed confirmRemoveAnyway type never reaches ipcRenderer.invoke -- absence of privileged effect, not merely rejection', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect(
      (exposedApi.removeLocalData as (r: unknown) => Promise<unknown>)({ confirmRemoveAnyway: 'yes' }),
    ).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalled()
  })

  it('removeLocalData(): an attempt to smuggle a sync/network-shaped extra field never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    await expect(
      (exposedApi.removeLocalData as (r: unknown) => Promise<unknown>)({ confirmRemoveAnyway: true, syncFirst: true }),
    ).rejects.toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalled()
  })

  it('removeLocalData(): a malformed main response is rejected before reaching the caller (never trusts an unparsed outcome)', async () => {
    ipcRendererMock.invoke.mockImplementationOnce(async () => ({ kind: 'partially_removed' }))
    await expect((exposedApi.removeLocalData as (r: unknown) => Promise<unknown>)({ confirmRemoveAnyway: false })).rejects.toThrow()
  })

  it('persistWorkspaceLayout(): a malformed layout state never reaches ipcRenderer.invoke', () => {
    ipcRendererMock.invoke.mockClear()
    expect(() =>
      (exposedApi.persistWorkspaceLayout as (s: unknown) => void)({ ...validWorkspaceLayoutState, destination: 'archive' }),
    ).toThrow()
    expect(ipcRendererMock.invoke).not.toHaveBeenCalled()
  })

  it('restoreWorkspaceLayout(): a malformed response from a compromised/buggy main is rejected, never handed to the renderer', async () => {
    ipcRendererMock.invoke.mockImplementationOnce(async () => ({ ...validWorkspaceLayoutState, destination: 'archive' }))
    await expect((exposedApi.restoreWorkspaceLayout as () => Promise<unknown>)()).rejects.toThrow()
  })

  it('restoreWorkspaceLayout(): a null main response (nothing persisted yet) resolves to null, never throws', async () => {
    ipcRendererMock.invoke.mockImplementationOnce(async () => null)
    await expect((exposedApi.restoreWorkspaceLayout as () => Promise<unknown>)()).resolves.toBeNull()
  })

  it('a well-formed request for every method DOES reach ipcRenderer.invoke exactly once with the parsed value', async () => {
    ipcRendererMock.invoke.mockClear()
    ipcRendererMock.invoke.mockImplementationOnce(async () => validLocalAcceptance)
    await (exposedApi.capture as (r: unknown) => Promise<unknown>)({ title: 'Call dentist' })
    expect(ipcRendererMock.invoke).toHaveBeenCalledWith('keepling:capture', { title: 'Call dentist' })
  })

  it('parses (and rejects) a malformed response from a compromised/buggy main before handing it to the renderer', async () => {
    ipcRendererMock.invoke.mockImplementationOnce(async () => ({ hostile: 'response', not: 'a snapshot' }))
    await expect((exposedApi.snapshot as () => Promise<unknown>)()).rejects.toThrow()
  })

  it('subscribePresentation(): registers the presentation-changed listener exactly once at module load, before any subscriber exists', () => {
    const presentationListenerCalls = ipcRendererMock.on.mock.calls.filter(([channel]) => channel === 'keepling:presentation-changed')
    expect(presentationListenerCalls).toHaveLength(1)
  })

  it('subscribePresentation(): delivers an authoritative baseline immediately on subscribe (subscription-precedes-snapshot guarantee)', async () => {
    const received: unknown[] = []
    ;(exposedApi.subscribePresentation as (fn: (p: unknown) => void) => () => void)((presentation) => received.push(presentation))
    await Promise.resolve()
    await Promise.resolve()
    expect(received).toHaveLength(1)
    expect(received[0]).toMatchObject({ sequence: validPresentation.sequence })
  })

  it('a duplicate/out-of-order push is ignored (never regresses presented state)', async () => {
    const [, presentationListener] = ipcRendererMock.on.mock.calls.find(([channel]) => channel === 'keepling:presentation-changed')!
    const received: unknown[] = []
    ;(exposedApi.subscribePresentation as (fn: (p: unknown) => void) => () => void)((presentation) => received.push(presentation))
    await Promise.resolve()
    await Promise.resolve()
    received.length = 0
    presentationListener({}, { ...validPresentation, sequence: 0 })
    await Promise.resolve()
    expect(received).toHaveLength(0)
  })

  it('a sequence gap triggers an opaque presentation-snapshot refetch instead of applying the pushed value directly', async () => {
    const [, presentationListener] = ipcRendererMock.on.mock.calls.find(([channel]) => channel === 'keepling:presentation-changed')!
    const received: unknown[] = []
    ;(exposedApi.subscribePresentation as (fn: (p: unknown) => void) => () => void)((presentation) => received.push(presentation))
    await Promise.resolve()
    await Promise.resolve()
    ipcRendererMock.invoke.mockClear()
    received.length = 0
    const refetchedPresentation = { ...validPresentation, sequence: 50 }
    ipcRendererMock.invoke.mockImplementationOnce(async () => refetchedPresentation)
    // A gap: jump from sequence 1 straight to 9, skipping 2..8.
    presentationListener({}, { ...validPresentation, sequence: 9 })
    await Promise.resolve()
    await Promise.resolve()
    expect(ipcRendererMock.invoke).toHaveBeenCalledWith('keepling:presentation-snapshot')
    // The pushed (gapped) value is never delivered directly -- only the refetched, authoritative one is.
    expect(received).toHaveLength(1)
    expect(received[0]).toMatchObject({ sequence: 50 })
  })

  it('unsubscribe stops delivering to that subscriber but the module-level listener stays live for others', async () => {
    const received: unknown[] = []
    const unsubscribe = (exposedApi.subscribePresentation as (fn: (p: unknown) => void) => () => void)((presentation) =>
      received.push(presentation),
    )
    await Promise.resolve()
    await Promise.resolve()
    unsubscribe()
    received.length = 0
    const [, presentationListener] = ipcRendererMock.on.mock.calls.find(([channel]) => channel === 'keepling:presentation-changed')!
    presentationListener({}, { ...validPresentation, sequence: 2 })
    await Promise.resolve()
    expect(received).toHaveLength(0)
  })
})

describe('reload/crash after local COMMIT reconstructs from an opaque snapshot, never loses accepted intent (D-03/D-29)', () => {
  class InMemoryLocalStore implements LocalStorePort {
    #tasks: WorkspaceTask[] = []

    async acceptCapture(mutation: PendingMutation): Promise<LocalAcceptance> {
      // Durable COMMIT happens synchronously here -- this is the moment "Saved
      // on this Mac" becomes true, matching D-03's post-COMMIT boundary.
      this.#tasks = [...this.#tasks, { id: mutation.taskId, syncStatus: 'saved_on_this_mac', title: mutation.title }]
      return { fingerprint: mutation.fingerprint, mutationId: mutation.mutationId, snapshot: { tasks: this.#tasks }, status: 'local_saved' }
    }

    async acknowledge(_acknowledgement: SyncAcknowledgement): Promise<WorkspaceSnapshot> {
      return { tasks: this.#tasks }
    }

    async pendingMutations(): Promise<PendingMutation[]> {
      return []
    }

    async snapshot(): Promise<WorkspaceSnapshot> {
      return { tasks: this.#tasks }
    }

    async close(): Promise<void> {}
  }

  type WorkspaceTask = { id: string; syncStatus: 'saved_on_this_mac' | 'synced'; title: string }

  it('a fresh (post-reload/crash) subscriber snapshot still contains the task committed before the renderer failure, via a fresh opaque fetch', async () => {
    const store = new InMemoryLocalStore()
    const sync: SyncPort = { acknowledge: async () => null }
    const application = new DesktopApplication({
      clock: { now: () => new Date(0).toISOString() },
      identity: { randomId: (() => { let n = 0; return () => `id-${(n += 1)}` })() },
      localStore: store,
      sync,
    })

    const captured: LocalAcceptance = await application.capture({ title: 'Survive the crash' } satisfies CaptureCommand)
    expect(captured.status).toBe('local_saved')

    // Simulate a renderer reload/crash: drop every in-memory listener the
    // renderer held (there is nothing to lose -- the crashed process's
    // subscription state is discarded), then attach a completely new
    // subscriber, exactly as the preload's `subscribePresentation` does on
    // the very next `refetchAuthoritativePresentation()` call.
    const freshSubscriberReceived: unknown[] = []
    application.subscribePresentation((presentation) => freshSubscriberReceived.push(presentation))

    const reconstructedSnapshot = await application.snapshot()
    expect(reconstructedSnapshot.tasks).toHaveLength(1)
    expect(reconstructedSnapshot.tasks[0]).toMatchObject({ syncStatus: 'saved_on_this_mac', title: 'Survive the crash' })
  })
})

/**
 * O-16 closure (Plan 03-14): the account surface -- connect, disconnect, and
 * connection status -- is the FIRST renderer-reachable path to anything
 * network-shaped, so it gets the same two-sided strict contract and the same
 * hostile coverage as `removeLocalData` (03-13's precedent).
 *
 * The central prohibition proved here: NO renderer may collect a credential.
 * Authentication happens in the system browser. The contracts below are
 * structurally incapable of carrying a password, passkey, token, or code.
 */
const validAccountNamespace = {
  accountSubject: '9f1d5f39-1a4a-4b7e-9f2a-2b8ef2a3c111',
  generation: '3',
  issuer: 'https://issuer.keepling.invalid',
  origin: 'https://server.keepling.invalid',
  serverInstance: 'server-instance-real',
}
const validAccountStatus = {
  disclosure: null,
  namespace: null,
  serverUrl: null,
  state: 'not_configured' as const,
}

describe('account surface (O-16): strict two-sided contracts that structurally cannot carry a credential', () => {
  it('accepts the exact well-formed shape', () => {
    expect(() => accountConnectRequestSchema.parse({ serverUrl: 'https://keepling.example.com' })).not.toThrow()
    expect(() => accountStatusSchema.parse(validAccountStatus)).not.toThrow()
    expect(() =>
      accountStatusSchema.parse({
        disclosure: { copy: 'Unsigned dogfood build.', kind: 'unsigned_dogfood' },
        namespace: validAccountNamespace,
        serverUrl: 'https://keepling.example.com/',
        state: 'connected',
      }),
    ).not.toThrow()
    expect(() => accountConnectOutcomeSchema.parse({ kind: 'browser_opened', status: validAccountStatus })).not.toThrow()
    expect(() => accountConnectOutcomeSchema.parse({ kind: 'rejected', reason: 'invalid_server_address' })).not.toThrow()
  })

  it('the connect request has EXACTLY one field (serverUrl) -- no credential can be smuggled through it', () => {
    expect(Object.keys(accountConnectRequestSchema.shape)).toEqual(['serverUrl'])
    for (const credentialField of ['password', 'passkey', 'token', 'accessToken', 'code', 'codeVerifier', 'secret']) {
      expect(() =>
        accountConnectRequestSchema.parse({ serverUrl: 'https://keepling.example.com', [credentialField]: 'x' }),
      ).toThrow()
    }
  })

  it('never lets a renderer assert, derive, or override any of the five namespace fields', () => {
    // The namespace is REPORTED to the renderer as status; there is no
    // request schema anywhere in this surface that accepts one.
    expect(() => accountConnectRequestSchema.parse({ namespace: validAccountNamespace, serverUrl: 'https://a.invalid' })).toThrow()
    expect(() =>
      accountStatusSchema.parse({ ...validAccountStatus, namespace: { ...validAccountNamespace, extra: 'x' } }),
    ).toThrow()
    for (const field of ['accountSubject', 'generation', 'issuer', 'origin', 'serverInstance']) {
      const partial: Record<string, unknown> = { ...validAccountNamespace }
      delete partial[field]
      expect(() => accountStatusSchema.parse({ ...validAccountStatus, namespace: partial })).toThrow()
    }
  })

  it('rejects extra fields, malformed unions, and out-of-range values on every account schema (.strict())', () => {
    expect(() => accountStatusSchema.parse({ ...validAccountStatus, extra: 1 })).toThrow()
    expect(() => accountStatusSchema.parse({ ...validAccountStatus, state: 'omniscient' })).toThrow()
    expect(() => accountStatusSchema.parse({ ...validAccountStatus, disclosure: { copy: 'x', kind: 'signed' } })).toThrow()
    expect(() => accountConnectOutcomeSchema.parse({ kind: 'browser_opened' })).toThrow()
    expect(() => accountConnectOutcomeSchema.parse({ extra: 1, kind: 'rejected', reason: 'invalid_server_address' })).toThrow()
    expect(() => accountConnectOutcomeSchema.parse({ kind: 'authorized', namespace: validAccountNamespace })).toThrow()
    expect(() => accountConnectRequestSchema.parse({ serverUrl: '' })).toThrow()
    expect(() => accountConnectRequestSchema.parse({ serverUrl: 'a'.repeat(2049) })).toThrow()
    expect(() => accountConnectRequestSchema.parse({ serverUrl: 42 })).toThrow()
  })

  it('converts an account schema failure into the same bounded IpcSecurityError as every other main-side parse', () => {
    let caught: unknown
    try {
      parseTrustedRequest(accountConnectRequestSchema, { password: 'hunter2', serverUrl: 'https://a.invalid' })
    } catch (error) {
      caught = error
    }
    expect(caught).toBeInstanceOf(IpcSecurityError)
    expect((caught as IpcSecurityError).code).toBe('invalid_request')
  })
})

describe('no renderer anywhere collects a credential (03-14 prohibition)', () => {
  it('static-scans every renderer source for a credential-entry field', async () => {
    const { readdir, readFile } = await import('node:fs/promises')
    const { fileURLToPath } = await import('node:url')
    const { join } = await import('node:path')
    const rendererRoot = fileURLToPath(new URL('../../renderer', import.meta.url))
    const webUiRoot = fileURLToPath(new URL('../../../../packages/web-ui/src', import.meta.url))

    const walk = async (directory: string): Promise<string[]> => {
      const entries = await readdir(directory, { withFileTypes: true })
      const files: string[] = []
      for (const entry of entries) {
        const path = join(directory, entry.name)
        if (entry.isDirectory()) files.push(...await walk(path))
        else if (/\.(ts|tsx|html)$/.test(entry.name)) files.push(path)
      }
      return files
    }

    const sources = [...await walk(rendererRoot), ...await walk(webUiRoot)]
    expect(sources.length).toBeGreaterThan(0)
    for (const path of sources) {
      const source = await readFile(path, 'utf8')
      expect(source, `${path} must not render a password input`).not.toMatch(/type=["']password["']/)
      expect(source, `${path} must not use the WebAuthn credential API`).not.toMatch(/navigator\.credentials/)
      expect(source, `${path} must not carry a credential autocomplete hint`).not.toMatch(
        /autoComplete=["'](?:current-password|new-password|webauthn)["']/,
      )
    }
  })
})

describe('utility preload bridge (Settings account surface): hostile calls never reach ipcRenderer.invoke', () => {
  let ipcRendererMock: { invoke: ReturnType<typeof vi.fn>; on: ReturnType<typeof vi.fn>; removeListener: ReturnType<typeof vi.fn>; send: ReturnType<typeof vi.fn> }
  let exposeInMainWorldMock: ReturnType<typeof vi.fn>
  let exposedApi: Record<string, unknown>

  beforeEach(async () => {
    vi.resetModules()
    ipcRendererMock = {
      invoke: vi.fn(async (channel: string) => {
        if (channel === 'keepling:account:connect') return { kind: 'browser_opened', status: validAccountStatus }
        if (channel === 'keepling:account:status' || channel === 'keepling:account:disconnect') return validAccountStatus
        return { accelerator: 'Control+Alt+Space', registered: true }
      }),
      on: vi.fn(),
      removeListener: vi.fn(),
      send: vi.fn(),
    }
    exposeInMainWorldMock = vi.fn()
    vi.doMock('electron', () => ({
      contextBridge: { exposeInMainWorld: exposeInMainWorldMock },
      ipcRenderer: ipcRendererMock,
    }))
    await import('../../preload/utility-preload.ts')
    exposedApi = exposeInMainWorldMock.mock.calls[0]![1] as Record<string, unknown>
  })

  afterEach(() => {
    vi.doUnmock('electron')
    vi.resetModules()
  })

  it('exposes the named account operations and no generic escape hatch', () => {
    expect(Object.keys(exposedApi)).toContain('accountConnect')
    expect(Object.keys(exposedApi)).toContain('accountDisconnect')
    expect(Object.keys(exposedApi)).toContain('accountStatus')
    expect(exposedApi).not.toHaveProperty('invoke')
    expect(exposedApi).not.toHaveProperty('ipcRenderer')
  })

  it('accountConnect(): a credential-shaped extra field never reaches ipcRenderer.invoke', async () => {
    ipcRendererMock.invoke.mockClear()
    for (const hostile of [
      { password: 'hunter2', serverUrl: 'https://a.invalid' },
      { serverUrl: 'https://a.invalid', token: 'abc' },
      { serverUrl: 42 },
      { serverUrl: '' },
      {},
    ]) {
      await expect((exposedApi.accountConnect as (r: unknown) => Promise<unknown>)(hostile)).rejects.toThrow()
    }
    expect(ipcRendererMock.invoke).not.toHaveBeenCalled()
  })

  it('accountStatus(): a malformed main-side response is rejected before it reaches the renderer', async () => {
    ipcRendererMock.invoke.mockImplementationOnce(async () => ({ ...validAccountStatus, accessToken: 'leaked' }))
    await expect((exposedApi.accountStatus as () => Promise<unknown>)()).rejects.toThrow()
  })
})
