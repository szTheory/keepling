import { useCallback, useEffect, useRef, useState } from 'react'

import {
  getTaskView,
  KeeplingApiError,
  moveTodayTask,
  type TaskViewItem,
  type TaskViewName,
  type TaskViewPage,
} from '@/api/keepling'

type TaskListProps = {
  csrfToken?: string
  view: TaskViewName
}

type LoadState =
  | { kind: 'error'; authenticationRequired: boolean }
  | { kind: 'loading' }
  | { kind: 'ready'; page: TaskViewPage }

const copy = {
  completed: {
    description: 'Completed tasks use their accepted completion date in account time.',
    emptyBody: 'Completed tasks will appear here with their accepted completion date.',
    emptyHeading: 'Nothing completed yet',
    title: 'Completed',
  },
  inbox: {
    description: 'Captured tasks stay here until you deliberately move them out.',
    emptyBody: 'Captured tasks appear here until you move them out. Add task.',
    emptyHeading: 'Inbox is clear',
    title: 'Inbox',
  },
  today: {
    description: 'Tasks appear here from deliberate planning or a deadline in account time.',
    emptyBody: 'Add a task or choose an existing task to make it part of today.',
    emptyHeading: 'Nothing for Today',
    title: 'Today',
  },
  upcoming: {
    description: 'Future planned dates and deadlines are grouped in account time.',
    emptyBody: 'Tasks with future planned dates or deadlines appear here.',
    emptyHeading: 'Nothing upcoming',
    title: 'Upcoming',
  },
} as const

const shortDate = (date: string | null) => {
  if (!date) return ''
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(
    new Date(`${date}T00:00:00Z`),
  )
}

const longDate = (date: string) =>
  new Intl.DateTimeFormat('en-US', {
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
    year: 'numeric',
  }).format(new Date(`${date}T00:00:00Z`))

const reasonText = (task: TaskViewItem) =>
  task.reasons
    .map((reason) => {
      switch (reason) {
        case 'planned_overdue':
          return 'Planned overdue'
        case 'planned_today':
          return 'Planned today'
        case 'planned_future':
          return `Planned ${shortDate(task.plannedOn)}`
        case 'deadline_overdue':
          return 'Overdue deadline'
        case 'deadline_today':
          return 'Deadline today'
        case 'deadline_future':
          return `Deadline ${shortDate(task.deadlineOn)}`
      }
    })
    .join(' · ')

const swap = (items: readonly TaskViewItem[], taskId: string, direction: 'earlier' | 'later') => {
  const current = items.findIndex((item) => item.id === taskId)
  if (current < 0) return items
  const candidate = direction === 'earlier' ? current - 1 : current + 1
  if (candidate < 0 || candidate >= items.length || items[candidate]?.section !== items[current]?.section) {
    return items
  }
  const reordered = [...items]
  ;[reordered[current], reordered[candidate]] = [reordered[candidate]!, reordered[current]!]
  return reordered
}

