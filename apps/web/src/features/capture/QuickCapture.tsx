import { useState, type FormEvent, type KeyboardEvent } from 'react'

import {
  KeeplingApiError,
  captureTask,
  getMutation,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type QuickCaptureProps = {
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onCaptured: (acknowledgement: CaptureAcknowledgement) => void
}

type Submission = {
  command: CaptureTaskSubmission
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
  const [submission, setSubmission] = useState<Submission | null>(null)
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  const reconcile = (acknowledgement: CaptureAcknowledgement, current: Submission) => {
    if (acknowledgement.mutationId !== current.command.mutationId) {
      setStatus({ kind: 'unknown' })
      return
    }

    onCaptured(acknowledgement)
    setDraft('')
    setSubmission(null)
    setStatus({ kind: 'idle' })
  }

  const deliver = async (current: Submission, activeCsrfToken = csrfToken) => {
    setSubmission(current)
    setStatus({ kind: 'submitting' })

    try {
      reconcile(await captureTask(current.command, activeCsrfToken), current)
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        setStatus({ kind: 'authentication-required' })
        onAuthenticationRequired(
          { kind: 'not-submitted', mutationId: current.command.mutationId },
          (nextCsrfToken) => deliver(current, nextCsrfToken),
        )
      } else if (error instanceof KeeplingApiError) {
        setSubmission(null)
        setStatus({ kind: 'problem', message: error.message })
      } else {
        setStatus({ kind: 'unknown' })
      }
    }
  }

  const checkSubmission = async (current: Submission, _activeCsrfToken = csrfToken) => {
    void _activeCsrfToken
    setStatus({ kind: 'submitting' })

    try {
      reconcile(await getMutation(current.command.mutationId), current)
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        setStatus({ kind: 'authentication-required' })
        onAuthenticationRequired(
          { kind: 'submitted-unknown', mutationId: current.command.mutationId },
          (nextCsrfToken) => checkSubmission(current, nextCsrfToken),
        )
      } else if (error instanceof KeeplingApiError && error.problem.code !== 'mutation_not_found') {
        setStatus({ kind: 'problem', message: error.message })
      } else {
        setStatus({ kind: 'unknown' })
      }
    }
  }

  const submit = async () => {
    if (draft.trim() === '' || status.kind === 'submitting') return

    const current =
      submission ??
      ({
        command: {
          mutationId: crypto.randomUUID(),
          taskId: crypto.randomUUID(),
          title: draft,
        },
      } satisfies Submission)

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
            className="min-h-11 w-full resize-y rounded-lg border border-input bg-card px-3 py-2 text-base leading-6 text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            id={fieldId}
            maxLength={512}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleKeyDown}
            readOnly={locked}
            rows={1}
            value={draft}
          />
          {message ? (
            <p className="text-sm text-destructive" id={errorId} role="alert">
              {message}
            </p>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-4">
          <p className="text-sm font-semibold text-muted-foreground">Destination: Inbox</p>
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
          <Button className="mt-3 min-h-11" onClick={() => void checkAgain()} variant="outline">
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
