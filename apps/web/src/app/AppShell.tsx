import {
  useEffect,
  useRef,
  useState,
  type MouseEvent,
  type ReactNode,
} from 'react'

import type { UndoAvailability, UndoResult } from '@/api/keepling'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryStrip from '@/features/recovery/RecoveryStrip'
import SessionList from '@/features/sessions/SessionList'

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
  onSaveDirtyWork?: () => void
}

const navigationItems = [
  ['/', 'Inbox'],
  ['/today', 'Today'],
  ['/upcoming', 'Upcoming'],
  ['/completed', 'Completed'],
  ['/projects', 'Projects'],
  ['/tags', 'Tags'],
  ['/trash', 'Trash'],
  ['/settings/sessions', 'Sessions'],
] as const

function AppShell({
  csrfToken,
  hasDirtyWork = false,
  inboxContent,
  onDiscardDirtyWork = () => undefined,
  onAuthenticationRequired,
  onLoggedOut,
  onSaveDirtyWork = () => undefined,
}: AppShellProps) {
  const [pathname, setPathname] = useState(window.location.pathname)
  const [latestUndo, setLatestUndo] = useState<UndoAvailability | null>(null)
  const [pendingHref, setPendingHref] = useState<string | null>(null)
  const stayButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const update = () => setPathname(window.location.pathname)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  useEffect(() => {
    if (pendingHref) stayButtonRef.current?.focus()
  }, [pendingHref])

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
    setPendingHref(href)
  }

  const finishNavigation = (disposition: 'discard' | 'save') => {
    if (!pendingHref) return
    if (disposition === 'save') onSaveDirtyWork()
    else onDiscardDirtyWork()
    const href = pendingHref
    setPendingHref(null)
    navigate(href)
  }

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
      <div className="keepling-workspace min-h-screen lg:grid lg:grid-cols-[var(--keepling-layout-nav)_minmax(0,1fr)]">
        <aside className="border-r border-border bg-card p-6">
          <p className="hidden text-xl font-semibold lg:block">Keepling</p>
          <nav aria-label="Keepling" className="mt-4 lg:mt-8">
            {navigationItems.map(([href, label], index) => (
              <a
                aria-current={isCurrent(href) ? 'page' : undefined}
                className={`${index === 0 ? '' : 'mt-2 ' }flex min-h-[var(--keepling-layout-target)] min-w-0 items-center truncate border-l-2 pl-3 text-[length:var(--keepling-type-label)] font-semibold ${isCurrent(href) ? 'border-primary' : 'border-transparent'}`}
                href={href}
                key={href}
                onClick={(event) => guardNavigation(event, href)}
                title={label}
              >
                {label}
              </a>
            ))}
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
                onAuthenticationRequired={onAuthenticationRequired}
                onLoggedOut={onLoggedOut}
              />
            </section>
          </div>
        </main>
      </div>
      {recovery}
      <div aria-atomic="true" aria-live="polite" className="sr-only" role="status" />
      {pendingHref ? (
        <div
          aria-labelledby="dirty-navigation-title"
          aria-modal="true"
          className="fixed inset-0 z-50 grid place-items-center bg-background/80 p-4"
          role="alertdialog"
        >
          <div className="w-full max-w-md rounded-lg border border-border bg-card p-6 shadow-lg">
            <h2 className="text-[length:var(--keepling-type-heading)] font-semibold" id="dirty-navigation-title">
              Unsaved changes
            </h2>
            <p className="mt-2">Save changes before leaving this page?</p>
            <div className="mt-6 flex flex-wrap justify-end gap-2">
              <button
                className="min-h-[var(--keepling-layout-target)] rounded-lg border border-border px-4 font-semibold"
                onClick={() => finishNavigation('save')}
                type="button"
              >
                Save changes
              </button>
              <button
                className="min-h-[var(--keepling-layout-target)] rounded-lg bg-destructive px-4 font-semibold text-white"
                onClick={() => finishNavigation('discard')}
                type="button"
              >
                Discard changes
              </button>
              <button
                className="min-h-[var(--keepling-layout-target)] rounded-lg border border-border px-4 font-semibold"
                onClick={() => setPendingHref(null)}
                ref={stayButtonRef}
                type="button"
              >
                Stay here
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}

export default AppShell
