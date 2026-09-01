import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react'

import type { BeginReauthentication, ContinuationScope } from '@/app/AuthProvider'
import type { WorkspaceLayoutContent } from '@/app/WorkspaceShell'
import LoginForm from '@/features/auth/LoginForm'
import Reauthenticate, { type InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryReset from '@/features/auth/RecoveryReset'
import SetupForm from '@/features/auth/SetupForm'
import ActivityList from '@/features/activity/ActivityList'
import OrganizationFields, {
  OrganizationManager,
} from '@/features/organizations/OrganizationFields'
import TaskList from '@/features/lists/TaskList'
import TrashList from '@/features/lists/TrashList'
import TaskEditor from '@/features/tasks/TaskEditor'
import type { CommandAcknowledgement } from '@/api/keepling'
import { Button } from '@/components/ui/button'

type AppRoutesProps = {
  authenticated: boolean
  authenticatedContent?: ReactNode | ((
    beginReauthentication: BeginReauthentication,
    routeContent?: WorkspaceLayoutContent,
  ) => ReactNode)
  continuationError?: boolean
  createContinuationScope?: () => ContinuationScope
  csrfToken?: string
  interruption?: InterruptedIntent | null
  onAcknowledged?: (acknowledgement: CommandAcknowledgement) => void
  onAuthenticated?: (csrfToken: string) => void
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onReauthenticated?: (interruption: InterruptedIntent, csrfToken: string) => void
  onRetryContinuations?: () => Promise<void>
}

const routeToken = (pathname: string, prefix: string) => {
  if (!pathname.startsWith(prefix)) return null
  const raw = pathname.slice(prefix.length)
  if (raw === '' || raw.includes('/')) return null
  try {
    return decodeURIComponent(raw)
  } catch {
    return null
  }
}

const decodeRoutePart = (raw: string | undefined) => {
  if (!raw) return null
  try {
    return decodeURIComponent(raw)
  } catch {
    return null
  }
}

const navigate = (pathname: string) => {
  window.history.replaceState({}, '', pathname)
  window.dispatchEvent(new PopStateEvent('popstate'))
}

function InterruptionBoundary({
  children,
  interrupted,
  overlay,
}: {
  children: ReactNode
  interrupted: boolean
  overlay: ReactNode
}) {
  const boundaryRef = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    if (!interrupted) return
    const contentElement = boundaryRef.current?.querySelector<HTMLElement>(
      '[data-auth-recovery-content="true"]',
    )
    const overlayElement = boundaryRef.current?.querySelector<HTMLElement>(
      '[data-auth-recovery-overlay="true"]',
    )
    if (!contentElement || !overlayElement) return

    const retainedElements = [contentElement]
    const previousValues = retainedElements.map((element) => ({
      ariaHidden: element.getAttribute('aria-hidden'),
      inert: element.getAttribute('inert'),
    }))
    const previousFocus = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null
    retainedElements.forEach((element) => {
      element.setAttribute('aria-hidden', 'true')
      element.setAttribute('inert', '')
    })

    const focusableSelector =
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
    const focusRecoverySurface = () => {
      const first = overlayElement.querySelector<HTMLElement>(focusableSelector)
      ;(first ?? overlayElement).focus()
    }
    focusRecoverySurface()

    const containFocus = (event: KeyboardEvent) => {
      if (event.key !== 'Tab') return
      const focusable = [...overlayElement.querySelectorAll<HTMLElement>(focusableSelector)]
      if (focusable.length === 0) {
        event.preventDefault()
        overlayElement.focus()
        return
      }
      const first = focusable[0]!
      const last = focusable[focusable.length - 1]!
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    overlayElement.addEventListener('keydown', containFocus)

    return () => {
      overlayElement.removeEventListener('keydown', containFocus)
      retainedElements.forEach((element, index) => {
        const previousValue = previousValues[index]!
        if (previousValue.ariaHidden === null) element.removeAttribute('aria-hidden')
        else element.setAttribute('aria-hidden', previousValue.ariaHidden)
        if (previousValue.inert === null) element.removeAttribute('inert')
        else element.setAttribute('inert', previousValue.inert)
      })
      if (previousFocus?.isConnected) previousFocus.focus()
    }
  }, [interrupted])

  return (
    <div className="contents" ref={boundaryRef}>
      <div className="contents" data-auth-recovery-content="true">{children}</div>
      {overlay}
    </div>
  )
}

