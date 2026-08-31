import { useRef, useState } from 'react'

import {
  prepareLifecycleTask,
  type CommandAcknowledgement,
  type LifecycleSubmission,
  type TaskViewItem,
} from '@/api/keepling'
import { createTaskSubmission, type TaskSubmissionState } from '@/commands/submission'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import MutationRecoveryPanel from '@/features/recovery/MutationRecoveryPanel'

type LifecycleAction = 'complete' | 'reopen'

type LifecycleReconciliation = {
  acknowledgement: CommandAcknowledgement
  action: LifecycleAction
  task: TaskViewItem
}

type LifecycleActionsProps = {
  csrfToken: string
  onAcknowledged: (result: LifecycleReconciliation) => void | Promise<void>
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  task: TaskViewItem
}

type RecoveryState = 'conflict' | 'generic' | null

function LifecycleActions({
  csrfToken,
  onAcknowledged,
  onAuthenticationRequired,
  task,
}: LifecycleActionsProps) {
  const action: LifecycleAction = task.completedAt ? 'reopen' : 'complete'
  const [recovery, setRecovery] = useState<RecoveryState>(null)
  const [recoveryState, setRecoveryState] = useState<TaskSubmissionState | null>(null)
  const [submission, setSubmission] = useState<LifecycleSubmission | null>(null)
  const exactSubmission = useRef<ReturnType<typeof createTaskSubmission> | null>(null)

  const label = action === 'complete' ? 'Complete' : 'Reopen'
  const pendingLabel = action === 'complete' ? 'Completing' : 'Reopening'

  const settle = async (exact: ReturnType<typeof createTaskSubmission>) => {
    const state = exact.snapshot
    if (state.kind === 'acknowledged') {
      exactSubmission.current = null
      setRecoveryState(null)
      setSubmission(null)
      await onAcknowledged({ acknowledgement: state.acknowledgement, action, task })
    } else if (state.kind === 'conflict') {
      exactSubmission.current = null
      setRecoveryState(null)
      setSubmission(null)
      setRecovery('conflict')
    } else if (state.kind === 'rejected') {
      exactSubmission.current = null
      setRecoveryState(null)
      setSubmission(null)
      setRecovery('generic')
    }
  }

  const run = async (nextSubmission: LifecycleSubmission, activeCsrfToken = csrfToken) => {
    setRecovery(null)
    const exact = createTaskSubmission(
      prepareLifecycleTask(action, nextSubmission),
      setRecoveryState,
    )
    exactSubmission.current = exact
    await exact.submit(activeCsrfToken)
    await settle(exact)
  }

  const begin = () => {
    const nextSubmission =
      submission ?? {
        expectedRevision: task.revision,
        mutationId: crypto.randomUUID(),
        taskId: task.id,
      }
    setSubmission(nextSubmission)
    void run(nextSubmission)
  }

  const check = async () => {
    const exact = exactSubmission.current
    if (!exact || !submission) return
    await exact.check(csrfToken)
    await settle(exact)
  }

  const requestAuthentication = () => {
    const exact = exactSubmission.current
    if (
      !exact ||
      exact.snapshot.kind !== 'authentication_required' ||
      !onAuthenticationRequired ||
      !submission
    ) {
      return
    }
    onAuthenticationRequired(
      {
        authentication: exact.snapshot.authentication,
        kind: exact.snapshot.operation === 'lookup' ? 'submitted-unknown' : 'not-submitted',
        mutationId: submission.mutationId,
      },
      async (nextCsrfToken) => {
        await exact.resumeAfterAuthentication(nextCsrfToken)
        await settle(exact)
      },
    )
  }

  const pending = recoveryState?.kind === 'in_flight'

  const recoveryMessage =
    recovery === 'conflict'
      ? 'This task changed somewhere else. Review the current task before trying again.'
      : recovery === 'generic'
        ? `Couldn’t ${action} this task. Nothing was changed.`
        : null

  return (
    <div className="shrink-0 text-right">
      <button
        aria-label={`${pending ? pendingLabel : label} “${task.title}”`}
        className="min-h-11 px-2 text-sm font-semibold text-primary underline motion-reduce:transition-none"
        disabled={pending}
        onClick={begin}
        type="button"
      >
        {pending ? `${pendingLabel}…` : label}
      </button>
      {recoveryMessage ? (
        <div className="max-w-72 text-left text-sm" role="alert">
          <p>{recoveryMessage}</p>
          <button
            className="min-h-11 font-semibold text-primary underline"
            onClick={begin}
            type="button"
          >
            {recovery === 'conflict' ? 'Refresh task' : `Retry ${action}`}
          </button>
        </div>
      ) : null}
      <MutationRecoveryPanel
        onCheck={() => void check()}
        onSignIn={requestAuthentication}
        state={recoveryState}
      />
    </div>
  )
}

export default LifecycleActions
export type { LifecycleAction, LifecycleReconciliation }
