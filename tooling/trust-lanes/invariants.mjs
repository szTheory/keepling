// tooling/trust-lanes/invariants.mjs (D-46, 06-12-PLAN.md Task 1)
//
// Eight schema-level predicates evaluated over a reconciliation dataset the
// oracle (oracle.mjs) assembles from three independent reads: the server
// (its own read endpoints plus a select-only database identity), a desktop
// SQLite store opened read-only, and an iOS SQLite store pulled from a
// device. This module imports nothing from any client package and performs
// no I/O of its own -- it is pure functions over plain data, which is what
// keeps a bug shared between a client and its checker from hiding a
// violation from both: this checker never runs the client's own code path.
//
// Every predicate returns { id, samples, violations }. `samples` is the
// number of independent things this invariant actually looked at on this
// run -- a lane that cannot report a positive count for its own contents is
// treated as a failure by verify-trust-soak.mjs, never a silently-skipped
// green. `violations` is an array of records drawn only from the closed
// REASONS vocabulary below, carrying identifiers, field names, revisions
// and reasons -- never plaintext content. Content the oracle compares is
// always a keyed digest computed under a run-local key (see keyedDigest
// below); nothing in this module ever receives, retains, or emits raw task
// titles, notes, prompts, tokens, or arbitrary identifiers.

import { createHmac } from 'node:crypto'

/** The eight invariant identifiers this module implements, in order. */
export const INVARIANT_IDS = Object.freeze(['I1', 'I2', 'I3', 'I4', 'I5', 'I6', 'I7', 'I8'])

/**
 * The closed violation-reason vocabulary. A violation record's `reason`
 * field is always one of these strings -- this is the same discipline the
 * iOS DiagnosticEvent type already applies to its own closed fields.
 */
export const REASONS = Object.freeze({
  UNSETTLED_INTENT: 'UNSETTLED_INTENT',
  RECEIPT_ABSENT: 'RECEIPT_ABSENT',
  REFUSAL_NOT_DURABLE: 'REFUSAL_NOT_DURABLE',
  PROJECTION_MISMATCH: 'PROJECTION_MISMATCH',
  FEED_GAP: 'FEED_GAP',
  CURSOR_REGRESSION: 'CURSOR_REGRESSION',
  REVISION_NOT_MONOTONIC: 'REVISION_NOT_MONOTONIC',
  TOMBSTONE_INCOHERENT: 'TOMBSTONE_INCOHERENT',
  ACTIVITY_INCOMPLETE: 'ACTIVITY_INCOMPLETE',
})

const REASON_VALUES = new Set(Object.values(REASONS))

/**
 * A client is considered to have gone quiet -- "no client process is
 * running" in D-46's own words -- once an in-flight outbox row has sat
 * unresolved longer than this window. A one-shot read cannot observe
 * process liveness directly, so age is the measurable proxy: a real
 * in-flight request settles in seconds, not minutes.
 */
export const STALE_IN_FLIGHT_MS = 5 * 60 * 1000

const keyedDigest = (runKey, value) =>
  createHmac('sha256', String(runKey)).update(String(value)).digest('hex')

const assertReason = (reason) => {
  if (!REASON_VALUES.has(reason)) {
    throw new Error(`invariants.mjs: "${reason}" is not in the closed REASONS vocabulary`)
  }
  return reason
}

const violation = (reason, fields) => ({ reason: assertReason(reason), ...fields })

const clientEntries = (dataset) =>
  [
    dataset.desktop ? { source: 'desktop', data: dataset.desktop } : null,
    dataset.ios ? { source: 'ios', data: dataset.ios } : null,
  ].filter(Boolean)

/** I1 -- no unsettled intent: no outbox row sits in-flight with no client process running. */
const i1NoUnsettledIntent = (dataset) => {
  const violations = []
  let samples = 0
  for (const { source, data } of clientEntries(dataset)) {
    for (const row of data.outbox ?? []) {
      samples += 1
      if (row.state === 'in_flight' && (row.ageMs ?? 0) > STALE_IN_FLIGHT_MS) {
        violations.push(
          violation(REASONS.UNSETTLED_INTENT, {
            source,
            mutationId: row.mutationId,
            ageMs: row.ageMs,
          }),
        )
      }
    }
  }
  return { id: 'I1', samples, violations }
}

