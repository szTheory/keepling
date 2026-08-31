import { useState, type FormEvent } from 'react'

import { KeeplingApiError, recoverAccount } from '@/api/keepling'
import { Button } from '@/components/ui/button'
import { AuthPage } from '@/features/auth/SetupForm'

type RecoveryResetProps = {
  onAuthenticated: (csrfToken: string) => void
  token: string
}

function RecoveryReset({ onAuthenticated, token }: RecoveryResetProps) {
  const [password, setPassword] = useState('')
  const [label, setLabel] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [state, setState] = useState<'idle' | 'submitting' | 'complete' | 'unavailable' | 'error'>('idle')

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (state === 'submitting') return
    setState('submitting')
    try {
      const transition = await recoverAccount(token, password, label.trim())
      setState('complete')
      onAuthenticated(transition.csrfToken)
    } catch (error) {
      if (error instanceof KeeplingApiError && error.problem.code === 'recovery_unavailable') {
        setState('unavailable')
      } else {
        setState('error')
      }
    }
  }

  if (state === 'complete') {
    return (
      <AuthPage title="Password changed">
        <p role="status">Password changed. This recovery link has been used.</p>
      </AuthPage>
    )
  }

  if (state === 'unavailable') {
    return (
      <AuthPage title="Recovery link unavailable">
        <p role="alert">This recovery link is invalid, expired, or already used.</p>
        <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/login">
          Return to sign in
        </a>
      </AuthPage>
    )
  }

  return (
    <AuthPage title="Set a new password">
      <p className="mt-2 text-muted-foreground">This operator-issued link works once.</p>
      <form className="mt-8 space-y-5" onSubmit={(event) => void submit(event)}>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor="recovery-password">
            New password
          </label>
          <div className="flex gap-2">
            <input
              autoComplete="new-password"
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="recovery-password"
              onChange={(event) => setPassword(event.target.value)}
              required
              type={showPassword ? 'text' : 'password'}
              value={password}
            />
            <Button
              aria-label={showPassword ? 'Hide new password' : 'Show new password'}
              className="min-h-11"
              onClick={() => setShowPassword((visible) => !visible)}
              type="button"
              variant="outline"
            >
              {showPassword ? 'Hide' : 'Show'}
            </Button>
          </div>
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor="recovery-session-label">
            Session label
          </label>
          <input
            className="min-h-11 w-full rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            id="recovery-session-label"
            maxLength={200}
            onChange={(event) => setLabel(event.target.value)}
            required
            value={label}
          />
        </div>
        {state === 'error' ? (
          <p role="alert">Couldn’t complete recovery. The link may still be usable. Try again.</p>
        ) : null}
        <Button className="min-h-11 px-4" disabled={state === 'submitting'} type="submit">
          {state === 'submitting' ? 'Setting password…' : 'Set new password'}
        </Button>
      </form>
    </AuthPage>
  )
}

export default RecoveryReset
