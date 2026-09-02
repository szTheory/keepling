import { useRef, type MouseEvent, type ReactNode } from 'react'

import { Drawer } from '@/components/ui/drawer'
import type { ClientFacade } from '../../../../packages/web-ui/src/ClientFacade'
import Workspace from '../../../../packages/web-ui/src/workspace/Workspace'

const navigationItems = [
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
  /**
   * The browser-owned ClientFacade adapter (D-26/D-27). Threaded through so
   * the shared `packages/web-ui` Workspace presentation can eventually own
   * the Inbox capture/list/detail slice; only rendered when
   * `useSharedWorkspace` is explicitly set so existing routed content is
   * unaffected.
   */
  clientFacade?: ClientFacade
  detailContent?: ReactNode
  detailSelected?: boolean
  listContent?: ReactNode
  onNavigate?: (event: MouseEvent<HTMLAnchorElement>, href: string) => void
  pathname: string
  useSharedWorkspace?: boolean
}

export type WorkspaceLayoutContent = {
  detailContent?: ReactNode
  detailSelected?: boolean
  listContent?: ReactNode
  mainContent?: ReactNode
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
            className={`${index === 0 ? '' : 'mt-2 '}flex min-h-[var(--keepling-layout-target)] min-w-0 items-center truncate border-l-2 pl-4 text-[length:var(--keepling-type-label)] font-semibold ${current ? 'border-primary bg-accent' : 'border-transparent'}`}
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

function WorkspaceShell({
  children,
  clientFacade,
  detailContent,
  detailSelected = false,
  listContent,
  onNavigate,
  pathname,
  useSharedWorkspace = false,
}: WorkspaceShellProps) {
  const firstDrawerLinkRef = useRef<HTMLAnchorElement>(null)
  const sharedWorkspace =
    useSharedWorkspace && clientFacade !== undefined ? <Workspace facade={clientFacade} /> : null

  return (
    <>
      <a
        className="fixed left-4 top-0 z-[60] -translate-y-full rounded-b-lg bg-primary px-4 py-4 text-primary-foreground focus:translate-y-0 motion-reduce:transition-none"
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

      <div className="keepling-workspace-shell">
        <aside
          className="keepling-persistent-navigation border-r border-border bg-card p-6"
          data-workspace-region="navigation"
        >
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
        <div className="keepling-workspace-content min-w-0">
          {listContent ? (
            <main
              className={`keepling-workspace-panes${detailSelected ? ' has-selected-detail' : ''}`}
              id="main-content"
              tabIndex={-1}
            >
              <div className="keepling-list-region min-w-0" data-workspace-region="list">
                {listContent}
              </div>
              <div className="keepling-detail-region min-w-0" data-workspace-region="detail">
                {detailContent}
              </div>
            </main>
          ) : (sharedWorkspace ?? children)}
        </div>
      </div>
    </>
  )
}

export default WorkspaceShell
