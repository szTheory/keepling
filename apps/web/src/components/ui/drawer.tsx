import { Drawer as BaseDrawer } from '@base-ui/react/drawer'
import { type ComponentProps, type ReactNode, type RefObject } from 'react'

type DrawerProps = {
  children: ReactNode
  description?: string
  initialFocus?: RefObject<HTMLElement | null>
  title: string
  triggerClassName?: string
  triggerLabel: string
}

function Drawer({
  children,
  description,
  initialFocus,
  title,
  triggerClassName,
  triggerLabel,
}: DrawerProps) {
  return (
    <BaseDrawer.Root modal swipeDirection="left">
      <BaseDrawer.Trigger className={triggerClassName}>{triggerLabel}</BaseDrawer.Trigger>
      <BaseDrawer.Portal>
        <BaseDrawer.Backdrop className="fixed inset-0 z-40 bg-background/80 transition-opacity duration-[var(--keepling-motion-overlay)] data-[ending-style]:opacity-0 data-[starting-style]:opacity-0 motion-reduce:transition-none" />
        <BaseDrawer.Viewport className="fixed inset-0 z-50 overflow-hidden pointer-events-none">
          <BaseDrawer.Popup
            className="pointer-events-auto absolute inset-y-0 left-0 flex w-[min(22rem,calc(100vw-var(--keepling-space-xl)))] max-w-full flex-col border-r border-border bg-card p-6 shadow-lg transition-transform duration-[var(--keepling-motion-overlay)] data-[ending-style]:-translate-x-full data-[starting-style]:-translate-x-full motion-reduce:transition-none"
            initialFocus={initialFocus}
          >
            <BaseDrawer.Content className="flex min-h-0 flex-1 flex-col">
              <BaseDrawer.Title className="text-[length:var(--keepling-type-heading)] font-semibold">
                {title}
              </BaseDrawer.Title>
              {description ? (
                <BaseDrawer.Description className="mt-2 text-muted-foreground">
                  {description}
                </BaseDrawer.Description>
              ) : null}
              <div className="mt-6 min-h-0 flex-1 overflow-y-auto">{children}</div>
              <BaseDrawer.Close className="mt-6 min-h-[var(--keepling-layout-target)] rounded-lg border border-border px-4 text-[length:var(--keepling-type-label)] font-semibold">
                Close navigation
              </BaseDrawer.Close>
            </BaseDrawer.Content>
          </BaseDrawer.Popup>
        </BaseDrawer.Viewport>
      </BaseDrawer.Portal>
    </BaseDrawer.Root>
  )
}

export type DrawerRootProps = ComponentProps<typeof BaseDrawer.Root>
export { Drawer }
