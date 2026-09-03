import { createHash, randomBytes } from 'node:crypto'

import type { CredentialPort, SyncNamespace } from '../application/DesktopApplication.ts'
import type { NativeCredentials } from './sync.ts'

/**
 * Browser-delegated authorization (RFC 8252) for the Mac app.
 *
 * Authentication happens in the SYSTEM BROWSER, never in an Electron
 * renderer. `/oauth/authorize` is `pipe_through [:api, :authenticated]` on
 * the server -- it requires an existing browser session -- and that is the
 * design, not an obstacle:
 *
 * - whatever authenticates that session (Argon2id password today,
 *   passkeys/SSO/MFA later) needs ZERO desktop changes;
 * - WebAuthn platform-authenticator support lives in the browser, so
 *   passkeys work without depending on Electron's incomplete macOS support;
 * - password-manager autofill behaves properly, which it does not reliably
 *   inside an Electron window.
 *
 * A private-use scheme (`keepling://auth/callback`) is used rather than an
 * RFC 8252 loopback redirect because the server's `allowed_redirect?/2` is
 * an EXACT-match allowlist and a loopback redirect needs an ephemeral port.
 *
 * KNOWN RESIDUAL, DISCLOSED: private-use-scheme registration is first-come
 * on macOS and cannot be exclusively claimed. A competing local app can
 * intercept a callback, so every callback reaching this class is UNTRUSTED
 * INPUT. PKCE S256 plus exact state matching against exactly one in-flight
 * request reduce interception to a denial of service: an intercepted code
 * is unusable without the verifier, which never leaves this process.
 *
 * Every side effect is injected (browser opening, clock, entropy, token
 * exchange, credential storage) so the whole flow runs under vitest without
 * Electron.
 */

const KEEPLING_REDIRECT_URI = 'keepling://auth/callback'
const CALLBACK_SCHEME = 'keepling:'
const CALLBACK_HOST = 'auth'
const CALLBACK_PATH = '/callback'
const CLIENT_ID = 'electron'
const DEFAULT_AUTHORIZATION_TTL_MS = 10 * 60 * 1_000

type AuthorizationCodeExchangeInput = {
  code: string
  codeVerifier: string
  redirectUri: string
  state: string
}

/** The narrow slice of `KeeplingSyncAdapter` this class needs, injected so the flow is testable without a network. */
type AuthorizationExchangePort = {
  exchangeAuthorizationCode(input: AuthorizationCodeExchangeInput): Promise<NativeCredentials>
  refresh(refreshToken: string): Promise<NativeCredentials>
}

/**
 * The ONLY shape ever written through the credential adapter. The five
 * namespace fields are stored EXACTLY as the server's token response
 * supplied them (D-02): this client never asserts, derives, defaults, or
 * overrides any of them, and nothing from the callback URL -- which is
 * attacker-controllable -- is ever a namespace input.
 */
type StoredCredentials = {
  accessToken: string
  namespace: SyncNamespace
  refreshToken: string
}

type AuthorizationRejection =
  | 'authorization_expired'
  | 'missing_code'
  | 'no_authorization_in_flight'
  | 'state_mismatch'
  | 'unknown_callback'

type AuthorizationOutcome =
  | { kind: 'authorized'; namespace: SyncNamespace }
  | { kind: 'failed'; reason: string }
  | { kind: 'rejected'; reason: AuthorizationRejection }

type BrowserDelegatedAuthorizationOptions = {
  authorizationTtlMs?: number
  clock: { now(): number }
  credentials: CredentialPort
  entropy?: (size: number) => Uint8Array
  exchange: AuthorizationExchangePort
  installationId: string
  label?: string
  openExternal: (url: string) => Promise<void> | void
  redirectUri?: string
  serverBaseUrl: string
}

type InFlightAuthorization = {
  expiresAt: number
  state: string
  verifier: string
}

const base64url = (bytes: Uint8Array): string => Buffer.from(bytes).toString('base64url')

const isStoredCredentials = (value: unknown): value is StoredCredentials => {
  if (typeof value !== 'object' || value === null) return false
  const candidate = value as Record<string, unknown>
  const namespace = candidate.namespace as Record<string, unknown> | undefined
  return typeof candidate.accessToken === 'string'
    && typeof candidate.refreshToken === 'string'
    && typeof namespace === 'object' && namespace !== null
    && typeof namespace.accountSubject === 'string'
    && typeof namespace.generation === 'string'
    && typeof namespace.issuer === 'string'
    && typeof namespace.origin === 'string'
    && typeof namespace.serverInstance === 'string'
}

class BrowserDelegatedAuthorization {
  readonly #authorizationTtlMs: number
  readonly #clock: { now(): number }
  readonly #credentials: CredentialPort
  readonly #entropy: (size: number) => Uint8Array
  readonly #exchange: AuthorizationExchangePort
  readonly #installationId: string
  readonly #label: string
  readonly #openExternal: (url: string) => Promise<void> | void
  readonly #redirectUri: string
  readonly #serverBaseUrl: string
  #inFlight: InFlightAuthorization | null = null

  constructor(options: BrowserDelegatedAuthorizationOptions) {
    this.#authorizationTtlMs = options.authorizationTtlMs ?? DEFAULT_AUTHORIZATION_TTL_MS
    this.#clock = options.clock
    this.#credentials = options.credentials
    this.#entropy = options.entropy ?? ((size) => randomBytes(size))
    this.#exchange = options.exchange
    this.#installationId = options.installationId
    this.#label = options.label ?? 'Keepling for Mac'
    this.#openExternal = options.openExternal
    this.#redirectUri = options.redirectUri ?? KEEPLING_REDIRECT_URI
    this.#serverBaseUrl = options.serverBaseUrl
  }

