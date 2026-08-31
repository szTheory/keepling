import { useEffect, useState, type ReactNode } from 'react'

import LoginForm from '@/features/auth/LoginForm'
import Reauthenticate, { type InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryReset from '@/features/auth/RecoveryReset'
import SetupForm from '@/features/auth/SetupForm'

type AppRoutesProps = {
  authenticated: boolean
  authenticatedContent?: ReactNode
  csrfToken?: string
  interruption?: InterruptedIntent | null
  onAuthenticated?: (csrfToken: string) => void
  onReauthenticated?: (interruption: InterruptedIntent, csrfToken: string) => void
}

const routeToken = (pathname: string, prefix: string) => {
  if (!pathname.startsWith(prefix)) return null
  const raw = pathname.slice(prefix.length)
  if (raw === '' || raw.includes('/')) return null
  try {
    return decodeURIComponent(raw)
  } catch {
    return null
  }
}

const navigate = (pathname: string) => {
  window.history.replaceState({}, '', pathname)
  window.dispatchEvent(new PopStateEvent('popstate'))
}

function AppRoutes({
  authenticated,
  authenticatedContent,
  csrfToken,
  interruption,
  onAuthenticated = () => undefined,
  onReauthenticated = () => undefined,
}: AppRoutesProps) {
  const [pathname, setPathname] = useState(window.location.pathname)

  useEffect(() => {
    const update = () => setPathname(window.location.pathname)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  const handleAuthenticated = (nextCsrfToken: string) => {
    onAuthenticated(nextCsrfToken)
    navigate('/')
  }
  const setupToken = routeToken(pathname, '/setup/')
  if (setupToken) return <SetupForm token={setupToken} />

  const recoveryToken = routeToken(pathname, '/recover/')
  if (recoveryToken) {
    return <RecoveryReset onAuthenticated={handleAuthenticated} token={recoveryToken} />
  }

  if (interruption && csrfToken) {
    return (
      <main className="mx-auto min-h-screen max-w-2xl bg-background px-4 py-16" id="main-content">
        <Reauthenticate
          csrfToken={csrfToken}
          interruption={interruption}
          onAuthenticated={onReauthenticated}
        />
      </main>
    )
  }

  if (!authenticated || pathname === '/login') {
    if (authenticated) {
      return (
        <main className="p-6" id="main-content">
          <h1 className="text-[1.75rem] font-semibold">Already signed in</h1>
          <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/">
            Return to Keepling
          </a>
        </main>
      )
    }
    return <LoginForm onAuthenticated={handleAuthenticated} />
  }

  return authenticatedContent ?? (
    <main className="p-6" id="main-content">
      <h1 className="text-[1.75rem] font-semibold">Keepling</h1>
    </main>
  )
}

export default AppRoutes
