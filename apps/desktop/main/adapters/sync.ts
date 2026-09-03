import { createHash } from 'node:crypto'

import type { components } from '../../../../packages/contracts/generated/keepling.ts'
import type {
  PullPage,
  SyncAcknowledgement,
  SyncNamespace,
  SyncPort,
  SyncSnapshot,
} from '../application/DesktopApplication.ts'
import { SyncUnreachableError } from '../application/sync-reachability.ts'

type NativeTokenResponse = components['schemas']['NativeTokenResponse']
type SyncFeedPage = components['schemas']['SyncFeedPage']

type Fetch = (input: string | URL, init?: RequestInit) => Promise<Response>

type KeeplingSyncAdapterOptions = {
  accessToken: () => Promise<string | null> | string | null
  baseUrl: string
  fetch?: Fetch
  timeoutMs?: number
}

type AuthorizationCodeExchange = {
  code: string
  codeVerifier: string
  redirectUri: string
  state: string
}

type NativeCredentials = {
  accessToken: string
  expiresIn: 900
  namespace: SyncNamespace
  refreshToken: string
}

const exactObject = (value: unknown, keys: readonly string[], label: string): Record<string, unknown> => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error(`${label} is invalid`)
  const object = value as Record<string, unknown>
  if (Object.keys(object).some((key) => !keys.includes(key))) throw new Error(`${label} has unknown fields`)
  return object
}

const requiredString = (value: unknown, label: string): string => {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`${label} is invalid`)
  return value
}

const mapNamespace = (value: unknown): SyncNamespace => {
  const namespace = exactObject(
    value,
    ['account_subject', 'generation', 'issuer', 'origin', 'server_instance'],
    'native synchronization namespace',
  )
  if (!Number.isInteger(namespace.generation) || Number(namespace.generation) < 1) {
    throw new Error('native synchronization namespace generation is invalid')
  }
  return {
    accountSubject: requiredString(namespace.account_subject, 'namespace account subject'),
    generation: String(namespace.generation),
    issuer: requiredString(namespace.issuer, 'namespace issuer'),
    origin: requiredString(namespace.origin, 'namespace origin'),
    serverInstance: requiredString(namespace.server_instance, 'namespace server instance'),
  }
}

const mapTokenResponse = (value: unknown): NativeCredentials => {
  const token = exactObject(
    value,
    ['access_token', 'expires_in', 'namespace', 'refresh_token', 'token_type'],
    'native token response',
  )
  if (token.expires_in !== 900 || token.token_type !== 'Bearer') throw new Error('native token response is invalid')
  return {
    accessToken: requiredString(token.access_token, 'access token'),
    expiresIn: 900,
    namespace: mapNamespace(token.namespace),
    refreshToken: requiredString(token.refresh_token, 'refresh token'),
  }
}

const mapAcknowledgement = (
  value: unknown,
  expectedFingerprint: string,
): SyncAcknowledgement => {
  const acknowledgement = value as Record<string, unknown>
  const snapshot = acknowledgement.snapshot as SyncSnapshot | undefined
  if (
    typeof acknowledgement.mutation_id !== 'string' ||
    (acknowledgement.outcome !== 'accepted' && acknowledgement.outcome !== 'already_satisfied') ||
    !snapshot || typeof snapshot.id !== 'string'
  ) throw new Error('server acknowledgement is invalid')
  return {
    fingerprint: expectedFingerprint,
    mutationId: acknowledgement.mutation_id,
    outcome: acknowledgement.outcome,
    snapshot,
  }
}

class KeeplingSyncAdapter implements SyncPort {
  readonly #accessToken: KeeplingSyncAdapterOptions['accessToken']
  readonly #baseUrl: URL
  readonly #fetch: Fetch
  readonly #timeoutMs: number

  constructor(options: KeeplingSyncAdapterOptions) {
    const baseUrl = new URL(options.baseUrl)
    if (baseUrl.protocol !== 'https:' && baseUrl.hostname !== '127.0.0.1' && baseUrl.hostname !== 'localhost') {
      throw new Error('Keepling server must use HTTPS')
    }
    this.#baseUrl = baseUrl
    this.#accessToken = options.accessToken
    this.#fetch = options.fetch ?? globalThis.fetch
    this.#timeoutMs = options.timeoutMs ?? 15_000
  }

  async compatibility(minimum: number, maximum: number): Promise<unknown> {
    const url = this.#url('/compatibility')
    url.searchParams.set('minimum_protocol_train', String(minimum))
    url.searchParams.set('maximum_protocol_train', String(maximum))
    return this.#json(url, { method: 'GET' }, false)
  }

