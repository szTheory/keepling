/* eslint-disable react-refresh/only-export-components -- Provider state and its sole consumer hook intentionally share this private composition boundary. */
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
  failed: boolean
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

  const syncContinuationState = useCallback(() => {
    const continuations = [...resumesRef.current.values()].filter(
      (continuation) => continuation.owner.active,
    )
    setContinuationError(continuations.some((continuation) => continuation.failed))
    setInterruption(continuations[0]?.intent ?? null)
  }, [])

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
        failed: false,
        generation: continuationGenerationRef.current,
        intent,
        owner,
        resume,
      }
      resumesRef.current.set(key, entry)
      syncContinuationState()

      let disposed = false
      return () => {
        if (disposed) return
        disposed = true
        if (resumesRef.current.get(key) === entry) resumesRef.current.delete(key)
        syncContinuationState()
      }
    },
    [syncContinuationState],
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
        syncContinuationState()
      },
    }
  }, [registerContinuation, syncContinuationState])

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
          const outcome = outcomes[index]
          if (
            continuation.owner.active &&
            outcome?.status === 'rejected' &&
            resumesRef.current.get(key) === continuation
          ) {
            continuation.failed = true
          }
          if (
            continuation.owner.active &&
            outcome?.status === 'fulfilled' &&
            resumesRef.current.get(key) === continuation
          ) {
            resumesRef.current.delete(key)
          }
        })
      }

      if (generation !== generationRef.current) return
      syncContinuationState()
    })()
      .finally(() => {
        if (drainRef.current === drain) drainRef.current = null
      })

    drainRef.current = drain
    return drain
  }, [syncContinuationState])

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

export {
  AuthProvider,
  useAuth,
  type AuthenticationState,
  type BeginReauthentication,
  type ContinuationScope,
}
