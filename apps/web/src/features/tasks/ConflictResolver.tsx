import { useEffect, useMemo, useRef, useState } from 'react'

import {
  KeeplingApiError,
  resolveTaskConflict,
  type CommandAcknowledgement,
  type ConflictResolutionSubmission,
  type TaskConflict,
  type TaskConflictField,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import { authenticationRecoveryFor } from '@/commands/submission'

type ConflictResolverProps = {
  conflict: TaskConflict
  csrfToken: string
  onAcknowledged: (acknowledgement: CommandAcknowledgement) => void | Promise<void>
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onKeepEditing: (field: TaskConflictField['field']) => void
  taskId: string
}

type ResolutionState =
  | { kind: 'authentication' }
  | { kind: 'idle' }
  | { kind: 'pending' }
  | { kind: 'problem'; message: string }
  | { kind: 'stale' }
  | { kind: 'unknown' }

const fieldLabel = (field: TaskConflictField['field']) =>
  field === 'title' ? 'Title' : 'Notes'

const valueNeedsDisclosure = (value: string | null) =>
  value !== null && (value.split('\n').length > 6 || value.length > 320)

function ConflictValue({
  id,
  label,
  value,
}: {
  id: string
  label: string
  value: string | null
}) {
  const [expanded, setExpanded] = useState(false)
  const needsDisclosure = valueNeedsDisclosure(value)

  return (
    <div className="min-w-0 rounded-lg border border-border bg-background p-3">
      <h4 className="text-sm font-semibold">{label}</h4>
      <p
        className={`mt-2 whitespace-pre-wrap break-words text-base ${
          needsDisclosure && !expanded ? 'line-clamp-6' : ''
        }`}
        id={id}
      >
        {value ?? 'No value'}
      </p>
      {needsDisclosure ? (
        <button
          aria-controls={id}
          aria-expanded={expanded}
          className="mt-2 min-h-11 text-sm font-semibold text-primary underline"
          onClick={() => setExpanded((current) => !current)}
          type="button"
        >
          {expanded ? 'Show less' : 'Show full value'}
        </button>
      ) : null}
    </div>
  )
}

function ConflictResolver({
  conflict,
  csrfToken,
  onAcknowledged,
  onAuthenticationRequired,
  onKeepEditing,
  taskId,
}: ConflictResolverProps) {
  const [selections, setSelections] = useState<ConflictResolutionSubmission['selections']>({})
  const [submission, setSubmission] = useState<ConflictResolutionSubmission | null>(null)
  const [state, setState] = useState<ResolutionState>({ kind: 'idle' })
  const headingRef = useRef<HTMLHeadingElement>(null)

  useEffect(() => {
    headingRef.current?.focus()
  }, [])

  const complete = useMemo(
    () => conflict.fields.every((field) => selections[field.field] !== undefined),
    [conflict.fields, selections],
  )

  const choose = (field: TaskConflictField['field'], selection: 'current' | 'mine') => {
    setSelections((current) => ({ ...current, [field]: selection }))
    setSubmission(null)
    setState({ kind: 'idle' })
  }

  const deliver = async (
    current: ConflictResolutionSubmission,
    activeCsrfToken = csrfToken,
  ) => {
    setSubmission(current)
    setState({ kind: 'pending' })

    try {
      const acknowledgement = await resolveTaskConflict(current, activeCsrfToken)
      if (
        acknowledgement.mutationId !== current.mutationId ||
        acknowledgement.taskId !== current.taskId ||
        acknowledgement.resolvedConflictId !== current.conflictId
      ) {
        setState({ kind: 'unknown' })
        return
      }

      setSubmission(null)
      await onAcknowledged(acknowledgement)
    } catch (error) {
      if (!(error instanceof KeeplingApiError)) {
        setState({ kind: 'unknown' })
      } else if (authenticationRecoveryFor(error.problem.code)) {
        const authentication = authenticationRecoveryFor(error.problem.code)!
        setState({ kind: 'authentication' })
        onAuthenticationRequired?.(
          { authentication, kind: 'not-submitted', mutationId: current.mutationId },
          (nextCsrfToken) => deliver(current, nextCsrfToken),
        )
      } else if (error.problem.code === 'task_conflict_stale') {
        setState({ kind: 'stale' })
      } else {
        setState({ kind: 'problem', message: error.message })
      }
    }
  }

  const resolve = () => {
    if (!complete || state.kind === 'pending') return

    const current =
      submission ??
      ({
        conflictId: conflict.id,
        latestRevision: conflict.latestRevision,
        mutationId: crypto.randomUUID(),
        selections: { ...selections },
        taskId,
      } satisfies ConflictResolutionSubmission)

    void deliver(current)
  }

  return (
    <section
      aria-labelledby={`task-conflict-${conflict.id}-title`}
      className="mt-6 rounded-xl border-2 border-border bg-muted p-4 sm:p-6"
      role="region"
    >
      <h2
        className="text-xl font-semibold outline-none"
        id={`task-conflict-${conflict.id}-title`}
        ref={headingRef}
        tabIndex={-1}
      >
        This task changed somewhere else.
      </h2>
      <p className="mt-2">Review the affected fields before saving again.</p>

      <div className="mt-5 space-y-5">
        {conflict.fields.map((field) => {
          const label = fieldLabel(field.field)
          const selection = selections[field.field]

          return (
            <fieldset className="rounded-lg border border-border p-4" key={field.field}>
              <legend className="px-1 text-base font-semibold">{label}</legend>
              <div className="mt-2 grid gap-3 sm:grid-cols-2">
                <ConflictValue
                  id={`task-conflict-${conflict.id}-${field.field}-mine`}
                  label="Your version"
                  value={field.mine}
                />
                <ConflictValue
                  id={`task-conflict-${conflict.id}-${field.field}-current`}
                  label="Current version"
                  value={field.current}
                />
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  aria-pressed={selection === 'mine'}
                  className={`min-h-11 rounded-lg border-2 px-3 text-sm font-semibold ${
                    selection === 'mine' ? 'border-primary' : 'border-border'
                  }`}
                  onClick={() => choose(field.field, 'mine')}
                  type="button"
                >
                  Use mine for {label}
                </button>
                <button
                  aria-pressed={selection === 'current'}
                  className={`min-h-11 rounded-lg border-2 px-3 text-sm font-semibold ${
                    selection === 'current' ? 'border-primary' : 'border-border'
                  }`}
                  onClick={() => choose(field.field, 'current')}
                  type="button"
                >
                  Use current for {label}
                </button>
              </div>
            </fieldset>
          )
        })}
      </div>

      {state.kind === 'unknown' ? (
        <div className="mt-4" role="status">
          <p>Checking whether your resolution was saved…</p>
          <Button className="mt-2" onClick={() => submission && void deliver(submission)} variant="outline">
            Check again
          </Button>
        </div>
      ) : null}
      {state.kind === 'authentication' ? (
        <div className="mt-4" role="alert">
          Sign in again to finish saving. Your changes are still here.
        </div>
      ) : null}
      {state.kind === 'stale' ? (
        <div className="mt-4" role="alert">
          This task changed again. Review the latest task before resolving it.
        </div>
      ) : null}
      {state.kind === 'problem' ? (
        <div className="mt-4" role="alert">
          Couldn’t resolve this conflict. Your changes are still here. {state.message}
        </div>
      ) : null}

      <div className="mt-5 flex flex-wrap gap-3">
        <Button disabled={!complete || state.kind === 'pending'} onClick={resolve} type="button">
          {state.kind === 'pending' ? 'Saving resolution…' : 'Save resolution'}
        </Button>
        <Button
          disabled={state.kind === 'pending'}
          onClick={() => onKeepEditing(conflict.fields[0]!.field)}
          type="button"
          variant="outline"
        >
          Keep editing
        </Button>
      </div>
    </section>
  )
}

export default ConflictResolver
