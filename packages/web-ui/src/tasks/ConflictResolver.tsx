import { useEffect, useRef, useState } from 'react'

import type { ClientFacade, WorkspaceConflictView } from '../ClientFacade'

/**
 * Inline conflict presentation (D-41). Conflicts never overlay or replace the
 * task detail silently -- the affected field's two values stay visible side
 * by side until the person makes an explicit mine/current choice through the
 * named `resolveConflict` operation.
 */
type ConflictResolverProps = {
  conflict: WorkspaceConflictView
  facade: ClientFacade
}

function ConflictResolver({ conflict, facade }: ConflictResolverProps) {
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const headingRef = useRef<HTMLHeadingElement>(null)

  useEffect(() => {
    headingRef.current?.focus()
  }, [conflict.id])

  const choose = async (choice: 'current' | 'mine') => {
    if (busy) return
    setBusy(true)
    const outcome = await facade.resolveConflict(choice)
    setBusy(false)
    if (outcome.kind === 'rejected') setProblem(outcome.message)
  }

  return (
    <section aria-labelledby={`workspace-conflict-${conflict.id}-title`} role="region">
      <h2 id={`workspace-conflict-${conflict.id}-title`} ref={headingRef} tabIndex={-1}>
        This task changed somewhere else.
      </h2>
      <p>Your draft is still here. Choose which title Keepling should keep.</p>
      <div>
        <p>
          <strong>Your version:</strong> {conflict.mine}
        </p>
        <p>
          <strong>Current version:</strong> {conflict.current}
        </p>
      </div>
      {problem ? <p role="alert">{problem}</p> : null}
      <button disabled={busy} onClick={() => void choose('mine')} type="button">
        Use mine
      </button>
      <button disabled={busy} onClick={() => void choose('current')} type="button">
        Use current
      </button>
    </section>
  )
}

export default ConflictResolver
