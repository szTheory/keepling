/**
 * RENAMED from `real-stack-sync.spec.ts` (O-34). It never had a real stack:
 * every adapter below is constructed against an in-process fixture server
 * and a stubbed `fetch` pointed at the deliberately non-resolving host
 * `server.keepling.invalid`. The old name was enough to get MAC-03 checked
 * on a false citation, and hours later unchecked again once someone read the
 * file instead of trusting its title.
 *
 * It is kept, not deleted, because what it actually does is valuable and is
 * NOT covered by the real-stack lane: PKCE with exact state matching, an
 * unsolicited callback from a competing app, single-use authorization codes,
 * refresh rotation, server-detected refresh replay, sign-out fencing order,
 * and a hostile server answering with someone else's mutation identity.
 * Several of those are hard or impossible to induce against an honest real
 * server, which is exactly what a contract-faithful fixture is for.
 *
 * The real-server claim lives in `test/real-stack/real-stack-sync.spec.ts`.
 */

import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { expect, test } from '@playwright/test'

import { BrowserDelegatedAuthorization, KEEPLING_REDIRECT_URI } from '../../main/adapters/auth.ts'
import { KeeplingSyncAdapter } from '../../main/adapters/sync.ts'
import { SafeStorageCredentialAdapter } from '../../main/adapters/credentials.ts'
import { DesktopApplication, type LocalStorePort } from '../../main/application/DesktopApplication.ts'
import { NodeSqliteLocalStore } from '../../store-worker/local-store.ts'

const credential = 'a'.repeat(43)
const namespace = {
  account_subject: 'e5b18471-bb3b-43cf-ae39-a71b84ad4dc28',
  generation: 1,
  issuer: 'https://issuer.keepling.invalid',
  origin: 'https://server.keepling.invalid',
  server_instance: 'server-instance-transport',
}

test('uses released operations, exact receipts, and only server-derived namespace authority', async () => {
  const requests: Array<{ body?: string; method: string; url: string }> = []
  const commandBytes = JSON.stringify({
    mutation_id: '11111111-1111-4111-8111-111111111111',
    task_id: '22222222-2222-4222-8222-222222222222',
    title: 'Exact local intent',
    type: 'capture_task',
    version: 1,
  })
  const adapter = new KeeplingSyncAdapter({
    accessToken: () => credential,
    baseUrl: 'https://server.keepling.invalid',
    fetch: async (url, init) => {
      requests.push({ body: typeof init?.body === 'string' ? init.body : undefined, method: init?.method ?? 'GET', url: String(url) })
      if (String(url).includes('/compatibility')) return Response.json({ compatibility_state: 'supported', selected_protocol_train: 1 })
      if (String(url).endsWith('/oauth/token')) return Response.json({
        access_token: credential,
        expires_in: 900,
        namespace,
        refresh_token: 'b'.repeat(43),
        token_type: 'Bearer',
      })
      if (String(url).includes('/sync?')) return Response.json({ changes: [], coverage_cursor: 'cursor-one', has_more: false })
      if (String(url).includes('/mutations/')) return Response.json({
        mutation_id: '11111111-1111-4111-8111-111111111111',
        outcome: 'accepted',
        revision: 1,
        snapshot: { id: '22222222-2222-4222-8222-222222222222', revision: 1, title: 'Exact local intent' },
        task_id: '22222222-2222-4222-8222-222222222222',
        undo: null,
        warnings: [],
      })
      return Response.json({
        mutation_id: '11111111-1111-4111-8111-111111111111',
        outcome: 'accepted',
        revision: 1,
        snapshot: { id: '22222222-2222-4222-8222-222222222222', revision: 1, title: 'Exact local intent' },
        task_id: '22222222-2222-4222-8222-222222222222',
        undo: null,
        warnings: [],
      }, { status: 201 })
    },
  })

  const tokens = await adapter.exchangeAuthorizationCode({
    code: 'code', codeVerifier: 'v'.repeat(64), redirectUri: 'keepling://authorization/callback', state: 's'.repeat(43),
  })
  await adapter.compatibility(1, 1)
  await adapter.pull(null, 50)
  const acknowledgement = await adapter.push(commandBytes)
  const replay = await adapter.lookup('11111111-1111-4111-8111-111111111111', createHash('sha256').update(commandBytes).digest('hex'))

  expect(tokens.namespace).toEqual({
    accountSubject: namespace.account_subject,
    generation: '1',
    issuer: namespace.issuer,
    origin: namespace.origin,
    serverInstance: namespace.server_instance,
  })
  expect(acknowledgement).toEqual(replay)
  expect(requests.map(({ method, url }) => `${method} ${new URL(url).pathname}`)).toEqual([
    'POST /oauth/token', 'GET /compatibility', 'GET /api/v1/sync', 'POST /api/v1/commands/capture-task', 'GET /api/v1/mutations/11111111-1111-4111-8111-111111111111',
  ])
  expect(requests[3]?.body).toBe(commandBytes)
})

