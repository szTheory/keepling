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

type BeginReauthentication = (
  intent: InterruptedIntent,
  resume: (csrfToken: string) => Promise<void>,
) => () => void

type ContinuationScope = {
  beginReauthentication: BeginReauthentication
  dispose: () => void
}

type AuthContextValue = {
  acceptAuthentication: (csrfToken: string) => void
  beginReauthentication: BeginReauthentication
  clearAuthentication: () => void
  completeReauthentication: (intent: InterruptedIntent, csrfToken: string) => Promise<void>
  continuationError: boolean
  createContinuationScope: () => ContinuationScope
  interruption: InterruptedIntent | null
  retryContinuations: () => Promise<void>
  state: AuthenticationState
}

type ContinuationEntry = {
  generation: number
  intent: InterruptedIntent
  owner: ContinuationOwner
  resume: (csrfToken: string) => Promise<void>
}

type ContinuationOwner = {
  active: boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthenticationState>({ kind: 'loading' })
  const [interruption, setInterruption] = useState<InterruptedIntent | null>(null)
  const [continuationError, setContinuationError] = useState(false)
  const resumesRef = useRef(
    new Map<string, ContinuationEntry>(),
  )
  const drainRef = useRef<Promise<void> | null>(null)
  const generationRef = useRef(0)
  const continuationGenerationRef = useRef(0)
  const globalOwnerRef = useRef<ContinuationOwner>({ active: true })

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

  const registerContinuation = useCallback(
    (
      owner: ContinuationOwner,
      intent: InterruptedIntent,
      resume: (csrfToken: string) => Promise<void>,
    ) => {
      if (!owner.active) return () => undefined

      const key = `${intent.kind}:${intent.mutationId}`
      continuationGenerationRef.current += 1
      const entry = {
        generation: continuationGenerationRef.current,
        intent,
        owner,
        resume,
      }
      resumesRef.current.set(key, entry)
      setInterruption((current) => current ?? intent)

      let disposed = false
      return () => {
        if (disposed) return
        disposed = true
        if (resumesRef.current.get(key) === entry) resumesRef.current.delete(key)
        setInterruption(resumesRef.current.values().next().value?.intent ?? null)
      }
    },
    [],
  )

  const beginReauthentication = useCallback<BeginReauthentication>(
    (intent, resume) => registerContinuation(globalOwnerRef.current, intent, resume),
    [registerContinuation],
  )

  const createContinuationScope = useCallback((): ContinuationScope => {
    const owner: ContinuationOwner = { active: true }

    return {
      beginReauthentication: (intent, resume) => registerContinuation(owner, intent, resume),
      dispose: () => {
        if (!owner.active) return
        owner.active = false

        for (const [key, continuation] of resumesRef.current) {
          if (continuation.owner === owner) resumesRef.current.delete(key)
        }
        setInterruption(resumesRef.current.values().next().value?.intent ?? null)
      },
    }
  }, [registerContinuation])

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
    const lastEligibleContinuation = continuationGenerationRef.current
    setContinuationError(false)

    const drain = (async () => {
      const attempted = new Set<number>()
      let failed = false

      while (generation === generationRef.current) {
        const pending = [...resumesRef.current.entries()].filter(
          ([, continuation]) =>
            continuation.owner.active &&
            continuation.generation <= lastEligibleContinuation &&
            !attempted.has(continuation.generation),
        )
        if (pending.length === 0) break
        pending.forEach(([, continuation]) => attempted.add(continuation.generation))

        const outcomes = await Promise.allSettled(
          pending.map(([, continuation]) => continuation.resume(csrfToken)),
        )
        if (generation !== generationRef.current) return

        pending.forEach(([key, continuation], index) => {
          if (
            continuation.owner.active &&
            outcomes[index]?.status === 'fulfilled' &&
            resumesRef.current.get(key) === continuation
          ) {
            resumesRef.current.delete(key)
          }
        })
        failed ||=
          outcomes.some(
            (outcome, index) =>
              pending[index]?.[1].owner.active && outcome.status === 'rejected',
          )
      }

      if (generation !== generationRef.current) return
      setContinuationError(failed)
      setInterruption(resumesRef.current.values().next().value?.intent ?? null)
    })()
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
      createContinuationScope,
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
      createContinuationScope,
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
export {
  AuthProvider,
  useAuth,
  type AuthenticationState,
  type BeginReauthentication,
  type ContinuationScope,
}
