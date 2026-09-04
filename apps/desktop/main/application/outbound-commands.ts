/**
 * O-41: the durable outbound intent for every task mutation that is NOT a
 * capture.
 *
 * Until this module existed, `type: 'capture_task'` was the only command
 * this client could construct, so completing, reopening, trashing,
 * restoring, retitling and moving to Today were durable on this Mac and
 * invisible to the server forever. The seam had only ever been built for
 * one command type, which stayed invisible while no packaged path reached a
 * real server at all (O-34).
 *
 * The capture path (`DesktopApplication.capture`) is the reference
 * implementation and this follows it exactly rather than inventing a second
 * durability mechanism:
 *
 *  - the bytes are the CONTRACT's request body for the endpoint the command
 *    will be posted to, plus the optional `type` discriminator, and they are
 *    fixed HERE because these exact bytes are what a real server receives;
 *  - `version: 1` is present, because the desktop's durable bytes omitted it
 *    until O-34 pointed this client at real Phoenix and the server refused
 *    every body 400 `invalid_command`;
 *  - `type` stays IN the bytes because an outbox that survives a relaunch
 *    has nothing else to route by and re-serializing on retry is forbidden.
 *    The server verifies it against the endpoint and never routes on it
 *    (`KeeplingWeb.CommandDiscriminator`).
 *
 * This module is deliberately pure: no store, no clock, no transport. Given
 * a basis and an intent it returns bytes. That is what makes the shapes
 * assertable against the contract without an Electron process.
 *
 * ## The basis, and why a chain rather than the canonical shadow alone
 *
 * `base_values`/`base_planned_on` are what this client believed the SERVER
 * held when it formed the intent. For a task with nothing queued that is
 * the canonical shadow. For a task that already has queued mutations it is
 * the effect of the LAST queued one -- otherwise two offline edits in a row
 * would send the same stale base twice and the second would be reported as
 * a conflict against a value this client itself had just supplied. The
 * local store computes that chain (`taskSyncBasis`); this module only
 * consumes it.
 *
 * `expected_revision` has a contract minimum of 1 and a freshly captured
 * task is revision 1 on the server, so an unacknowledged task's basis
 * resolves to 1 rather than to a fabricated higher number.
 *
 * Each command's EFFECT records `expectedRevision + 1`, because that is
 * what the server produces when it accepts one (`Task#finish` sets
 * `revision: task.revision + 1`). Without that, two commands queued on one
 * task before the first is acknowledged would both claim the same expected
 * revision, and `trash_task`/`restore_task` -- which the server compares
 * EXACTLY -- would be refused on the second. This is a prediction, not a
 * fact: an `already_satisfied` answer bumps nothing, so the prediction can
 * be one too high. When it is, the server raises a real conflict and the
 * person is now told (O-38) instead of the command being retried forever.
 */

type OutboundLifecycle = 'complete' | 'reopen' | 'restore' | 'trash'

type OutboundCommandType =
  | 'complete_task'
  | 'edit_task'
  | 'plan_for_today'
  | 'reopen_task'
  | 'restore_task'
  | 'trash_task'
  | 'unplan_task'

/** The last state this client believes the server holds for one task. */
type OutboundBasis = {
  baseNotes: string
  basePlannedOn: string | null
  baseTitle: string
  expectedRevision: number
}

type OutboundIntent =
  | { kind: 'edit'; notes: string; taskId: string; title: string }
  | { kind: 'lifecycle'; lifecycle: OutboundLifecycle; taskId: string }
  | { kind: 'move_today'; planned: boolean; taskId: string }

/**
 * Structurally a `SyncSnapshot`. Declared locally so this module imports
 * nothing from `DesktopApplication` and the dependency runs one way only.
 */
type OutboundSnapshot = {
  id: string
  notes: string
  planned_on: string | null
  revision: number
  title: string
}

type OutboundCommand = {
  commandBytes: string
  effect: { entityId: string; snapshot: OutboundSnapshot }
  resourceKeys: string[]
  type: OutboundCommandType
}

const LIFECYCLE_COMMAND_TYPES: Readonly<Record<OutboundLifecycle, OutboundCommandType>> = Object.freeze({
  complete: 'complete_task',
  reopen: 'reopen_task',
  restore: 'restore_task',
  trash: 'trash_task',
})

/**
 * The endpoint path segment for a command type. This is the SAME derivation
 * the adapter performs on the durable bytes (`type.replaceAll('_', '-')`),
 * stated once here so a test can assert every type this module emits
 * resolves to a path the contract actually publishes.
 */