test('encrypts credentials asynchronously and persists only ciphertext', async () => {
  const written: Buffer[] = []
  const adapter = new SafeStorageCredentialAdapter({
    filePath: join(tmpdir(), `keepling-credentials-${process.pid}`),
    read: async () => written.at(-1) ?? null,
    remove: async () => { written.length = 0 },
    safeStorage: {
      decryptStringAsync: async (encrypted) => ({ result: encrypted.toString('utf8').replace('cipher:', ''), shouldReEncrypt: false }),
      encryptStringAsync: async (value) => Buffer.from(`cipher:${value}`),
      isAsyncEncryptionAvailable: async () => true,
    },
    write: async (_path, encrypted) => { written.push(encrypted) },
  })

  await adapter.store(credential)
  expect(written[0]?.toString('utf8')).toBe(`cipher:${credential}`)
  await expect(adapter.load()).resolves.toBe(credential)
  expect(adapter.settingsDisclosure()).toEqual({
    copy: 'This unsigned dogfood build may not keep sign-in through an app replacement. Your tasks and pending changes remain saved on this Mac.',
    kind: 'unsigned_dogfood',
  })
  await adapter.clear()
  await expect(adapter.load()).resolves.toBeNull()
})

test('fences the active namespace before best-effort remote revocation', async () => {
  const events: string[] = []
  const localStore = {
    acceptCapture: async () => { throw new Error('unused') },
    acknowledge: async () => ({ tasks: [] }),
    close: async () => undefined,
    pendingMutations: async () => [],
    setSyncFence: async (reason: string | null) => { events.push(`fence:${reason}`) },
    snapshot: async () => ({ tasks: [] }),
  } satisfies LocalStorePort
  const application = new DesktopApplication({
    clock: { now: () => '2026-09-02T12:00:00.000Z' },
    credentials: {
      clear: async () => { events.push('credentials:clear') },
      load: async () => credential,
      store: async () => undefined,
    },
    identity: { randomId: () => 'unused' },
    localStore,
    sync: {},
  })

  await application.signOut(async () => { events.push('remote:revoke'); throw new Error('offline') })

  expect(events).toEqual(['fence:signed_out', 'credentials:clear', 'remote:revoke'])
})

/**
 * O-16 closure proof: the WHOLE acquire-then-synchronize loop, driven end to
 * end against a fixture server that enforces the SAME rules the real
 * `Keepling.Accounts.DeviceGrant` enforces -- exact redirect allowlisting,
 * unpredictable 32-byte state, PKCE S256 verification, single-use
 * authorization codes, refresh rotation with replay detection, and exact
 * mutation receipts.
 *
 * Authorization is driven through an INJECTED browser-open seam: the test
 * captures the URL the app would have handed to the system browser, drives
 * the fixture server's authorize endpoint itself, and feeds the resulting
 * `keepling://auth/callback` back in. No real browser is launched, and the
 * app never sees a credential -- exactly the shipped shape.
 *
 * The local side is the REAL `NodeSqliteLocalStore` on a real SQLite file,
 * so "Synced" is only reachable through the real projection/outbox tables.
 */

const migrationPath = fileURLToPath(new URL('../../migrations/0001_initial.sql', import.meta.url))
const loopRoots: string[] = []

test.afterEach(() => {
  for (const root of loopRoots.splice(0)) rmSync(root, { force: true, recursive: true })
})

