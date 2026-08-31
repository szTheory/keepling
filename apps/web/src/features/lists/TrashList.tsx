import { useCallback, useEffect, useRef, useState } from 'react'

import {
  getTrash,
  getRestoreMutation,
  KeeplingApiError,
  prepareRestoreTask,
  submitPreparedRestoreTask,
  type BrowserTask,
  type LifecycleSubmission,
  type PreparedRestoreTask,
  type RestoreAcknowledgement,
} from '@/api/keepling'
import {
  classifyKeeplingError,
  createExactSubmission,
  type ExactSubmission,
  type ExactSubmissionState,
} from '@/commands/submission'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type TrashListProps = {
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
}

type LoadState = 'error' | 'loaded' | 'loading'
type RestoreRecovery = 'authentication' | 'conflict' | 'generic' | 'unknown' | null

type RestoreState = {
  pending: boolean
  recovery: RestoreRecovery
  submission: LifecycleSubmission
}

type RestoreSubmissionState = ExactSubmissionState<
  PreparedRestoreTask,
  RestoreAcknowledgement,
  KeeplingApiError
>

type RestoreExact = ExactSubmission<PreparedRestoreTask, RestoreAcknowledgement, KeeplingApiError>

const restoredAnnouncement = (destinations: readonly string[]) => {
  if (destinations.length === 0) return 'Task restored. It is not in an active list.'
  if (destinations.length === 1) return `Task restored to ${destinations[0]}.`
  if (destinations.length === 2) {
    return `Task restored to ${destinations[0]} and ${destinations[1]}.`
  }

  return `Task restored to ${destinations.slice(0, -1).join(', ')}, and ${destinations.at(-1)}.`
}

