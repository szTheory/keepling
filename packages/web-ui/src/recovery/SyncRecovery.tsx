import { useEffect, useState } from 'react'

import type { ClientFacade, RecoveryAvailabilityView, UnresolvedRefusalView } from '../ClientFacade'

/**
 * Latest supported undo recovery strip (D-14/D-41). Names what is durable
 * ("Saved on this Mac" only after atomic local commit) and offers the exact
 * next safe action through the named `undoLastChange` operation. When
 * nothing is recoverable the healthy copy says so explicitly rather than
 * showing nothing (UI-SPEC empty-state contract).
 *
 * Widened (Task 2, O-44) to also surface every unresolved refusal for a task
 * the person is not currently viewing -- the same strip, no new UI surface.
 * `onReviewRefusal` navigates to the task and opens its conflict resolver;
 * the eligible-undo entry is preserved unchanged alongside any refusals.
 */
type SyncRecoveryProps = {
  facade: ClientFacade
  onReviewRefusal?: (taskId: string) => void
  unresolvedRefusals?: readonly UnresolvedRefusalView[]
}

function SyncRecovery({ facade, onReviewRefusal, unresolvedRefusals = [] }: SyncRecoveryProps) {
  const [availability, setAvailability] = useState<RecoveryAvailabilityView>(() =>
    facade.getRecoveryAvailability(),
  )
  const [busy, setBusy] = useState(false)
  const [settledMessage, setSettledMessage] = useState<string | null>(null)

  useEffect(
    () =>
      facade.subscribeRecovery((next) => {
        setAvailability(next)
        if (next !== null) setSettledMessage(null)
      }),
    [facade],
  )

  const undo = async () => {
    if (busy || availability === null) return
    setBusy(true)
    const outcome = await facade.undoLastChange()
    setBusy(false)
    setSettledMessage(outcome.kind === 'accepted' ? 'Change undone.' : outcome.message)
  }

  return (
    <aside
      aria-label="Latest recovery action"
      data-workspace-recovery="true"
      id="sync-recovery-region"
      tabIndex={-1}
    >
      <div aria-atomic="true" aria-live="polite" role="status">
        {settledMessage !== null ? (
          <p>{settledMessage}</p>
        ) : availability === null ? (
          <p>No Changes Need Your Attention</p>
        ) : (
          <p>Latest action can be recovered.</p>
        )}
      </div>
      {availability !== null ? (
        <button disabled={busy} onClick={() => void undo()} type="button">
          {busy ? 'Undoing…' : availability.label}
        </button>
      ) : null}
      {unresolvedRefusals.map((refusal) => (
        <p key={refusal.taskId}>
          {refusal.taskTitle} changed while you were away. Review the conflict.{' '}
          <button onClick={() => onReviewRefusal?.(refusal.taskId)} type="button">
            Review conflict
          </button>
        </p>
      ))}
    </aside>
  )
}

export default SyncRecovery
