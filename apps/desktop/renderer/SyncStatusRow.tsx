import { useEffect, useState } from 'react'

/**
 * The MAC-04 status row (O-30), and the surface that finally performs its
 * recovery actions (O-42).
 *
 * `DesktopApplication` has published a closed, main-owned presentation row
 * for every synchronization and recovery state since Plan 03-05, and the
 * preload bridge has delivered it with a sequence contract since 03-08 --
 * but nothing ever RENDERED it. 03-19 fixed the copy half. The ACTIONS
 * stayed unread: `presentation.ts` authors up to three per state,
 * `preload/contracts.ts` validates the array, and this component read only
 * `summary.copy` and `summary.kind`. So a person who was signed out was
 * told to sign in with no way to do it from that surface, and MAC-04's
 * "inspect ... without reading logs" was satisfied for copy but not for
 * remedy.
 *
 * Four properties it deliberately keeps:
 *
 *  - It renders main's copy and main's LABELS verbatim and infers nothing.
 *    The renderer never derives a state, never re-words a row, never
 *    invents a count, and never invents an action: `summary.actions` is
 *    authored in `main/application/presentation.ts` and is the single
 *    source of what a person is offered (D-26/D-27). This component decides
 *    only what each code DOES.
 *  - A `null` copy renders NOTHING. `healthy` and a pass inside the
 *    anti-flicker grace period are quiet states by design, so the row must
 *    disappear rather than say "everything is fine" -- a persistent
 *    reassurance is exactly the claim this app must not make.
 *  - It is NOT a live region. The workspace already owns exactly one
 *    announcer (`packages/web-ui/src/recovery/SyncRecovery.tsx`), and
 *    `test/e2e/accessibility.spec.ts` pins that count at one on purpose --
 *    a second announcer would turn every background synchronization change
 *    into an interruption of whatever someone is typing. This row is a
 *    labeled, always-inspectable complementary landmark instead, which is
 *    precisely what MAC-04 asks for: a state a person can INSPECT without
 *    reading logs. The action RESULT below is likewise a plain paragraph,
 *    not a second `role="status"`.
 *  - No action is decorative. Every code the presentation can author has a
 *    real effect here, and `assertExhaustive` makes adding a code without
 *    an effect a TYPE error rather than another silently dead button.
 */
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

type PresentationSummary = {
  actions: Array<{ code: RecoveryActionCode; label: string }>
  copy: string | null
  count: number | null
  kind: string
}

/**
 * The Sync & Recovery strip the workspace already owns. `inspect`,
 * `review`, and `show_recovery_options` all mean "take me to where I can
 * see and undo what happened", and that region IS that place -- moving
 * focus there is the remedy, not a new panel.
 */
const focusRecoveryRegion = () => {
  document.getElementById('sync-recovery-region')?.focus()
}

function SyncStatusRow() {
  const [summary, setSummary] = useState<PresentationSummary | null>(null)
  const [busyCode, setBusyCode] = useState<RecoveryActionCode | null>(null)
  const [result, setResult] = useState<string | null>(null)

  useEffect(
    () =>
      window.keepling.subscribePresentation((presentation) => {
        setSummary(presentation.summary as PresentationSummary)
        // A new row supersedes whatever the previous action reported. The
        // authored copy is always the more authoritative of the two.
        setResult(null)
      }),
    [],
  )

  const perform = async (code: RecoveryActionCode): Promise<string | null> => {
    switch (code) {
      case 'inspect':
      case 'review':
      case 'show_recovery_options':
        focusRecoveryRegion()
        return null
      case 'retry':
      case 'check_again': {
        const outcome = await window.keepling.retrySync()
        if (outcome.kind === 'ran') return null
        // The row main publishes says what went wrong; this only confirms
        // the press landed on something.
        return outcome.kind === 'unavailable'
          ? 'No Keepling server is connected on this Mac.'
          : 'Couldn’t reach the server. Your changes stay on this Mac.'
      }
      case 'sign_in':
        await window.keepling.beginSignIn()
        return null
      case 'review_conflict': {
        const conflicts = await window.keepling.listConflicts()
        // A conflict the server named a divergent title for has a
        // mine/current chooser in the workspace; a lifecycle or Trash
        // conflict does not, and the server's own recovery action for those
        // is `refresh_task`. Both land somewhere real.
        if (conflicts.length > 0) {
          focusRecoveryRegion()
          return null
        }
        const outcome = await window.keepling.retrySync()
        return outcome.kind === 'ran' ? 'Refreshed from the server.' : null
      }
      case 'export': {
        const outcome = await window.keepling.exportLocalData()
        return outcome.kind === 'exported'
          ? `Exported ${String(outcome.taskCount)} tasks to ${outcome.path}`
          : 'Couldn’t export the tasks saved on this Mac.'
      }
      case 'remove_local_data': {
        // Never `confirmRemoveAnyway: true` from a one-press button. The
        // main-owned state machine refuses while unsent intent exists and
        // reports what is at stake, which is the confirmation step (D-24).
        const outcome = await window.keepling.removeLocalData({ confirmRemoveAnyway: false })
        if (outcome.kind === 'removed') return 'Removed the tasks saved on this Mac.'
        if (outcome.kind === 'blocked_pending_intent') {
          return `${String(outcome.pendingCount)} changes have not reached a server yet. Export them first.`
        }
        return 'Couldn’t remove the tasks saved on this Mac.'
      }
      case 'retry_save':
      case 'retry_opening': {
        // The store worker transparently retries OPENING the local store on
        // every request, so an ordinary read is the retry -- an externally
        // repaired permission or disk-full condition self-heals here.
        try {
          await window.keepling.snapshot()
          return null
        } catch {
          return 'Keepling still can’t open the tasks saved on this Mac.'
        }
      }
      default: {
        const unreachable: never = code
        throw new Error(`unhandled recovery action: ${String(unreachable)}`)
      }
    }
  }

  const dispatch = async (code: RecoveryActionCode) => {
    if (busyCode !== null) return
    setBusyCode(code)
    try {
      setResult(await perform(code))
    } catch {
      setResult('That didn’t work. Nothing was changed.')
    } finally {
      setBusyCode(null)
    }
  }

  if (summary === null || summary.copy === null) return null

  return (
    <aside
      aria-label="Synchronization status"
      data-sync-status={summary.kind}
      id="sync-status-row"
    >
      {/*
        The copy is addressable on its own (`data-sync-copy`) so an assertion
        about WHAT A PERSON IS TOLD is not silently coupled to which recovery
        buttons happen to sit beside it -- reading the whole landmark's text
        would make every future action change look like a copy regression.
      */}
      <p data-sync-copy="true">{summary.copy}</p>
      {summary.actions.map((action) => (
        <button
          data-recovery-action={action.code}
          disabled={busyCode !== null}
          key={action.code}
          onClick={() => void dispatch(action.code)}
          type="button"
        >
          {action.label}
        </button>
      ))}
      {result === null ? null : <p data-recovery-result="true">{result}</p>}
    </aside>
  )
}

export default SyncStatusRow
