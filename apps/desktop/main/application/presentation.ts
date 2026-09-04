type RecoveryActionCode =
  | 'inspect'
  | 'retry'
  | 'check_again'
  | 'review'
  | 'review_conflict'
  | 'sign_in'
  | 'export'
  | 'remove_local_data'
  | 'retry_save'
  | 'retry_opening'
  | 'show_recovery_options'

type DesktopPresentationKind =
  | 'healthy'
  | 'opening'
  | 'preparing'
  | 'updating'
  | 'offline'
  | 'retryable_failure'
  | 'local_saved'
  | 'uncertain'
  | 'rejected'
  | 'conflict'
  | 'authentication_required'
  | 'namespace_mismatch'
  | 'local_save_failure'
  | 'store_unavailable'
  | 'undo_unavailable'

type DesktopPresentationInput =
  | { kind: 'healthy'; lastSuccessfulContact?: string }
  | { kind: 'opening' }
  | { kind: 'preparing' }
  | { kind: 'updating'; startedAt: number }
  | { kind: 'offline'; lastSuccessfulContact?: string }
  | { kind: 'retryable_failure'; pendingCount?: number }
  | { kind: 'local_saved'; pendingCount?: number }
  | { kind: 'uncertain'; pendingCount?: number }
  | { affectedCount?: number; kind: 'rejected' }
  | { affectedCount?: number; kind: 'conflict' }
  | { kind: 'authentication_required'; pendingCount?: number }
  | { kind: 'namespace_mismatch'; pendingCount?: number }
  | { kind: 'local_save_failure' }
  | { kind: 'store_unavailable' }
  /**
   * O-45. An undo this Mac REFUSED to perform, and why.
   *
   * `unsent`: the mutation being undone has not been acknowledged, so the
   * server has issued no compensation capability and there is nothing to
   * send. Syncing is a real remedy -- once the acknowledgement lands the
   * handle exists -- so `retry` is offered.
   *
   * `expired`: the server-issued handle's own `expires_at` has passed. No
   * action can change that, so none is offered. Offering a button that
   * cannot work is the dead-remedy failure O-42 removed.
   *
   * This is NOT `rejected`. That row says "The server didn't accept this
   * change", and in both cases here the server was never asked.
   */
  | { kind: 'undo_unavailable'; reason: 'expired' | 'unsent' }

type RecoveryAction = { code: RecoveryActionCode; label: string }

type DesktopPresentationSummary = {
  actions: RecoveryAction[]
  copy: string | null
  count: number | null
  kind: DesktopPresentationKind
  lastSuccessfulContact: string | null
}

type DesktopPresentation = {
  sequence: number
  summary: DesktopPresentationSummary
  surfaces: {
    panel: DesktopPresentationSummary
    row: DesktopPresentationSummary
    shell: DesktopPresentationSummary
  }
}

const GRACE_PERIOD_MS = 3_000
const MAXIMUM_PRESENTED_COUNT = 99

const action = (code: RecoveryActionCode, label: string): RecoveryAction => ({ code, label })
const boundedCount = (value?: number): number | null =>
  value === undefined ? null : Math.max(0, Math.min(Math.trunc(value), MAXIMUM_PRESENTED_COUNT))

