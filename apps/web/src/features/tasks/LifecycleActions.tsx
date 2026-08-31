import { useState } from 'react'

import {
  completeTask,
  KeeplingApiError,
  reopenTask,
  type CommandAcknowledgement,
  type LifecycleSubmission,
  type TaskViewItem,
} from '@/api/keepling'

type LifecycleAction = 'complete' | 'reopen'

type LifecycleReconciliation = {
  acknowledgement: CommandAcknowledgement
  action: LifecycleAction
  task: TaskViewItem
}

type LifecycleActionsProps = {
  csrfToken: string
  onAcknowledged: (result: LifecycleReconciliation) => void | Promise<void>
  task: TaskViewItem
}

type RecoveryState = 'authentication' | 'conflict' | 'generic' | 'unknown' | null

function LifecycleActions({ csrfToken, onAcknowledged, task }: LifecycleActionsProps) {
  const action: LifecycleAction = task.completedAt ? 'reopen' : 'complete'
  const [pending, setPending] = useState(false)
  const [recovery, setRecovery] = useState<RecoveryState>(null)
  const [submission, setSubmission] = useState<LifecycleSubmission | null>(null)

  const label = action === 'complete' ? 'Complete' : 'Reopen'
  const pendingLabel = action === 'complete' ? 'Completing' : 'Reopening'

  const run = async (nextSubmission: LifecycleSubmission) => {
    setPending(true)
    setRecovery(null)

    try {
      const acknowledgement =
        action === 'complete'
          ? await completeTask(nextSubmission, csrfToken)
          : await reopenTask(nextSubmission, csrfToken)

      if (
        acknowledgement.mutationId !== nextSubmission.mutationId ||
        acknowledgement.taskId !== nextSubmission.taskId
      ) {
        setRecovery('unknown')
        return
      }

      setSubmission(null)
      await onAcknowledged({ acknowledgement, action, task })
    } catch (error) {
      if (!(error instanceof KeeplingApiError)) {
        setRecovery('unknown')
      } else if (error.problem.code === 'authentication_required') {
        setRecovery('authentication')
      } else if (error.problem.code === 'task_lifecycle_conflict') {
        setRecovery('conflict')
      } else {
        setRecovery('generic')
      }
    } finally {
      setPending(false)
    }
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

  const recoveryMessage =
    recovery === 'unknown'
      ? 'Checking whether your change was saved…'
      : recovery === 'authentication'
        ? 'Sign in again to finish saving. Your changes are still here.'
        : recovery === 'conflict'
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
        <div className="max-w-72 text-left text-sm" role={recovery === 'unknown' ? 'status' : 'alert'}>
          <p>{recoveryMessage}</p>
          <button
            className="min-h-11 font-semibold text-primary underline"
            onClick={begin}
            type="button"
          >
            {recovery === 'unknown'
              ? 'Check again'
              : recovery === 'conflict'
                ? 'Refresh task'
                : recovery === 'authentication'
                  ? 'Sign in and continue'
                  : `Retry ${action}`}
          </button>
        </div>
      ) : null}
    </div>
  )
}

export default LifecycleActions
export type { LifecycleAction, LifecycleReconciliation }
