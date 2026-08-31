import { useEffect, useRef, useState } from 'react'

import {
  KeeplingApiError,
  listSessions,
  logout,
  revokeSession,
  updateSession,
  type BrowserSession,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type SessionListProps = {
  csrfToken: string
  hasDirtyWork: boolean
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onLoggedOut: () => void
}

type Confirmation = { kind: 'logout'; session: BrowserSession } | { kind: 'revoke'; session: BrowserSession }

const clientKind = (kind: BrowserSession['clientKind']) =>
  ({ electron: 'Electron', iphone: 'iPhone', mcp: 'MCP', web: 'Web' })[kind]

const coarseActivity = (activity: BrowserSession['coarseActivity']) =>
  ({ active_now: 'Active now', earlier: 'Earlier', today: 'Today' })[activity]

const exactCreatedTime = (value: string) =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  }).format(new Date(value)) + ' UTC'

function SessionList({
  csrfToken,
  hasDirtyWork,
  onAuthenticationRequired,
  onLoggedOut,
}: SessionListProps) {
  const keepActiveRef = useRef<HTMLButtonElement>(null)
  const [state, setState] = useState<
    | { kind: 'loading' }
    | { kind: 'error' }
    | { kind: 'ready'; sessions: readonly BrowserSession[] }
  >({ kind: 'loading' })
  const [draftLabels, setDraftLabels] = useState<Record<string, string>>({})
  const [busySessionId, setBusySessionId] = useState<string | null>(null)
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null)
  const [message, setMessage] = useState('')

  const retryLoad = async () => {
    setState({ kind: 'loading' })
    try {
      const sessions = await listSessions()
      setDraftLabels(Object.fromEntries(sessions.map((session) => [session.id, session.label])))
      setState({ kind: 'ready', sessions })
    } catch (error) {
      setState({ kind: 'error' })
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        onAuthenticationRequired(
          { authentication: 'sign_in', kind: 'read', mutationId: 'sessions:list' },
          async () => {
            const sessions = await listSessions()
            setDraftLabels(
              Object.fromEntries(sessions.map((session) => [session.id, session.label])),
            )
            setState({ kind: 'ready', sessions })
          },
        )
      }
    }
  }

  useEffect(() => {
    let active = true
    void listSessions()
      .then((sessions) => {
        if (!active) return
        setDraftLabels(Object.fromEntries(sessions.map((session) => [session.id, session.label])))
        setState({ kind: 'ready', sessions })
      })
      .catch((error: unknown) => {
        if (!active) return
        setState({ kind: 'error' })
        if (
          error instanceof KeeplingApiError &&
          error.problem.code === 'authentication_required' &&
          onAuthenticationRequired
        ) {
          onAuthenticationRequired(
            { authentication: 'sign_in', kind: 'read', mutationId: 'sessions:list' },
            async () => {
              const sessions = await listSessions()
              setDraftLabels(
                Object.fromEntries(sessions.map((session) => [session.id, session.label])),
              )
              setState({ kind: 'ready', sessions })
            },
          )
        }
      })
    return () => {
      active = false
    }
  }, [onAuthenticationRequired])

  useEffect(() => {
    if (confirmation) keepActiveRef.current?.focus()
  }, [confirmation])

  const saveLabel = async (session: BrowserSession, activeCsrfToken = csrfToken) => {
    if (state.kind !== 'ready') return
    const nextLabel = draftLabels[session.id]?.trim() ?? ''
    if (nextLabel === '' || nextLabel === session.label) return
    setBusySessionId(session.id)
    try {
      await updateSession(session.id, nextLabel, activeCsrfToken)
      setState({
        kind: 'ready',
        sessions: state.sessions.map((candidate) =>
          candidate.id === session.id ? { ...candidate, label: nextLabel } : candidate,
        ),
      })
      setMessage(`Session label changed to ${nextLabel}.`)
    } catch (error) {
      const authentication =
        error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
          ? 'sign_in'
          : error instanceof KeeplingApiError &&
              error.problem.code === 'recent_authentication_required'
            ? 'reauthenticate'
            : null
      if (authentication && onAuthenticationRequired) {
        onAuthenticationRequired(
          { authentication, kind: 'action', mutationId: `session-label:${session.id}` },
          async (nextCsrfToken) => saveLabel(session, nextCsrfToken),
        )
        return
      }
      setMessage(`Couldn’t rename ${session.label}. The existing label is unchanged.`)
    } finally {
      setBusySessionId(null)
    }
  }

  const confirmAction = async (activeCsrfToken = csrfToken) => {
    if (!confirmation || state.kind !== 'ready') return
    const { session } = confirmation
    setBusySessionId(session.id)
    try {
      if (confirmation.kind === 'logout') {
        await logout(activeCsrfToken)
        onLoggedOut()
        return
      }
      await revokeSession(session.id, activeCsrfToken)
      setState({
        kind: 'ready',
        sessions: state.sessions.filter((candidate) => candidate.id !== session.id),
      })
      setMessage(`${session.label} revoked.`)
      setConfirmation(null)
    } catch (error) {
      const authentication =
        error instanceof KeeplingApiError && error.problem.code === 'authentication_required'
          ? 'sign_in'
          : error instanceof KeeplingApiError &&
              error.problem.code === 'recent_authentication_required'
            ? 'reauthenticate'
            : null
      if (authentication && onAuthenticationRequired) {
        onAuthenticationRequired(
          { authentication, kind: 'action', mutationId: `session-revoke:${session.id}` },
          async (nextCsrfToken) => confirmAction(nextCsrfToken),
        )
        return
      }
      setMessage(
        `Couldn’t revoke ${session.label}. The session remains active.`,
      )
      setConfirmation(null)
    } finally {
      setBusySessionId(null)
    }
  }

  if (state.kind === 'loading') {
    return <p role="status">Loading sessions…</p>
  }

  if (state.kind === 'error') {
    return (
      <div className="rounded-lg border border-border bg-card p-4" role="alert">
        <p>Couldn’t load Sessions. Nothing was changed.</p>
        <Button className="mt-3 min-h-11" onClick={() => void retryLoad()} variant="outline">
          Retry loading Sessions
        </Button>
      </div>
    )
  }

  return (
    <>
      {state.sessions.length === 0 ? (
        <p role="status">No active sessions were returned. Sign in again before retrying.</p>
      ) : (
        <ul className="divide-y divide-border" aria-label="Active sessions">
          {state.sessions.map((session) => {
            const draftLabel = draftLabels[session.id] ?? session.label
            return (
              <li className="py-6" key={session.id}>
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <h2 className="text-xl font-semibold">{session.label}</h2>
                      {session.current ? (
                        <span className="rounded-full border border-border px-2 py-1 text-sm font-semibold">
                          Current browser
                        </span>
                      ) : null}
                    </div>
                    <dl className="mt-3 grid gap-1 text-sm text-muted-foreground">
                      <div className="flex gap-2">
                        <dt className="font-semibold text-foreground">Client</dt>
                        <dd>{clientKind(session.clientKind)}</dd>
                      </div>
                      <div className="flex gap-2">
                        <dt className="font-semibold text-foreground">Created</dt>
                        <dd>
                          <time dateTime={session.createdAt}>{exactCreatedTime(session.createdAt)}</time>
                        </dd>
                      </div>
                      <div className="flex gap-2">
                        <dt className="font-semibold text-foreground">Recent activity</dt>
                        <dd>{coarseActivity(session.coarseActivity)}</dd>
                      </div>
                    </dl>
                  </div>
                  <Button
                    className="min-h-11"
                    onClick={() =>
                      setConfirmation({ kind: session.current ? 'logout' : 'revoke', session })
                    }
                    variant="destructive"
                  >
                    {session.current ? 'Log out this browser' : `Revoke ${session.label}`}
                  </Button>
                </div>

                <div className="mt-4 flex flex-wrap items-end gap-3">
                  <div className="min-w-56 flex-1 space-y-2">
                    <label className="block text-sm font-semibold" htmlFor={`session-label-${session.id}`}>
                      Label for {session.label}
                    </label>
                    <input
                      className="min-h-11 w-full rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                      id={`session-label-${session.id}`}
                      maxLength={200}
                      onChange={(event) =>
                        setDraftLabels((labels) => ({ ...labels, [session.id]: event.target.value }))
                      }
                      value={draftLabel}
                    />
                  </div>
                  <Button
                    aria-label={`Save label for ${session.label}`}
                    className="min-h-11"
                    disabled={
                      busySessionId === session.id ||
                      draftLabel.trim() === '' ||
                      draftLabel.trim() === session.label
                    }
                    onClick={() => void saveLabel(session)}
                    variant="outline"
                  >
                    {busySessionId === session.id ? 'Saving…' : 'Save label'}
                  </Button>
                </div>
              </li>
            )
          })}
        </ul>
      )}

      {confirmation ? (
        <div
          aria-labelledby="session-confirmation-heading"
          aria-modal="true"
          className="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4"
          role="alertdialog"
        >
          <div className="w-full max-w-md rounded-lg border border-border bg-card p-6 shadow-lg">
            <h2 className="text-xl font-semibold" id="session-confirmation-heading">
              {confirmation.kind === 'revoke'
                ? `Revoke ${confirmation.session.label}?`
                : 'Log out this browser?'}
            </h2>
            <p className="mt-2">
              {confirmation.kind === 'revoke'
                ? `Revoke ${confirmation.session.label}? Keepling on that device will need to sign in again.`
                : hasDirtyWork
                  ? 'Log out and discard unsaved changes? Saved tasks will remain in Keepling.'
                  : 'The current browser will need to sign in again. Saved tasks will remain in Keepling.'}
            </p>
            <div className="mt-6 flex flex-wrap justify-end gap-3">
              <Button onClick={() => setConfirmation(null)} ref={keepActiveRef} variant="outline">
                {confirmation.kind === 'revoke' ? 'Keep session active' : 'Stay here'}
              </Button>
              <Button
                disabled={busySessionId === confirmation.session.id}
                onClick={() => void confirmAction()}
                variant="destructive"
              >
                {confirmation.kind === 'revoke'
                  ? 'Revoke session'
                  : hasDirtyWork
                    ? 'Discard changes and log out'
                    : 'Log out'}
              </Button>
            </div>
          </div>
        </div>
      ) : null}

      <div aria-atomic="true" aria-live="polite" className="sr-only">
        {message}
      </div>
    </>
  )
}

export default SessionList