  async exchangeAuthorizationCode(exchange: AuthorizationCodeExchange): Promise<NativeCredentials> {
    const response: NativeTokenResponse = await this.#json(this.#url('/oauth/token'), {
      body: JSON.stringify({
        code: exchange.code,
        code_verifier: exchange.codeVerifier,
        grant_type: 'authorization_code',
        redirect_uri: exchange.redirectUri,
        state: exchange.state,
      }),
      method: 'POST',
    }, false) as NativeTokenResponse
    return mapTokenResponse(response)
  }

  async refresh(refreshToken: string): Promise<NativeCredentials> {
    return mapTokenResponse(await this.#json(this.#url('/oauth/token/refresh'), {
      body: JSON.stringify({ grant_type: 'refresh_token', refresh_token: refreshToken }),
      method: 'POST',
    }, false))
  }

  async pull(cursor: string | null, limit: 50): Promise<PullPage> {
    const url = this.#url('/api/v1/sync')
    url.searchParams.set('limit', String(limit))
    if (cursor) url.searchParams.set('cursor', cursor)
    const page = await this.#json(url, { method: 'GET' }, true) as SyncFeedPage
    const changes = page.changes.flatMap((change) => {
      if (
        change.entity_id === null ||
        (change.kind !== 'task_snapshot' && change.kind !== 'organization_snapshot') ||
        typeof change.payload !== 'object' || change.payload === null || !('id' in change.payload)
      ) return []
      return [{ entityId: change.entity_id, snapshot: change.payload as SyncSnapshot }]
    })
    return { changes, cursor: page.coverage_cursor ?? cursor }
  }

  async bootstrap(cursor: string | null): Promise<unknown> {
    const url = this.#url('/api/v1/sync/bootstrap')
    url.searchParams.set('limit', '50')
    if (cursor) url.searchParams.set('cursor', cursor)
    return this.#json(url, { method: 'GET' }, true)
  }

  async push(commandBytes: string): Promise<SyncAcknowledgement | null> {
    const command = JSON.parse(commandBytes) as Record<string, unknown>
    const mutationId = requiredString(command.mutation_id, 'command mutation identity')
    const commandType = requiredString(command.type, 'command type').replaceAll('_', '-')
    const response = await this.#json(this.#url(`/api/v1/commands/${encodeURIComponent(commandType)}`), {
      body: commandBytes,
      method: 'POST',
    }, true)
    const fingerprint = createHash('sha256').update(commandBytes).digest('hex')
    const acknowledgement = mapAcknowledgement(response, fingerprint)
    if (acknowledgement.mutationId !== mutationId) throw new Error('server acknowledgement mutation mismatch')
    return acknowledgement
  }

  async lookup(mutationId: string, fingerprint: string): Promise<SyncAcknowledgement> {
    const response = await this.#json(
      this.#url(`/api/v1/mutations/${encodeURIComponent(mutationId)}`),
      { method: 'GET' },
      true,
    )
    const acknowledgement = mapAcknowledgement(response, fingerprint)
    if (acknowledgement.mutationId !== mutationId) throw new Error('mutation lookup identity mismatch')
    return acknowledgement
  }

  async revoke(installationId: string): Promise<void> {
    await this.#json(this.#url(`/api/v1/device-grants/${encodeURIComponent(installationId)}`), { method: 'DELETE' }, true)
  }

  #url(path: string): URL {
    return new URL(path, this.#baseUrl)
  }

  async #json(url: URL, init: RequestInit, authenticated: boolean): Promise<unknown> {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), this.#timeoutMs)
    try {
      const headers = new Headers(init.headers)
      headers.set('accept', 'application/json, application/problem+json')
      if (init.body) headers.set('content-type', 'application/json')
      if (authenticated) {
        const accessToken = await this.#accessToken()
        if (!accessToken) throw new Error('authentication_required')
        headers.set('authorization', `Bearer ${accessToken}`)
      }
      // O-30: THIS is the only line that can tell "unreachable" from
      // "rejected", because it is the only place that knows whether any
      // bytes came back. `fetch` rejects for DNS failure, connection
      // refused, TLS failure, and the abort above firing on timeout -- in
      // every one of those the request never got an answer, which is
      // exactly what the `offline` row means.
      let response: Response
      try {
        response = await this.#fetch(url, { ...init, headers, signal: controller.signal })
      } catch (error) {
        throw new SyncUnreachableError('the Keepling server could not be reached', { cause: error })
      }
      // Everything below this line ran because the server ANSWERED. A
      // malformed body or a non-OK status is a rejected answer, not an
      // absent one, and must keep landing on the retryable-failure row.
      const value = await response.json()
      if (!response.ok) {
        const problem = value as { code?: unknown }
        throw new Error(typeof problem.code === 'string' ? problem.code : `server_${response.status}`)
      }
      return value
    } finally {
      clearTimeout(timeout)
    }
  }
}

export { KeeplingSyncAdapter, mapNamespace, mapTokenResponse }
export type { AuthorizationCodeExchange, KeeplingSyncAdapterOptions, NativeCredentials }
