import { useState, type FormEvent, type KeyboardEvent } from 'react'

import {
  KeeplingApiError,
  getMutation,
  prepareCaptureTask,
  preparePlanForToday,
  submitPreparedTaskCommand,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type CommandAcknowledgement,
  type PlanningSubmission,
  type PreparedTaskCommand,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import { classifyKeeplingError } from '@/commands/submission'

type QuickCaptureProps = {
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onCaptured: (acknowledgement: CaptureAcknowledgement) => void
}

type Submission = {
  addToToday: boolean
  captureCommand: CaptureTaskSubmission
  captureRequest: PreparedTaskCommand
  planCommand?: PlanningSubmission
  planRequest?: PreparedTaskCommand
}

type Status =
  | { kind: 'idle' }
  | { kind: 'submitting' }
  | { kind: 'authentication-required' }
  | { kind: 'problem'; message: string }
  | { kind: 'unknown' }

function QuickCapture({ csrfToken, onAuthenticationRequired, onCaptured }: QuickCaptureProps) {
  const fieldId = 'quick-capture-title'
  const errorId = `${fieldId}-error`
  const [draft, setDraft] = useState('')
  const [addToToday, setAddToToday] = useState(false)
  const [submission, setSubmission] = useState<Submission | null>(null)
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  const finish = (acknowledgement: CommandAcknowledgement) => {
    onCaptured(acknowledgement)
    setDraft('')
    setAddToToday(false)
    setSubmission(null)
    setStatus({ kind: 'idle' })
  }

  const reconcile = async (
    acknowledgement: CommandAcknowledgement,
    current: Submission,
    activeCsrfToken: string,
  ) => {
    const activeRequest = current.planRequest ?? current.captureRequest
    if (
      acknowledgement.mutationId !== activeRequest.mutationId ||
      acknowledgement.taskId !== activeRequest.taskId
    ) {
      setStatus({ kind: 'unknown' })
      return
    }

    if (current.addToToday && current.planCommand === undefined) {
      const planCommand = {
        basePlannedOn: acknowledgement.snapshot.plannedOn,
        expectedRevision: acknowledgement.revision,
        mutationId: crypto.randomUUID(),
        taskId: acknowledgement.taskId,
      } satisfies PlanningSubmission
      const next: Submission = {
        ...current,
        planCommand,
        planRequest: preparePlanForToday(planCommand),
      }
      await deliver(next, activeCsrfToken)
      return
    }

    finish(acknowledgement)
  }

  const deliver = async (current: Submission, activeCsrfToken = csrfToken) => {
    setSubmission(current)
    setStatus({ kind: 'submitting' })

    try {
      const acknowledgement = await submitPreparedTaskCommand(
        current.planRequest ?? current.captureRequest,
        activeCsrfToken,
      )
      await reconcile(acknowledgement, current, activeCsrfToken)
    } catch (error) {
      const classification = classifyKeeplingError(error)
      if (classification.kind === 'authentication_required' && onAuthenticationRequired) {
        setStatus({ kind: 'authentication-required' })
        onAuthenticationRequired(
          {
            authentication: classification.authentication,
            kind: 'submitted-unknown',
            mutationId: (current.planRequest ?? current.captureRequest).mutationId,
          },
          (nextCsrfToken) => checkSubmission(current, nextCsrfToken),
        )
      } else if (classification.kind === 'unknown') {
        setStatus({ kind: 'unknown' })
      } else if (error instanceof KeeplingApiError) {
        setSubmission(current.planCommand ? current : null)
        setStatus({ kind: 'problem', message: error.message })
      }
    }
  }

  const checkSubmission = async (current: Submission, _activeCsrfToken = csrfToken) => {
    setStatus({ kind: 'submitting' })

    try {
      const activeRequest = current.planRequest ?? current.captureRequest
      await reconcile(await getMutation(activeRequest.mutationId), current, _activeCsrfToken)
    } catch (error) {
      const classification = classifyKeeplingError(error)
      if (classification.kind === 'authentication_required' && onAuthenticationRequired) {
        setStatus({ kind: 'authentication-required' })
        onAuthenticationRequired(
          {
            authentication: classification.authentication,
            kind: 'submitted-unknown',
            mutationId: (current.planRequest ?? current.captureRequest).mutationId,
          },
          (nextCsrfToken) => checkSubmission(current, nextCsrfToken),
        )
      } else if (error instanceof KeeplingApiError && error.problem.code === 'mutation_not_found') {
        await deliver(current, _activeCsrfToken)
      } else if (error instanceof KeeplingApiError) {
        setStatus({ kind: 'problem', message: error.message })
      } else {
        setStatus({ kind: 'unknown' })
      }
    }
  }

  const submit = async () => {
    if (draft.trim() === '' || status.kind === 'submitting') return

    const current = submission ?? (() => {
      const captureCommand = {
        mutationId: crypto.randomUUID(),
        taskId: crypto.randomUUID(),
        title: draft,
      } satisfies CaptureTaskSubmission
      return {
        addToToday,
        captureCommand,
        captureRequest: prepareCaptureTask(captureCommand),
      } satisfies Submission
    })()

    await deliver(current)
  }

  const checkAgain = async () => {
    if (submission) await checkSubmission(submission)
  }

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    void submit()
  }

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      void submit()
    }
  }

  const message = status.kind === 'problem' ? status.message : undefined
  const locked = submission !== null

  return (
    <section
      aria-labelledby={`${fieldId}-heading`}
      className="border-b border-border p-6"
      id="quick-capture"
    >
      <h2 className="text-xl font-semibold" id={`${fieldId}-heading`}>
        Add task
      </h2>
      <form className="mt-4 space-y-4" onSubmit={handleSubmit}>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor={fieldId}>
            What do you want to keep?
          </label>
          <textarea
            aria-describedby={message ? errorId : undefined}
            aria-invalid={message ? true : undefined}
            className="min-h-11 w-full resize-y rounded-lg border border-input bg-card px-4 py-2 text-base leading-6 text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            id={fieldId}
            maxLength={512}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleKeyDown}
            readOnly={locked}
            rows={1}
            value={draft}
          />
          {message ? (
            <div className="space-y-2" id={errorId} role="alert">
              <p className="text-sm text-destructive">{message}</p>
              {submission?.planCommand ? (
                <Button onClick={() => void deliver(submission)} type="button" variant="outline">
                  Retry adding to Today
                </Button>
              ) : null}
            </div>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="space-y-2">
            <p className="text-sm font-semibold text-muted-foreground">Destination: Inbox</p>
            <label className="flex min-h-11 items-center gap-4 text-sm font-semibold">
              <input
                checked={addToToday}
                className="size-5 rounded border-input accent-primary"
                disabled={locked}
                onChange={(event) => setAddToToday(event.target.checked)}
                type="checkbox"
              />
              Add to Today
            </label>
          </div>
          <Button
            className="min-h-11 px-4"
            disabled={draft.trim() === '' || status.kind === 'submitting' || locked}
            type="submit"
          >
            {status.kind === 'submitting' ? 'Adding…' : 'Add task'}
          </Button>
        </div>
      </form>

      {status.kind === 'unknown' ? (
        <div className="mt-4 rounded-lg border border-border bg-card p-4" role="status">
          <p>Checking whether your change was saved…</p>
          <Button className="mt-4 min-h-11" onClick={() => void checkAgain()} variant="outline">
            Check again
          </Button>
        </div>
      ) : null}

      {status.kind === 'authentication-required' ? (
        <div className="mt-4 rounded-lg border border-border bg-card p-4" role="status">
          Sign in again to finish saving. Your changes are still here.
        </div>
      ) : null}
    </section>
  )
}

export default QuickCapture
