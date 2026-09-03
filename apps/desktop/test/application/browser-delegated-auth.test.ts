import { createHash } from 'node:crypto'

import { describe, expect, it } from 'vitest'

import {
  BrowserDelegatedAuthorization,
  KEEPLING_REDIRECT_URI,
  type AuthorizationExchangePort,
} from '../../main/adapters/auth.ts'
import {
  FileServerConfiguration,
  assertAllowedServerUrl,
} from '../../main/adapters/server-config.ts'

/**
 * Task 2 (03-14): credential acquisition is delegated to the system browser
 * (RFC 8252) -- authorization code + PKCE S256, unpredictable state, and a
 * private-use `keepling://auth/callback` redirect. Every case here runs
 * WITHOUT Electron: the browser-opening side effect, the clock, the entropy
 * source, the token exchange, and the credential adapter are all injected.
 *
 * The hostile cases are the point. A `keepling://` scheme registration is
 * first-come on macOS, so a callback is untrusted input: a state that was
 * never issued, a replayed code, or a callback arriving with nothing in
 * flight must all be rejected WITHOUT mutating stored credentials.
 */

const namespace = {
  account_subject: '9f1d5f39-1a4a-4b7e-9f2a-2b8ef2a3c111',
  generation: 3,
  issuer: 'https://issuer.keepling.invalid',
  origin: 'https://server.keepling.invalid',
  server_instance: 'server-instance-real',
}

const mappedNamespace = {
  accountSubject: namespace.account_subject,
  generation: '3',
  issuer: namespace.issuer,
  origin: namespace.origin,
  serverInstance: namespace.server_instance,
}

const s256 = (verifier: string) => createHash('sha256').update(verifier).digest('base64url')

type Recorded = { code: string; codeVerifier: string; redirectUri: string; state: string }

const stubCredentials = () => {
  let value: string | null = null
  const writes: string[] = []
  return {
    adapter: {
      clear: async () => {
        value = null
        writes.push('<cleared>')
      },
      load: async () => value,
      store: async (next: string) => {
        value = next
        writes.push(next)
      },
    },
    current: () => value,
    writes,
  }
}

const stubExchange = (
  overrides: Partial<AuthorizationExchangePort> = {},
): { exchanges: Recorded[]; port: AuthorizationExchangePort; refreshed: string[] } => {
  const exchanges: Recorded[] = []
  const refreshed: string[] = []
  return {
    exchanges,
    port: {
      exchangeAuthorizationCode: async (input) => {
        exchanges.push(input)
        return {
          accessToken: 'access-token-one',
          expiresIn: 900,
          namespace: mappedNamespace,
          refreshToken: 'refresh-token-one',
        }
      },
      refresh: async (token) => {
        refreshed.push(token)
        return {
          accessToken: 'access-token-two',
          expiresIn: 900,
          namespace: mappedNamespace,
          refreshToken: 'refresh-token-two',
        }
      },
      ...overrides,
    },
    refreshed,
  }
}

const build = (options: {
  credentials?: ReturnType<typeof stubCredentials>
  exchange?: ReturnType<typeof stubExchange>
  now?: () => number
} = {}) => {
  const credentials = options.credentials ?? stubCredentials()
  const exchange = options.exchange ?? stubExchange()
  const opened: string[] = []
  const authorization = new BrowserDelegatedAuthorization({
    clock: { now: options.now ?? (() => 1_800_000_000_000) },
    credentials: credentials.adapter,
    exchange: exchange.port,
    installationId: 'installation-real',
    label: 'Jon’s Mac',
    openExternal: (url) => {
      opened.push(url)
    },
    serverBaseUrl: 'https://server.keepling.invalid',
  })
  return { authorization, credentials, exchange, opened }
}

