import { useEffect, useState } from 'react'

import type { ClientFacade, RecoveryAvailabilityView } from '../ClientFacade'

/**
 * Latest supported undo recovery strip (D-14/D-41). Names what is durable
 * ("Saved on this Mac" only after atomic local commit) and offers the exact
 * next safe action through the named `undoLastChange` operation. When
 * nothing is recoverable the healthy copy says so explicitly rather than
 * showing nothing (UI-SPEC empty-state contract).
 */
type SyncRecoveryProps = {
  facade: ClientFacade
}

function SyncRecovery({ facade }: SyncRecoveryProps) {
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
    <aside aria-label="Latest recovery action" data-workspace-recovery="true">
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
    </aside>
  )
}

export default SyncRecovery
