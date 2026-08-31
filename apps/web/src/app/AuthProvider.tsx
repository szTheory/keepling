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
  continuationError: boolean
  interruption: InterruptedIntent | null
  retryContinuations: () => Promise<void>
  state: AuthenticationState
}

const AuthContext = createContext<AuthContextValue | null>(null)

function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthenticationState>({ kind: 'loading' })
  const [interruption, setInterruption] = useState<InterruptedIntent | null>(null)
  const [continuationError, setContinuationError] = useState(false)
  const resumesRef = useRef(
    new Map<
      string,
      { intent: InterruptedIntent; resume: (csrfToken: string) => Promise<void> }
    >(),
  )
  const drainRef = useRef<Promise<void> | null>(null)
  const generationRef = useRef(0)

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
    setContinuationError(false)
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
    generationRef.current += 1
    resumesRef.current.clear()
    drainRef.current = null
    setContinuationError(false)
    setInterruption(null)
    setState({ kind: 'unauthenticated' })
  }, [])

  const drainContinuations = useCallback((csrfToken: string): Promise<void> => {
    if (drainRef.current) return drainRef.current

    const generation = generationRef.current
    const pending = [...resumesRef.current.entries()]
    setContinuationError(false)

    const drain = Promise.allSettled(
      pending.map(([, continuation]) => continuation.resume(csrfToken)),
    )
      .then((outcomes) => {
        if (generation !== generationRef.current) return
        pending.forEach(([key], index) => {
          if (outcomes[index]?.status === 'fulfilled') resumesRef.current.delete(key)
        })
        const failed = outcomes.some((outcome) => outcome.status === 'rejected')
        setContinuationError(failed)
        setInterruption(resumesRef.current.values().next().value?.intent ?? null)
      })
      .finally(() => {
        if (drainRef.current === drain) drainRef.current = null
      })

    drainRef.current = drain
    return drain
  }, [])

  const completeReauthentication = useCallback(
    async (_intent: InterruptedIntent, csrfToken: string) => {
      setState({ csrfToken, kind: 'authenticated' })
      await drainContinuations(csrfToken)
    },
    [drainContinuations],
  )

  const retryContinuations = useCallback(async () => {
    if (state.kind !== 'authenticated') return
    await drainContinuations(state.csrfToken)
  }, [drainContinuations, state])

  const value = useMemo<AuthContextValue>(
    () => ({
      acceptAuthentication,
      beginReauthentication,
      clearAuthentication,
      completeReauthentication,
      continuationError,
      interruption,
      retryContinuations,
      state,
    }),
    [
      acceptAuthentication,
      beginReauthentication,
      clearAuthentication,
      completeReauthentication,
      continuationError,
      interruption,
      retryContinuations,
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