const ALLOWED_REDIRECT_URIS: Record<string, readonly string[]> = {
  electron: [KEEPLING_REDIRECT_URI],
  iphone: [KEEPLING_REDIRECT_URI],
}
const SERVER_NAMESPACE = {
  account_subject: 'c0ffee00-1111-4222-8333-444455556666',
  generation: 2,
  issuer: 'https://issuer.keepling.invalid',
  origin: 'https://server.keepling.invalid',
  server_instance: 'server-instance-loop',
}

type FixtureServer = {
  authorizeInBrowser(authorizeUrl: string): string
  commandBodies: string[]
  fetch: (input: string | URL, init?: RequestInit) => Promise<Response>
  revoked: string[]
  setOffline(offline: boolean): void
}

const createFixtureServer = (): FixtureServer => {
  let offline = false
  let issuedCode: { challenge: string; redirectUri: string; state: string; used: boolean } | null = null
  let accessToken: string | null = null
  let refreshToken: string | null = null
  const spentRefreshTokens = new Set<string>()
  let familyRevoked = false
  const journal = new Map<string, { bytes: string; taskId: string }>()
  const commandBodies: string[] = []
  const revoked: string[] = []

  const problem = (code: string, status: number) => Response.json({ code }, { status })

  return {
    // The "system browser" half: exactly what the server's
    // `/oauth/authorize` does before redirecting back.
    authorizeInBrowser(authorizeUrl) {
      const url = new URL(authorizeUrl)
      const parameters = url.searchParams
      if (url.pathname !== '/oauth/authorize') throw new Error('unexpected authorization endpoint')
      const clientId = parameters.get('client_id') ?? ''
      const redirectUri = parameters.get('redirect_uri') ?? ''
      if (!(ALLOWED_REDIRECT_URIS[clientId] ?? []).includes(redirectUri)) {
        throw new Error('invalid_authorization_request: redirect_uri is not allowlisted')
      }
      if (parameters.get('response_type') !== 'code') throw new Error('invalid_authorization_request')
      if (parameters.get('code_challenge_method') !== 'S256') throw new Error('invalid_authorization_request')
      const state = parameters.get('state') ?? ''
      if (Buffer.from(state, 'base64url').byteLength < 32) throw new Error('state is not unpredictable')
      const challenge = parameters.get('code_challenge') ?? ''
      if (Buffer.from(challenge, 'base64url').byteLength !== 32) throw new Error('malformed code_challenge')
      issuedCode = { challenge, redirectUri, state, used: false }
      return `${redirectUri}?code=authorization-code-one&state=${encodeURIComponent(state)}`
    },
    commandBodies,
    async fetch(input, init) {
      if (offline) throw new TypeError('fetch failed')
      const url = new URL(String(input))
      const method = init?.method ?? 'GET'
      const body = typeof init?.body === 'string' ? (JSON.parse(init.body) as Record<string, unknown>) : {}
      const authorized = (init?.headers as Headers | undefined)?.get('authorization') === `Bearer ${accessToken}`

      if (url.pathname === '/oauth/token' && method === 'POST') {
        if (
          issuedCode === null || issuedCode.used
          || body.code !== 'authorization-code-one'
          || body.redirect_uri !== issuedCode.redirectUri
          || body.state !== issuedCode.state
          || createHash('sha256').update(String(body.code_verifier)).digest('base64url') !== issuedCode.challenge
        ) return problem('invalid_authorization_code', 401)
        issuedCode.used = true
        accessToken = 'access-one'
        refreshToken = 'refresh-one'
        return Response.json({
          access_token: accessToken, expires_in: 900, namespace: SERVER_NAMESPACE,
          refresh_token: refreshToken, token_type: 'Bearer',
        })
      }

      if (url.pathname === '/oauth/token/refresh' && method === 'POST') {
        const presented = String(body.refresh_token)
        if (familyRevoked) return problem('invalid_grant', 401)
        if (spentRefreshTokens.has(presented)) {
          // Replay detection revokes the whole family, as device_grant.ex does.
          familyRevoked = true
          accessToken = null
          return problem('refresh_replay_detected', 401)
        }
        if (presented !== refreshToken) return problem('invalid_grant', 401)
        spentRefreshTokens.add(presented)
        accessToken = 'access-two'
        refreshToken = 'refresh-two'
        return Response.json({
          access_token: accessToken, expires_in: 900, namespace: SERVER_NAMESPACE,
          refresh_token: refreshToken, token_type: 'Bearer',
        })
      }

      if (!authorized) return problem('authentication_required', 401)

      if (url.pathname === '/api/v1/sync') {
        return Response.json({ changes: [], coverage_cursor: 'cursor-loop-1', has_more: false })
      }

      if (url.pathname.startsWith('/api/v1/commands/')) {
        const bytes = String(init?.body)
        commandBodies.push(bytes)
        const command = JSON.parse(bytes) as { mutation_id: string; task_id: string; title: string }
        journal.set(command.mutation_id, { bytes, taskId: command.task_id })
        return Response.json({
          mutation_id: command.mutation_id, outcome: 'accepted', revision: 1,
          snapshot: { id: command.task_id, revision: 1, title: command.title },
          task_id: command.task_id, undo: null, warnings: [],
        }, { status: 201 })
      }

      if (url.pathname.startsWith('/api/v1/mutations/')) {
        const mutationId = decodeURIComponent(url.pathname.split('/').pop() ?? '')
        const recorded = journal.get(mutationId)
        if (recorded === undefined) return problem('mutation_not_found', 404)
        const command = JSON.parse(recorded.bytes) as { title: string }
        return Response.json({
          mutation_id: mutationId, outcome: 'accepted', revision: 1,
          snapshot: { id: recorded.taskId, revision: 1, title: command.title },
          task_id: recorded.taskId, undo: null, warnings: [],
        })
      }

      if (url.pathname.startsWith('/api/v1/device-grants/') && method === 'DELETE') {
        revoked.push(decodeURIComponent(url.pathname.split('/').pop() ?? ''))
        return Response.json({ installation_id: revoked.at(-1), status: 'device_grant_revoked' })
      }

      return problem('not_found', 404)
    },
    revoked,
    setOffline(next) {
      offline = next
    },
  }
}

