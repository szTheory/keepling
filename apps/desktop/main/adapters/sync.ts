import { createHash } from 'node:crypto'

import type { components } from '../../../../packages/contracts/generated/keepling.ts'
import type {
  PullPage,
  SyncAcknowledgement,
  SyncNamespace,
  SyncPort,
  SyncSnapshot,
  SyncUndoAvailability,
} from '../application/DesktopApplication.ts'
import {
  SYNC_FAILURE_AUTHENTICATION_REQUIRED,
  SyncUnreachableError,
} from '../application/sync-reachability.ts'
import { classifyServerRefusal, type ServerRefusal } from './server-refusal.ts'

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

/**
 * A refusal the server ANSWERED with (O-38). The `message` stays the problem
 * code, exactly as before, so every existing caller and test that reads it
 * keeps working; the structured fields are additive and are what lets `push`
 * tell a decided command from a transport failure.
 */
class SyncRefusedError extends Error {
  readonly problem: unknown
  readonly status: number
  /** Set only for a 401, so the application can publish its own row without sniffing status codes. */
  readonly syncFailure: string | undefined

  constructor(code: string, status: number, problem: unknown) {
    super(code)
    this.name = 'SyncRefusedError'
    this.problem = problem
    this.status = status
    this.syncFailure = status === 401 ? SYNC_FAILURE_AUTHENTICATION_REQUIRED : undefined
  }
}

/**
 * O-38: turns a refusal the server ANSWERED with into the settled outcome it
 * is, or `null` when the caller must keep throwing.
 *
 * The snapshot carried on a conflict is built from the SERVER's own conflict
 * extension and from nothing else -- the client never derives what the
 * server currently holds. `already_satisfied` and `accepted` still come from
 * a 200 body through `mapAcknowledgement`, which stays strict: a 200 that
 * claimed `conflict` would be an invalid acknowledgement and must still be
 * refused loudly.
 */
const settleClassified = (
  refusal: ServerRefusal | null,
  identity: { fingerprint: string; mutationId: string; taskId: string | null },
): SyncAcknowledgement | null => {
  if (refusal === null || refusal.kind === 'authentication_required') return null
  // A conflict snapshot is a TASK snapshot and needs the identity it belongs
  // to; a rejection carries no task state at all and the store never reads
  // its snapshot beyond journalling it. `taskId` is absent only for an undo
  // (O-45), whose `UndoTaskCommand` publishes no `task_id` -- and which the
  // server answers with a no-change, never a 409.
  if (identity.taskId === null && refusal.kind === 'conflict') return null
  if (refusal.kind === 'rejected') {
    return {
      fingerprint: identity.fingerprint,
      mutationId: identity.mutationId,
      outcome: 'rejected',
      snapshot: { id: identity.taskId ?? '', rejection_code: refusal.code },
    }
  }
  return {
    fingerprint: identity.fingerprint,
    mutationId: identity.mutationId,
    outcome: 'conflict',
    snapshot: {
      affected_fields: refusal.affectedFields,
      conflict_id: refusal.conflictId,
      id: identity.taskId as string,
      ...(refusal.latestRevision === null ? {} : { revision: refusal.latestRevision }),
      ...(refusal.currentTitle === null ? {} : { title: refusal.currentTitle }),
    },
  }
}

const settleRefusal = (
  error: unknown,
  identity: { fingerprint: string; mutationId: string; taskId: string | null },
): SyncAcknowledgement | null =>
  error instanceof SyncRefusedError ? settleClassified(classifyServerRefusal(error.status, error.problem), identity) : null

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

