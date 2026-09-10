import { useEffect, useRef, useState } from 'react'

import {
  KeeplingApiError,
  listDeviceGrants,
  revokeDeviceGrant,
  type AgentGrant,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import { AlertDialog } from '@/components/ui/alert-dialog'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type AgentGrantListProps = {
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
}

type RevokeRecovery = {
  installationId: string
  label: string
  status: 'checking' | 'unknown'
}

const isUncertainFailure = (error: unknown) =>
  !(error instanceof KeeplingApiError) || error.problem.status >= 500

const exactAuthorizedTime = (value: string) =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  }).format(new Date(value)) + ' UTC'

function AgentGrantList({ csrfToken, onAuthenticationRequired }: AgentGrantListProps) {
  const revokeTriggerRef = useRef<HTMLElement>(null)
  const keepAuthorizedRef = useRef<HTMLButtonElement>(null)
  const writeInFlightRef = useRef(false)
  const [state, setState] = useState<
    | { kind: 'loading' }
    | { kind: 'error' }
    | { kind: 'ready'; grants: readonly AgentGrant[] }
  >({ kind: 'loading' })
  const [confirmation, setConfirmation] = useState<AgentGrant | null>(null)
  const [recovery, setRecovery] = useState<RevokeRecovery | null>(null)
  const [busyInstallationId, setBusyInstallationId] = useState<string | null>(null)
  const [message, setMessage] = useState('')

  const retryLoad = async () => {
    setState({ kind: 'loading' })
    try {
      setState({ grants: await listDeviceGrants(), kind: 'ready' })
    } catch (error) {
      setState({ kind: 'error' })
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        onAuthenticationRequired(
          { authentication: 'sign_in', kind: 'read', mutationId: 'agent-grants:list' },
          async () => {
            setState({ grants: await listDeviceGrants(), kind: 'ready' })
          },
        )
      }
    }
  }

  useEffect(() => {
    let active = true
    void listDeviceGrants()
      .then((grants) => {
        if (!active) return
        setState({ grants, kind: 'ready' })
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
            { authentication: 'sign_in', kind: 'read', mutationId: 'agent-grants:list' },
            async () => {
              const grants = await listDeviceGrants()
              if (active) setState({ grants, kind: 'ready' })
            },
          )
        }
      })
    return () => {
      active = false
    }
  }, [onAuthenticationRequired])

  const reconcile = async (action: RevokeRecovery, allowAuthenticationRecovery = true) => {
    setRecovery({ ...action, status: 'checking' })
    setMessage('')

    try {
      const grants = await listDeviceGrants()
      setState({ grants, kind: 'ready' })
      const stillAuthorized = grants.some(
        (grant) => grant.installationId === action.installationId,
      )
      setRecovery(null)
      setMessage(stillAuthorized ? `${action.label} remains authorized.` : `${action.label} revoked.`)
    } catch (error) {
      setRecovery({ ...action, status: 'unknown' })
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required'
      ) {
        if (allowAuthenticationRecovery && onAuthenticationRequired) {
          onAuthenticationRequired(
            {
              authentication: 'sign_in',
              kind: 'read',
              mutationId: `agent-grants:reconcile:${action.installationId}`,
            },
            async () => {
              await reconcile(action, false)
            },
          )
          return
        }
        if (!allowAuthenticationRecovery) throw error
      }
    }
  }

  const resumeRevocation = async (action: RevokeRecovery, activeCsrfToken: string) => {
    setRecovery({ ...action, status: 'checking' })
    setMessage('')

    const grants = await listDeviceGrants()
    setState({ grants, kind: 'ready' })
    if (!grants.some((grant) => grant.installationId === action.installationId)) {
      setRecovery(null)
      setMessage(`${action.label} revoked.`)
      return
    }

    await revokeDeviceGrant(action.installationId, activeCsrfToken)
    setState((current) =>
      current.kind === 'ready'
        ? {
            grants: current.grants.filter(
              (grant) => grant.installationId !== action.installationId,
            ),
            kind: 'ready',
          }
        : current,
    )
    setRecovery(null)
    setMessage(`${action.label} revoked.`)
  }

  const confirmRevoke = async (activeCsrfToken = csrfToken) => {
    if (!confirmation || state.kind !== 'ready' || writeInFlightRef.current) return
    const grant = confirmation
    writeInFlightRef.current = true
    setBusyInstallationId(grant.installationId)
    try {
      await revokeDeviceGrant(grant.installationId, activeCsrfToken)
      setState((current) =>
        current.kind === 'ready'
          ? {
              grants: current.grants.filter(
                (candidate) => candidate.installationId !== grant.installationId,
              ),
              kind: 'ready',
            }
          : current,
      )
      setMessage(`${grant.label} revoked.`)
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
        const action: RevokeRecovery = {
          installationId: grant.installationId,
          label: grant.label,
          status: 'checking',
        }
        setConfirmation(null)
        setRecovery(action)
        onAuthenticationRequired(
          { authentication, kind: 'action', mutationId: `agent-grant-revoke:${grant.installationId}` },
          async (nextCsrfToken) => resumeRevocation(action, nextCsrfToken),
        )
        return
      }
      if (isUncertainFailure(error)) {
        const action: RevokeRecovery = {
          installationId: grant.installationId,
          label: grant.label,
          status: 'checking',
        }
        setConfirmation(null)
        await reconcile(action)
      } else {
        setMessage(`Couldn’t revoke ${grant.label}. The agent remains authorized.`)
        setConfirmation(null)
      }
    } finally {
      writeInFlightRef.current = false
      setBusyInstallationId(null)
    }
  }

  if (state.kind === 'loading') {
    return <p role="status">Loading AI agents…</p>
  }

  if (state.kind === 'error') {
    return (
      <div className="rounded-lg border border-border bg-card p-4" role="alert">
        <p>Couldn’t load AI agents. Nothing was changed.</p>
        <Button className="mt-4 min-h-11" onClick={() => void retryLoad()} variant="outline">
          Retry loading AI agents
        </Button>
      </div>
    )
  }

  return (
    <>
      {recovery ? (
        <div className="mb-4 rounded-lg border border-border bg-card p-4" role="status">
          <p>
            {recovery.status === 'checking'
              ? 'Checking the authoritative agent-grant state…'
              : `Keepling could not confirm whether ${recovery.label} was revoked.`}
          </p>
          {recovery.status === 'unknown' ? (
            <Button
              className="mt-4 min-h-11"
              onClick={() => void reconcile(recovery)}
              variant="outline"
            >
              Check revocation again
            </Button>
          ) : null}
        </div>
      ) : null}

      {state.grants.length === 0 ? (
        <p role="status">No AI agents are authorized.</p>
      ) : (
        <ul aria-label="Authorized AI agents" className="divide-y divide-border">
          {state.grants.map((grant) => (
            <li className="py-6" key={grant.installationId}>
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-xl font-semibold">{grant.label}</h2>
                    <span className="rounded-full border border-border px-2 py-1 text-sm font-semibold">
                      AI agent
                    </span>
                  </div>
                  <dl className="mt-4 grid gap-1 text-sm text-muted-foreground">
                    <div className="flex gap-2">
                      <dt className="font-semibold text-foreground">Scopes</dt>
                      <dd>
                        {grant.scope.length === 0 ? (
                          'No scopes granted'
                        ) : (
                          <span className="flex flex-wrap gap-2">
                            {grant.scope.map((scope) => (
                              <code
                                className="rounded border border-border px-2 py-1"
                                key={scope}
                              >
                                {scope}
                              </code>
                            ))}
                          </span>
                        )}
                      </dd>
                    </div>
                    <div className="flex gap-2">
                      <dt className="font-semibold text-foreground">Authorized</dt>
                      <dd>
                        {grant.authorizedAt ? (
                          <time dateTime={grant.authorizedAt}>
                            {exactAuthorizedTime(grant.authorizedAt)}
                          </time>
                        ) : (
                          'Not yet reported'
                        )}
                      </dd>
                    </div>
                    <div className="flex gap-2">
                      <dt className="font-semibold text-foreground">Last used</dt>
                      <dd>
                        {grant.lastUsedAt ? (
                          <time dateTime={grant.lastUsedAt}>
                            {exactAuthorizedTime(grant.lastUsedAt)}
                          </time>
                        ) : (
                          'Not yet used'
                        )}
                      </dd>
                    </div>
                  </dl>
                </div>
                <Button
                  className="min-h-11"
                  disabled={busyInstallationId !== null || recovery !== null}
                  onClick={(event) => {
                    revokeTriggerRef.current = event.currentTarget
                    setConfirmation(grant)
                  }}
                  variant="destructive"
                >
                  Revoke {grant.label}
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <AlertDialog
        actions={
          confirmation
            ? [
                {
                  disabled: recovery !== null,
                  label: 'Keep authorized',
                  onClick: () => setConfirmation(null),
                  ref: keepAuthorizedRef,
                  variant: 'outline',
                },
                {
                  disabled: busyInstallationId === confirmation.installationId || recovery !== null,
                  label: 'Revoke agent',
                  onClick: () => void confirmRevoke(),
                  variant: 'destructive',
                },
              ]
            : []
        }
        description={`${confirmation?.label ?? ''} will lose access to Keepling immediately. Its next request will be refused.`}
        finalFocus={revokeTriggerRef}
        initialFocus={keepAuthorizedRef}
        onCancel={() => setConfirmation(null)}
        open={confirmation !== null}
        title={`Revoke ${confirmation?.label ?? ''}?`}
      />

      <div aria-atomic="true" aria-live="polite" className="sr-only">
        {message}
      </div>
    </>
  )
}

export default AgentGrantList
