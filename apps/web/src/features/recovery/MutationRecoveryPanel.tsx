import { Button } from '@/components/ui/button'
import type { TaskSubmissionState } from '@/commands/submission'

type MutationRecoveryPanelProps = {
  onCheck: () => void
  onSignIn: () => void
  state: TaskSubmissionState | null
}

function MutationRecoveryPanel({ onCheck, onSignIn, state }: MutationRecoveryPanelProps) {
  if (state?.kind === 'unknown') {
    return (
      <div className="mt-6 rounded-lg border border-border p-4" role="status">
        <p>Checking whether your change was saved…</p>
        <Button className="mt-3" onClick={onCheck} variant="outline">
          Check again
        </Button>
      </div>
    )
  }

  if (state?.kind === 'authentication_required') {
    return (
      <div className="mt-6 rounded-lg border border-border p-4" role="alert">
        <p>Sign in again. Keepling will check whether your change was saved.</p>
        <Button className="mt-3" onClick={onSignIn} variant="outline">
          Sign in and continue
        </Button>
      </div>
    )
  }

  return null
}

export default MutationRecoveryPanel