/** I2 -- receipt closure: a mutation id absent from both a client's outbox and the server's receipts is silent loss. */
const i2ReceiptClosure = (dataset) => {
  const violations = []
  let samples = 0
  const serverMutationIds = new Set((dataset.server?.receipts ?? []).map((r) => r.mutationId))
  for (const { source, data } of clientEntries(dataset)) {
    const outboxIds = new Set((data.outbox ?? []).map((r) => r.mutationId))
    for (const command of data.commands ?? []) {
      samples += 1
      const knownToServer = dataset.server != null && serverMutationIds.has(command.mutationId)
      const knownLocally = outboxIds.has(command.mutationId)
      if (dataset.server != null && !knownToServer && !knownLocally) {
        violations.push(
          violation(REASONS.RECEIPT_ABSENT, { source, mutationId: command.mutationId }),
        )
      }
    }
  }
  return { id: 'I2', samples, violations }
}

/** I3 -- refusal durability: every refused/conflicted receipt has a durable local home. */
const i3RefusalDurability = (dataset) => {
  const violations = []
  let samples = 0
  if (dataset.server == null) return { id: 'I3', samples, violations }
  const refusedReceipts = (dataset.server.receipts ?? []).filter((r) =>
    ['rejected', 'conflict'].includes(r.outcome),
  )
  for (const { source, data } of clientEntries(dataset)) {
    const durableIds = new Set((data.refusals ?? []).map((f) => f.mutationId))
    const conflictIds = new Set((data.conflicts ?? []).map((c) => c.mutationId))
    for (const receipt of refusedReceipts) {
      if (!(data.commands ?? []).some((c) => c.mutationId === receipt.mutationId)) continue
      samples += 1
      if (!durableIds.has(receipt.mutationId) && !conflictIds.has(receipt.mutationId)) {
        violations.push(
          violation(REASONS.REFUSAL_NOT_DURABLE, { source, mutationId: receipt.mutationId }),
        )
      }
    }
  }
  return { id: 'I3', samples, violations }
}

/** I4 -- projection agreement: the client projection and the server agree, or the difference is explained by an outbox row. */
const i4ProjectionAgreement = (dataset) => {
  const violations = []
  let samples = 0
  if (dataset.server == null) return { id: 'I4', samples, violations }
  const serverByEntity = new Map((dataset.server.entities ?? []).map((e) => [e.entityId, e]))
  for (const { source, data } of clientEntries(dataset)) {
    const pendingEntityIds = new Set((data.outbox ?? []).map((r) => r.entityId).filter(Boolean))
    for (const entity of data.entities ?? []) {
      const serverEntity = serverByEntity.get(entity.entityId)
      if (!serverEntity) continue
      samples += 1
      if (entity.digest !== serverEntity.digest && !pendingEntityIds.has(entity.entityId)) {
        violations.push(
          violation(REASONS.PROJECTION_MISMATCH, {
            source,
            entityId: entity.entityId,
            revision: entity.revision,
          }),
        )
      }
    }
  }
  return { id: 'I4', samples, violations }
}

/** I5 -- feed continuity: no gap in the ordered feed, and a client cursor never moves backward. */
const i5FeedContinuity = (dataset) => {
  const violations = []
  let samples = 0
  const feed = dataset.server?.feed
  if (feed) {
    const entries = [...(feed.entries ?? [])].sort(
      (a, b) => a.sequence - b.sequence || a.ordinal - b.ordinal,
    )
    for (let i = 1; i < entries.length; i += 1) {
      samples += 1
      const prev = entries[i - 1]
      const current = entries[i]
      const contiguous =
        current.sequence === prev.sequence
          ? current.ordinal === prev.ordinal + 1
          : current.sequence === prev.sequence + 1 && current.ordinal === 0
      if (!contiguous) {
        violations.push(
          violation(REASONS.FEED_GAP, {
            afterSequence: prev.sequence,
            afterOrdinal: prev.ordinal,
            atSequence: current.sequence,
            atOrdinal: current.ordinal,
          }),
        )
      }
    }
  }
  for (const { source, data } of clientEntries(dataset)) {
    if (data.priorCursor == null || data.cursor == null) continue
    samples += 1
    if (Number(data.cursor) < Number(data.priorCursor)) {
      violations.push(
        violation(REASONS.CURSOR_REGRESSION, {
          source,
          cursor: data.cursor,
          priorCursor: data.priorCursor,
        }),
      )
    }
  }
  return { id: 'I5', samples, violations }
}

