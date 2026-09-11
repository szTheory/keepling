import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState } from 'react'

import type { ClientFacade, WorkspaceLayoutState, WorkspaceRoute, WorkspaceSnapshotView } from '../ClientFacade'
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
   * O-11 gap closure (D-06): called (at most once) with a restored
   * sidebar-visibility value when a persisted layout is found. Workspace
   * does not own sidebar visibility itself (the Electron renderer's
   * DesktopShell does, via `sidebarVisible` below) -- this is how a
   * restored value reaches that owner without Workspace needing to own it.
   * Absent means "no caller wants restored sidebar visibility" (e.g. the
   * browser adapter, which has no such concept); never called with a
   * dangling or transient value.
   */
  onSidebarVisibleRestored?: (visible: boolean) => void
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

type PendingNavigation =
  | { kind: 'route'; onComplete?: () => void; route: WorkspaceRoute }
  | { kind: 'select'; onComplete?: () => void; taskId: string | null }

/**
 * Imperative seam (Task 3, O-22) letting a host outside this component --
 * today only `DesktopShell.tsx`'s keyboard-command dispatch -- request a
 * route change that goes through the SAME dirty-state guard the mouse nav
 * links already use, instead of calling `facade.setRoute` directly and
 * walking past it. `onComplete` runs only once the navigation actually
 * takes effect (immediately when clean, or after Save/Discard resolves the
 * dialog when dirty) -- never when the person chooses Keep Editing.
 */
type WorkspaceHandle = {
  guardedSetRoute: (route: WorkspaceRoute, onComplete?: () => void) => void
}