const buildLoop = (server: FixtureServer) => {
  const root = mkdtempSync(join(tmpdir(), 'keepling-real-loop-'))
  loopRoots.push(root)
  const localStore = new NodeSqliteLocalStore({
    databasePath: join(root, 'namespace.sqlite3'),
    migrationPath,
  })
  const stored = { value: null as string | null }
  const credentials = {
    clear: async () => { stored.value = null },
    load: async () => stored.value,
    store: async (value: string) => { stored.value = value },
  }
  const openedBrowserUrls: string[] = []
  let authorization: BrowserDelegatedAuthorization

  const adapter = new KeeplingSyncAdapter({
    accessToken: async () => authorization.accessToken(),
    baseUrl: 'https://server.keepling.invalid',
    fetch: (input, init) => server.fetch(input, init),
  })
  authorization = new BrowserDelegatedAuthorization({
    clock: { now: () => Date.now() },
    credentials,
    exchange: adapter,
    installationId: 'installation-loop',
    openExternal: (url) => { openedBrowserUrls.push(url) },
    serverBaseUrl: 'https://server.keepling.invalid',
  })

  const application = new DesktopApplication({
    clock: { now: () => new Date().toISOString() },
    credentials,
    identity: { randomId: () => crypto.randomUUID() },
    localStore: {
      acceptCapture: async (mutation) => localStore.acceptCapture(mutation),
      acknowledge: async (acknowledgement) => localStore.acknowledge(acknowledgement),
      acknowledgeSync: async (acknowledgement) => localStore.acknowledgeSync(acknowledgement),
      applyPull: async (page) => localStore.applyPull(page),
      bindNamespace: async (namespace) => localStore.bindNamespace(namespace),
      close: async () => localStore.close(),
      pendingMutations: async () => localStore.pendingMutations(),
      readyMutations: async () => localStore.readyMutations(),
      setSyncFence: async (reason) => localStore.setSyncFence(reason),
      snapshot: async () => localStore.snapshot(),
      syncState: async () => localStore.syncState(),
    } satisfies LocalStorePort,
    sync: {
      acknowledge: async (mutation) => {
        try {
          return await adapter.lookup(mutation.mutationId, mutation.fingerprint)
        } catch {
          return null
        }
      },
      pull: async (cursor, limit) => adapter.pull(cursor, limit),
      push: async (bytes) => adapter.push(bytes),
    },
  })

  return { adapter, application, authorization: () => authorization, credentials, localStore, openedBrowserUrls, stored }
}