/** I6 -- revision monotonicity: per entity, on both sides, against the last recorded run. */
const i6RevisionMonotonicity = (dataset) => {
  const violations = []
  let samples = 0
  const sides = [
    dataset.server ? { source: 'server', entities: dataset.server.entities ?? [] } : null,
    ...clientEntries(dataset).map(({ source, data }) => ({ source, entities: data.entities ?? [] })),
  ].filter(Boolean)
  for (const { source, entities } of sides) {
    for (const entity of entities) {
      if (entity.priorRevision == null) continue
      samples += 1
      if (entity.revision < entity.priorRevision) {
        violations.push(
          violation(REASONS.REVISION_NOT_MONOTONIC, {
            source,
            entityId: entity.entityId,
            revision: entity.revision,
            priorRevision: entity.priorRevision,
          }),
        )
      }
    }
  }
  return { id: 'I6', samples, violations }
}

/** I7 -- tombstone and restore coherence. */
const i7TombstoneCoherence = (dataset) => {
  const violations = []
  let samples = 0
  const sides = [
    dataset.server ? { source: 'server', entities: dataset.server.entities ?? [] } : null,
    ...clientEntries(dataset).map(({ source, data }) => ({ source, entities: data.entities ?? [] })),
  ].filter(Boolean)
  for (const { source, entities } of sides) {
    for (const entity of entities) {
      if (entity.trashedAt == null && entity.restoredAt == null) continue
      samples += 1
      const incoherent =
        entity.restoredAt != null &&
        entity.trashedAt != null &&
        new Date(entity.restoredAt).getTime() < new Date(entity.trashedAt).getTime()
      if (incoherent) {
        violations.push(
          violation(REASONS.TOMBSTONE_INCOHERENT, {
            source,
            entityId: entity.entityId,
            revision: entity.revision,
          }),
        )
      }
    }
  }
  return { id: 'I7', samples, violations }
}

/**
 * I8 -- activity completeness, in the direction the existing foreign key
 * does not cover: task_activities.task_id has a foreign key to tasks, so an
 * orphan activity is already structurally impossible. The uncovered
 * direction is the other way -- an accepted mutation with no matching
 * activity record at all, which is an audit trail the FK cannot protect.
 */
const i8ActivityCompleteness = (dataset) => {
  const violations = []
  let samples = 0
  if (dataset.server == null) return { id: 'I8', samples, violations }
  const activityMutationIds = new Set((dataset.server.activities ?? []).map((a) => a.mutationId))
  const acceptedReceipts = (dataset.server.receipts ?? []).filter((r) =>
    ['accepted', 'already_satisfied'].includes(r.outcome),
  )
  for (const receipt of acceptedReceipts) {
    samples += 1
    if (!activityMutationIds.has(receipt.mutationId)) {
      violations.push(violation(REASONS.ACTIVITY_INCOMPLETE, { mutationId: receipt.mutationId }))
    }
  }
  return { id: 'I8', samples, violations }
}

const INVARIANTS = Object.freeze({
  I1: i1NoUnsettledIntent,
  I2: i2ReceiptClosure,
  I3: i3RefusalDurability,
  I4: i4ProjectionAgreement,
  I5: i5FeedContinuity,
  I6: i6RevisionMonotonicity,
  I7: i7TombstoneCoherence,
  I8: i8ActivityCompleteness,
})

/** Evaluate every invariant (or a named subset) over one dataset. */
export const evaluateInvariants = (dataset, ids = INVARIANT_IDS) =>
  ids.map((id) => {
    const fn = INVARIANTS[id]
    if (!fn) throw new Error(`invariants.mjs: unknown invariant id "${id}"`)
    return fn(dataset)
  })

export { keyedDigest }