const Workspace = forwardRef<WorkspaceHandle, WorkspaceProps>(function Workspace(
  { facade, onSidebarVisibleRestored, sidebarVisible = true },
  ref,
) {
  const [snapshot, setSnapshot] = useState<WorkspaceSnapshotView>(() => facade.getSnapshot())
  const [dirty, setDirty] = useState(false)
  const [pendingNavigation, setPendingNavigation] = useState<PendingNavigation | null>(null)
  const [focusTaskId, setFocusTaskId] = useState<string | null>(null)
  const breakpoint = useBreakpoint()
  const editorRef = useRef<TaskEditorHandle>(null)
  const headingRef = useRef<HTMLHeadingElement>(null)
  // A4: the unsaved-changes alertdialog must announce itself the way the
  // Quick Entry and conflict dialogs already do. `keepEditingRef` is the
  // safe, non-destructive default action focus lands on when the dialog
  // opens; `dialogReturnFocusRef` remembers the element that was focused
  // when the dialog opened so closing it never strands focus on a removed
  // node or silently resets it to <body>.
  const keepEditingRef = useRef<HTMLButtonElement>(null)
  const dialogReturnFocusRef = useRef<HTMLElement | null>(null)
  const previousTasksRef = useRef(snapshot.tasks)
  // O-11 gap closure (D-06 renderer-semantic restoration). `restoreAttemptedRef`
  // gates persistence: we must not persist (and thereby overwrite a real
  // saved layout with fresh-mount defaults) until a restore attempt has
  // actually resolved. `pendingRestoreRef` holds a restored layout between
  // "route applied" and "tasks loaded enough to validate selection/scroll/
  // draft against" -- see the two effects below.
  const restoreAttemptedRef = useRef(false)
  const pendingRestoreRef = useRef<WorkspaceLayoutState | null>(null)
  const [restoredDraft, setRestoredDraft] = useState<{ notes: string; taskId: string; title: string } | null>(null)

  useEffect(() => facade.subscribe(setSnapshot), [facade])

  // Restore step 1: fetch the persisted layout once per facade instance and
  // apply the destination + sidebar visibility immediately -- both are safe
  // to apply without waiting for tasks to load. Selection/scroll/draft are
  // deferred to step 2 because they must be validated against real tasks
  // (D-06: "a selected task that no longer exists degrades safely rather
  // than restoring a dangling selection").
  useEffect(() => {
    let cancelled = false
    const restore = facade.restoreWorkspaceLayout
    if (restore === undefined) {
      restoreAttemptedRef.current = true
      return undefined
    }
    void restore()
      .then((state) => {
        if (cancelled) return
        if (state !== null) {
          pendingRestoreRef.current = state
          facade.setRoute(state.destination)
          onSidebarVisibleRestored?.(state.sidebarVisible)
        }
      })
      .catch(() => {
        // Restoration is UI convenience only (D-03/D-21) -- a failure here
        // degrades to the ordinary fresh-workspace defaults, never a crash
        // and never blocks the workspace from rendering.
      })
      .finally(() => {
        if (!cancelled) restoreAttemptedRef.current = true
      })
    return () => {
      cancelled = true
    }
    // Deliberately run once per facade instance (a fresh facade means a
    // fresh relaunch/mount), not on every onSidebarVisibleRestored identity
    // change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facade])

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

  // Restore step 2: once the destination has actually taken effect on the
  // live snapshot (proving step 1's `setRoute` has landed and `routeTasks`
  // above reflects it), validate the restored selection/scroll-anchor/draft
  // against tasks that ACTUALLY exist right now. Anything not found is
  // dropped, never applied -- this is the "degrades safely" contract
  // (D-06: "a selected task that no longer exists degrades safely rather
  // than restoring a dangling selection").
  useEffect(() => {
    const pending = pendingRestoreRef.current
    if (pending === null) return
    if (snapshot.route !== pending.destination) return
    pendingRestoreRef.current = null
    const restoredTaskId =
      pending.selectedTaskId !== null && routeTasks.some((task) => task.id === pending.selectedTaskId)
        ? pending.selectedTaskId
        : null
    if (restoredTaskId !== null) facade.selectTask(restoredTaskId)
    const anchor =
      pending.scrollAnchorTaskId !== null && routeTasks.some((task) => task.id === pending.scrollAnchorTaskId)
        ? pending.scrollAnchorTaskId
        : restoredTaskId
    if (anchor !== null) setFocusTaskId(anchor)
    if (pending.draft !== null && routeTasks.some((task) => task.id === pending.draft!.taskId)) {
      setRestoredDraft(pending.draft)
    }
  }, [facade, routeTasks, snapshot.route])

  // Persist step: whenever meaningful semantic layout inputs change AFTER
  // the initial restore attempt has resolved (never before -- persisting
  // fresh-mount defaults before restoration runs would overwrite a real
  // saved layout with nothing), best-effort persist the current layout for
  // the next relaunch. `sidebarVisible` is a prop (owned by the Electron
  // renderer's DesktopShell), so it flows in here already current.
  useEffect(() => {
    if (!restoreAttemptedRef.current) return
    if (facade.persistWorkspaceLayout === undefined) return
    const draft = editorRef.current?.getDraft() ?? null
    facade.persistWorkspaceLayout({
      destination: snapshot.route,
      draft: draft !== null && selectedTask !== null ? { notes: draft.notes, taskId: selectedTask.id, title: draft.title } : null,
      scrollAnchorTaskId: focusTaskId ?? snapshot.selectedTaskId,
      selectedTaskId: snapshot.selectedTaskId,
      sidebarVisible,
    })
  }, [dirty, facade, focusTaskId, selectedTask, sidebarVisible, snapshot.route, snapshot.selectedTaskId])

  // A4 fix: move focus INTO the unsaved-changes alertdialog on open, onto
  // the safe non-destructive default action, and restore it to the
  // previously focused element on close. Without this a screen reader user
  // is never told the navigation was interrupted -- they keep hearing
  // whatever the triggering click happened to focus.
  useEffect(() => {
    if (pendingNavigation === null) {
      const previous = dialogReturnFocusRef.current
      dialogReturnFocusRef.current = null
      if (previous !== null && previous.isConnected) previous.focus()
      else if (previous !== null) {
        // The trigger was removed while the dialog was open (a task row
        // that left the route). Degrade to the list heading, then to the
        // main landmark -- never to a detached node, never to <body>.
        const fallback = headingRef.current ?? document.getElementById('main-content')
        fallback?.focus()
      }
      return
    }
    const active = document.activeElement
    dialogReturnFocusRef.current = active instanceof HTMLElement ? active : null
    keepEditingRef.current?.focus()
  }, [pendingNavigation])

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
    navigation.onComplete?.()
  }

  useImperativeHandle(
    ref,
    (): WorkspaceHandle => ({
      guardedSetRoute: (route, onComplete) => {
        void attemptNavigation({ kind: 'route', onComplete, route })
      },
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dirty, facade],
  )

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
              <TaskEditor
                facade={facade}
                initialDraft={restoredDraft && restoredDraft.taskId === selectedTask.id ? restoredDraft : undefined}
                onDirtyChange={setDirty}
                ref={editorRef}
                task={selectedTask}
              />
            </>
          )}
        </section>
      ) : null}

      <SyncRecovery
        facade={facade}
        onReviewRefusal={(taskId) => {
          const refusal = snapshot.unresolvedRefusals.find((entry) => entry.taskId === taskId)
          if (refusal === undefined) return
          facade.setRoute(refusal.route)
          facade.selectTask(taskId)
        }}
        unresolvedRefusals={snapshot.unresolvedRefusals}
      />

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
          <button onClick={() => setPendingNavigation(null)} ref={keepEditingRef} type="button">
            Keep Editing
          </button>
        </div>
      ) : null}
    </main>
  )
})

export default Workspace
export { resolveBreakpoint }
export type { Breakpoint, WorkspaceHandle }