function AppRoutes({
  authenticated,
  authenticatedContent,
  continuationError = false,
  createContinuationScope,
  csrfToken,
  interruption,
  onAcknowledged = () => undefined,
  onAuthenticated = () => undefined,
  onAuthenticationRequired,
  onReauthenticated = () => undefined,
  onRetryContinuations = async () => undefined,
}: AppRoutesProps) {
  const [locationKey, setLocationKey] = useState(
    `${window.location.pathname}${window.location.search}`,
  )
  const scopeEffectVersions = useRef(new WeakMap<ContinuationScope, number>())

  useEffect(() => {
    const update = () => setLocationKey(`${window.location.pathname}${window.location.search}`)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  const location = new URL(locationKey, window.location.origin)
  const { pathname } = location
  const routeContinuationScope = useMemo<ContinuationScope>(() => {
    if (createContinuationScope) return createContinuationScope()

    return {
      beginReauthentication: (intent, resume) => {
        onAuthenticationRequired?.(intent, resume)
        return () => undefined
      },
      dispose: () => undefined,
    }
  }, [createContinuationScope, onAuthenticationRequired, pathname])

  useEffect(() => {
    const versions = scopeEffectVersions.current
    const version = (versions.get(routeContinuationScope) ?? 0) + 1
    versions.set(routeContinuationScope, version)

    return () => {
      queueMicrotask(() => {
        if (versions.get(routeContinuationScope) === version) {
          routeContinuationScope.dispose()
        }
      })
    }
  }, [routeContinuationScope])

  const scopedAuthenticationRequired = routeContinuationScope.beginReauthentication
  const renderAuthenticatedContent = (routeContent?: WorkspaceLayoutContent) =>
    typeof authenticatedContent === 'function'
      ? authenticatedContent(scopedAuthenticationRequired, routeContent)
      : routeContent?.mainContent ?? authenticatedContent
  const routedAuthenticatedContent = renderAuthenticatedContent()

  const handleAuthenticated = (nextCsrfToken: string) => {
    onAuthenticated(nextCsrfToken)
    navigate('/')
  }
  const setupToken = routeToken(pathname, '/setup/') ??
    (pathname === '/setup' ? location.searchParams.get('token') : null)
  if (setupToken) return <SetupForm token={setupToken} />

  const recoveryToken = routeToken(pathname, '/recover/') ??
    (pathname === '/recover' ? location.searchParams.get('token') : null)
  if (recoveryToken) {
    return <RecoveryReset onAuthenticated={handleAuthenticated} token={recoveryToken} />
  }

  const withInterruption = (content: ReactNode) => {
    const finish = (nextCsrfToken: string) => {
      if (interruption) onReauthenticated(interruption, nextCsrfToken)
    }

    return (
      <InterruptionBoundary
        interrupted={Boolean(interruption && csrfToken)}
        overlay={interruption && csrfToken ? (
          <div
            aria-label="Authentication recovery"
            aria-modal="true"
            className="fixed inset-0 z-50 overflow-y-auto bg-background/95 px-4 py-16"
            data-auth-recovery-overlay="true"
            role="dialog"
            tabIndex={-1}
          >
            <div className="mx-auto max-w-2xl">
              {continuationError ? (
              <section
                aria-labelledby="continuation-error-heading"
                className="rounded-lg border border-border bg-card p-6"
                role="alert"
              >
                <h2 className="text-xl font-semibold" id="continuation-error-heading">
                  Recovery needs another try
                </h2>
                <p className="mt-2">
                  Couldn’t finish restoring everything. Your work is still here.
                </p>
                <Button
                  className="mt-5 min-h-11"
                  onClick={() => void onRetryContinuations()}
                  type="button"
                  variant="outline"
                >
                  Try continuing again
                </Button>
              </section>
              ) : interruption.authentication === 'sign_in' ? (
                <LoginForm continuation onAuthenticated={finish} />
              ) : (
                <Reauthenticate
                  csrfToken={csrfToken}
                  interruption={interruption}
                  onAuthenticated={onReauthenticated}
                />
              )}
            </div>
          </div>
        ) : null}
      >
        {content}
      </InterruptionBoundary>
    )
  }

  if (!authenticated || pathname === '/login') {
    if (authenticated) {
      return (
        <main className="p-6" id="main-content">
          <h1 className="text-[1.75rem] font-semibold">Already signed in</h1>
          <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/">
            Return to Keepling
          </a>
        </main>
      )
    }
    return <LoginForm onAuthenticated={handleAuthenticated} />
  }

  const listLayout = (view: 'completed' | 'inbox' | 'today' | 'upcoming') => ({
    detailContent: (
      <section aria-labelledby="detail-heading" className="p-8">
        <h2 className="text-xl font-semibold" id="detail-heading">Task details</h2>
        <p className="mt-2 max-w-xl text-muted-foreground">
          Select a task to review its accepted details.
        </p>
      </section>
    ),
    listContent: <TaskList csrfToken={csrfToken} embedded key={view} onAuthenticationRequired={scopedAuthenticationRequired} view={view} />,
  })

  if (pathname === '/today' && csrfToken) return withInterruption(renderAuthenticatedContent(listLayout('today')))
  if (pathname === '/upcoming' && csrfToken) return withInterruption(renderAuthenticatedContent(listLayout('upcoming')))
  if (pathname === '/completed' && csrfToken) return withInterruption(renderAuthenticatedContent(listLayout('completed')))
  if (pathname === '/inbox' && csrfToken) return withInterruption(renderAuthenticatedContent(listLayout('inbox')))
  if (pathname === '/trash' && csrfToken) {
    return withInterruption(
      renderAuthenticatedContent({
        mainContent: <TrashList
          csrfToken={csrfToken}
          onAuthenticationRequired={scopedAuthenticationRequired}
        />,
      }),
    )
  }

  if (pathname === '/projects' && csrfToken) {
    return withInterruption(
      renderAuthenticatedContent({
        mainContent: <OrganizationManager
          csrfToken={csrfToken}
          kind="project"
          onAuthenticationRequired={scopedAuthenticationRequired}
        />,
      }),
    )
  }

  if (pathname === '/tags' && csrfToken) {
    return withInterruption(
      renderAuthenticatedContent({
        mainContent: <OrganizationManager
          csrfToken={csrfToken}
          kind="tag"
          onAuthenticationRequired={scopedAuthenticationRequired}
        />,
      }),
    )
  }

  const assignmentMatch = pathname.match(/^\/tasks\/([^/]+)\/organizations$/)
  const assignmentTaskId = decodeRoutePart(assignmentMatch?.[1])
  if (assignmentTaskId && csrfToken) {
    return withInterruption(
      renderAuthenticatedContent({
        mainContent: <OrganizationFields
          csrfToken={csrfToken}
          onAuthenticationRequired={scopedAuthenticationRequired}
          taskId={assignmentTaskId}
        />,
      }),
    )
  }

  const taskId = routeToken(pathname, '/tasks/')
  if (taskId && csrfToken) {
    const historyView = (window.history.state as { keeplingListView?: unknown } | null)?.keeplingListView
    const returnView = ['completed', 'inbox', 'today', 'upcoming'].includes(String(historyView))
      ? historyView as 'completed' | 'inbox' | 'today' | 'upcoming'
      : 'inbox'

    return withInterruption(
      renderAuthenticatedContent({
        detailContent: <div className="min-h-full bg-card" key={taskId}>
          <TaskEditor
            csrfToken={csrfToken}
            embedded
            onAcknowledged={onAcknowledged}
            onAuthenticationRequired={scopedAuthenticationRequired}
            onNavigate={navigate}
            returnViewLabel={{ completed: 'Completed', inbox: 'Inbox', today: 'Today', upcoming: 'Upcoming' }[returnView]}
            taskId={taskId}
          />
          <ActivityList
            onAuthenticationRequired={scopedAuthenticationRequired}
            taskId={taskId}
          />
        </div>,
        detailSelected: true,
        listContent: <TaskList
          csrfToken={csrfToken}
          embedded
          key={returnView}
          onAuthenticationRequired={scopedAuthenticationRequired}
          view={returnView}
        />,
      }),
    )
  }

  return withInterruption(routedAuthenticatedContent ?? (
    <main className="p-6" id="main-content">
      <h1 className="text-[1.75rem] font-semibold">Keepling</h1>
    </main>
  ))
}

export default AppRoutes
