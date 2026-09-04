/**
 * O-38: hearing what the server actually says when it does not accept a
 * command.
 *
 * ## The defect, stated accurately
 *
 * The item was filed as "`mapAcknowledgement` accepts only `accepted` and
 * `already_satisfied` and throws on the `conflict` and `rejected` the
 * contract publishes". Reading the contract and the server together shows
 * the shape is different, and the difference matters:
 *
 *  - `CommandAcknowledgement.outcome` in `keepling.yaml` publishes EXACTLY
 *    `accepted` and `already_satisfied`. A 200 body claiming `conflict`
 *    would genuinely be an invalid acknowledgement, and `mapAcknowledgement`
 *    is right to refuse it. `conflict`/`rejected` at line 1392 are
 *    `MutationTrustState` -- a CLIENT-side vocabulary, not an ack outcome.
 *  - The real server answers a conflict with an RFC 9457 problem and HTTP
 *    409 (`Keepling.Adapters.Postgres.CommandStore#semantic_rejection`), and
 *    a semantic refusal with 422. It persists the conflict either way
 *    (`persist_command_conflict`).
 *
 * So the defect is real and worse than filed: `#json` threw a plain `Error`
 * for every non-OK status, `runSyncPass` caught it, and a 409 conflict
 * landed on "Couldn't reach the server. Your changes stay on this Mac." with
 * a Retry button that would retry, forever, a command the server has already
 * decided about. Not merely unheard -- MISHEARD, as a transport failure.
 *
 * ## Why this is a closed list rather than "anything the server refuses"
 *
 * Turning every refusal into a settled outcome is the failure this phase
 * keeps finding: it converts a loud failure into a silent one. In
 * particular a 401 must NOT become a per-mutation rejection -- every
 * authentication problem carries `retryable: false`, so a rule keyed on
 * that field alone would quietly discard a whole outbox as "the server
 * didn't accept these changes" when the truth is "sign in again". Anything
 * not named here -- 403, 5xx, a malformed body, a bounded-page violation --
 * keeps throwing and keeps landing on the retryable-failure row.
 */

/** 409 codes the server emits for a genuine divergence, all of which it persists. */
const CONFLICT_CODES: ReadonlySet<string> = new Set([
  'task_assignment_conflict',
  'task_edit_conflict',
  'task_lifecycle_conflict',
  'task_trash_conflict',
])

/**
 * Refusals that are about THIS command's content and will never succeed on
 * retry, so the mutation is terminal and the person must be told rather
 * than have it retried forever.
 */
const REJECTION_CODES: ReadonlySet<string> = new Set([
  'invalid_command',
  'task_not_found',
])

type ServerRefusal =
  | { affectedFields: string[]; conflictId: string | null; currentTitle: string | null; kind: 'conflict'; latestRevision: number | null }
  | { code: string; kind: 'authentication_required' }
  | { code: string; kind: 'rejected' }

type ProblemBody = {
  code?: unknown
  conflict?: unknown
}

const readString = (value: unknown): string | null => (typeof value === 'string' && value.length > 0 ? value : null)

/**
 * Reads the server's own conflict extension. The shape is
 * `{ fields: [{ base, current, field, mine }], id, latest_revision }`
 * (`CommandStore#conflict_field_bodies`). Only the SERVER may say what
 * diverged and what it currently holds; nothing here derives or defaults a
 * value the server did not send.
 */
const readConflict = (value: unknown): ServerRefusal => {
  const conflict = (typeof value === 'object' && value !== null ? value : {}) as {
    fields?: unknown
    id?: unknown
    latest_revision?: unknown
  }
  const fields = Array.isArray(conflict.fields) ? conflict.fields : []
  const entries = fields.flatMap((entry) => {
    if (typeof entry !== 'object' || entry === null) return []
    const record = entry as { current?: unknown; field?: unknown }
    const field = readString(record.field)
    return field === null ? [] : [{ current: record.current, field }]
  })
  const title = entries.find((entry) => entry.field === 'title')
  return {
    affectedFields: entries.map((entry) => entry.field),
    conflictId: readString(conflict.id),
    currentTitle: title === undefined ? null : readString(title.current),
    kind: 'conflict',
    latestRevision:
      typeof conflict.latest_revision === 'number' && Number.isSafeInteger(conflict.latest_revision)
        ? conflict.latest_revision
        : null,
  }
}

/**
 * Classifies one non-OK answer from the server. `null` means "this is not a
 * decision about the mutation" -- the caller MUST keep throwing.
 */
const classifyServerRefusal = (status: number, body: unknown): ServerRefusal | null => {
  const problem = (typeof body === 'object' && body !== null ? body : {}) as ProblemBody
  const code = readString(problem.code)
  if (code === null) return null

  if (status === 401) return { code, kind: 'authentication_required' }
  if (status === 409 && CONFLICT_CODES.has(code)) return readConflict(problem.conflict)
  // Every 422 from the command surface is a semantic refusal of this exact
  // body (title_required, notes_too_long, no_fields_touched,
  // base_values_mismatch, invalid_task_details, invalid_timezone...). None
  // of them can succeed on a retry of the same immutable bytes.
  if (status === 422) return { code, kind: 'rejected' }
  if ((status === 400 || status === 404) && REJECTION_CODES.has(code)) return { code, kind: 'rejected' }
  return null
}

export { CONFLICT_CODES, REJECTION_CODES, classifyServerRefusal }
export type { ServerRefusal }
