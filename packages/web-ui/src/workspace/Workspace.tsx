import { useEffect, useMemo, useRef, useState } from 'react'

import type { ClientFacade, WorkspaceRoute, WorkspaceSnapshotView } from '../ClientFacade'
import CaptureForm from '../capture/CaptureForm'
import ConflictResolver from '../tasks/ConflictResolver'
import TaskEditor, { type TaskEditorHandle } from '../tasks/TaskEditor'
import TaskList from '../tasks/TaskList'
import SyncRecovery from '../recovery/SyncRecovery'

/**
 * Responsive workspace presentation (D-04/D-05, UI-SPEC "Main Window
 * Contract"). Composes Inbox/Today/Trash navigation, the task list, the task
 * detail editor, inline conflict resolution, and the recovery strip through
 * the shared ClientFacade only. It renders unchanged by the browser adapter
 * and the Electron renderer.
 */
type WorkspaceProps = {
  facade: ClientFacade
  /**
   * Desktop-only sidebar visibility (D-14 "Toggle Sidebar", Command-Control-S).
   * Optional and defaults to visible so browser/fixture callers are
   * unaffected; only the Electron renderer toggles this.
   */
  sidebarVisible?: boolean
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

const routeLabel = (route: WorkspaceRoute): string => {
  if (route === 'today') return 'Today'
  if (route === 'trash') return 'Trash'
  return 'Inbox'
}

const emptyCopy: Record<WorkspaceRoute, { body: string; title: string }> = {
  inbox: { body: 'Captured tasks appear here until you move them out.', title: 'Inbox Is Clear' },
  today: { body: 'Add a task to Today to see it here.', title: 'Nothing Planned for Today' },
  trash: { body: 'Tasks you move to Trash appear here until restored.', title: 'Trash Is Empty' },
}

type PendingNavigation = { kind: 'route'; route: WorkspaceRoute } | { kind: 'select'; taskId: string | null }

function Workspace({ facade, sidebarVisible = true }: WorkspaceProps) {
  const [snapshot, setSnapshot] = useState<WorkspaceSnapshotView>(() => facade.getSnapshot())
  const [dirty, setDirty] = useState(false)
  const [pendingNavigation, setPendingNavigation] = useState<PendingNavigation | null>(null)
  const [focusTaskId, setFocusTaskId] = useState<string | null>(null)
  const breakpoint = useBreakpoint()
  const editorRef = useRef<TaskEditorHandle>(null)
  const headingRef = useRef<HTMLHeadingElement>(null)
  const previousTasksRef = useRef(snapshot.tasks)

  useEffect(() => facade.subscribe(setSnapshot), [facade])

  const routeTasks = useMemo(
    () =>
      snapshot.tasks.filter((task) => {
        if (snapshot.route === 'trash') return task.trashedAt !== null
        if (task.trashedAt !== null) return false
        if (snapshot.route === 'today') return task.planned && task.completedAt === null
        return !task.planned
      }),
    [snapshot.route, snapshot.tasks],
  )

  const selectedTask = useMemo(
    () => routeTasks.find((task) => task.id === snapshot.selectedTaskId) ?? null,
    [routeTasks, snapshot.selectedTaskId],
  )

  // When a task falls out of the current route view (completed, trashed, or
  // moved), restore focus by stable identity: the row now at the same
  // position, else the previous row, else the list heading (D-14).
  useEffect(() => {
    const previous = previousTasksRef.current
    previousTasksRef.current = snapshot.tasks
    if (snapshot.selectedTaskId === null) return
    const stillVisible = routeTasks.some((task) => task.id === snapshot.selectedTaskId)
    if (stillVisible) return
    const removedIndex = previous.findIndex((task) => task.id === snapshot.selectedTaskId)
    const next =
      routeTasks[Math.min(removedIndex, routeTasks.length - 1)] ??
      routeTasks[routeTasks.length - 1] ??
      null
    facade.selectTask(null)
    if (next) setFocusTaskId(next.id)
    else headingRef.current?.focus()
  }, [facade, routeTasks, snapshot.selectedTaskId, snapshot.tasks])

  const showList = breakpoint !== 'compact' || selectedTask === null
  const showDetail = breakpoint !== 'compact' || selectedTask !== null

  const attemptNavigation = async (navigation: PendingNavigation) => {
    if (!dirty) {
      commitNavigation(navigation)
      return
    }
    setPendingNavigation(navigation)
  }

  const commitNavigation = (navigation: PendingNavigation) => {
    if (navigation.kind === 'route') facade.setRoute(navigation.route)
    else facade.selectTask(navigation.taskId)
  }

  const resolvePendingSave = async () => {
    const saved = (await editorRef.current?.save()) ?? true
    if (saved && pendingNavigation) {
      commitNavigation(pendingNavigation)
      setPendingNavigation(null)
    }
  }

  const resolvePendingDiscard = () => {
    editorRef.current?.discard()
    if (pendingNavigation) commitNavigation(pendingNavigation)
    setPendingNavigation(null)
  }

  const handleBack = () => {
    void attemptNavigation({ kind: 'select', taskId: null })
  }

  const handleEscape = () => {
    if (selectedTask === null) return
    void attemptNavigation({ kind: 'select', taskId: null })
  }

  return (
    <main data-workspace-breakpoint={breakpoint} id="main-content" tabIndex={-1}>
      <nav
        aria-label="Workspace destinations"
        data-workspace-region="nav"
        hidden={!sidebarVisible}
      >
        {(['inbox', 'today', 'trash'] as const).map((route) => (
          <button
            aria-current={snapshot.route === route ? 'true' : undefined}
            data-workspace-nav={route}
            key={route}
            onClick={() => void attemptNavigation({ kind: 'route', route })}
            type="button"
          >
            {routeLabel(route)}
          </button>
        ))}
      </nav>

      {snapshot.conflict !== null ? (
        <ConflictResolver conflict={snapshot.conflict} facade={facade} />
      ) : null}

      {showList ? (
        <section aria-label={routeLabel(snapshot.route)} data-workspace-region="list">
          {snapshot.route === 'inbox' ? <CaptureForm facade={facade} /> : null}
          {routeTasks.length === 0 ? (
            <div data-workspace-empty={snapshot.route}>
              <h2 ref={headingRef} tabIndex={-1}>
                {emptyCopy[snapshot.route].title}
              </h2>
              <p>{emptyCopy[snapshot.route].body}</p>
            </div>
          ) : (
            <TaskList
              focusTaskId={focusTaskId}
              onSelect={(taskId) => void attemptNavigation({ kind: 'select', taskId })}
              selectedTaskId={snapshot.selectedTaskId}
              tasks={routeTasks}
            />
          )}
        </section>
      ) : null}
      {showDetail ? (
        <section
          aria-label="Task detail"
          data-workspace-region="detail"
          onKeyDown={(event) => {
            if (event.key === 'Escape') {
              event.preventDefault()
              handleEscape()
            }
          }}
        >
          {selectedTask === null ? (
            <>
              <h2>Choose a Task</h2>
              <p>Select a task from the list to view or edit it.</p>
            </>
          ) : (
            <>
              {breakpoint === 'compact' ? (
                <button onClick={handleBack} type="button">
                  Back
                </button>
              ) : null}
              <h2 id="workspace-detail-title">{selectedTask.title}</h2>
              <TaskEditor facade={facade} onDirtyChange={setDirty} ref={editorRef} task={selectedTask} />
            </>
          )}
        </section>
      ) : null}

      <SyncRecovery facade={facade} />

      {pendingNavigation !== null ? (
        <div aria-label="Discard unsaved changes?" data-workspace-dirty-dialog="true" role="alertdialog">
          <h2>Discard unsaved changes?</h2>
          <p>These edits haven't been saved.</p>
          <button onClick={() => void resolvePendingSave()} type="button">
            Save Changes
          </button>
          <button onClick={resolvePendingDiscard} type="button">
            Discard Changes
          </button>
          <button onClick={() => setPendingNavigation(null)} type="button">
            Keep Editing
          </button>
        </div>
      ) : null}
    </main>
  )
}

export default Workspace
export { resolveBreakpoint }
export type { Breakpoint }