test('authorizes through the browser seam, captures offline, and reaches Synced only on an exact receipt', async () => {
  const server = createFixtureServer()
  const loop = buildLoop(server)
  const authorization = loop.authorization()

  // 1. Authorize. The app opens the system browser and never sees a credential.
  await authorization.begin()
  expect(loop.openedBrowserUrls).toHaveLength(1)
  const callbackUrl = server.authorizeInBrowser(loop.openedBrowserUrls[0]!)

  // An unsolicited callback from a competing app that registered the same
  // private-use scheme cannot displace the in-flight request.
  await expect(
    authorization.handleCallback(`${KEEPLING_REDIRECT_URI}?code=stolen&state=${'z'.repeat(43)}`),
  ).resolves.toEqual({ kind: 'rejected', reason: 'state_mismatch' })

  const authorized = await authorization.handleCallback(callbackUrl)
  expect(authorized).toEqual({
    kind: 'authorized',
    namespace: {
      accountSubject: SERVER_NAMESPACE.account_subject,
      generation: '2',
      issuer: SERVER_NAMESPACE.issuer,
      origin: SERVER_NAMESPACE.origin,
      serverInstance: SERVER_NAMESPACE.server_instance,
    },
  })
  // The five namespace fields are exactly what the server supplied.
  expect(JSON.parse(loop.stored.value ?? '{}').namespace).toEqual(authorized.kind === 'authorized' ? authorized.namespace : null)
  expect(await loop.application.activateNamespace((authorized as { namespace: never }).namespace)).toBe(true)

  // A replayed callback is refused, and the server also refuses the reused code.
  await expect(authorization.handleCallback(callbackUrl)).resolves.toEqual({
    kind: 'rejected', reason: 'no_authorization_in_flight',
  })

  // 2. Capture while offline. The local commit is durable; nothing claims Synced.
  server.setOffline(true)
  const acceptance = await loop.application.capture({ title: 'Book the ferry' })
  expect(acceptance.status).toBe('local_saved')
  const offlineSnapshot = await loop.application.snapshot()
  expect(offlineSnapshot.tasks.map((task) => task.syncStatus)).toEqual(['saved_on_this_mac'])

  const pendingBefore = await loop.localStore.readyMutations()
  const exactBytes = pendingBefore[0]!.commandBytes
  expect(pendingBefore[0]!.fingerprint).toBe(createHash('sha256').update(exactBytes).digest('hex'))

  // An offline pass never loses, mutates, or reorders the pending intent.
  await expect(loop.application.runSyncPass()).rejects.toThrow()
  const pendingAfterFailure = await loop.localStore.readyMutations()
  expect(pendingAfterFailure[0]!.commandBytes).toBe(exactBytes)
  expect((await loop.application.snapshot()).tasks[0]!.syncStatus).toBe('saved_on_this_mac')

  // 3. Reconnect. The EXACT serialized bytes are retried, byte for byte.
  server.setOffline(false)
  const pass = await loop.application.runSyncPass()
  expect(pass.settled).toBe(1)
  expect(server.commandBodies).toEqual([exactBytes])

  const syncedSnapshot = await loop.application.snapshot()
  expect(syncedSnapshot.tasks.map((task) => task.syncStatus)).toEqual(['synced'])
  expect((await loop.localStore.readyMutations())).toHaveLength(0)

  // 4. The receipt is exact: the same mutation identity AND fingerprint.
  const receipt = await loop.adapter.lookup(
    pendingBefore[0]!.mutationId,
    createHash('sha256').update(exactBytes).digest('hex'),
  )
  expect(receipt.mutationId).toBe(pendingBefore[0]!.mutationId)
  expect(receipt.fingerprint).toBe(createHash('sha256').update(exactBytes).digest('hex'))

  await loop.localStore.close()
})

