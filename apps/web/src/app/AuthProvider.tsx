import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

import { getSession, KeeplingApiError } from '@/api/keepling'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type AuthenticationState =
  | { kind: 'loading' }
  | { kind: 'unauthenticated' }
  | { kind: 'error' }
  | { csrfToken: string; kind: 'authenticated' }

type AuthContextValue = {
  acceptAuthentication: (csrfToken: string) => void
  beginReauthentication: (intent: InterruptedIntent) => void
  clearAuthentication: () => void
  completeReauthentication: (intent: InterruptedIntent, csrfToken: string) => void
  interruption: InterruptedIntent | null
  state: AuthenticationState
}

const AuthContext = createContext<AuthContextValue | null>(null)

function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthenticationState>({ kind: 'loading' })
  const [interruption, setInterruption] = useState<InterruptedIntent | null>(null)

  useEffect(() => {
    let active = true
    void getSession()
      .then((session) => {
        if (active) setState({ csrfToken: session.csrf_token, kind: 'authenticated' })
      })
      .catch((error: unknown) => {
        if (!active) return
        setState(
          error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
            ? { kind: 'unauthenticated' }
            : { kind: 'error' },
        )
      })
    return () => {
      active = false
    }
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      acceptAuthentication: (csrfToken) => {
        setState({ csrfToken, kind: 'authenticated' })
        setInterruption(null)
      },
      beginReauthentication: (intent) => setInterruption(intent),
      clearAuthentication: () => {
        setInterruption(null)
        setState({ kind: 'unauthenticated' })
      },
      completeReauthentication: (intent, csrfToken) => {
        setState({ csrfToken, kind: 'authenticated' })
        setInterruption((current) => (current === intent ? null : current))
      },
      interruption,
      state,
    }),
    [interruption, state],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

const useAuth = () => {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}

// Auth state and its provider intentionally share this narrow composition module.
// eslint-disable-next-line react-refresh/only-export-components
export { AuthProvider, useAuth, type AuthenticationState }