const deriveSummary = (
  input: DesktopPresentationInput,
  nowMs: number,
): DesktopPresentationSummary => {
  switch (input.kind) {
    case 'healthy':
      return { actions: [], copy: null, count: null, kind: 'healthy', lastSuccessfulContact: input.lastSuccessfulContact ?? null }
    case 'opening':
      return { actions: [], copy: 'Opening your tasks…', count: null, kind: input.kind, lastSuccessfulContact: null }
    case 'preparing':
      return { actions: [], copy: 'Preparing your tasks for offline use…', count: null, kind: input.kind, lastSuccessfulContact: null }
    case 'updating':
      if (nowMs - input.startedAt < GRACE_PERIOD_MS) {
        return { actions: [], copy: null, count: null, kind: 'healthy', lastSuccessfulContact: null }
      }
      return { actions: [action('inspect', 'Sync & Recovery')], copy: 'Updating…', count: null, kind: input.kind, lastSuccessfulContact: null }
    case 'offline':
      return { actions: [], copy: 'Offline — showing tasks saved on this Mac', count: null, kind: input.kind, lastSuccessfulContact: input.lastSuccessfulContact ?? null }
    case 'retryable_failure':
      return { actions: [action('retry', 'Retry')], copy: 'Couldn’t reach the server. Your changes stay on this Mac.', count: boundedCount(input.pendingCount), kind: input.kind, lastSuccessfulContact: null }
    case 'local_saved':
      return { actions: [], copy: 'Saved on this Mac. Sync when you’re back online', count: boundedCount(input.pendingCount), kind: input.kind, lastSuccessfulContact: null }
    case 'uncertain':
      return { actions: [action('check_again', 'Check Again')], copy: 'Checking whether this change was accepted…', count: boundedCount(input.pendingCount), kind: input.kind, lastSuccessfulContact: null }
    case 'rejected':
      return { actions: [action('review', 'Review')], copy: 'The server didn’t accept this change. Your version is still on this Mac.', count: boundedCount(input.affectedCount), kind: input.kind, lastSuccessfulContact: null }
    case 'conflict':
      return { actions: [action('review_conflict', 'Review Conflict')], copy: 'This task changed somewhere else. Choose what to keep. Other tasks can continue.', count: boundedCount(input.affectedCount), kind: input.kind, lastSuccessfulContact: null }
    case 'authentication_required':
      return { actions: [action('sign_in', 'Sign In')], copy: 'Sign in to continue syncing. Changes remain safe on this Mac.', count: boundedCount(input.pendingCount), kind: input.kind, lastSuccessfulContact: null }
    case 'namespace_mismatch':
      return { actions: [action('inspect', 'Inspect'), action('export', 'Export'), action('remove_local_data', 'Remove data from this Mac…')], copy: 'These changes belong to a different account or server and won’t be sent here.', count: boundedCount(input.pendingCount), kind: input.kind, lastSuccessfulContact: null }
    case 'local_save_failure':
      return { actions: [action('retry_save', 'Try Again')], copy: 'Couldn’t save this change on this Mac. Keep this window open and try again.', count: null, kind: input.kind, lastSuccessfulContact: null }
    case 'store_unavailable':
      return { actions: [action('retry_opening', 'Retry Opening'), action('show_recovery_options', 'Show Recovery Options')], copy: 'Keepling can’t open the tasks saved on this Mac. Your data was not replaced or removed.', count: null, kind: input.kind, lastSuccessfulContact: null }
    case 'undo_unavailable':
      return input.reason === 'unsent'
        ? { actions: [action('retry', 'Retry')], copy: 'This change hasn’t reached the server yet, so it can’t be undone. Nothing was changed.', count: null, kind: input.kind, lastSuccessfulContact: null }
        : { actions: [], copy: 'This change can no longer be undone. Nothing was changed.', count: null, kind: input.kind, lastSuccessfulContact: null }
  }
}

const deriveDesktopPresentation = (
  input: DesktopPresentationInput,
  sequence: number,
  nowMs = Date.now(),
): DesktopPresentation => {
  if (!Number.isSafeInteger(sequence) || sequence < 0) throw new Error('presentation sequence is invalid')
  const summary = deriveSummary(input, nowMs)
  return { sequence, summary, surfaces: { panel: summary, row: summary, shell: summary } }
}

const diagnosticKeys = new Set([
  'artifactVersion', 'count', 'operation', 'outcome', 'processRole', 'schemaVersion', 'timingMs',
])
const diagnosticOperations = new Set(['application_open', 'local_save', 'sync_pass', 'namespace_fence', 'store_open'])
const diagnosticOutcomes = new Set(['ready', 'local_saved', 'retryable_failure', 'authentication_required', 'namespace_mismatch', 'store_unavailable'])
const diagnosticRoles = new Set(['main', 'preload', 'renderer', 'worker'])

const sanitizeDesktopDiagnostic = (input: Record<string, unknown>): Record<string, string | number> => {
  if (Object.keys(input).some((key) => !diagnosticKeys.has(key))) throw new Error('diagnostic field is not allowlisted')
  if (!diagnosticOperations.has(String(input.operation))) throw new Error('diagnostic operation is invalid')
  if (!diagnosticOutcomes.has(String(input.outcome))) throw new Error('diagnostic outcome is invalid')
  if (!diagnosticRoles.has(String(input.processRole))) throw new Error('diagnostic process role is invalid')
  const output: Record<string, string | number> = {
    operation: String(input.operation),
    outcome: String(input.outcome),
    processRole: String(input.processRole),
  }
  if (typeof input.count === 'number') output.count = boundedCount(input.count) ?? 0
  if (typeof input.timingMs === 'number') output.timingBucketSeconds = Math.min(3600, Math.max(0, Math.round(input.timingMs / 1000)))
  if (typeof input.artifactVersion === 'string') output.artifactVersion = input.artifactVersion.slice(0, 32)
  if (typeof input.schemaVersion === 'number') output.schemaVersion = Math.max(0, Math.trunc(input.schemaVersion))
  return output
}

export { GRACE_PERIOD_MS, deriveDesktopPresentation, sanitizeDesktopDiagnostic }
export type {
  DesktopPresentation,
  DesktopPresentationInput,
  DesktopPresentationKind,
  DesktopPresentationSummary,
  RecoveryAction,
  RecoveryActionCode,
}