function TaskList({ csrfToken, view }: TaskListProps) {
  const [state, setState] = useState<LoadState>({ kind: 'loading' })
  const [updating, setUpdating] = useState(false)
  const [loadMoreError, setLoadMoreError] = useState<'background' | 'stale' | null>(null)
  const [movingTaskId, setMovingTaskId] = useState<string | null>(null)
  const [moveError, setMoveError] = useState<'authentication' | 'generic' | 'stale' | null>(null)
  const [announcement, setAnnouncement] = useState('')
  const rowLinks = useRef(new Map<string, HTMLAnchorElement>())
  const viewCopy = copy[view]

  const load = useCallback(
    async (preserveRows = false) => {
      if (preserveRows) setUpdating(true)
      else setState({ kind: 'loading' })
      setLoadMoreError(null)

      try {
        const page = await getTaskView(view)
        setState({ kind: 'ready', page })
      } catch (error) {
        const authenticationRequired =
          error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
        if (!preserveRows) setState({ authenticationRequired, kind: 'error' })
        else setLoadMoreError('background')
      } finally {
        setUpdating(false)
      }
    },
    [view],
  )

  useEffect(() => {
    let active = true

    void getTaskView(view)
      .then((page) => {
        if (active) setState({ kind: 'ready', page })
      })
      .catch((error: unknown) => {
        if (!active) return
        const authenticationRequired =
          error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
        setState({ authenticationRequired, kind: 'error' })
      })

    return () => {
      active = false
    }
  }, [view])

  const loadMore = async () => {
    if (state.kind !== 'ready' || !state.page.nextCursor) return
    setUpdating(true)
    setLoadMoreError(null)
    const knownIds = new Set(state.page.items.map((task) => task.id))

    try {
      const page = await getTaskView(view, state.page.nextCursor)
      const appended = page.items.filter((task) => !knownIds.has(task.id))
      setState({
        kind: 'ready',
        page: { ...page, items: [...state.page.items, ...appended] },
      })
      window.requestAnimationFrame(() => rowLinks.current.get(appended[0]?.id ?? '')?.focus())
    } catch (error) {
      const stale = error instanceof KeeplingApiError && error.problem.code === 'task_view_cursor_stale'
      setLoadMoreError(stale ? 'stale' : 'background')
    } finally {
      setUpdating(false)
    }
  }

  const refreshAfterStale = async () => {
    if (state.kind !== 'ready') return
    const knownIds = new Set(state.page.items.map((task) => task.id))
    setUpdating(true)
    setLoadMoreError(null)
    try {
      const page = await getTaskView(view)
      const firstNew = page.items.find((task) => !knownIds.has(task.id))
      setState({ kind: 'ready', page })
      window.requestAnimationFrame(() => rowLinks.current.get(firstNew?.id ?? '')?.focus())
    } catch {
      setLoadMoreError('background')
    } finally {
      setUpdating(false)
    }
  }

  const move = async (taskId: string, direction: 'earlier' | 'later') => {
    if (state.kind !== 'ready' || state.page.orderRevision === null || !csrfToken) return
    setMovingTaskId(taskId)
    setMoveError(null)
    try {
      const result = await moveTodayTask(
        {
          direction,
          expectedOrderRevision: state.page.orderRevision,
          mutationId: crypto.randomUUID(),
          taskId,
        },
        csrfToken,
      )
      setState({
        kind: 'ready',
        page: {
          ...state.page,
          items: swap(state.page.items, taskId, direction),
          orderRevision: result.orderRevision,
        },
      })
      setAnnouncement('Today order updated.')
    } catch (error) {
      if (error instanceof KeeplingApiError && error.problem.code === 'today_order_stale') {
        setMoveError('stale')
      } else if (error instanceof KeeplingApiError && error.problem.code === 'authentication_required') {
        setMoveError('authentication')
      } else {
        setMoveError('generic')
      }
    } finally {
      setMovingTaskId(null)
    }
  }

  const taskRow = (task: TaskViewItem) => (
    <li className="min-h-[3.25rem] border-b border-border py-3" key={task.id}>
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <a
            className="break-words text-base leading-6 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            href={`/tasks/${encodeURIComponent(task.id)}`}
            ref={(node) => {
              if (node) rowLinks.current.set(task.id, node)
              else rowLinks.current.delete(task.id)
            }}
          >
            {task.title}
          </a>
          {task.reasons.length > 0 ? (
            <p className="mt-1 text-sm text-muted-foreground">{reasonText(task)}</p>
          ) : null}
        </div>
        {view === 'today' ? (
          <div className="flex shrink-0 flex-wrap justify-end gap-1">
            <button
              aria-label={`Move earlier “${task.title}”`}
              className="min-h-11 px-2 text-sm font-semibold text-primary underline"
              disabled={movingTaskId !== null}
              onClick={() => void move(task.id, 'earlier')}
              type="button"
            >
              Earlier
            </button>
            <button
              aria-label={`Move later “${task.title}”`}
              className="min-h-11 px-2 text-sm font-semibold text-primary underline"
              disabled={movingTaskId !== null}
              onClick={() => void move(task.id, 'later')}
              type="button"
            >
              Later
            </button>
          </div>
        ) : null}
      </div>
      {movingTaskId === task.id ? (
        <p className="mt-1 text-sm text-muted-foreground" role="status">
          Moving…
        </p>
      ) : null}
    </li>
  )

  const populated = (page: TaskViewPage) => {
    if (view === 'today') {
      return (
        <div className="mt-6 space-y-8">
          {(['overdue', 'today'] as const).map((section) => (
            <section aria-labelledby={`${section}-heading`} key={section}>
              <h2 className="text-xl font-semibold" id={`${section}-heading`}>
                {section === 'overdue' ? 'Overdue' : 'Today'}
              </h2>
              <ul aria-label={`${section === 'overdue' ? 'Overdue' : 'Today'} tasks`} className="mt-3">
                {page.items.filter((task) => task.section === section).map(taskRow)}
              </ul>
            </section>
          ))}
        </div>
      )
    }

    if (view === 'upcoming') {
      const groups = page.items.reduce<Map<string, TaskViewItem[]>>((result, task) => {
        const date = task.groupOn ?? ''
        const existing = result.get(date) ?? []
        existing.push(task)
        result.set(date, existing)
        return result
      }, new Map())
      return (
        <div className="mt-6 space-y-8">
          {[...groups.entries()].map(([date, tasks]) => (
            <section aria-labelledby={`upcoming-${date}`} key={date}>
              <h2 className="text-xl font-semibold" id={`upcoming-${date}`}>
                {longDate(date)}
              </h2>
              <ul aria-label={`${longDate(date)} tasks`} className="mt-3">
                {tasks.map(taskRow)}
              </ul>
            </section>
          ))}
        </div>
      )
    }

    return <ul aria-label={`${viewCopy.title} tasks`} className="mt-6">{page.items.map(taskRow)}</ul>
  }

  return (
    <main className="min-h-screen min-w-0 bg-background px-4 py-8 sm:px-6 lg:px-8" id="main-content" tabIndex={-1}>
      <div className="mx-auto max-w-3xl">
        <nav aria-label="Primary" className="mb-8 flex flex-wrap gap-x-6 gap-y-2 border-b border-border pb-4">
          {(['inbox', 'today', 'upcoming', 'completed'] as const).map((destination) => (
            <a
              aria-current={view === destination ? 'page' : undefined}
              className={`min-h-11 content-center font-semibold underline-offset-4 hover:underline ${view === destination ? 'border-b-2 border-primary' : ''}`}
              href={`/${destination}`}
              key={destination}
            >
              {copy[destination].title}
            </a>
          ))}
        </nav>
        <h1 className="text-[1.75rem] font-semibold leading-[1.2]">{viewCopy.title}</h1>
        <p className="mt-2 text-muted-foreground">{viewCopy.description}</p>

        {state.kind === 'loading' ? <p className="mt-8" role="status">Loading {viewCopy.title}…</p> : null}

        {state.kind === 'error' ? (
          <div className="mt-8 rounded-lg border border-border bg-card p-4" role="alert">
            <p>
              {state.authenticationRequired
                ? 'Sign in again to load this view. Your tasks weren’t changed.'
                : `Couldn’t load ${viewCopy.title}. Your tasks weren’t changed.`}
            </p>
            <button className="mt-3 min-h-11 font-semibold text-primary underline" onClick={() => void load()} type="button">
              {state.authenticationRequired ? 'Sign in again' : `Retry loading ${viewCopy.title}`}
            </button>
          </div>
        ) : null}

        {state.kind === 'ready' && state.page.items.length === 0 ? (
          <div className="mt-12 max-w-md">
            <h2 className="text-xl font-semibold">{viewCopy.emptyHeading}</h2>
            <p className="mt-2 text-muted-foreground">{viewCopy.emptyBody}</p>
          </div>
        ) : null}

        {state.kind === 'ready' && state.page.items.length > 0 ? populated(state.page) : null}

        {updating ? <p className="mt-4" role="status">Updating…</p> : null}

        {state.kind === 'ready' && state.page.nextCursor && !loadMoreError ? (
          <button className="mt-6 min-h-11 font-semibold text-primary underline" disabled={updating} onClick={() => void loadMore()} type="button">
            Load more tasks
          </button>
        ) : null}

        {loadMoreError ? (
          <div className="mt-6 rounded-lg border border-border bg-card p-4" role="alert">
            <p>
              {loadMoreError === 'stale'
                ? 'This view changed before more items could load.'
                : 'Couldn’t update this view. Showing the last loaded version.'}
            </p>
            <button className="mt-3 min-h-11 font-semibold text-primary underline" onClick={() => void refreshAfterStale()} type="button">
              {loadMoreError === 'stale' ? 'Refresh view' : `Retry updating ${viewCopy.title}`}
            </button>
          </div>
        ) : null}

        {moveError ? (
          <div className="mt-6 rounded-lg border border-border bg-card p-4" role="alert">
            <p>
              {moveError === 'stale'
                ? 'Today changed elsewhere. Refresh the list before moving this task.'
                : moveError === 'authentication'
                  ? 'Sign in again to finish saving. Your changes are still here.'
                  : 'Couldn’t move this task. Nothing was changed.'}
            </p>
            {moveError === 'stale' ? (
              <button className="mt-3 min-h-11 font-semibold text-primary underline" onClick={() => void load(true)} type="button">
                Refresh Today
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
      <div aria-atomic="true" aria-live="polite" className="sr-only">{announcement}</div>
    </main>
  )
}

export default TaskList
