import { useState, type FormEvent } from 'react'

import { KeeplingApiError, login } from '@/api/keepling'
import { Button } from '@/components/ui/button'
import { AuthPage } from '@/features/auth/SetupForm'

type LoginFormProps = {
  continuation?: boolean
  onAuthenticated: (csrfToken: string) => void
}

function LoginForm({ continuation = false, onAuthenticated }: LoginFormProps) {
  const [password, setPassword] = useState('')
  const [label, setLabel] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [state, setState] = useState<'idle' | 'submitting' | 'failed' | 'error'>('idle')

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (state === 'submitting') return
    setState('submitting')
    try {
      const transition = await login(password, label.trim())
      onAuthenticated(transition.csrfToken)
    } catch (error) {
      setState(
        error instanceof KeeplingApiError && error.problem.code === 'authentication_failed'
          ? 'failed'
          : 'error',
      )
    }
  }

  return (
    <AuthPage title={continuation ? 'Sign in to continue' : 'Sign in'}>
      <p className="mt-2 text-muted-foreground">Sign in to your private Keepling account.</p>
      <form className="mt-8 space-y-5" onSubmit={(event) => void submit(event)}>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor="login-password">
            Password
          </label>
          <div className="flex gap-2">
            <input
              autoComplete="current-password"
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="login-password"
              onChange={(event) => setPassword(event.target.value)}
              required
              type={showPassword ? 'text' : 'password'}
              value={password}
            />
            <Button
              aria-label={showPassword ? 'Hide password' : 'Show password'}
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
          <label className="block text-sm font-semibold" htmlFor="login-session-label">
            Session label
          </label>
          <input
            autoComplete="off"
            className="min-h-11 w-full rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            id="login-session-label"
            maxLength={200}
            onChange={(event) => setLabel(event.target.value)}
            required
            value={label}
          />
          <p className="text-sm text-muted-foreground">Name this browser so you can recognize and revoke it later.</p>
        </div>

        {state === 'failed' ? <p role="alert">Password not accepted. Check it and try again.</p> : null}
        {state === 'error' ? (
          <p role="alert">Couldn’t sign in. Your password remains in this form so you can try again.</p>
        ) : null}
        <Button className="min-h-11 px-4" disabled={state === 'submitting'} type="submit">
          {state === 'submitting' ? 'Signing in…' : continuation ? 'Sign in and continue' : 'Sign in'}
        </Button>
      </form>
    </AuthPage>
  )
}

export default LoginForm
