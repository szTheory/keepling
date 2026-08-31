import { useEffect, useRef, useState, type FormEvent } from 'react'

import { KeeplingApiError, reauthenticate } from '@/api/keepling'
import { Button } from '@/components/ui/button'

type InterruptedIntent =
  | { kind: 'not-submitted'; mutationId: string }
  | { kind: 'submitted-unknown'; mutationId: string }

type ReauthenticateProps = {
  csrfToken: string
  interruption: InterruptedIntent
  onAuthenticated: (interruption: InterruptedIntent, csrfToken: string) => void
}

function Reauthenticate({ csrfToken, interruption, onAuthenticated }: ReauthenticateProps) {
  const passwordRef = useRef<HTMLInputElement>(null)
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [state, setState] = useState<'idle' | 'submitting' | 'failed' | 'error'>('idle')

  useEffect(() => {
    passwordRef.current?.focus()
  }, [])

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (state === 'submitting') return
    setState('submitting')
    try {
      const transition = await reauthenticate(password, csrfToken)
      onAuthenticated(interruption, transition.csrfToken)
    } catch (error) {
      setState(
        error instanceof KeeplingApiError && error.problem.code === 'authentication_failed'
          ? 'failed'
          : 'error',
      )
      queueMicrotask(() => passwordRef.current?.focus())
    }
  }

  return (
    <section
      aria-labelledby="reauthentication-heading"
      className="rounded-lg border border-border bg-card p-6"
      role="alert"
    >
      <h2 className="text-xl font-semibold" id="reauthentication-heading">
        Authentication required
      </h2>
      <p className="mt-2">Sign in again to finish saving. Your changes are still here.</p>
      <p className="mt-2 text-sm text-muted-foreground">
        {interruption.kind === 'submitted-unknown'
          ? 'The submitted change will be checked with its original identity.'
          : 'The change has not been submitted yet.'}
      </p>
      <form className="mt-5 space-y-4" onSubmit={(event) => void submit(event)}>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor="reauthenticate-password">
            Password
          </label>
          <div className="flex gap-2">
            <input
              autoComplete="current-password"
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="reauthenticate-password"
              onChange={(event) => setPassword(event.target.value)}
              ref={passwordRef}
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
        {state === 'failed' ? <p role="alert">Password not accepted. Check it and try again.</p> : null}
        {state === 'error' ? (
          <p role="alert">Couldn’t refresh authentication. Your changes are still here.</p>
        ) : null}
        <Button className="min-h-11 px-4" disabled={state === 'submitting'} type="submit">
          {state === 'submitting' ? 'Signing in…' : 'Sign in and continue'}
        </Button>
      </form>
    </section>
  )
}

export { type InterruptedIntent }
export default Reauthenticate