const outboundCommandPath = (type: OutboundCommandType): string => `/commands/${type.replaceAll('_', '-')}`

const assertBasis = (basis: OutboundBasis): void => {
  if (!Number.isSafeInteger(basis.expectedRevision) || basis.expectedRevision < 1) {
    throw new Error('outbound command basis revision is invalid')
  }
}

/**
 * Builds the exact serialized bytes for one non-capture mutation.
 *
 * `mutationId` is supplied rather than generated so the caller owns identity
 * exactly as `capture` does, and so a test can pin the bytes.
 */
const buildOutboundCommand = (
  intent: OutboundIntent,
  basis: OutboundBasis,
  mutationId: string,
): OutboundCommand => {
  assertBasis(basis)
  const resourceKeys = [`task:${intent.taskId}`]

  if (intent.kind === 'edit') {
    const title = intent.title.trim()
    if (title.length === 0 || [...title].length > 512) {
      throw new Error('task title must contain between 1 and 512 Unicode scalar values')
    }
    if ([...intent.notes].length > 50_000) throw new Error('task notes must not exceed 50000 characters')
    // `fields` and `base_values` MUST carry the same key set: the server
    // refuses a mismatched pair as `invalid_command` before any merge
    // happens (CommandController.decode_edit). Sending both touched fields
    // every time keeps that true without the client having to decide what
    // "touched" means across a relaunch.
    const commandBytes = JSON.stringify({
      base_values: { notes: basis.baseNotes, title: basis.baseTitle },
      expected_revision: basis.expectedRevision,
      fields: { notes: intent.notes, title },
      mutation_id: mutationId,
      task_id: intent.taskId,
      type: 'edit_task',
      version: 1,
    })
    return {
      commandBytes,
      effect: {
        entityId: intent.taskId,
        snapshot: {
          id: intent.taskId,
          notes: intent.notes,
          planned_on: basis.basePlannedOn,
          revision: basis.expectedRevision + 1,
          title,
        },
      },
      resourceKeys,
      type: 'edit_task',
    }
  }

  if (intent.kind === 'lifecycle') {
    const type = LIFECYCLE_COMMAND_TYPES[intent.lifecycle]
    const commandBytes = JSON.stringify({
      expected_revision: basis.expectedRevision,
      mutation_id: mutationId,
      task_id: intent.taskId,
      type,
      version: 1,
    })
    return {
      commandBytes,
      effect: {
        entityId: intent.taskId,
        // A lifecycle transition changes no detail field, so the effect
        // carries the basis values verbatim. This matters: the local
        // store replays outbox effects over the canonical shadow, and an
        // effect that dropped the title would blank the row on the next
        // pull.
        snapshot: {
          id: intent.taskId,
          notes: basis.baseNotes,
          planned_on: basis.basePlannedOn,
          revision: basis.expectedRevision + 1,
          title: basis.baseTitle,
        },
      },
      resourceKeys,
      type,
    }
  }

  const type: OutboundCommandType = intent.planned ? 'plan_for_today' : 'unplan_task'
  const commandBytes = JSON.stringify({
    base_planned_on: basis.basePlannedOn,
    expected_revision: basis.expectedRevision,
    mutation_id: mutationId,
    task_id: intent.taskId,
    type,
    version: 1,
  })
  return {
    commandBytes,
    effect: {
      entityId: intent.taskId,
      snapshot: {
        id: intent.taskId,
        notes: basis.baseNotes,
        // The account day that `plan_for_today` resolves is the SERVER's,
        // derived from the account timezone at acceptance. This client does
        // not know it and must not invent one, so a queued plan leaves the
        // planned date unknown (`null`) until a real acknowledgement or
        // pull supplies it. The honest consequence is recorded in
        // 03-22-SUMMARY.md: planning and then unplanning the SAME task
        // while offline sends a base the server has moved past, and the
        // server answers with a real conflict -- which is now surfaced
        // (O-38) rather than swallowed.
        planned_on: null,
        revision: basis.expectedRevision + 1,
        title: basis.baseTitle,
      },
    },
    resourceKeys,
    type,
  }
}

export { LIFECYCLE_COMMAND_TYPES, buildOutboundCommand, outboundCommandPath }
export type {
  OutboundBasis,
  OutboundCommand,
  OutboundCommandType,
  OutboundIntent,
  OutboundLifecycle,
  OutboundSnapshot,
}
