import { z } from 'zod'

/**
 * Centralized, strict, clone-safe request/response schemas for the main
 * window's `keepling` preload bridge (D-27/D-28). BOTH sides parse against
 * these exact schemas -- `preload/index.ts` parses outgoing requests before
 * `ipcRenderer.invoke` and incoming responses/pushes before handing them to
 * the renderer, and `main/index.ts` parses every incoming request again
 * before it reaches `DesktopApplication`, because a compromised renderer can
 * always call `ipcRenderer.invoke` directly and bypass preload entirely --
 * the main-process parse is the actual security boundary, the preload parse
 * is defense in depth plus an early, cheap rejection.
 *
 * Every schema is `.strict()`: unknown/extra fields (deep or shallow) are
 * rejected rather than silently dropped, so a hostile renderer cannot smuggle
 * additional fields through an otherwise-valid request.
 */

const recoveryActionCodeSchema = z.enum([
  'inspect', 'retry', 'check_again', 'review', 'review_conflict', 'sign_in', 'export',
  'remove_local_data', 'retry_save', 'retry_opening', 'show_recovery_options',
])
const desktopPresentationKindSchema = z.enum([
  'healthy', 'opening', 'preparing', 'updating', 'offline', 'retryable_failure',
  'local_saved', 'uncertain', 'rejected', 'conflict', 'authentication_required',
  'namespace_mismatch', 'local_save_failure', 'store_unavailable', 'undo_unavailable',
])
const recoveryActionSchema = z.object({
  code: recoveryActionCodeSchema,
  label: z.string().min(1).max(80),
}).strict()
const desktopPresentationSummarySchema = z.object({
  actions: z.array(recoveryActionSchema).max(3),
  copy: z.string().min(1).max(240).nullable(),
  count: z.number().int().min(0).max(99).nullable(),
  kind: desktopPresentationKindSchema,
  lastSuccessfulContact: z.string().min(1).max(80).nullable(),
}).strict()
const desktopPresentationSchema = z.object({
  sequence: z.number().int().nonnegative(),
  summary: desktopPresentationSummarySchema,
  surfaces: z.object({
    panel: desktopPresentationSummarySchema,
    row: desktopPresentationSummarySchema,
    shell: desktopPresentationSummarySchema,
  }).strict(),
}).strict()

const captureRequestSchema = z.object({
  addToToday: z.boolean().optional(),
  title: z.string().trim().min(1).max(512),
}).strict()
const taskSchema = z.object({
  completedAt: z.string().nullable().optional(),
  id: z.string().min(1),
  notes: z.string().optional(),
  planned: z.boolean().optional(),
  syncStatus: z.enum(['saved_on_this_mac', 'synced']),
  title: z.string().min(1),
  trashedAt: z.string().nullable().optional(),
}).strict()
const snapshotSchema = z.object({ tasks: z.array(taskSchema) }).strict()
const localAcceptanceSchema = z.object({
  fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  mutationId: z.string().min(1),
  snapshot: snapshotSchema,
  status: z.literal('local_saved'),
}).strict()
const editRequestSchema = z.object({
  notes: z.string().max(50_000),
  taskId: z.string().min(1),
  title: z.string().trim().min(1).max(512),
}).strict()
const lifecycleRequestSchema = z.object({
  kind: z.enum(['complete', 'reopen', 'restore', 'trash']),
  taskId: z.string().min(1),
}).strict()
const moveTodayRequestSchema = z.object({
  planned: z.boolean(),
  taskId: z.string().min(1),
}).strict()
const conflictSchema = z.object({
  conflictId: z.string().min(1),
  current: z.string(),
  mine: z.string(),
  taskId: z.string().min(1),
}).strict()
/**
 * O-45: `reason` says why an undo did NOT happen. It is additive and
 * optional, so an applied undo is byte-identical to what this contract
 * accepted before. The refusal itself reaches a person through the
 * main-owned presentation row, not through this value -- `DesktopShell`
 * discards the outcome of `undoLastChange` -- so this exists for the
 * renderer's own messaging and for tests, never as the only surfacing.
 */
const undoResultSchema = z.object({
  applied: z.boolean(),
  // O-51: `in_flight` is the refusal for a command whose bytes have been
  // handed to the transport with no outcome yet -- distinct from `unsent`,
  // which claims the change is still only on this Mac.
  reason: z.enum(['expired', 'in_flight', 'nothing_to_undo', 'unsent']).optional(),
  snapshot: snapshotSchema,
}).strict()
const resolveConflictRequestSchema = z.object({
  choice: z.enum(['current', 'mine']),
  conflictId: z.string().min(1),
}).strict()

/**
 * O-12 gap closure: the strict both-side contract for "Remove data from
 * this Mac..." (D-24), following 03-10's established pattern exactly.
 * `confirmRemoveAnyway` is the ONLY input -- no sync/network capability is
 * ever part of this shape, so a hostile renderer cannot smuggle a path to
 * server deletion through this contract even in principle.
 */
const removeLocalDataRequestSchema = z.object({
  confirmRemoveAnyway: z.boolean(),
}).strict()

/**
 * O-42: the two capabilities the recovery actions needed and that no
 * surface could reach.
 *
 * `retrySync` takes NO argument -- `retry` and `Check Again` mean "try the
 * synchronization pass again now", never "send this particular thing", so
 * there is nothing for a renderer to choose and no way for one to aim a
 * push. `exportLocalData` also takes no argument: the destination is
 * main-owned, and the renderer learns only the path that was written, so a
 * hostile renderer cannot direct a write anywhere.
 */
const retrySyncOutcomeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('ran'), pulled: z.number().int().min(0), settled: z.number().int().min(0) }).strict(),
  z.object({ kind: z.literal('failed'), reason: z.string().min(1).max(200) }).strict(),
  z.object({ kind: z.literal('unavailable') }).strict(),
])
const exportLocalDataOutcomeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('exported'), path: z.string().min(1).max(4096), taskCount: z.number().int().min(0) }).strict(),
  z.object({ kind: z.literal('failed'), reason: z.string().min(1).max(200) }).strict(),
])
const removeLocalDataOutcomeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('removed') }).strict(),
  z.object({
    conflictedCount: z.number().int().min(0),
    kind: z.literal('blocked_pending_intent'),
    pendingCount: z.number().int().min(0),
  }).strict(),
  z.object({ kind: z.literal('failed'), reason: z.string().min(1).max(500) }).strict(),
])

/**
 * O-11 gap closure: the D-06 renderer-semantic restoration snapshot.
 * Deliberately narrow -- only the fields D-06 names (destination, surviving
 * selection, a semantic scroll anchor, and a recoverable editor draft).
 * Pane sizes are NOT included: no resizable-pane UI exists anywhere in the
 * shared Workspace presentation to size, so there is nothing to persist for
 * that field (see 03-13-SUMMARY.md "Deviations"). Never a durability claim
 * (D-03) -- this is UI convenience state, not task data.
 */
const workspaceDraftSchema = z.object({
  notes: z.string().max(50_000),
  taskId: z.string().min(1),
  title: z.string().max(512),
}).strict()
const workspaceLayoutStateSchema = z.object({
  destination: z.enum(['inbox', 'today', 'trash']),
  draft: workspaceDraftSchema.nullable(),
  scrollAnchorTaskId: z.string().min(1).nullable(),
  selectedTaskId: z.string().min(1).nullable(),
  sidebarVisible: z.boolean(),
}).strict()

/**
 * O-16 gap closure: the account surface (connect / disconnect / status).
 *
 * The request shape is deliberately minimal and closed. `serverUrl` is the
 * ONLY thing a renderer may supply, because authentication happens in the
 * SYSTEM BROWSER (RFC 8252) -- no password, passkey, token, authorization
 * code, or PKCE verifier is ever collected by, passed through, or visible
 * to any renderer. `.strict()` makes that a structural property rather than
 * a policy that could be relaxed by accident.
 *
 * The namespace appears ONLY in the reported status, never in a request:
 * the five server-derived fields are echoed exactly as the token response
 * supplied them and can never be asserted, derived, defaulted, or
 * overridden by a client.
 */
const syncNamespaceSchema = z.object({
  accountSubject: z.string().min(1).max(200),
  generation: z.string().min(1).max(40),
  issuer: z.string().min(1).max(2048),
  origin: z.string().min(1).max(2048),
  serverInstance: z.string().min(1).max(200),
}).strict()
const accountConnectRequestSchema = z.object({
  serverUrl: z.string().min(1).max(2048),
}).strict()
const credentialDisclosureSchema = z.object({
  copy: z.string().min(1).max(500),
  kind: z.literal('unsigned_dogfood'),
}).strict()
const accountStatusSchema = z.object({
  disclosure: credentialDisclosureSchema.nullable(),
  namespace: syncNamespaceSchema.nullable(),
  serverUrl: z.string().min(1).max(2048).nullable(),
  state: z.enum(['not_configured', 'signed_out', 'authorizing', 'connected']),
}).strict()
const accountConnectOutcomeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('browser_opened'), status: accountStatusSchema }).strict(),
  z.object({
    kind: z.literal('rejected'),
    reason: z.enum(['invalid_server_address', 'authorization_unavailable']),
  }).strict(),
])

/**
 * D-29 sequence contract for `keepling:presentation-changed` pushes. The
 * preload bridge is always subscribed (its `ipcRenderer.on` listener is
 * registered at module load, before any renderer code runs or calls
 * `subscribePresentation`), so it never has to reason about "did I miss the
 * first push" -- the only remaining question is whether the STREAM of pushes
 * it does receive is contiguous. This is a pure decision function so the
 * hostile-bridge suite can exercise missing/out-of-order/duplicate sequences
 * directly, without needing a live Electron process.
 *
 * - `null` last sequence (nothing observed yet): always apply.
 * - Exact successor: apply normally.
 * - Equal or lower than the last applied sequence (duplicate/stale replay,
 *   or a compromised main sending an out-of-order push): ignore -- never
 *   regress the renderer to older presented state.
 * - Anything higher than the exact successor (a gap -- one or more pushes
 *   were lost): never try to reconstruct the skipped state by incrementing
 *   unsafely; refetch the authoritative snapshot instead (opaque recovery).
 */
type SequenceOutcome = 'apply' | 'ignore_stale' | 'refetch'

const decideSequenceOutcome = (lastSequence: number | null, incomingSequence: number): SequenceOutcome => {
  if (lastSequence === null) return 'apply'
  if (incomingSequence === lastSequence + 1) return 'apply'
  if (incomingSequence <= lastSequence) return 'ignore_stale'
  return 'refetch'
}

export {
  accountConnectOutcomeSchema,
  accountConnectRequestSchema,
  accountStatusSchema,
  captureRequestSchema,
  conflictSchema,
  decideSequenceOutcome,
  desktopPresentationSchema,
  editRequestSchema,
  exportLocalDataOutcomeSchema,
  lifecycleRequestSchema,
  localAcceptanceSchema,
  moveTodayRequestSchema,
  removeLocalDataOutcomeSchema,
  removeLocalDataRequestSchema,
  resolveConflictRequestSchema,
  retrySyncOutcomeSchema,
  snapshotSchema,
  syncNamespaceSchema,
  taskSchema,
  undoResultSchema,
  workspaceDraftSchema,
  workspaceLayoutStateSchema,
}
export type { SequenceOutcome }