function TrashList({ csrfToken, onAuthenticationRequired }: TrashListProps) {
  const [announcement, setAnnouncement] = useState('')
  const [loadState, setLoadState] = useState<LoadState>('loading')
  const [restoreStates, setRestoreStates] = useState<Record<string, RestoreState>>({})
  const [tasks, setTasks] = useState<readonly BrowserTask[]>([])
  const heading = useRef<HTMLHeadingElement>(null)
  const restoreButtons = useRef(new Map<string, HTMLButtonElement>())
  const exactRestores = useRef(new Map<string, RestoreExact>())

  const load = useCallback(async () => {
    setLoadState('loading')
    try {
      setTasks(await getTrash())
      setLoadState('loaded')
    } catch (error) {
      setLoadState('error')
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        onAuthenticationRequired(
          { authentication: 'sign_in', kind: 'read', mutationId: 'trash:list' },
          async () => {
            setLoadState('loading')
            setTasks(await getTrash())
            setLoadState('loaded')
          },
        )
      }
    }
  }, [onAuthenticationRequired])

  useEffect(() => {
    void load()
  }, [load])

  const setRestoreState = (taskId: string, state: RestoreState) => {
    setRestoreStates((current) => ({ ...current, [taskId]: state }))
  }

  const settleRestore = (task: BrowserTask, state: RestoreSubmissionState) => {
    const submission = restoreStates[task.id]?.submission ?? {
      expectedRevision: task.revision,
      mutationId: state.request.mutationId,
      taskId: task.id,
    }

    if (state.kind === 'acknowledged') {
      const acknowledgement = state.acknowledgement
      const index = tasks.findIndex((candidate) => candidate.id === task.id)
      const nextTask = tasks[index + 1] ?? tasks[index - 1]

      exactRestores.current.delete(task.id)
      setRestoreStates((current) => {
        const next = { ...current }
        delete next[task.id]
        return next
      })
      setTasks((current) => current.filter((candidate) => candidate.id !== task.id))
      setAnnouncement(restoredAnnouncement(acknowledgement.destinations))
      window.requestAnimationFrame(() => {
        if (nextTask) restoreButtons.current.get(nextTask.id)?.focus()
        else heading.current?.focus()
      })
      return
    }

    const recovery: RestoreRecovery =
      state.kind === 'unknown'
        ? 'unknown'
        : state.kind === 'authentication_required'
          ? 'authentication'
          : state.kind === 'conflict'
            ? 'conflict'
            : state.kind === 'rejected'
              ? 'generic'
              : null

    setRestoreState(task.id, {
      pending: state.kind === 'in_flight',
      recovery,
      submission,
    })
  }

  const runRestore = async (
    task: BrowserTask,
    exact: RestoreExact,
    operation: 'check' | 'submit',
    activeCsrfToken = csrfToken,
  ) => {
    const current = restoreStates[task.id]
    setRestoreState(task.id, {
      pending: true,
      recovery: null,
      submission:
        current?.submission ?? {
          expectedRevision: task.revision,
          mutationId: exact.snapshot.request.mutationId,
          taskId: task.id,
        },
    })
    if (operation === 'check') await exact.check(activeCsrfToken)
    else await exact.submit(activeCsrfToken)
    settleRestore(task, exact.snapshot)
  }

  const beginRestore = (task: BrowserTask) => {
    const existing = exactRestores.current.get(task.id)
    if (existing) {
      if (existing.snapshot.kind === 'unknown') void runRestore(task, existing, 'check')
      else if (existing.snapshot.kind === 'conflict' || existing.snapshot.kind === 'rejected') {
        void load()
      }
      return
    }

    const submission = {
        expectedRevision: task.revision,
        mutationId: crypto.randomUUID(),
        taskId: task.id,
      }
    setRestoreState(task.id, { pending: true, recovery: null, submission })
    const request = prepareRestoreTask(submission)
    const exact = createExactSubmission<
      PreparedRestoreTask,
      RestoreAcknowledgement,
      KeeplingApiError
    >({
      classifyError: classifyKeeplingError,
      lookup: (original) => getRestoreMutation(original.mutationId),
      matchesAcknowledgement: (acknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send: submitPreparedRestoreTask,
    })
    exactRestores.current.set(task.id, exact)
    void runRestore(task, exact, 'submit')
  }

  const authenticateRestore = (task: BrowserTask) => {
    const exact = exactRestores.current.get(task.id)
    if (
      !exact ||
      exact.snapshot.kind !== 'authentication_required' ||
      !onAuthenticationRequired
    ) return

    const { authentication, request } = exact.snapshot
    onAuthenticationRequired(
      { authentication, kind: 'submitted-unknown', mutationId: request.mutationId },
      async (nextCsrfToken) => {
        await exact.resumeAfterAuthentication(nextCsrfToken)
        settleRestore(task, exact.snapshot)
      },
    )
  }

  const recoveryMessage = (recovery: RestoreRecovery) => {
    if (recovery === 'unknown') return 'Checking whether your change was saved…'
    if (recovery === 'authentication') {
      return 'Sign in again to finish saving. Your changes are still here.'
    }
    if (recovery === 'conflict') {
      return 'This task changed somewhere else. Refresh Trash before restoring it.'
    }
    if (recovery === 'generic') return 'Couldn’t restore this task. Nothing was changed.'
    return null
  }

  const recoveryAction = (recovery: RestoreRecovery) => {
    if (recovery === 'unknown') return 'Check again'
    if (recovery === 'authentication') return 'Sign in and continue'
    if (recovery === 'conflict') return 'Refresh Trash'
    return 'Retry restore'
  }

  return (
    <main className="min-h-screen bg-background px-4 py-6 sm:px-6" id="main-content">
      <div className="mx-auto max-w-3xl">
        <h1
          className="text-[1.75rem] font-semibold"
          id="trash-heading"
          ref={heading}
          tabIndex={-1}
        >
          Trash
        </h1>
        <p className="mt-2 text-muted-foreground">
          Tasks stay recoverable here until you restore them.
        </p>

        {loadState === 'loading' ? (
          <p className="mt-8" role="status">Loading Trash…</p>
        ) : null}

        {loadState === 'error' ? (
          <section className="mt-8" role="alert">
            <p>Couldn’t load Trash. Your tasks weren’t changed.</p>
            <button
              className="min-h-11 font-semibold text-primary underline"
              onClick={() => void load()}
              type="button"
            >
              Retry loading Trash
            </button>
          </section>
        ) : null}

        {loadState === 'loaded' && tasks.length === 0 ? (
          <section className="mt-12">
            <h2 className="text-xl font-semibold">Trash is empty</h2>
            <p className="mt-2 text-muted-foreground">Tasks moved to Trash stay recoverable here.</p>
          </section>
        ) : null}

        {loadState === 'loaded' && tasks.length > 0 ? (
          <ul aria-label="Trash tasks" className="mt-8 divide-y divide-border">
            {tasks.map((task) => {
              const restoreState = restoreStates[task.id]
              const recovery = restoreState?.recovery ?? null
              const message = recoveryMessage(recovery)

              return (
                <li className="flex min-h-14 items-start justify-between gap-4 py-3" key={task.id}>
                  <div className="min-w-0">
                    <p className="break-words">{task.title}</p>
                    {task.trashedAt ? (
                      <p className="mt-1 text-sm text-muted-foreground">
                        Moved to Trash{' '}
                        <time dateTime={task.trashedAt}>{task.trashedAt}</time>
                      </p>
                    ) : null}
                    {message ? (
                      <div className="mt-2 text-sm" role={recovery === 'unknown' ? 'status' : 'alert'}>
                        <p>{message}</p>
                        <button
                          className="min-h-11 font-semibold text-primary underline"
                          onClick={() => {
                            if (recovery === 'authentication') authenticateRestore(task)
                            else beginRestore(task)
                          }}
                          type="button"
                        >
                          {recoveryAction(recovery)}
                        </button>
                      </div>
                    ) : null}
                  </div>
                  <button
                    aria-label={`${restoreState?.pending ? 'Restoring' : 'Restore'} “${task.title}”`}
                    className="min-h-11 shrink-0 px-2 text-sm font-semibold text-primary underline motion-reduce:transition-none"
                    data-trash-task-id={task.id}
                    disabled={restoreState?.pending ?? false}
                    onClick={() => beginRestore(task)}
                    ref={(element) => {
                      if (element) restoreButtons.current.set(task.id, element)
                      else restoreButtons.current.delete(task.id)
                    }}
                    type="button"
                  >
                    {restoreState?.pending ? 'Restoring…' : 'Restore'}
                  </button>
                </li>
              )
            })}
          </ul>
        ) : null}

        <p aria-live="polite" className="sr-only">{announcement}</p>
      </div>
    </main>
  )
}

export default TrashList
