import { useEffect, useRef, useState } from 'react'

import {
  getTaskActivity,
  KeeplingApiError,
  type ActivityChange,
  type TaskActivity,
  type TaskActivityPage,
  type TaskOrganizationReference,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'

type ActivityListProps = {
  taskId: string
}

type ViewState =
  | 'earlier-error'
  | 'initial-error'
  | 'loading'
  | 'loading-earlier'
  | 'ready'
  | 'refreshing'
  | 'stale'

const actionCopy: Record<TaskActivity['type'], string> = {
  task_captured: 'captured this task',
  task_clarified: 'moved this task out of Inbox',
  task_completed: 'completed this task',
  task_details_updated: 'updated task details',
  task_planned: 'planned this task',
  task_reopened: 'reopened this task',
  task_restored: 'restored this task',
  task_returned_to_inbox: 'returned this task to Inbox',
  task_trashed: 'moved this task to Trash',
  task_undo_applied: 'undid an accepted change',
  task_unplanned: 'removed this task from the plan',
}

const recoveryCopy: Record<TaskActivity['recoveryState'], string> = {
  available: 'Undo available',
  expired: 'Undo expired',
  not_available: 'No undo available',
  stale: 'Undo unavailable after a later change',
  undone: 'Undone',
}

const fieldCopy: Record<ActivityChange['field'], string> = {
  completed_at: 'Completion time',
  deadline_on: 'Deadline',
  inbox_state: 'Inbox state',
  notes: 'Notes',
  planned_on: 'Planned date',
  project: 'Project',
  tags: 'Tags',
  title: 'Title',
  trashed_at: 'Trash time',
}

const formatAcceptedAt = (acceptedAt: string, timeZone: string) =>
  new Intl.DateTimeFormat('en-US', {
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    month: 'short',
    timeZone,
    timeZoneName: 'short',
    year: 'numeric',
  }).format(new Date(acceptedAt))

const OrganizationValue = ({ value }: { value: TaskOrganizationReference }) => (
  <span>
    {value.name}
    {value.archived ? <span className="ml-2 font-semibold">Archived</span> : null}
  </span>
)

const ChangeValue = ({ value }: { value: ActivityChange['new'] }) => {
  if (value === null) return <span>None</span>
  if (typeof value === 'string') return <span className="whitespace-pre-wrap">{value}</span>
  if (Array.isArray(value)) {
    if (value.length === 0) return <span>None</span>
    return (
      <span className="flex flex-wrap gap-2">
        {value.map((organization) => (
          <OrganizationValue key={organization.id} value={organization} />
        ))}
      </span>
    )
  }
  return <OrganizationValue value={value as TaskOrganizationReference} />
}

const ChangeDetails = ({ changes }: { changes: readonly ActivityChange[] }) => {
  const textChanges = changes.filter((change) => change.kind === 'text')
  const visibleChanges = changes.filter((change) => change.kind !== 'text')

  return (
    <div className="space-y-3">
      {visibleChanges.length > 0 ? (
        <dl className="space-y-2">
          {visibleChanges.map((change) => (
            <div key={change.field}>
              <dt className="text-sm font-semibold">{fieldCopy[change.field]}</dt>
              <dd className="grid gap-1 text-sm text-muted-foreground sm:grid-cols-2">
                <span>
                  <span className="font-semibold text-foreground">Before: </span>
                  <ChangeValue value={change.old} />
                </span>
                <span>
                  <span className="font-semibold text-foreground">After: </span>
                  <ChangeValue value={change.new} />
                </span>
              </dd>
            </div>
          ))}
        </dl>
      ) : null}

      {textChanges.length > 0 ? (
        <details className="text-sm">
          <summary className="min-h-11 cursor-pointer py-3 font-semibold text-primary">
            Show change
          </summary>
          <dl className="space-y-4 border-l border-border pl-4">
            {textChanges.map((change) => (
              <div key={change.field}>
                <dt className="font-semibold">{fieldCopy[change.field]}</dt>
                <dd className="mt-1 grid gap-3 sm:grid-cols-2">
                  <div>
                    <span className="block text-muted-foreground">Before</span>
                    <ChangeValue value={change.old} />
                  </div>
                  <div>
                    <span className="block text-muted-foreground">After</span>
                    <ChangeValue value={change.new} />
                  </div>
                </dd>
              </div>
            ))}
          </dl>
        </details>
      ) : null}
    </div>
  )
}

const copyText = (value: string) => {
  if (navigator.clipboard) void navigator.clipboard.writeText(value)
}

const ActivityItem = ({
  accountTimezone,
  activity,
}: {
  accountTimezone: string
  activity: TaskActivity
}) => (
  <li
    className="space-y-3 border-b border-border py-5 [content-visibility:auto] [contain-intrinsic-size:auto_180px]"
    data-activity-id={activity.activityId}
    tabIndex={-1}
  >
    <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
      <p>
        <span className="font-semibold">{activity.actor.label}</span>{' '}
        {actionCopy[activity.type]}.
      </p>
      <time
        className="text-sm tabular-nums text-muted-foreground"
        dateTime={activity.acceptedAt}
      >
        {formatAcceptedAt(activity.acceptedAt, accountTimezone)}
      </time>
    </div>

    <p className="text-sm">
      <span className="font-semibold">Accepted</span>
      <span className="text-muted-foreground"> · {recoveryCopy[activity.recoveryState]}</span>
    </p>

    <ChangeDetails changes={activity.changes} />

    <details className="text-sm">
      <summary className="min-h-11 cursor-pointer py-3 font-semibold text-primary">
        Technical details
      </summary>
      <dl className="space-y-3 border-l border-border pl-4 tabular-nums">
        <div>
          <dt className="font-semibold">Revision</dt>
          <dd>
            {activity.fromRevision === null
              ? `Created at revision ${activity.toRevision}`
              : `Revision ${activity.fromRevision} → ${activity.toRevision}`}
          </dd>
        </div>
        <div>
          <dt className="font-semibold">Mutation ID</dt>
          <dd className="flex flex-wrap items-center gap-2">
            <code className="break-all">{activity.mutationId}</code>
            <Button
              aria-label="Copy mutation ID"
              onClick={() => copyText(activity.mutationId)}
              size="sm"
              type="button"
              variant="outline"
            >
              Copy
            </Button>
          </dd>
        </div>
        <div>
          <dt className="font-semibold">Activity ID</dt>
          <dd className="flex items-center gap-2">
            <code>{activity.activityId}</code>
            <Button
              aria-label="Copy activity ID"
              onClick={() => copyText(String(activity.activityId))}
              size="sm"
              type="button"
              variant="outline"
            >
              Copy
            </Button>
          </dd>
        </div>
        <div>
          <dt className="font-semibold">Client</dt>
          <dd>{activity.clientKind}</dd>
        </div>
      </dl>
    </details>
  </li>
)

function ActivityListForTask({ taskId }: ActivityListProps) {
  const [page, setPage] = useState<TaskActivityPage | null>(null)
  const [viewState, setViewState] = useState<ViewState>('loading')
  const appendedFocusId = useRef<number | null>(null)

  useEffect(() => {
    let active = true

    void getTaskActivity(taskId)
      .then((nextPage) => {
        if (!active) return
        setPage(nextPage)
        setViewState('ready')
      })
      .catch(() => {
        if (active) setViewState('initial-error')
      })

    return () => {
      active = false
    }
  }, [taskId])

  useEffect(() => {
    if (appendedFocusId.current === null) return
    const target = document.querySelector<HTMLElement>(
      `[data-activity-id="${appendedFocusId.current}"]`,
    )
    target?.focus()
    appendedFocusId.current = null
  }, [page?.items.length])

  const retryInitial = async () => {
    setViewState('loading')
    try {
      setPage(await getTaskActivity(taskId))
      setViewState('ready')
    } catch {
      setViewState('initial-error')
    }
  }

  const loadEarlier = async () => {
    if (!page?.nextCursor) return
    setViewState('loading-earlier')
    try {
      const earlierPage = await getTaskActivity(taskId, page.nextCursor)
      appendedFocusId.current = earlierPage.items[0]?.activityId ?? null
      setPage((current) =>
        current === null
          ? earlierPage
          : {
              accountTimezone: current.accountTimezone,
              items: [...current.items, ...earlierPage.items],
              nextCursor: earlierPage.nextCursor,
            },
      )
      setViewState('ready')
    } catch (error) {
      if (error instanceof KeeplingApiError && error.problem.code === 'activity_cursor_stale') {
        setViewState('stale')
      } else {
        setViewState('earlier-error')
      }
    }
  }

  const refresh = async () => {
    setViewState('refreshing')
    try {
      setPage(await getTaskActivity(taskId))
      setViewState('ready')
    } catch {
      setViewState('earlier-error')
    }
  }

  if (viewState === 'loading' && page === null) {
    return (
      <section aria-labelledby="activity-heading" className="mx-auto max-w-3xl p-6 lg:px-8">
        <h2 className="text-xl font-semibold" id="activity-heading">
          Activity
        </h2>
        <p aria-live="polite" className="mt-4" role="status">
          Loading activity…
        </p>
      </section>
    )
  }

  if (viewState === 'initial-error' && page === null) {
    return (
      <section aria-labelledby="activity-heading" className="mx-auto max-w-3xl p-6 lg:px-8">
        <h2 className="text-xl font-semibold" id="activity-heading">
          Activity
        </h2>
        <div className="mt-4 space-y-3" role="alert">
          <p>Couldn’t load activity. Your tasks weren’t changed.</p>
          <Button onClick={() => void retryInitial()} type="button" variant="outline">
            Retry loading activity
          </Button>
        </div>
      </section>
    )
  }

  return (
    <section
      aria-labelledby="activity-heading"
      className="mx-auto max-w-3xl border-t border-border p-6 lg:px-8"
    >
      <h2 className="text-xl font-semibold" id="activity-heading">
        Activity
      </h2>

      {page?.items.length === 0 ? (
        <div className="mt-6 space-y-2">
          <h3 className="font-semibold">No activity yet</h3>
          <p>Accepted changes to this task will appear here.</p>
        </div>
      ) : null}

      {page && page.items.length > 0 ? (
        <ul className="mt-2">
          {page.items.map((activity) => (
            <ActivityItem
              accountTimezone={page.accountTimezone}
              activity={activity}
              key={activity.activityId}
            />
          ))}
        </ul>
      ) : null}

      {viewState === 'stale' ? (
        <div className="mt-4 space-y-3 border border-border p-4" role="alert">
          <p>This view changed before more items could load.</p>
          <Button onClick={() => void refresh()} type="button" variant="outline">
            Refresh view
          </Button>
        </div>
      ) : null}

      {viewState === 'earlier-error' ? (
        <div className="mt-4 space-y-3 border border-border p-4" role="alert">
          <p>Couldn’t load earlier activity. Showing the last loaded version.</p>
          <Button onClick={() => void loadEarlier()} type="button" variant="outline">
            Retry loading earlier activity
          </Button>
        </div>
      ) : null}

      {viewState === 'refreshing' ? (
        <p aria-live="polite" className="mt-4" role="status">
          Updating…
        </p>
      ) : null}

      {page?.nextCursor && !['stale', 'refreshing'].includes(viewState) ? (
        <Button
          className="mt-5"
          disabled={viewState === 'loading-earlier'}
          onClick={() => void loadEarlier()}
          type="button"
          variant="outline"
        >
          {viewState === 'loading-earlier' ? 'Loading earlier…' : 'Load earlier activity'}
        </Button>
      ) : null}
    </section>
  )
}

function ActivityList({ taskId }: ActivityListProps) {
  return <ActivityListForTask key={taskId} taskId={taskId} />
}

export default ActivityList
