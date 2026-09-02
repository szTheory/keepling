import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
  type ReactNode,
} from 'react'

import {
  KeeplingApiError,
  listSessions,
  logout,
  type BrowserSession,
  type UndoAvailability,
  type UndoResult,
} from '@/api/keepling'
import { createBrowserClientFacade } from '@/adapters/browserClientFacade'
import { AlertDialog, type AlertDialogAction } from '@/components/ui/alert-dialog'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryStrip from '@/features/recovery/RecoveryStrip'
import SessionList from '@/features/sessions/SessionList'
import WorkspaceShell, { type WorkspaceLayoutContent } from '@/app/WorkspaceShell'

type AppShellProps = {
  csrfToken: string
  hasDirtyWork?: boolean
  inboxContent?: ReactNode
  onDiscardDirtyWork?: () => void
  onLoggedOut: () => void
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onSaveDirtyWork?: () => Promise<void> | void
  routeContent?: WorkspaceLayoutContent
}

function AppShell({
  csrfToken,
  hasDirtyWork = false,
  inboxContent,
  onDiscardDirtyWork = () => undefined,
  onAuthenticationRequired,
  onLoggedOut,
  onSaveDirtyWork = () => undefined,
  routeContent,
}: AppShellProps) {
  const [pathname, setPathname] = useState(window.location.pathname)
  // The presentation-only ClientFacade adapter (D-26/D-27) is the seam
  // recovery/undo availability now flows through, instead of AppShell
  // reading window CustomEvents directly. The underlying event mechanism,
  // timing, and payload are unchanged.
  const clientFacade = useMemo(() => createBrowserClientFacade(csrfToken), [csrfToken])
  const [latestUndo, setLatestUndo] = useState<UndoAvailability | null>(
    clientFacade.getRecoveryAvailability(),
  )
  const [pendingAction, setPendingAction] = useState<
    | { href: string; kind: 'navigate' }
    | { kind: 'logout'; session: BrowserSession }
    | null
  >(null)
  const [logoutBusy, setLogoutBusy] = useState(false)
  const [logoutMessage, setLogoutMessage] = useState('')
  const stayButtonRef = useRef<HTMLButtonElement>(null)
  const confirmationTriggerRef = useRef<HTMLElement>(null)
  const logoutInFlightRef = useRef(false)

  useEffect(() => {
    const update = () => setPathname(window.location.pathname)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  useEffect(() => clientFacade.subscribeRecovery(setLatestUndo), [clientFacade])

  const handleUndoSettled = (result: UndoResult) => {
    if (result.kind === 'acknowledged') {
      window.dispatchEvent(
        new CustomEvent('keepling:task-acknowledged', {
          detail: result.acknowledgement,
        }),
      )
    }
  }

  const recovery = latestUndo ? (
    <RecoveryStrip
      availability={latestUndo}
      csrfToken={csrfToken}
      key={latestUndo.handle}
      onAuthenticationRequired={onAuthenticationRequired}
      onSettled={handleUndoSettled}
    />
  ) : null

  const isCurrent = (href: string) =>
    href === '/' ? pathname === '/' || pathname === '/inbox' : pathname === href

  const navigate = (href: string) => {
    window.history.pushState({}, '', href)
    window.dispatchEvent(new PopStateEvent('popstate'))
  }

  const guardNavigation = (event: MouseEvent<HTMLAnchorElement>, href: string) => {
    if (!hasDirtyWork || isCurrent(href)) return
    event.preventDefault()
    confirmationTriggerRef.current = event.currentTarget
    setPendingAction({ href, kind: 'navigate' })
  }

  const finishNavigation = async (href: string, disposition: 'discard' | 'save') => {
    if (disposition === 'save') await onSaveDirtyWork()
    else onDiscardDirtyWork()
    setPendingAction(null)
    navigate(href)
  }

  const reconcileLogout = async (session: BrowserSession, allowRetry: boolean, activeCsrfToken: string) => {
    let sessions: readonly BrowserSession[]
    try {
      sessions = await listSessions()
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required'
      ) {
        onLoggedOut()
        return
      }
      throw error
    }
    if (!sessions.some((candidate) => candidate.id === session.id)) {
      setLogoutMessage('The previous browser session was logged out.')
      return
    }
    if (!allowRetry) {
      setLogoutMessage('The previous browser session remains active.')
      return
    }
    await logout(activeCsrfToken)
    onLoggedOut()
  }

  const performLogout = async (session: BrowserSession, activeCsrfToken = csrfToken) => {
    if (logoutInFlightRef.current) return
    logoutInFlightRef.current = true
    setLogoutBusy(true)
    setLogoutMessage('')
    try {
      await logout(activeCsrfToken)
      onLoggedOut()
    } catch (error) {
      const authentication =
        error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
          ? 'sign_in'
          : error instanceof KeeplingApiError &&
              error.problem.code === 'recent_authentication_required'
            ? 'reauthenticate'
            : null
      if (authentication && onAuthenticationRequired) {
        onAuthenticationRequired(
          { authentication, kind: 'action', mutationId: `session-logout:${session.id}` },
          async (nextCsrfToken) => {
            await reconcileLogout(session, true, nextCsrfToken)
          },
        )
      } else {
        try {
          await reconcileLogout(session, false, activeCsrfToken)
        } catch {
          setLogoutMessage('Keepling could not confirm whether this browser was logged out.')
        }
      }
    } finally {
      logoutInFlightRef.current = false
      setLogoutBusy(false)
      setPendingAction(null)
    }
  }

  const requestLogout = (session: BrowserSession, trigger: HTMLElement) => {
    confirmationTriggerRef.current = trigger
    setPendingAction({ kind: 'logout', session })
  }

  const content: WorkspaceLayoutContent = pathname === '/settings/sessions' ? { mainContent: (
    <main className="min-w-0 bg-background px-4 py-8 sm:px-6 lg:px-8" id="main-content" tabIndex={-1}>
      <div className="mx-auto max-w-3xl">
        <h1 className="text-[1.75rem] font-semibold leading-[1.2]">Sessions</h1>
        <p className="mt-2 text-muted-foreground">
          Review where Keepling is signed in. Activity is intentionally coarse and is not a trusted-device claim.
        </p>
        <section aria-label="Session administration" className="mt-8">
          <SessionList
            csrfToken={csrfToken}
            hasDirtyWork={hasDirtyWork}
            onAuthenticationRequired={onAuthenticationRequired}
            onLoggedOut={onLoggedOut}
            onRequestLogout={requestLogout}
          />
        </section>
      </div>
    </main>
  ) } : routeContent ?? { mainContent: inboxContent }

  return (
    <>
      <WorkspaceShell
        clientFacade={clientFacade}
        detailContent={content.detailContent}
        detailSelected={content.detailSelected}
        listContent={content.listContent}
        onNavigate={guardNavigation}
        pathname={pathname}
      >
        {content.mainContent ?? (
          <main className="p-6" id="main-content" tabIndex={-1}>
            <h1 className="text-[1.75rem] font-semibold">Keepling</h1>
          </main>
        )}
      </WorkspaceShell>
      {recovery}
      {logoutMessage ? <p className="p-4" role="status">{logoutMessage}</p> : null}
      <div aria-atomic="true" aria-live="polite" className="sr-only" role="status" />
      <AlertDialog
        actions={((): AlertDialogAction[] => {
          if (!pendingAction) return []
          const keepEditing: AlertDialogAction = {
            label: 'Keep editing',
            onClick: () => setPendingAction(null),
            ref: stayButtonRef,
            variant: 'outline',
          }
          if (pendingAction.kind === 'navigate') {
            return [
              keepEditing,
              {
                label: 'Save changes',
                onClick: () => void finishNavigation(pendingAction.href, 'save'),
              },
              {
                label: 'Discard changes',
                onClick: () => void finishNavigation(pendingAction.href, 'discard'),
                variant: 'destructive',
              },
            ]
          }
          if (!hasDirtyWork) {
            return [
              keepEditing,
              {
                disabled: logoutBusy,
                label: 'Log out',
                onClick: () => void performLogout(pendingAction.session),
                variant: 'destructive',
              },
            ]
          }
          return [
            keepEditing,
            {
              disabled: logoutBusy,
              label: 'Save changes',
              onClick: async () => {
                await onSaveDirtyWork()
                await performLogout(pendingAction.session)
              },
            },
            {
              disabled: logoutBusy,
              label: 'Discard changes and log out',
              onClick: () => {
                onDiscardDirtyWork()
                void performLogout(pendingAction.session)
              },
              variant: 'destructive',
            },
          ]
        })()}
        description={
          pendingAction?.kind === 'logout'
            ? hasDirtyWork
              ? 'Unsaved edits remain unless you save them before this browser signs out.'
              : 'The current browser will sign out. Saved tasks will remain in Keepling.'
            : 'These edits haven’t been saved.'
        }
        finalFocus={confirmationTriggerRef}
        initialFocus={stayButtonRef}
        onCancel={() => setPendingAction(null)}
        open={pendingAction !== null}
        title={pendingAction?.kind === 'logout' ? 'Log out this browser?' : 'Discard unsaved changes?'}
      />
    </>
  )
}

export default AppShell
