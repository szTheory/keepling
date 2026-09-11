import { useEffect, useRef, useState } from 'react'

import type { ClientFacade } from '../../../packages/web-ui/src/ClientFacade.ts'
import Workspace, { type WorkspaceHandle } from '../../../packages/web-ui/src/workspace/Workspace.tsx'
import SyncStatusRow from './SyncStatusRow.tsx'
import { matchSemanticCommand, shouldDispatchCommand, type SemanticCommand } from './keyboardCommands.ts'

type DesktopShellProps = {
  facade: ClientFacade
}

const destinationTitle = (route: 'inbox' | 'today' | 'trash'): string => {
  if (route === 'today') return 'Keepling — Today'
  if (route === 'trash') return 'Keepling — Trash'
  return 'Keepling — Inbox'
}

/**
 * Desktop-only shell around the shared `Workspace` presentation. Owns:
 *  - the sidebar-visibility toggle (Command-Control-S, D-14), and
 *  - the native-menu-equivalent keyboard commands not already implemented
 *    by TaskEditor (Command-S/Command-Return) or TaskList (Up/Down/Return).
 *
 * `document.title` is set here directly from the ClientFacade snapshot
 * (D-07): Electron's BrowserWindow mirrors `document.title` as the native
 * window title by default, so this never needs a main-process round trip
 * and never contains task content (only the coarse destination name).
 *
 * O-11 gap closure (D-06 renderer-semantic restoration): `sidebarVisible`
 * starts optimistically `true` (the pre-existing default) and is updated by
 * `onSidebarVisibleRestored` if `Workspace` finds a persisted layout. This
 * file is a necessary, disclosed addition beyond this plan's originally
 * declared `files_modified` (see 03-13-SUMMARY.md "Deviations") -- sidebar
 * visibility is real state this component alone owns, so restoring it
 * requires a two-line wire here regardless of file scope.
 */
function DesktopShell({ facade }: DesktopShellProps) {
  const [sidebarVisible, setSidebarVisible] = useState(true)
  // Task 3 (O-22): the keyboard-command dispatch below must route every
  // route/selection-changing command through Workspace's own dirty-state
  // guard instead of calling `facade.setRoute`/`facade.selectTask` directly
  // -- this ref is the reachable seam `Workspace` exposes for that.
  const workspaceRef = useRef<WorkspaceHandle>(null)

  useEffect(() => {
    const applyTitle = () => {
      document.title = destinationTitle(facade.getSnapshot().route)
    }
    applyTitle()
    return facade.subscribe(applyTitle)
  }, [facade])

  useEffect(() => {
    const dispatch = (command: SemanticCommand) => {
      const snapshot = facade.getSnapshot()
      const selected = snapshot.tasks.find((task) => task.id === snapshot.selectedTaskId) ?? null
      switch (command) {
        case 'new-task': {
          workspaceRef.current?.guardedSetRoute('inbox', () => {
            queueMicrotask(() => {
              document.getElementById('workspace-capture-title')?.focus()
            })
          })
          break
        }
        case 'go-inbox':
          workspaceRef.current?.guardedSetRoute('inbox')
          break
        case 'go-today':
          workspaceRef.current?.guardedSetRoute('today')
          break
        case 'toggle-complete-reopen': {
          if (selected === null) break
          if (selected.completedAt === null) void facade.completeTask(selected.id)
          else void facade.reopenTask(selected.id)
          break
        }
        case 'toggle-trash-restore': {
          if (selected === null) break
          if (selected.trashedAt === null) void facade.trashTask(selected.id)
          else void facade.restoreTask(selected.id)
          break
        }
        case 'undo':
          void facade.undoLastChange()
          break
        case 'toggle-sidebar':
          setSidebarVisible((visible) => !visible)
          break
        case 'sync-recovery':
          document.getElementById('sync-recovery-region')?.focus()
          break
      }
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      const command = matchSemanticCommand(event)
      if (command === null) return
      if (
        !shouldDispatchCommand(command, {
          activeElement: document.activeElement,
          isComposing: event.isComposing,
          repeat: event.repeat,
        })
      ) {
        return
      }
      event.preventDefault()
      dispatch(command)
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [facade])

  return (
    <>
      {/*
        O-30 (Rule 2): the main-owned MAC-04 status row. Rendered ABOVE the
        workspace rather than inside `packages/web-ui` because it is fed by
        the desktop preload bridge's presentation channel, which the shared
        browser presentation has no equivalent of.
      */}
      <SyncStatusRow />
      <Workspace
        facade={facade}
        onSidebarVisibleRestored={setSidebarVisible}
        ref={workspaceRef}
        sidebarVisible={sidebarVisible}
      />
    </>
  )
}

export default DesktopShell