test('a receipt for a different mutation identity never settles anything and never claims Synced', async () => {
  const server = createFixtureServer()
  const honest = server.fetch
  // A hostile/buggy server answers the push with a receipt for SOMEONE
  // ELSE'S mutation identity.
  server.fetch = async (input, init) => {
    const response = await honest(input, init)
    if (!String(input).includes('/api/v1/commands/')) return response
    const value = await response.json() as Record<string, unknown>
    return Response.json({ ...value, mutation_id: '00000000-0000-4000-8000-000000000000' }, { status: 201 })
  }

  const loop = buildLoop(server)
  const authorization = loop.authorization()
  await authorization.begin()
  await authorization.handleCallback(server.authorizeInBrowser(loop.openedBrowserUrls[0]!))

  await loop.application.capture({ title: 'Never settled' })
  const [pending] = await loop.localStore.readyMutations()

  await expect(loop.application.runSyncPass()).rejects.toThrow(/acknowledgement mutation mismatch/)

  // The pending intent is untouched, byte for byte, and nothing claims Synced.
  const stillPending = await loop.localStore.readyMutations()
  expect(stillPending[0]!.commandBytes).toBe(pending!.commandBytes)
  expect((await loop.application.snapshot()).tasks[0]!.syncStatus).toBe('saved_on_this_mac')

  await loop.localStore.close()
})

test('rotates refresh tokens, surfaces a detected replay as authentication expiry, and revokes on sign out', async () => {
  const server = createFixtureServer()
  const loop = buildLoop(server)
  const authorization = loop.authorization()
  await authorization.begin()
  await authorization.handleCallback(server.authorizeInBrowser(loop.openedBrowserUrls[0]!))
  await expect(authorization.accessToken()).resolves.toBe('access-one')

  // Rotation: a new access AND refresh token, same server-derived namespace.
  await expect(authorization.refresh()).resolves.toMatchObject({ kind: 'authorized' })
  await expect(authorization.accessToken()).resolves.toBe('access-two')
  expect(JSON.parse(loop.stored.value ?? '{}').refreshToken).toBe('refresh-two')

  // Sign out fences local intent and clears the credential BEFORE the
  // best-effort remote revocation. That order means the bearer token must
  // be captured FIRST -- an adapter that reads the token from storage
  // inside the revocation callback always finds it already gone, which is
  // exactly the bug this test caught in the shipped disconnect handler.
  const revocationToken = await authorization.accessToken()
  const revocationAdapter = new KeeplingSyncAdapter({
    accessToken: () => revocationToken,
    baseUrl: 'https://server.keepling.invalid',
    fetch: (input, init) => server.fetch(input, init),
  })
  await loop.application.signOut(async () => {
    await revocationAdapter.revoke('installation-loop')
  })
  expect(server.revoked).toEqual(['installation-loop'])
  await expect(authorization.accessToken()).resolves.toBeNull()

  await loop.localStore.close()
})

test('a replayed refresh token expires authentication rather than retrying silently', async () => {
  const server = createFixtureServer()
  const loop = buildLoop(server)
  const authorization = loop.authorization()
  await authorization.begin()
  await authorization.handleCallback(server.authorizeInBrowser(loop.openedBrowserUrls[0]!))

  await authorization.refresh()
  // Put the SPENT refresh token back and present it again.
  const stored = JSON.parse(loop.stored.value ?? '{}') as Record<string, unknown>
  loop.stored.value = JSON.stringify({ ...stored, refreshToken: 'refresh-one' })

  await expect(authorization.refresh()).resolves.toEqual({
    kind: 'failed', reason: 'refresh_replay_detected',
  })
  // The credential is cleared, so the app surfaces the closed
  // authentication_required recovery presentation instead of looping on a
  // dead credential family.
  await expect(authorization.accessToken()).resolves.toBeNull()
  const presentation = loop.application.publishPresentation({ kind: 'authentication_required' })
  expect(presentation.summary.kind).toBe('authentication_required')
  expect(presentation.summary.actions.map((action) => action.code)).toContain('sign_in')

  await loop.localStore.close()
})
