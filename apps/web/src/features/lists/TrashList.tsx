import { useEffect, useRef, useState } from 'react'

import {
  getTrash,
  KeeplingApiError,
  restoreTask,
  type BrowserTask,
  type LifecycleSubmission,
} from '@/api/keepling'

type TrashListProps = {
  csrfToken: string
}

type LoadState = 'error' | 'loaded' | 'loading'
type RestoreRecovery = 'authentication' | 'conflict' | 'generic' | 'unknown' | null

type RestoreState = {
  pending: boolean
  recovery: RestoreRecovery
  submission: LifecycleSubmission
}

const restoredAnnouncement = (destinations: readonly string[]) => {
  if (destinations.length === 0) return 'Task restored. It is not in an active list.'
  if (destinations.length === 1) return `Task restored to ${destinations[0]}.`
  if (destinations.length === 2) {
    return `Task restored to ${destinations[0]} and ${destinations[1]}.`
  }

  return `Task restored to ${destinations.slice(0, -1).join(', ')}, and ${destinations.at(-1)}.`
}

function TrashList({ csrfToken }: TrashListProps) {
  const [announcement, setAnnouncement] = useState('')
  const [loadState, setLoadState] = useState<LoadState>('loading')
  const [restoreStates, setRestoreStates] = useState<Record<string, RestoreState>>({})
  const [tasks, setTasks] = useState<readonly BrowserTask[]>([])
  const heading = useRef<HTMLHeadingElement>(null)
  const restoreButtons = useRef(new Map<string, HTMLButtonElement>())

  const load = async () => {
    setLoadState('loading')
    try {
      setTasks(await getTrash())
      setLoadState('loaded')
    } catch {
      setLoadState('error')
    }
  }

  useEffect(() => {
    let active = true

    void getTrash()
      .then((loadedTasks) => {
        if (!active) return
        setTasks(loadedTasks)
        setLoadState('loaded')
      })
      .catch(() => {
        if (active) setLoadState('error')
      })

    return () => {
      active = false
    }
  }, [])

  const setRestoreState = (taskId: string, state: RestoreState) => {
    setRestoreStates((current) => ({ ...current, [taskId]: state }))
  }

  const runRestore = async (task: BrowserTask, submission: LifecycleSubmission) => {
    setRestoreState(task.id, { pending: true, recovery: null, submission })

    try {
      const acknowledgement = await restoreTask(submission, csrfToken)

      if (
        acknowledgement.mutationId !== submission.mutationId ||
        acknowledgement.taskId !== submission.taskId
      ) {
        setRestoreState(task.id, { pending: false, recovery: 'unknown', submission })
        return
      }

      const index = tasks.findIndex((candidate) => candidate.id === task.id)
      const nextTask = tasks[index + 1] ?? tasks[index - 1]

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
    } catch (error) {
      const recovery: RestoreRecovery =
        !(error instanceof KeeplingApiError)
          ? 'unknown'
          : error.problem.code === 'authentication_required'
            ? 'authentication'
            : error.problem.code === 'task_trash_conflict'
              ? 'conflict'
              : 'generic'

      setRestoreState(task.id, { pending: false, recovery, submission })
    }
  }

  const beginRestore = (task: BrowserTask) => {
    const submission =
      restoreStates[task.id]?.submission ?? {
        expectedRevision: task.revision,
        mutationId: crypto.randomUUID(),
        taskId: task.id,
      }

    void runRestore(task, submission)
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
                          onClick={() => beginRestore(task)}
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