describe('BrowserDelegatedAuthorization (RFC 8252 system-browser delegation)', () => {
  it('opens the system browser at /oauth/authorize with PKCE S256 and unpredictable state', async () => {
    const { authorization, opened } = build()

    const started = await authorization.begin()

    expect(opened).toEqual([started.authorizationUrl])
    const url = new URL(started.authorizationUrl)
    expect(url.origin).toBe('https://server.keepling.invalid')
    expect(url.pathname).toBe('/oauth/authorize')
    expect(url.searchParams.get('client_id')).toBe('electron')
    expect(url.searchParams.get('response_type')).toBe('code')
    expect(url.searchParams.get('code_challenge_method')).toBe('S256')
    expect(url.searchParams.get('redirect_uri')).toBe(KEEPLING_REDIRECT_URI)
    expect(url.searchParams.get('installation_id')).toBe('installation-real')
    expect(url.searchParams.get('label')).toBe('Jon’s Mac')

    // Unpredictable state: exactly 32 decoded bytes, matching the server's
    // own `unpredictable_state?/1` predicate in device_grant.ex.
    const state = url.searchParams.get('state') ?? ''
    expect(Buffer.from(state, 'base64url')).toHaveLength(32)
    const challenge = url.searchParams.get('code_challenge') ?? ''
    expect(Buffer.from(challenge, 'base64url')).toHaveLength(32)
  })

  it('exchanges a matching callback and persists the server namespace verbatim', async () => {
    const { authorization, credentials, exchange } = build()

    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''

    const outcome = await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=authorization-code&state=${encodeURIComponent(state)}`,
    )

    expect(outcome).toEqual({ kind: 'authorized', namespace: mappedNamespace })

    const recorded = exchange.exchanges[0]
    expect(recorded?.code).toBe('authorization-code')
    expect(recorded?.state).toBe(state)
    expect(recorded?.redirectUri).toBe(KEEPLING_REDIRECT_URI)
    // The challenge the browser was sent is exactly S256 of the verifier the
    // exchange used -- proving no second, unrelated verifier was generated.
    expect(s256(recorded?.codeVerifier ?? '')).toBe(
      new URL(started.authorizationUrl).searchParams.get('code_challenge'),
    )

    expect(JSON.parse(credentials.current() ?? '{}')).toEqual({
      accessToken: 'access-token-one',
      namespace: mappedNamespace,
      refreshToken: 'refresh-token-one',
    })
    await expect(authorization.accessToken()).resolves.toBe('access-token-one')
  })

  it('never reuses a verifier or a state across authorizations', async () => {
    const { authorization, exchange } = build()

    const first = await authorization.begin()
    const firstState = new URL(first.authorizationUrl).searchParams.get('state')
    const second = await authorization.begin()
    const secondState = new URL(second.authorizationUrl).searchParams.get('state')

    expect(firstState).not.toBe(secondState)
    expect(new URL(first.authorizationUrl).searchParams.get('code_challenge')).not.toBe(
      new URL(second.authorizationUrl).searchParams.get('code_challenge'),
    )

    // Only ONE authorization is ever in flight: the superseded first state is
    // no longer accepted.
    const stale = await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(firstState ?? '')}`,
    )
    expect(stale).toEqual({ kind: 'rejected', reason: 'state_mismatch' })
    expect(exchange.exchanges).toHaveLength(0)

    await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(secondState ?? '')}`,
    )
    expect(exchange.exchanges).toHaveLength(1)
  })

  it.each([
    ['a state that was never issued', (state: string) => `${KEEPLING_REDIRECT_URI}?code=c&state=${state}forged`, 'state_mismatch'],
    ['a callback with no state at all', () => `${KEEPLING_REDIRECT_URI}?code=c`, 'state_mismatch'],
    ['a callback with no code', (state: string) => `${KEEPLING_REDIRECT_URI}?state=${state}`, 'missing_code'],
    ['a callback on a foreign scheme', (state: string) => `https://phishing.invalid/auth/callback?code=c&state=${state}`, 'unknown_callback'],
    ['a callback on a foreign keepling path', (state: string) => `keepling://auth/other?code=c&state=${state}`, 'unknown_callback'],
    ['an unparseable callback', () => 'not a url at all', 'unknown_callback'],
  ])('rejects %s without mutating stored credentials', async (_label, callback, reason) => {
    const { authorization, credentials, exchange } = build()
    await credentials.adapter.store('pre-existing-credential')
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''

    const outcome = await authorization.handleCallback(callback(state))

    expect(outcome).toEqual({ kind: 'rejected', reason })
    expect(exchange.exchanges).toHaveLength(0)
    expect(credentials.current()).toBe('pre-existing-credential')
    expect(credentials.writes).toEqual(['pre-existing-credential'])
  })

  it('rejects an unsolicited callback that arrives with no authorization in flight', async () => {
    const { authorization, credentials, exchange } = build()
    await credentials.adapter.store('pre-existing-credential')

    const outcome = await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${'a'.repeat(43)}`,
    )

    expect(outcome).toEqual({ kind: 'rejected', reason: 'no_authorization_in_flight' })
    expect(exchange.exchanges).toHaveLength(0)
    expect(credentials.current()).toBe('pre-existing-credential')
  })

  it('rejects a replayed callback after a successful exchange', async () => {
    const { authorization, exchange } = build()
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''
    const callback = `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`

    await expect(authorization.handleCallback(callback)).resolves.toEqual({
      kind: 'authorized',
      namespace: mappedNamespace,
    })
    await expect(authorization.handleCallback(callback)).resolves.toEqual({
      kind: 'rejected',
      reason: 'no_authorization_in_flight',
    })
    expect(exchange.exchanges).toHaveLength(1)
  })

  it('rejects a callback that arrives after the authorization request expired', async () => {
    let now = 1_800_000_000_000
    const { authorization, credentials, exchange } = build({ now: () => now })
    await credentials.adapter.store('pre-existing-credential')
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''

    now += 11 * 60 * 1_000

    await expect(
      authorization.handleCallback(`${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`),
    ).resolves.toEqual({ kind: 'rejected', reason: 'authorization_expired' })
    expect(exchange.exchanges).toHaveLength(0)
    expect(credentials.current()).toBe('pre-existing-credential')
  })

  it('leaves prior credentials intact when the token exchange fails', async () => {
    const exchange = stubExchange({
      exchangeAuthorizationCode: async () => {
        throw new Error('invalid_authorization_code')
      },
    })
    const { authorization, credentials } = build({ exchange })
    await credentials.adapter.store('pre-existing-credential')

    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''

    await expect(
      authorization.handleCallback(`${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`),
    ).resolves.toEqual({ kind: 'failed', reason: 'invalid_authorization_code' })
    expect(credentials.current()).toBe('pre-existing-credential')

    // The authorization code is single-use server-side, so a failed exchange
    // ends the in-flight request rather than inviting a retry of dead input.
    expect(authorization.hasAuthorizationInFlight()).toBe(false)
  })

  it('never lets a client-supplied namespace reach storage', async () => {
    const { authorization, credentials } = build()
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''

    await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}` +
        '&issuer=https%3A%2F%2Fattacker.invalid&generation=999&account_subject=someone-else',
    )

    expect(JSON.parse(credentials.current() ?? '{}').namespace).toEqual(mappedNamespace)
  })

  it('rotates the refresh token and stores the server namespace verbatim', async () => {
    const { authorization, credentials, exchange } = build()
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''
    await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`,
    )

    await expect(authorization.refresh()).resolves.toEqual({
      kind: 'authorized',
      namespace: mappedNamespace,
    })
    expect(exchange.refreshed).toEqual(['refresh-token-one'])
    expect(JSON.parse(credentials.current() ?? '{}')).toEqual({
      accessToken: 'access-token-two',
      namespace: mappedNamespace,
      refreshToken: 'refresh-token-two',
    })
  })

  it('surfaces a detected refresh replay as authentication expiry and clears the credential', async () => {
    const exchange = stubExchange({
      refresh: async () => {
        throw new Error('refresh_replay_detected')
      },
    })
    const { authorization, credentials } = build({ exchange })
    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''
    await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`,
    )

    await expect(authorization.refresh()).resolves.toEqual({
      kind: 'failed',
      reason: 'refresh_replay_detected',
    })
    expect(credentials.current()).toBeNull()
    await expect(authorization.accessToken()).resolves.toBeNull()
  })

  it('reports no access token when nothing was ever stored, and after clear()', async () => {
    const { authorization, credentials } = build()
    await expect(authorization.accessToken()).resolves.toBeNull()

    const started = await authorization.begin()
    const state = new URL(started.authorizationUrl).searchParams.get('state') ?? ''
    await authorization.handleCallback(
      `${KEEPLING_REDIRECT_URI}?code=code&state=${encodeURIComponent(state)}`,
    )
    await expect(authorization.accessToken()).resolves.toBe('access-token-one')

    await authorization.clear()
    expect(credentials.current()).toBeNull()
    await expect(authorization.accessToken()).resolves.toBeNull()
  })

  it('treats an unreadable stored credential as signed out rather than throwing', async () => {
    const credentials = stubCredentials()
    await credentials.adapter.store('{ not json')
    const { authorization } = build({ credentials })

    await expect(authorization.accessToken()).resolves.toBeNull()
    await expect(authorization.loadCredentials()).resolves.toBeNull()
  })
})

