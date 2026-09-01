import { useRef, useState, type FormEvent } from 'react'

import { completeSetup, KeeplingApiError } from '@/api/keepling'
import { Button } from '@/components/ui/button'

type SetupFormProps = {
  token: string
}

const isIanaTimezone = (value: string) => {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format()
    return value.includes('/') || value === 'UTC'
  } catch {
    return false
  }
}

function SetupForm({ token }: SetupFormProps) {
  const timezoneRef = useRef<HTMLInputElement>(null)
  const [password, setPassword] = useState('')
  const [timezone, setTimezone] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [state, setState] = useState<
    | { kind: 'idle' }
    | { kind: 'submitting' }
    | { kind: 'created' }
    | { kind: 'invalid-timezone' }
    | { kind: 'invalid-link' }
    | { kind: 'consumed' }
    | { kind: 'error'; message: string }
  >({ kind: 'idle' })

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (state.kind === 'submitting') return

    const canonicalTimezone = timezone.trim()
    if (!isIanaTimezone(canonicalTimezone)) {
      setState({ kind: 'invalid-timezone' })
      queueMicrotask(() => timezoneRef.current?.focus())
      return
    }

    setState({ kind: 'submitting' })
    try {
      await completeSetup(token, password, canonicalTimezone)
      setState({ kind: 'created' })
    } catch (error) {
      if (error instanceof KeeplingApiError && error.problem.code === 'setup_unavailable') {
        setState({ kind: 'consumed' })
      } else if (error instanceof KeeplingApiError && error.problem.code === 'invalid_setup') {
        setState({ kind: 'invalid-link' })
      } else {
        setState({
          kind: 'error',
          message: 'Couldn’t create the account. The setup link was not consumed. Try again.',
        })
      }
    }
  }

  if (state.kind === 'created') {
    return (
      <AuthPage title="Account created">
        <p role="status">Account created. Sign in to continue.</p>
        <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/login">
          Sign in
        </a>
      </AuthPage>
    )
  }

  if (state.kind === 'consumed') {
    return (
      <AuthPage title="Setup already complete">
        <p role="alert">This setup link has already been used. Sign in to continue.</p>
        <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/login">
          Return to sign in
        </a>
      </AuthPage>
    )
  }

  if (state.kind === 'invalid-link') {
    return (
      <AuthPage title="Setup link unavailable">
        <p role="alert">This setup link is invalid or expired. Request a new setup link from the operator.</p>
      </AuthPage>
    )
  }

  const timezoneError = state.kind === 'invalid-timezone'

  return (
    <AuthPage title="Set up Keepling">
      <p className="mt-2 text-muted-foreground">
        This private setup link creates the sole account. There is no public registration.
      </p>
      <form className="mt-8 space-y-4" onSubmit={(event) => void submit(event)}>
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor="setup-password">
            Password
          </label>
          <div className="flex gap-2">
            <input
              autoComplete="new-password"
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-input bg-card px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="setup-password"
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
          <label className="block text-sm font-semibold" htmlFor="setup-timezone">
            Account timezone
          </label>
          <input
            aria-describedby={timezoneError ? 'setup-timezone-help setup-timezone-error' : 'setup-timezone-help'}
            aria-invalid={timezoneError || undefined}
            className="min-h-11 w-full rounded-lg border border-input bg-card px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            id="setup-timezone"
            onChange={(event) => setTimezone(event.target.value)}
            placeholder="America/New_York"
            ref={timezoneRef}
            required
            value={timezone}
          />
          <p className="text-sm text-muted-foreground" id="setup-timezone-help">
            Enter an IANA timezone. Keepling will use it for account dates on every device.
          </p>
          {timezoneError ? (
            <p className="text-sm text-destructive" id="setup-timezone-error" role="alert">
              Enter a valid IANA timezone, such as America/New_York.
            </p>
          ) : null}
        </div>

        {state.kind === 'error' ? <p role="alert">{state.message}</p> : null}
        <Button className="min-h-11 px-4" disabled={state.kind === 'submitting'} type="submit">
          {state.kind === 'submitting' ? 'Creating account…' : 'Create account'}
        </Button>
      </form>
    </AuthPage>
  )
}

function AuthPage({ children, title }: { children: React.ReactNode; title: string }) {
  return (
    <main className="min-h-screen bg-background px-4 py-16" id="main-content">
      <section className="mx-auto max-w-lg rounded-lg border border-border bg-card p-6 sm:p-8">
        <p className="text-sm font-semibold text-muted-foreground">Keepling</p>
        <h1 className="mt-2 text-[1.75rem] font-semibold leading-[1.2]">{title}</h1>
        {children}
      </section>
    </main>
  )
}

export { AuthPage }
export default SetupForm
