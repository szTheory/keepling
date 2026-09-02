import { useEffect, useMemo, useState } from 'react'

import type { ClientFacade, WorkspaceSnapshotView, WorkspaceTaskView } from '../ClientFacade'
import CaptureForm from '../capture/CaptureForm'
import TaskList from '../tasks/TaskList'

/**
 * Responsive Inbox capture/list/detail presentation (D-04/D-05, UI-SPEC "Main
 * Window Contract"). It renders through the shared ClientFacade only and is
 * consumed unchanged by the browser adapter and the Electron renderer.
 */
type WorkspaceProps = {
  facade: ClientFacade
}

const PERSISTENT_NAV_START = 1064
const COMPACT_WIDE_START = 1024

type Breakpoint = 'compact' | 'compact-wide' | 'persistent'

const resolveBreakpoint = (width: number): Breakpoint => {
  if (width >= PERSISTENT_NAV_START) return 'persistent'
  if (width >= COMPACT_WIDE_START) return 'compact-wide'
  return 'compact'
}

const useBreakpoint = (): Breakpoint => {
  const [breakpoint, setBreakpoint] = useState<Breakpoint>(() =>
    resolveBreakpoint(typeof window === 'undefined' ? 0 : window.innerWidth),
  )

  useEffect(() => {
    const update = () => setBreakpoint(resolveBreakpoint(window.innerWidth))
    update()
    window.addEventListener('resize', update)
    return () => window.removeEventListener('resize', update)
  }, [])

  return breakpoint
}

const syncStatusLabel = (status: WorkspaceTaskView['syncStatus']): string => {
  if (status === 'synced') return 'Synced'
  if (status === 'saved_on_this_mac') return 'Saved on this Mac'
  return 'Draft'
}

function Workspace({ facade }: WorkspaceProps) {
  const [snapshot, setSnapshot] = useState<WorkspaceSnapshotView>(() => facade.getSnapshot())
  const breakpoint = useBreakpoint()

  useEffect(() => facade.subscribe(setSnapshot), [facade])

  const selectedTask = useMemo(
    () => snapshot.tasks.find((task) => task.id === snapshot.selectedTaskId) ?? null,
    [snapshot.selectedTaskId, snapshot.tasks],
  )

  // Below 1024px show one routed surface at a time (D-04); at and above it,
  // list and detail stay independently visible and independently scrollable.
  const showList = breakpoint !== 'compact' || selectedTask === null
  const showDetail = breakpoint !== 'compact' || selectedTask !== null

  return (
    <main data-workspace-breakpoint={breakpoint} id="main-content" tabIndex={-1}>
      {showList ? (
        <section aria-label="Inbox" data-workspace-region="list">
          <CaptureForm facade={facade} />
          {snapshot.tasks.length === 0 ? (
            <div data-workspace-empty="inbox">
              <h2>Inbox Is Clear</h2>
              <p>Captured tasks appear here until you move them out.</p>
            </div>
          ) : (
            <TaskList
              onSelect={(taskId) => facade.selectTask(taskId)}
              selectedTaskId={snapshot.selectedTaskId}
              tasks={snapshot.tasks}
            />
          )}
        </section>
      ) : null}
      {showDetail ? (
        <section aria-label="Task detail" data-workspace-region="detail">
          {selectedTask === null ? (
            <>
              <h2>Choose a Task</h2>
              <p>Select a task from the list to view or edit it.</p>
            </>
          ) : (
            <article aria-labelledby="workspace-detail-title">
              <h2 id="workspace-detail-title">{selectedTask.title}</h2>
              {breakpoint === 'compact' ? (
                <button onClick={() => facade.selectTask(null)} type="button">
                  Back
                </button>
              ) : null}
              {selectedTask.notes === '' ? null : <p>{selectedTask.notes}</p>}
              <p data-workspace-sync-status={selectedTask.syncStatus}>
                {syncStatusLabel(selectedTask.syncStatus)}
              </p>
            </article>
          )}
        </section>
      ) : null}
    </main>
  )
}

export default Workspace
export { resolveBreakpoint }
export type { Breakpoint }
