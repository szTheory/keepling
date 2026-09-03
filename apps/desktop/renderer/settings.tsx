import { useCallback, useEffect, useState } from 'react'

/**
 * Settings (D-10, D-14 `Command-,`). Surfaces the configurable Quick Entry
 * global shortcut and, when registration failed (a collision with another
 * application), the persistent `Quick Entry shortcut isn’t available.`
 * notice with a direct `Change Shortcut…` action -- never a silent
 * fallback to a different shortcut.
 *
 * O-16 gap closure adds the Account section: STATUS PLUS ACTIONS ONLY.
 * There is deliberately no password field, no passkey affordance, and no
 * token entry anywhere in this (or any) renderer -- `Connect…` takes a
 * server address and hands authentication to the SYSTEM BROWSER (RFC 8252),
 * which is what lets passkeys, SSO, MFA, and password-manager autofill work
 * without this app ever seeing a credential.
 */
type ShortcutStatus = { accelerator: string; registered: boolean }

type AccountStatus = Awaited<ReturnType<typeof window.keeplingUtility.accountStatus>>

const ACCOUNT_STATE_COPY: Record<AccountStatus['state'], string> = {
  authorizing: 'Finish signing in with Keepling in your browser.',
  connected: 'Connected.',
  not_configured: 'No Keepling server is configured on this Mac.',
  signed_out: 'Signed out.',
}

function Settings() {
  const [status, setStatus] = useState<ShortcutStatus | null>(null)
  const [rebinding, setRebinding] = useState(false)
  const [candidate, setCandidate] = useState('')
  const [account, setAccount] = useState<AccountStatus | null>(null)
  const [serverAddress, setServerAddress] = useState('')
  const [accountError, setAccountError] = useState<string | null>(null)

  useEffect(() => {
    void window.keeplingUtility.getShortcutStatus().then(setStatus)
    return window.keeplingUtility.onShortcutStatus(setStatus)
  }, [])

  const refreshAccount = useCallback(async () => {
    const next = await window.keeplingUtility.accountStatus()
    setAccount(next)
    setServerAddress((current) => (current === '' ? next.serverUrl ?? '' : current))
  }, [])

  useEffect(() => {
    void refreshAccount()
  }, [refreshAccount])

  const submitRebind = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (candidate.trim() === '') return
    const next = await window.keeplingUtility.setShortcut(candidate.trim())
    setStatus(next)
    if (next.registered) {
      setRebinding(false)
      setCandidate('')
    }
  }

  const submitConnect = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setAccountError(null)
    if (serverAddress.trim() === '') return
    const outcome = await window.keeplingUtility.accountConnect({ serverUrl: serverAddress.trim() })
    if (outcome.kind === 'rejected') {
      setAccountError(
        outcome.reason === 'invalid_server_address'
          ? 'That server address isn’t usable. Use an https address, or a loopback address for local development.'
          : 'Sign-in isn’t available right now.',
      )
      await refreshAccount()
      return
    }
    setAccount(outcome.status)
  }

  const disconnect = async () => {
    setAccountError(null)
    setAccount(await window.keeplingUtility.accountDisconnect())
  }

  return (
    <section aria-label="Settings">
      <h1>Settings</h1>
      <h2>Quick Entry Shortcut</h2>
      {status === null ? null : status.registered ? (
        <p>Current shortcut: {status.accelerator}</p>
      ) : (
        <p role="alert">Quick Entry shortcut isn’t available.</p>
      )}
      {rebinding ? (
        <form onSubmit={(event) => void submitRebind(event)}>
          <label htmlFor="settings-shortcut-candidate">New shortcut</label>
          <input
            id="settings-shortcut-candidate"
            onChange={(event) => setCandidate(event.target.value)}
            placeholder="Control+Alt+Space"
            value={candidate}
          />
          <button type="submit">Save Shortcut</button>
          <button onClick={() => setRebinding(false)} type="button">
            Cancel
          </button>
        </form>
      ) : (
        <button onClick={() => setRebinding(true)} type="button">
          Change Shortcut…
        </button>
      )}

      <h2>Account</h2>
      {account === null ? null : (
        <>
          <p data-testid="account-state">{ACCOUNT_STATE_COPY[account.state]}</p>
          {account.namespace === null ? null : (
            <p data-testid="account-server">Signed in to {account.namespace.origin}</p>
          )}
          {account.disclosure === null ? null : <p role="note">{account.disclosure.copy}</p>}
          {account.state === 'connected' ? (
            <button onClick={() => void disconnect()} type="button">
              Sign Out
            </button>
          ) : (
            <form onSubmit={(event) => void submitConnect(event)}>
              <label htmlFor="settings-server-address">Keepling server address</label>
              <input
                autoComplete="url"
                id="settings-server-address"
                inputMode="url"
                onChange={(event) => setServerAddress(event.target.value)}
                placeholder="https://keepling.example.com"
                type="url"
                value={serverAddress}
              />
              <button type="submit">Connect…</button>
              <p>Signing in opens your browser. Keepling never asks for your password here.</p>
            </form>
          )}
          {accountError === null ? null : <p role="alert">{accountError}</p>}
        </>
      )}
    </section>
  )
}

export default Settings
