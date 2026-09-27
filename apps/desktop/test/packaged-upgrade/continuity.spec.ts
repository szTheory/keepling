import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { join } from 'node:path'
import { test, expect, _electron as electron, type ElectronApplication } from '@playwright/test'

import { BrowserDelegatedAuthorization, KEEPLING_REDIRECT_URI } from '../../main/adapters/auth.ts'
import { KeeplingSyncAdapter } from '../../main/adapters/sync.ts'
import type { SyncNamespace } from '../../main/application/DesktopApplication.ts'

type PackageManifest = {
  executablePath: string
  sourceRevision: string
}

type TestCredentials = {
  accessToken: string
  namespace: SyncNamespace
  refreshToken: string
}

type TestMainGlobal = typeof globalThis & {
  __keeplingTestCredentials?: {
    load(): Promise<string | null>
    store(value: string): Promise<void>
  }
  __keeplingTestDesktopApplication?: {
    activateNamespace(namespace: SyncNamespace): Promise<boolean>
  }
}

const readManifest = (path: string): PackageManifest =>
  JSON.parse(readFileSync(path, 'utf8')) as PackageManifest

const launch = async (manifest: PackageManifest, profilePath: string): Promise<ElectronApplication> => {
  const application = await electron.launch({
    args: [`--user-data-dir=${profilePath}`],
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_EXPOSE_INTERNALS: '1',
      KEEPLING_TEST_SYNC_MODE: 'offline',
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
    },
    executablePath: manifest.executablePath,
    timeout: 30_000,
  })
  await application.firstWindow()
  return application
}

const readNamespaceBinding = (profilePath: string): SyncNamespace | null => {
  const database = new DatabaseSync(join(profilePath, 'namespace.sqlite3'), { timeout: 2_500 })
  try {
    const row = database
      .prepare("SELECT value FROM namespace_metadata WHERE key = 'sync_namespace'")
      .get() as { value: string } | undefined
    return row === undefined ? null : JSON.parse(row.value) as SyncNamespace
  } finally {
    database.close()
  }
}

const authorizeSyntheticServerCredential = async (): Promise<TestCredentials> => {
  const stored = { value: null as string | null }
  const serverNamespace = {
    account_subject: 'synthetic-account-subject',
    generation: 7,
    issuer: 'https://identity.example.invalid',
    origin: 'https://api.example.invalid',
    server_instance: 'synthetic-server-instance',
  }
  const serverResponse = {
    access_token: 'synthetic:access:kpl03-upgrade',
    expires_in: 900,
    namespace: serverNamespace,
    refresh_token: 'synthetic:refresh:kpl03-upgrade',
    token_type: 'Bearer',
  }
  const exchange = new KeeplingSyncAdapter({
    accessToken: () => null,
    baseUrl: serverNamespace.origin,
    fetch: async (input, init) => {
      if (new URL(input).pathname !== '/oauth/token' || init?.method !== 'POST') {
        throw new Error('synthetic authorization fixture received an unexpected request')
      }
      return Response.json(serverResponse)
    },
  })
  let authorizationUrl: string | null = null
  const authorization = new BrowserDelegatedAuthorization({
    clock: { now: () => Date.now() },
    credentials: {
      clear: async () => { stored.value = null },
      load: async () => stored.value,
      store: async (value) => { stored.value = value },
    },
    exchange,
    installationId: 'synthetic-upgrade-installation',
    openExternal: (url) => { authorizationUrl = url },
    serverBaseUrl: serverNamespace.origin,
  })

  await authorization.begin()
  const state = authorizationUrl === null ? null : new URL(authorizationUrl).searchParams.get('state')
  if (state === null) throw new Error('synthetic authorization fixture did not start')
  const outcome = await authorization.handleCallback(
    `${KEEPLING_REDIRECT_URI}?code=synthetic-upgrade-code&state=${encodeURIComponent(state)}`,
  )
  if (outcome.kind !== 'authorized' || stored.value === null) {
    throw new Error('synthetic server did not authorize the packaged-upgrade fixture')
  }

  // The real token-response mapper and authorization flow derive these
  // fields from the synthetic server response; the test never invents the
  // persisted SyncNamespace itself.
  return JSON.parse(stored.value) as TestCredentials
}

