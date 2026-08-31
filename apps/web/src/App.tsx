import { useEffect, useState } from 'react'

import {
  KeeplingApiError,
  getInbox,
  getSession,
  type BrowserTask,
  type CaptureAcknowledgement,
} from '@/api/keepling'
import QuickCapture from '@/features/capture/QuickCapture'

type AppState =
  | { kind: 'loading' }
  | { kind: 'authentication-required' }
  | { kind: 'error' }
  | { csrfToken: string; kind: 'ready'; tasks: readonly BrowserTask[] }

function App() {
  const [state, setState] = useState<AppState>({ kind: 'loading' })
  const [announcement, setAnnouncement] = useState('')

  useEffect(() => {
    let active = true

    void Promise.all([getSession(), getInbox()])
      .then(([session, tasks]) => {
        if (active) {
          setState({ csrfToken: session.csrf_token, kind: 'ready', tasks })
        }
      })
      .catch((error: unknown) => {
        if (!active) return

        if (error instanceof KeeplingApiError && error.problem.code === 'authentication_required') {
          setState({ kind: 'authentication-required' })
        } else {
          setState({ kind: 'error' })
        }
      })

    return () => {
      active = false
    }
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
      <a
        className="fixed left-4 top-0 z-50 -translate-y-full rounded-b-lg bg-primary px-4 py-3 text-primary-foreground focus:translate-y-0"
        href="#main-content"
      >
        Skip to main content
      </a>

      <header className="flex min-h-16 items-center justify-between border-b border-border bg-card px-4 lg:hidden">
        <p className="text-xl font-semibold">Keepling</p>
        <a className="font-semibold text-primary underline-offset-4 hover:underline" href="#quick-capture">
          Add task
        </a>
      </header>

      <div className="min-h-screen lg:grid lg:grid-cols-[14rem_minmax(22.5rem,27.5rem)_minmax(30rem,1fr)]">
        <aside className="hidden border-r border-border bg-card p-6 lg:block">
          <p className="text-xl font-semibold">Keepling</p>
          <a
            className="mt-8 flex min-h-11 items-center justify-center rounded-lg bg-primary px-4 text-sm font-semibold text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            href="#quick-capture"
          >
            Add task
          </a>
          <nav aria-label="Primary" className="mt-8">
            <a
              aria-current="page"
              className="flex min-h-11 items-center border-l-2 border-primary pl-3 font-semibold"
              href="/"
            >
              Inbox
            </a>
          </nav>
        </aside>

        <main className="min-w-0 bg-background" id="main-content" tabIndex={-1}>
          <div className="border-b border-border px-6 py-8">
            <h1 className="text-[1.75rem] font-semibold leading-[1.2]">Inbox</h1>
            <p className="mt-2 text-muted-foreground">
              Captured tasks stay here until you deliberately move them out.
            </p>
          </div>

          {state.kind === 'ready' ? (
            <QuickCapture csrfToken={state.csrfToken} onCaptured={handleCaptured} />
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

            {state.kind === 'authentication-required' ? (
              <div className="mt-4 rounded-lg border border-border bg-card p-4" role="alert">
                <p>Sign in again to finish saving. Your changes are still here.</p>
              </div>
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
                    <span className="break-words text-base leading-6">{task.title}</span>
                  </li>
                ))}
              </ul>
            ) : null}
          </section>
        </main>

        <section
          aria-labelledby="detail-heading"
          className="hidden min-w-0 border-l border-border bg-card p-8 lg:block"
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

export default App
