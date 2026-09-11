import { useEffect, useMemo, useRef, useState } from 'react'

import type { ClientFacade, ConflictFieldName, WorkspaceConflictView } from '../ClientFacade'

/**
 * Inline conflict presentation (D-41). Conflicts never overlay or replace the
 * task detail silently -- the affected fields' two values stay visible side
 * by side until the person makes an explicit mine/current choice through the
 * named `resolveConflict` operation.
 *
 * Widened from a single-field, single-choice chooser to one labelled row per
 * affected field (O-44/D-37): a field the conflict payload does not name is
 * not rendered at all, and a lifecycle/Trash divergence gets its own row
 * stated in plain lifecycle words rather than a title diff. Choices stage
 * locally and mutate nothing until the whole set is submitted at once.
 */
type ConflictResolverProps = {
  conflict: WorkspaceConflictView
  facade: ClientFacade
}

const FIELD_LABELS: Record<ConflictFieldName, string> = {
  completion: 'Completion',
  deadline: 'Deadline',
  notes: 'Notes',
  plannedDate: 'Planned date',
  project: 'Project',
  tags: 'Tags',
  title: 'Title',
  trashStatus: 'Trash status',
}

// Existing six-line collapse-with-disclosure pattern (01-UI-SPEC.md),
// applied per row instead of once per conflict.
const needsDisclosure = (value: string | null) =>
  value !== null && (value.split('\n').length > 6 || value.length > 320)

function ConflictFieldValue({ id, label, value }: { id: string; label: string; value: string | null }) {
  const [expanded, setExpanded] = useState(false)
  const collapse = needsDisclosure(value)

  return (
    <p>
      <strong>{label}:</strong>{' '}
      <span
        id={id}
        style={
          collapse && !expanded
            ? { WebkitBoxOrient: 'vertical', WebkitLineClamp: 6, display: '-webkit-box', overflow: 'hidden' }
            : undefined
        }
      >
        {value ?? ''}
      </span>
      {collapse ? (
        <button
          aria-controls={id}
          aria-expanded={expanded}
          onClick={() => setExpanded((current) => !current)}
          type="button"
        >
          {expanded ? 'Show less' : 'Show full value'}
        </button>
      ) : null}
    </p>
  )
}

function ConflictResolver({ conflict, facade }: ConflictResolverProps) {
  const [selections, setSelections] = useState<Partial<Record<ConflictFieldName, 'current' | 'mine'>>>({})
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const headingRef = useRef<HTMLHeadingElement>(null)

  useEffect(() => {
    headingRef.current?.focus()
    setSelections({})
    setProblem(null)
  }, [conflict.id])

  const complete = useMemo(
    () => conflict.fields.length > 0 && conflict.fields.every((field) => selections[field.field] !== undefined),
    [conflict.fields, selections],
  )

  const choose = (field: ConflictFieldName, choice: 'current' | 'mine') => {
    if (busy) return
    setSelections((current) => ({ ...current, [field]: choice }))
  }

  const submit = async () => {
    if (busy || !complete) return
    setBusy(true)
    const outcome = await facade.resolveConflict(selections)
    setBusy(false)
    // Reuses the existing rejected/uncertain-result copy verbatim -- both
    // classes arrive here as `{ kind: 'rejected', message }`, so no new
    // error language is introduced by this row-level widening.
    if (outcome.kind === 'rejected') setProblem(outcome.message)
  }

  return (
    <section aria-labelledby={`workspace-conflict-${conflict.id}-title`} role="region">
      <h2 id={`workspace-conflict-${conflict.id}-title`} ref={headingRef} tabIndex={-1}>
        This task changed somewhere else.
      </h2>
      <p>Your draft is still here. Choose which title Keepling should keep.</p>
      {conflict.fields.map((field) => {
        const label = FIELD_LABELS[field.field]
        const groupName = `workspace-conflict-${conflict.id}-${field.field}`
        const selection = selections[field.field]

        return (
          <fieldset key={field.field}>
            <legend>{label}</legend>
            <ConflictFieldValue id={`${groupName}-mine`} label="Your version" value={field.mine} />
            <ConflictFieldValue id={`${groupName}-current`} label="Current version" value={field.current} />
            <label>
              <input
                checked={selection === 'mine'}
                disabled={busy}
                name={groupName}
                onChange={() => choose(field.field, 'mine')}
                type="radio"
                value="mine"
              />
              Use mine
            </label>
            <label>
              <input
                checked={selection === 'current'}
                disabled={busy}
                name={groupName}
                onChange={() => choose(field.field, 'current')}
                type="radio"
                value="current"
              />
              Use current
            </label>
          </fieldset>
        )
      })}
      {problem ? <p role="alert">{problem}</p> : null}
      <button disabled={busy || !complete} onClick={() => void submit()} type="button">
        Save resolution
      </button>
    </section>
  )
}

export default ConflictResolver
