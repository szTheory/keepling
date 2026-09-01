import { useRef, type MouseEvent, type ReactNode } from 'react'

import { Drawer } from '@/components/ui/drawer'

export const navigationItems = [
  ['/', 'Inbox'],
  ['/today', 'Today'],
  ['/upcoming', 'Upcoming'],
  ['/projects', 'Projects'],
  ['/tags', 'Tags'],
  ['/completed', 'Completed'],
  ['/trash', 'Trash'],
  ['/settings/sessions', 'Sessions'],
] as const

type WorkspaceShellProps = {
  children: ReactNode
  onNavigate?: (event: MouseEvent<HTMLAnchorElement>, href: string) => void
  pathname: string
}

const isCurrentRoute = (pathname: string, href: string) =>
  href === '/' ? pathname === '/' || pathname === '/inbox' : pathname === href

function NavigationLinks({
  firstLinkRef,
  label,
  onNavigate,
  pathname,
}: {
  firstLinkRef?: React.RefObject<HTMLAnchorElement | null>
  label: string
  onNavigate?: WorkspaceShellProps['onNavigate']
  pathname: string
}) {
  return (
    <nav aria-label={label}>
      {navigationItems.map(([href, itemLabel], index) => {
        const current = isCurrentRoute(pathname, href)
        return (
          <a
            aria-current={current ? 'page' : undefined}
            className={`${index === 0 ? '' : 'mt-2 '}flex min-h-[var(--keepling-layout-target)] min-w-0 items-center truncate border-l-2 pl-3 text-[length:var(--keepling-type-label)] font-semibold ${current ? 'border-primary bg-accent' : 'border-transparent'}`}
            href={href}
            key={href}
            onClick={(event) => onNavigate?.(event, href)}
            ref={index === 0 ? firstLinkRef : undefined}
            title={itemLabel}
          >
            {itemLabel}
          </a>
        )
      })}
    </nav>
  )
}

function WorkspaceShell({ children, onNavigate, pathname }: WorkspaceShellProps) {
  const firstDrawerLinkRef = useRef<HTMLAnchorElement>(null)

  return (
    <>
      <a
        className="fixed left-4 top-0 z-[60] -translate-y-full rounded-b-lg bg-primary px-4 py-3 text-primary-foreground focus:translate-y-0 motion-reduce:transition-none"
        href="#main-content"
      >
        Skip to main content
      </a>

      <header className="keepling-compact-header min-h-16 items-center justify-between border-b border-border bg-card px-4">
        <div className="flex items-center gap-4">
          <Drawer
            initialFocus={firstDrawerLinkRef}
            title="Navigation"
            triggerClassName="min-h-[var(--keepling-layout-target)] rounded-lg border border-border px-4 text-[length:var(--keepling-type-label)] font-semibold"
            triggerLabel="Open navigation"
          >
            <NavigationLinks
              firstLinkRef={firstDrawerLinkRef}
              label="Primary navigation"
              onNavigate={onNavigate}
              pathname={pathname}
            />
          </Drawer>
          <p className="text-[length:var(--keepling-type-heading)] font-semibold">Keepling</p>
        </div>
        <a
          className="flex min-h-[var(--keepling-layout-target)] items-center font-semibold text-primary underline-offset-4 hover:underline"
          href={pathname === '/' || pathname === '/inbox' ? '#quick-capture' : '/#quick-capture'}
        >
          Add task
        </a>
      </header>

      <div className="keepling-workspace-shell min-h-screen">
        <aside className="keepling-persistent-navigation border-r border-border bg-card p-6">
          <p className="text-[length:var(--keepling-type-heading)] font-semibold">Keepling</p>
          <a
            className="mt-8 flex min-h-[var(--keepling-layout-target)] items-center justify-center rounded-lg bg-primary px-4 text-[length:var(--keepling-type-label)] font-semibold text-primary-foreground"
            href={pathname === '/' || pathname === '/inbox' ? '#quick-capture' : '/#quick-capture'}
          >
            Add task
          </a>
          <div className="mt-8">
            <NavigationLinks label="Keepling" onNavigate={onNavigate} pathname={pathname} />
          </div>
        </aside>
        <div className="keepling-workspace-content min-w-0">{children}</div>
      </div>
    </>
  )
}

export default WorkspaceShell
