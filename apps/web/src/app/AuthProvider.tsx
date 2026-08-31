import {
  useCallback,
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
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
  beginReauthentication: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  clearAuthentication: () => void
  completeReauthentication: (intent: InterruptedIntent, csrfToken: string) => Promise<void>
  interruption: InterruptedIntent | null
  state: AuthenticationState
}

const AuthContext = createContext<AuthContextValue | null>(null)

function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthenticationState>({ kind: 'loading' })
  const [interruption, setInterruption] = useState<InterruptedIntent | null>(null)
  const resumesRef = useRef(
    new Map<
      string,
      { intent: InterruptedIntent; resume: (csrfToken: string) => Promise<void> }
    >(),
  )

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

  const acceptAuthentication = useCallback((csrfToken: string) => {
    setState({ csrfToken, kind: 'authenticated' })
    setInterruption(null)
  }, [])

  const beginReauthentication = useCallback(
    (intent: InterruptedIntent, resume: (csrfToken: string) => Promise<void>) => {
      const key = `${intent.kind}:${intent.mutationId}`
      resumesRef.current.set(key, { intent, resume })
      setInterruption((current) => current ?? intent)
    },
    [],
  )

  const clearAuthentication = useCallback(() => {
    resumesRef.current.clear()
    setInterruption(null)
    setState({ kind: 'unauthenticated' })
  }, [])

  const completeReauthentication = useCallback(
    async (_intent: InterruptedIntent, csrfToken: string) => {
      setState({ csrfToken, kind: 'authenticated' })
      const pending = [...resumesRef.current.entries()]
      const outcomes = await Promise.allSettled(
        pending.map(([, continuation]) => continuation.resume(csrfToken)),
      )
      pending.forEach(([key], index) => {
        if (outcomes[index]?.status === 'fulfilled') resumesRef.current.delete(key)
      })
      setInterruption(resumesRef.current.values().next().value?.intent ?? null)
    },
    [],
  )

  const value = useMemo<AuthContextValue>(
    () => ({
      acceptAuthentication,
      beginReauthentication,
      clearAuthentication,
      completeReauthentication,
      interruption,
      state,
    }),
    [
      acceptAuthentication,
      beginReauthentication,
      clearAuthentication,
      completeReauthentication,
      interruption,
      state,
    ],
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
