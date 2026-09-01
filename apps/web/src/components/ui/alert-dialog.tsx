import { AlertDialog as BaseAlertDialog } from '@base-ui/react/alert-dialog'
import { type ReactNode, type RefObject } from 'react'

import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type AlertDialogAction = {
  disabled?: boolean
  label: string
  onClick: () => void
  ref?: RefObject<HTMLButtonElement | null>
  variant?: 'default' | 'destructive' | 'outline'
}

type AlertDialogProps = {
  actions: AlertDialogAction[]
  description: ReactNode
  finalFocus?: RefObject<HTMLElement | null>
  initialFocus?: RefObject<HTMLElement | null>
  onCancel: () => void
  open: boolean
  title: string
}

function AlertDialog({
  actions,
  description,
  finalFocus,
  initialFocus,
  onCancel,
  open,
  title,
}: AlertDialogProps) {
  return (
    <BaseAlertDialog.Root
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onCancel()
      }}
      open={open}
    >
      <BaseAlertDialog.Portal>
        <BaseAlertDialog.Backdrop className="fixed inset-0 z-40 bg-foreground/30 transition-opacity duration-[var(--keepling-motion-overlay)] data-[ending-style]:opacity-0 data-[starting-style]:opacity-0 motion-reduce:transition-none" />
        <BaseAlertDialog.Viewport className="fixed inset-0 z-50 grid place-items-center overflow-y-auto p-4">
          <BaseAlertDialog.Popup
            className="w-full max-w-md rounded-xl border border-border bg-background p-6 shadow-lg transition-opacity duration-[var(--keepling-motion-overlay)] data-[ending-style]:opacity-0 data-[starting-style]:opacity-0 motion-reduce:transition-none"
            finalFocus={finalFocus}
            initialFocus={initialFocus}
          >
            <BaseAlertDialog.Title className="text-xl font-semibold">
              {title}
            </BaseAlertDialog.Title>
            <BaseAlertDialog.Description className="mt-2 text-muted-foreground">
              {description}
            </BaseAlertDialog.Description>
            <div className="mt-6 flex flex-wrap gap-4">
              {actions.map((action) => (
                <BaseAlertDialog.Close
                  className={cn(
                    buttonVariants({ variant: action.variant ?? 'default' }),
                    'min-h-[var(--keepling-layout-target)] px-4',
                  )}
                  disabled={action.disabled}
                  key={action.label}
                  onClick={action.onClick}
                  ref={action.ref}
                >
                  {action.label}
                </BaseAlertDialog.Close>
              ))}
            </div>
          </BaseAlertDialog.Popup>
        </BaseAlertDialog.Viewport>
      </BaseAlertDialog.Portal>
    </BaseAlertDialog.Root>
  )
}

export { AlertDialog, type AlertDialogAction }