/**
 * O-45: the SERVER-ISSUED undo capability, read from the acknowledgement and
 * from nothing else.
 *
 * `CommandAcknowledgement.undo` is a `UndoAvailability`: exactly
 * `expires_at`, `handle` and `label`, where the handle is an opaque
 * account-bound one-shot capability of 43..128 URL-safe base64 characters.
 * It is present only when the accepted command was one the server can
 * compensate (`Undo.@supported_commands` -- notably NOT `capture_task`).
 *
 * A MALFORMED `undo` block throws, exactly as a 200 claiming `conflict`
 * does. Retaining a handle whose shape the contract does not publish would
 * durably queue a body the server answers 400 `invalid_command` to, and
 * repairing one would be synthesising a capability -- the single thing this
 * client must never do with a credential it did not mint.
 */
const mapUndoAvailability = (value: unknown): SyncUndoAvailability => {
  const undo = exactObject(value, ['expires_at', 'handle', 'label'], 'undo availability')
  const handle = requiredString(undo.handle, 'undo availability handle')
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(handle)) throw new Error('undo availability handle is invalid')
  return {
    expiresAt: requiredString(undo.expires_at, 'undo availability expiry'),
    handle,
    label: requiredString(undo.label, 'undo availability label'),
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
    ...(acknowledgement.undo === undefined || acknowledgement.undo === null
      ? {}
      : { undo: mapUndoAvailability(acknowledgement.undo) }),
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

  /**
   * `context.taskId` exists for exactly one command (O-45): `UndoTaskCommand`
   * publishes no `task_id`, because the server resolves the task from the
   * handle it minted. The caller supplies the task this Mac queued the undo
   * AGAINST, which is its own local routing key -- never a claim about
   * server state -- so a refused undo can still be journalled against the
   * row it belongs to.
   */
  async push(commandBytes: string, context?: { taskId: string }): Promise<SyncAcknowledgement | null> {
    const command = JSON.parse(commandBytes) as Record<string, unknown>
    const mutationId = requiredString(command.mutation_id, 'command mutation identity')
    const commandType = requiredString(command.type, 'command type').replaceAll('_', '-')
    const fingerprint = createHash('sha256').update(commandBytes).digest('hex')
    const taskId = typeof command.task_id === 'string' ? command.task_id : context?.taskId ?? null
    let response: unknown
    try {
      response = await this.#json(this.#url(`/api/v1/commands/${encodeURIComponent(commandType)}`), {
        body: commandBytes,
        method: 'POST',
      }, true)
    } catch (error) {
      // O-38: a 409 conflict and a 422 semantic refusal are DECISIONS about
      // this command, not transport failures. Before this they threw, were
      // caught by `runSyncPass`, and landed on "Couldn't reach the server"
      // with a Retry button that would retry the same immutable bytes
      // forever. Anything not classified here still throws.
      const settled = settleRefusal(error, { fingerprint, mutationId, taskId })
      if (settled === null) throw error
      return settled
    }
    // O-45. `POST /commands/undo-task` answers a no-change with HTTP **200**
    // and an `UndoNoChange` body (404 only for `unknown`), so this is the
    // one settled refusal that does not arrive as a thrown non-OK status.
    // The classification is the SAME closed list, through the same function
    // -- not a parallel branch. An ordinary acknowledgement has no `code`
    // and classifies as null, so this cannot swallow one.
    const settledNoChange = settleClassified(classifyServerRefusal(200, response), { fingerprint, mutationId, taskId })
    if (settledNoChange !== null) return settledNoChange
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
        // O-38: the STATUS and the whole problem body travel with the error.
        // Without them a 409 conflict is indistinguishable from a 500 at the
        // call site, and both landed on the retryable-failure row -- so a
        // decided command was retried forever and its conflict was never
        // told to anyone.
        throw new SyncRefusedError(
          typeof problem.code === 'string' ? problem.code : `server_${response.status}`,
          response.status,
          value,
        )
      }
      return value
    } finally {
      clearTimeout(timeout)
    }
  }
}

export { KeeplingSyncAdapter, SyncRefusedError, mapNamespace, mapTokenResponse, mapUndoAvailability, settleRefusal }
export type { AuthorizationCodeExchange, KeeplingSyncAdapterOptions, NativeCredentials }
