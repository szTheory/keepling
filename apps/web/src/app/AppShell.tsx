import { useEffect, useState, type ReactNode } from 'react'

import type { UndoAvailability, UndoResult } from '@/api/keepling'
import RecoveryStrip from '@/features/recovery/RecoveryStrip'
import SessionList from '@/features/sessions/SessionList'

type AppShellProps = {
  csrfToken: string
  hasDirtyWork?: boolean
  inboxContent?: ReactNode
  onLoggedOut: () => void
}

function AppShell({ csrfToken, hasDirtyWork = false, inboxContent, onLoggedOut }: AppShellProps) {
  const [pathname, setPathname] = useState(window.location.pathname)
  const [latestUndo, setLatestUndo] = useState<UndoAvailability | null>(null)

  useEffect(() => {
    const update = () => setPathname(window.location.pathname)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  useEffect(() => {
    const rememberLatest = (event: Event) => {
      setLatestUndo((event as CustomEvent<UndoAvailability>).detail)
    }

    window.addEventListener('keepling:undo-available', rememberLatest)
    return () => window.removeEventListener('keepling:undo-available', rememberLatest)
  }, [])

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
      onSettled={handleUndoSettled}
    />
  ) : null

  if (pathname !== '/settings/sessions' && inboxContent) {
    return (
      <>
        {inboxContent}
        {recovery}
      </>
    )
  }

  return (
    <>
      <a
        className="fixed left-4 top-0 z-50 -translate-y-full rounded-b-lg bg-primary px-4 py-3 text-primary-foreground focus:translate-y-0 motion-reduce:transition-none"
        href="#main-content"
      >
        Skip to main content
      </a>
      <header className="flex min-h-16 items-center border-b border-border bg-card px-4 lg:hidden">
        <p className="text-xl font-semibold">Keepling</p>
      </header>
      <div className="min-h-screen lg:grid lg:grid-cols-[14rem_minmax(0,1fr)]">
        <aside className="border-r border-border bg-card p-6">
          <p className="hidden text-xl font-semibold lg:block">Keepling</p>
          <nav aria-label="Keepling" className="mt-4 lg:mt-8">
            <a
              className="flex min-h-11 items-center border-l-2 border-transparent pl-3 font-semibold"
              href="/"
            >
              Inbox
            </a>
            {[
              ['/today', 'Today'],
              ['/upcoming', 'Upcoming'],
              ['/completed', 'Completed'],
            ].map(([href, label]) => (
              <a
                aria-current={pathname === href ? 'page' : undefined}
                className="mt-2 flex min-h-11 items-center border-l-2 border-transparent pl-3 font-semibold"
                href={href}
                key={href}
              >
                {label}
              </a>
            ))}
            <p className="mt-6 px-3 text-sm font-semibold text-muted-foreground">Settings</p>
            <a
              aria-current={pathname === '/settings/sessions' ? 'page' : undefined}
              className="mt-2 flex min-h-11 items-center border-l-2 border-primary pl-3 font-semibold"
              href="/settings/sessions"
            >
              Sessions
            </a>
          </nav>
        </aside>
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
                onLoggedOut={onLoggedOut}
              />
            </section>
          </div>
        </main>
      </div>
      {recovery}
    </>
  )
}

export default AppShell
