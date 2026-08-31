import { useRef, useState } from 'react'

import {
  KeeplingApiError,
  getMutation,
  undoTask,
  type UndoAvailability,
  type UndoResult,
  type UndoSubmission,
} from '@/api/keepling'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import { authenticationRecoveryFor } from '@/commands/submission'

type RecoveryStripProps = {
  availability: UndoAvailability
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onSettled: (result: UndoResult) => void
}

type RecoveryState =
  | { kind: 'available' }
  | { kind: 'submitting' }
  | { kind: 'uncertain' }
  | { kind: 'authentication-required' }
  | { copy: string; kind: 'settled' }

const noChangeCopy = (result: Extract<UndoResult, { kind: 'no-change' }>['result']) => {
  switch (result.outcome) {
    case 'already_applied':
      return 'That change was already undone.'
    case 'expired':
      return 'Undo expired. Nothing was changed.'
    case 'stale':
      return 'This task changed after that action. Nothing was changed.'
    case 'unknown':
      return 'This undo is unavailable. Nothing was changed.'
    case 'uncertain':
      return 'Checking whether undo was applied…'
  }
}

function RecoveryStrip({
  availability,
  csrfToken,
  onAuthenticationRequired,
  onSettled,
}: RecoveryStripProps) {
  const [state, setState] = useState<RecoveryState>({ kind: 'available' })
  const submissionRef = useRef<UndoSubmission | null>(null)

  const settleAcknowledgement = (acknowledgement: Awaited<ReturnType<typeof getMutation>>) => {
    onSettled({ acknowledgement, kind: 'acknowledged' })
    setState({ copy: 'Change undone.', kind: 'settled' })
  }

  const requestAuthentication = (
    authentication: 'reauthenticate' | 'sign_in',
    submission: UndoSubmission,
    resume: (csrfToken: string) => Promise<void>,
  ) => {
    setState({ kind: 'authentication-required' })
    onAuthenticationRequired?.(
      { authentication, kind: 'submitted-unknown', mutationId: submission.mutationId },
      resume,
    )
  }

  const reconcile = async (submission: UndoSubmission, activeCsrfToken: string) => {
    setState({ kind: 'uncertain' })
    try {
      settleAcknowledgement(await getMutation(submission.mutationId))
    } catch (error: unknown) {
      const authentication =
        error instanceof KeeplingApiError
          ? authenticationRecoveryFor(error.problem.code)
          : null
      if (authentication) {
        requestAuthentication(authentication, submission, (nextCsrfToken) =>
          reconcile(submission, nextCsrfToken),
        )
      } else if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'mutation_not_found'
      ) {
        await submit(activeCsrfToken)
      } else {
        setState({ kind: 'uncertain' })
      }
    }
  }

  const submit = async (activeCsrfToken = csrfToken) => {
    const submission =
      submissionRef.current ??
      ({ availability, mutationId: crypto.randomUUID() } satisfies UndoSubmission)

    submissionRef.current = submission
    setState({ kind: 'submitting' })

    try {
      const result = await undoTask(submission, activeCsrfToken)
      onSettled(result)

      if (result.kind === 'acknowledged') {
        setState({ copy: 'Change undone.', kind: 'settled' })
      } else if (result.result.outcome === 'uncertain') {
        setState({ kind: 'uncertain' })
      } else {
        setState({ copy: noChangeCopy(result.result), kind: 'settled' })
      }
    } catch (error: unknown) {
      const authentication =
        error instanceof KeeplingApiError
          ? authenticationRecoveryFor(error.problem.code)
          : null
      if (authentication) {
        requestAuthentication(
          authentication,
          submission,
          (nextCsrfToken) => reconcile(submission, nextCsrfToken),
        )
      } else {
        setState({ kind: 'uncertain' })
      }
    }
  }

  return (
    <aside
      aria-label="Latest recovery action"
      className="fixed inset-x-4 bottom-4 z-40 mx-auto flex max-w-3xl items-center justify-between gap-4 rounded-lg border border-border bg-card p-4 shadow-lg motion-reduce:transition-none"
    >
      <div aria-atomic="true" aria-live="polite" role="status">
        {state.kind === 'available' ? <p>Latest action can be recovered.</p> : null}
        {state.kind === 'submitting' ? <p>Applying undo…</p> : null}
        {state.kind === 'uncertain' ? <p>Checking whether undo was applied…</p> : null}
        {state.kind === 'authentication-required' ? (
          <p>Sign in to continue. Keepling will check whether undo was applied.</p>
        ) : null}
        {state.kind === 'settled' ? <p>{state.copy}</p> : null}
      </div>

      {state.kind === 'available' ? (
        <button
          className="min-h-11 shrink-0 rounded-lg bg-primary px-4 font-semibold text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
          onClick={() => void submit()}
          type="button"
        >
          {availability.label}
        </button>
      ) : null}

      {state.kind === 'uncertain' ? (
        <button
          className="min-h-11 shrink-0 font-semibold text-primary underline underline-offset-4"
          onClick={() => {
            const submission = submissionRef.current
            if (submission) void reconcile(submission, csrfToken)
          }}
          type="button"
        >
          Check again
        </button>
      ) : null}

    </aside>
  )
}

export default RecoveryStrip