test('a signed packaged replacement retains encrypted synthetic credentials and the server namespace binding', async () => {
  test.setTimeout(180_000)
  const profilePath = process.env.KEEPLING_TEST_USER_DATA_DIR
  const previousManifestPath = process.env.KEEPLING_PREVIOUS_PACKAGE_MANIFEST
  const currentManifestPath = process.env.KEEPLING_PACKAGE_MANIFEST
  if (!profilePath || !previousManifestPath || !currentManifestPath) {
    throw new Error('the signed packaged-upgrade runner must provide two manifests and a disposable profile')
  }

  const previousManifest = readManifest(previousManifestPath)
  const currentManifest = readManifest(currentManifestPath)
  const credentials = await authorizeSyntheticServerCredential()
  const namespace = credentials.namespace
  const serializedCredentials = JSON.stringify(credentials)

  expect(previousManifest.sourceRevision).not.toBe(currentManifest.sourceRevision)

  const firstBuild = await launch(previousManifest, profilePath)
  try {
    const isPackaged = await firstBuild.evaluate(({ app }) => app.isPackaged)
    expect(isPackaged).toBe(true)

    const seeded = await firstBuild.evaluate(async (_electron, serialized) => {
      const main = globalThis as TestMainGlobal
      const credentialAdapter = main.__keeplingTestCredentials
      const desktopApplication = main.__keeplingTestDesktopApplication
      if (credentialAdapter?.constructor.name !== 'SafeStorageCredentialAdapter' || !desktopApplication) {
        throw new Error('real packaged credential adapter or namespace binding seam is unavailable')
      }
      await credentialAdapter.store(serialized)
      const decryptedInFirstBuild = await credentialAdapter.load() === serialized
      const parsed = JSON.parse(serialized) as TestCredentials
      const namespaceBound = await desktopApplication.activateNamespace(parsed.namespace)
      return decryptedInFirstBuild && namespaceBound
    }, serializedCredentials)
    expect(seeded).toBe(true)
  } finally {
    await firstBuild.close()
  }

  const credentialPath = join(profilePath, 'credential.enc')
  const encryptedCredential = readFileSync(credentialPath)
  expect(encryptedCredential.includes(Buffer.from(credentials.accessToken))).toBe(false)
  expect(encryptedCredential.includes(Buffer.from(credentials.refreshToken))).toBe(false)
  expect(JSON.stringify(readNamespaceBinding(profilePath)) === JSON.stringify(namespace)).toBe(true)

  const replacementBuild = await launch(currentManifest, profilePath)
  try {
    const isPackaged = await replacementBuild.evaluate(({ app }) => app.isPackaged)
    expect(isPackaged).toBe(true)

    // Compare inside the packaged main process and return only a boolean.
    // Test output and CI artifacts therefore never contain credential text.
    const decryptedInReplacement = await replacementBuild.evaluate(async (_electron, serialized) => {
      const main = globalThis as TestMainGlobal
      const credentialAdapter = main.__keeplingTestCredentials
      if (credentialAdapter?.constructor.name !== 'SafeStorageCredentialAdapter') {
        throw new Error('real packaged credential adapter is unavailable after replacement')
      }
      return await credentialAdapter.load() === serialized
    }, serializedCredentials)
    expect(decryptedInReplacement).toBe(true)
  } finally {
    await replacementBuild.close()
  }

  expect(JSON.stringify(readNamespaceBinding(profilePath)) === JSON.stringify(namespace)).toBe(true)
  console.log('PACKAGED_UPGRADE_CONTINUITY passed=1 synthetic_credentials=retained namespace_binding=retained')
})
