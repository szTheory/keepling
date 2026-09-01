import { useEffect, useState } from 'react'

import {
  KeeplingApiError,
  getInbox,
  type BrowserTask,
  type CaptureAcknowledgement,
} from '@/api/keepling'
import { AuthProvider, useAuth } from '@/app/AuthProvider'
import type { BeginReauthentication } from '@/app/AuthProvider'
import AppShell from '@/app/AppShell'
import AppRoutes from '@/app/routes'
import QuickCapture from '@/features/capture/QuickCapture'

type AppState =
  | { kind: 'loading' }
  | { kind: 'error' }
  | { kind: 'ready'; tasks: readonly BrowserTask[] }

function InboxWorkspace({
  onAuthenticationRequired,
}: {
  onAuthenticationRequired: BeginReauthentication
}) {
  const auth = useAuth()
  const [state, setState] = useState<AppState>({ kind: 'loading' })
  const [announcement, setAnnouncement] = useState('')

  useEffect(() => {
    let active = true

    void getInbox()
      .then((tasks) => {
        if (active) {
          setState({ kind: 'ready', tasks })
        }
      })
      .catch((error: unknown) => {
        if (!active) return

        if (error instanceof KeeplingApiError && error.problem.code === 'authentication_required') {
          onAuthenticationRequired(
            { authentication: 'sign_in', kind: 'read', mutationId: 'inbox:list' },
            async () => {
              setState({ kind: 'ready', tasks: await getInbox() })
            },
          )
        } else {
          setState({ kind: 'error' })
        }
      })

    return () => {
      active = false
    }
  }, [onAuthenticationRequired])

  useEffect(() => {
    const updateTask = (event: Event) => {
      const acknowledgement = (event as CustomEvent<CaptureAcknowledgement>).detail
      setState((current) => {
        if (current.kind !== 'ready') return current
        const withoutCurrent = current.tasks.filter((task) => task.id !== acknowledgement.taskId)

        return acknowledgement.snapshot.inboxState === 'inbox'
          ? { ...current, tasks: [acknowledgement.snapshot, ...withoutCurrent] }
          : { ...current, tasks: withoutCurrent }
      })
    }

    window.addEventListener('keepling:task-acknowledged', updateTask)
    return () => window.removeEventListener('keepling:task-acknowledged', updateTask)
  }, [])

  const handleCaptured = (acknowledgement: CaptureAcknowledgement) => {
    setState((current) => {
      if (current.kind !== 'ready') return current

      const withoutCurrent = current.tasks.filter((task) => task.id !== acknowledgement.taskId)

      return {
        ...current,
        tasks: [acknowledgement.snapshot, ...withoutCurrent],
      }
    })
    setAnnouncement('Task added to Inbox.')
  }

  return (
    <>
      <div className="keepling-inbox-workspace min-h-screen">
        <main className="min-w-0 bg-background" id="main-content" tabIndex={-1}>
          <div className="border-b border-border px-6 py-8">
            <h1 className="text-[1.75rem] font-semibold leading-[1.2]">Inbox</h1>
            <p className="mt-2 text-muted-foreground">
              Captured tasks stay here until you deliberately move them out.
            </p>
          </div>

          {state.kind === 'ready' && auth.state.kind === 'authenticated' ? (
            <QuickCapture
              csrfToken={auth.state.csrfToken}
              onAuthenticationRequired={onAuthenticationRequired}
              onCaptured={handleCaptured}
            />
          ) : null}

          <section aria-labelledby="inbox-list-heading" className="p-6">
            <h2 className="text-xl font-semibold" id="inbox-list-heading">
              Tasks
            </h2>

            {state.kind === 'loading' ? (
              <p className="mt-4" role="status">
                Loading Inbox…
              </p>
            ) : null}

            {state.kind === 'error' ? (
              <div className="mt-4 rounded-lg border border-border bg-card p-4" role="alert">
                <p>Couldn’t load Inbox. Your tasks weren’t changed.</p>
                <button
                  className="mt-3 min-h-11 font-semibold text-primary underline"
                  onClick={() => window.location.reload()}
                  type="button"
                >
                  Retry loading Inbox
                </button>
              </div>
            ) : null}

            {state.kind === 'ready' && state.tasks.length === 0 ? (
              <div className="mt-8 max-w-md">
                <h3 className="text-xl font-semibold">Inbox is clear</h3>
                <p className="mt-2 text-muted-foreground">
                  Captured tasks appear here until you move them out. Add task.
                </p>
              </div>
            ) : null}

            {state.kind === 'ready' && state.tasks.length > 0 ? (
              <ul className="mt-4 divide-y divide-border">
                {state.tasks.map((task) => (
                  <li className="flex min-h-[3.25rem] items-center py-3" key={task.id}>
                    <a
                      className="break-words text-base leading-6 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                      href={`/tasks/${encodeURIComponent(task.id)}`}
                    >
                      {task.title}
                    </a>
                  </li>
                ))}
              </ul>
            ) : null}
          </section>
        </main>

        <section
          aria-labelledby="detail-heading"
          className="keepling-detail-placeholder min-w-0 border-l border-border bg-card p-8"
        >
          <h2 className="text-xl font-semibold" id="detail-heading">
            Task details
          </h2>
          <p className="mt-2 max-w-xl text-muted-foreground">
            Select a task to review its accepted details.
          </p>
        </section>
      </div>

      <div aria-atomic="true" aria-live="polite" className="sr-only">
        {announcement}
      </div>
    </>
  )
}

function RoutedApp() {
  const auth = useAuth()

  if (auth.state.kind === 'loading') {
    return (
      <main className="p-6" id="main-content">
        <p role="status">Loading Keepling…</p>
      </main>
    )
  }

  if (auth.state.kind === 'error') {
    return (
      <main className="p-6" id="main-content">
        <div role="alert">
          <p>Couldn’t check your session. Nothing was changed.</p>
          <button className="mt-3 min-h-11 font-semibold text-primary underline" onClick={() => window.location.reload()} type="button">
            Retry checking session
          </button>
        </div>
      </main>
    )
  }

  const authenticatedState = auth.state.kind === 'authenticated' ? auth.state : null
  const handleLoggedOut = () => {
    auth.clearAuthentication()
    window.location.assign('/login')
  }
  const handleTaskAcknowledged = (acknowledgement: CaptureAcknowledgement) => {
    window.dispatchEvent(
      new CustomEvent<CaptureAcknowledgement>('keepling:task-acknowledged', {
        detail: acknowledgement,
      }),
    )
  }

  return (
    <AppRoutes
      authenticated={authenticatedState !== null}
      authenticatedContent={
        authenticatedState
          ? (onAuthenticationRequired, routeContent) => (
              <AppShell
                csrfToken={authenticatedState.csrfToken}
                inboxContent={(
                  <InboxWorkspace onAuthenticationRequired={onAuthenticationRequired} />
                )}
                onAuthenticationRequired={onAuthenticationRequired}
                onLoggedOut={handleLoggedOut}
                routeContent={routeContent}
              />
            )
          : undefined
      }
      authenticatedContentOwnsRoutes
      createContinuationScope={auth.createContinuationScope}
      csrfToken={authenticatedState?.csrfToken}
      continuationError={auth.continuationError}
      interruption={auth.interruption}
      onAcknowledged={handleTaskAcknowledged}
      onAuthenticated={auth.acceptAuthentication}
      onReauthenticated={auth.completeReauthentication}
      onRetryContinuations={auth.retryContinuations}
    />
  )
}

function App() {
  return (
    <AuthProvider>
      <RoutedApp />
    </AuthProvider>
  )
}

export default App
