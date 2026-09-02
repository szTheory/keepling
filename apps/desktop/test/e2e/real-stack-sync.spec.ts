import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { expect, test } from '@playwright/test'

import { KeeplingSyncAdapter } from '../../main/adapters/sync.ts'
import { SafeStorageCredentialAdapter } from '../../main/adapters/credentials.ts'
import { DesktopApplication, type LocalStorePort } from '../../main/application/DesktopApplication.ts'

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