  hasAuthorizationInFlight(): boolean {
    return this.#inFlight !== null && this.#inFlight.expiresAt > this.#clock.now()
  }

  /**
   * Starts exactly one authorization. A fresh 32-byte verifier and a fresh
   * unpredictable 32-byte state are generated per call and REPLACE any
   * previous in-flight request -- a verifier is never reused, and a
   * superseded state stops being accepted the moment this returns.
   */
  async begin(): Promise<{ authorizationUrl: string }> {
    const verifier = base64url(this.#entropy(32))
    const state = base64url(this.#entropy(32))
    const challenge = createHash('sha256').update(verifier).digest('base64url')

    this.#inFlight = {
      expiresAt: this.#clock.now() + this.#authorizationTtlMs,
      state,
      verifier,
    }

    const url = new URL('/oauth/authorize', this.#serverBaseUrl)
    url.searchParams.set('client_id', CLIENT_ID)
    url.searchParams.set('code_challenge', challenge)
    url.searchParams.set('code_challenge_method', 'S256')
    url.searchParams.set('installation_id', this.#installationId)
    url.searchParams.set('label', this.#label)
    url.searchParams.set('redirect_uri', this.#redirectUri)
    url.searchParams.set('response_type', 'code')
    url.searchParams.set('state', state)

    const authorizationUrl = url.toString()
    await this.#openExternal(authorizationUrl)
    return { authorizationUrl }
  }

  /**
   * Handles one untrusted `keepling://` callback. Rejection is total: no
   * rejected path performs a token exchange or touches stored credentials.
   */
  async handleCallback(callbackUrl: string): Promise<AuthorizationOutcome> {
    let parsed: URL
    try {
      parsed = new URL(callbackUrl)
    } catch {
      return { kind: 'rejected', reason: 'unknown_callback' }
    }
    if (
      parsed.protocol !== CALLBACK_SCHEME
      || parsed.host !== CALLBACK_HOST
      || parsed.pathname !== CALLBACK_PATH
    ) {
      return { kind: 'rejected', reason: 'unknown_callback' }
    }

    const inFlight = this.#inFlight
    if (inFlight === null) return { kind: 'rejected', reason: 'no_authorization_in_flight' }

    const state = parsed.searchParams.get('state')
    if (state === null || state !== inFlight.state) {
      return { kind: 'rejected', reason: 'state_mismatch' }
    }
    if (inFlight.expiresAt <= this.#clock.now()) {
      this.#inFlight = null
      return { kind: 'rejected', reason: 'authorization_expired' }
    }

    const code = parsed.searchParams.get('code')
    if (code === null || code.length === 0) return { kind: 'rejected', reason: 'missing_code' }

    // The authorization code is single-use server-side, so the in-flight
    // request ends here whether the exchange succeeds or fails -- a replayed
    // callback then falls through to `no_authorization_in_flight`.
    this.#inFlight = null

    let credentials: NativeCredentials
    try {
      credentials = await this.#exchange.exchangeAuthorizationCode({
        code,
        codeVerifier: inFlight.verifier,
        redirectUri: this.#redirectUri,
        state,
      })
    } catch (error) {
      return { kind: 'failed', reason: error instanceof Error ? error.message : 'exchange_failed' }
    }

    return this.#persist(credentials)
  }

  /**
   * Rotates the refresh token. A server-detected replay (or any other
   * refusal) clears the local credential so the app surfaces the closed
   * `authentication_required` recovery presentation rather than retrying a
   * dead credential family silently.
   */
  async refresh(): Promise<AuthorizationOutcome> {
    const stored = await this.loadCredentials()
    if (stored === null) return { kind: 'rejected', reason: 'no_authorization_in_flight' }

    let credentials: NativeCredentials
    try {
      credentials = await this.#exchange.refresh(stored.refreshToken)
    } catch (error) {
      await this.#credentials.clear()
      return { kind: 'failed', reason: error instanceof Error ? error.message : 'refresh_failed' }
    }

    return this.#persist(credentials)
  }

  async loadCredentials(): Promise<StoredCredentials | null> {
    let raw: string | null
    try {
      raw = await this.#credentials.load()
    } catch {
      return null
    }
    if (raw === null) return null
    try {
      const parsed: unknown = JSON.parse(raw)
      return isStoredCredentials(parsed) ? parsed : null
    } catch {
      return null
    }
  }

  async accessToken(): Promise<string | null> {
    return (await this.loadCredentials())?.accessToken ?? null
  }

  async namespace(): Promise<SyncNamespace | null> {
    return (await this.loadCredentials())?.namespace ?? null
  }

  async clear(): Promise<void> {
    this.#inFlight = null
    await this.#credentials.clear()
  }

  async #persist(credentials: NativeCredentials): Promise<AuthorizationOutcome> {
    const stored: StoredCredentials = {
      accessToken: credentials.accessToken,
      namespace: credentials.namespace,
      refreshToken: credentials.refreshToken,
    }
    try {
      await this.#credentials.store(JSON.stringify(stored))
    } catch (error) {
      return { kind: 'failed', reason: error instanceof Error ? error.message : 'credential_storage_failed' }
    }
    return { kind: 'authorized', namespace: stored.namespace }
  }
}

export { BrowserDelegatedAuthorization, KEEPLING_REDIRECT_URI }
export type {
  AuthorizationExchangePort,
  AuthorizationOutcome,
  AuthorizationRejection,
  BrowserDelegatedAuthorizationOptions,
  StoredCredentials,
}