describe('durable desktop server configuration', () => {
  it('accepts https and loopback origins only', () => {
    expect(assertAllowedServerUrl('https://keepling.example.com')).toBe('https://keepling.example.com/')
    expect(assertAllowedServerUrl('http://127.0.0.1:4000')).toBe('http://127.0.0.1:4000/')
    expect(assertAllowedServerUrl('http://localhost:4000/')).toBe('http://localhost:4000/')

    for (const rejected of [
      'http://keepling.example.com',
      'ftp://keepling.example.com',
      'keepling://auth/callback',
      'not a url',
      '',
    ]) {
      expect(() => assertAllowedServerUrl(rejected)).toThrow(/Keepling server/)
    }
  })

  it('persists the selected server durably and rejects a tampered or disallowed stored value', async () => {
    let file: string | null = null
    const configuration = new FileServerConfiguration({
      filePath: '/unused',
      read: async () => file,
      remove: async () => {
        file = null
      },
      write: async (_path, value) => {
        file = value
      },
    })

    await expect(configuration.load()).resolves.toBeNull()
    await expect(configuration.save('https://keepling.example.com')).resolves.toBe(
      'https://keepling.example.com/',
    )
    await expect(configuration.load()).resolves.toBe('https://keepling.example.com/')

    await expect(configuration.save('http://keepling.example.com')).rejects.toThrow(/Keepling server/)
    expect(file).toBe(JSON.stringify({ baseUrl: 'https://keepling.example.com/' }))

    file = JSON.stringify({ baseUrl: 'http://keepling.example.com' })
    await expect(configuration.load()).resolves.toBeNull()

    file = 'not json'
    await expect(configuration.load()).resolves.toBeNull()

    file = JSON.stringify({ baseUrl: 'https://keepling.example.com/' })
    await configuration.clear()
    expect(file).toBeNull()
  })
})
