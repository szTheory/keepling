import { spawn, type ChildProcess } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { mkdtemp, rm } from 'node:fs/promises'
import { createServer, request, type Server } from 'node:http'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { expect, test } from '@playwright/test'

import {
  configuredPort,
  resolvedHost,
  runtimePreflight,
  selectedRuntime,
  startBackend,
  stopOwnedProcess,
  waitForPort,
  type OwnedChild,
} from './backend.ts'

/**
 * The WEB lane's stack: the shared real backend (`backend.ts` -- real
 * PostgreSQL, real migrations, the real seed, real Phoenix) plus the two
 * pieces only a BROWSER needs on top, Vite and a single-origin proxy.
 *
 * The PostgreSQL/Phoenix half used to live in this file. It was moved to
 * `backend.ts` so `apps/desktop/test/packaged/real-stack-sync.spec.ts` can
 * prove the packaged Mac app against the SAME real server rather than
 * against a second, drifting copy of this harness.
 */

const supportDirectory = fileURLToPath(new URL('.', import.meta.url))
const repositoryRoot = resolve(supportDirectory, '../../../..')
const webRoot = join(repositoryRoot, 'apps/web')
const host = resolvedHost()

const publicPort = configuredPort('KEEPLING_E2E_PORT', '4173')
const vitePort = configuredPort('KEEPLING_E2E_VITE_PORT', '4174')
const phoenixPort = configuredPort('KEEPLING_E2E_PHOENIX_PORT', '4002')
const postgresPort = configuredPort('KEEPLING_E2E_POSTGRES_PORT', '55432')
const testFaultToken = process.env.KEEPLING_TEST_FAULT_TOKEN

if (!testFaultToken || testFaultToken.length < 32) {
  throw new Error('KEEPLING_TEST_FAULT_TOKEN must be a per-run high-entropy value')
}

const ownedChildren: OwnedChild[] = []
let proxyServer: Server | undefined
let temporaryRoot: string | undefined
let cleaningUp = false

const spawnOwned = (
  label: string,
  command: string,
  args: string[],
  cwd: string,
  env: NodeJS.ProcessEnv = process.env,
): ChildProcess => {
  const child = spawn(command, args, {
    cwd,
    detached: true,
    env,
    stdio: 'inherit',
  })
  ownedChildren.push({ child, label })
  child.once('exit', (code, signal) => {
    if (!cleaningUp) {
      void cleanup(1, `${label} exited with ${signal ?? `code ${String(code)}`}`)
    }
  })
  return child
}

const cleanup = async (exitCode: number, reason?: string) => {
  if (cleaningUp) return
  cleaningUp = true
  if (reason) process.stderr.write(`${reason}\n`)
  if (proxyServer) {
    await new Promise<void>((resolvePromise) => proxyServer?.close(() => resolvePromise()))
  }
  await Promise.all(ownedChildren.reverse().map(stopOwnedProcess))
  if (temporaryRoot) await rm(temporaryRoot, { force: true, recursive: true })
  process.exit(exitCode)
}

const start = async () => {
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) {
    process.once(signal, () => void cleanup(0))
  }
  process.once('uncaughtException', (error) =>
    void cleanup(1, error.stack ?? error.message),
  )
  process.once('unhandledRejection', (error) => void cleanup(1, String(error)))

  temporaryRoot = await mkdtemp(join(tmpdir(), 'keepling-playwright-'))

  const backend = await startBackend({
    faultToken: testFaultToken,
    onUnexpectedExit: (reason) => {
      if (!cleaningUp) void cleanup(1, reason)
    },
    ownedChildren,
    phoenixPort,
    postgresPort,
    secretKeyBase:
      process.env.KEEPLING_TEST_SECRET_KEY_BASE ?? randomBytes(64).toString('hex'),
    temporaryRoot,
  })

  spawnOwned(
    'Vite',
    'pnpm',
    ['exec', 'vite', '--host', host, '--port', String(vitePort), '--strictPort'],
    webRoot,
    backend.environment,
  )
  await waitForPort('Vite', vitePort)

  proxyServer = createServer((incoming, outgoing) => {
    const apiRequest = incoming.url === '/api' || incoming.url?.startsWith('/api/')
    const targetPort = apiRequest ? phoenixPort : vitePort
    const upstream = request(
      {
        headers: incoming.headers,
        host,
        method: incoming.method,
        path: incoming.url,
        port: targetPort,
      },
      (response) => {
        outgoing.writeHead(response.statusCode ?? 502, response.headers)
        response.pipe(outgoing)
      },
    )
    upstream.once('error', (error) => {
      outgoing.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
      outgoing.end(`Keepling test proxy failed: ${error.message}`)
    })
    incoming.pipe(upstream)
  })

  await new Promise<void>((resolvePromise, reject) => {
    proxyServer?.once('error', reject)
    proxyServer?.listen(publicPort, host, () => resolvePromise())
  })
  process.stdout.write(`Keepling Playwright stack ready at http://${host}:${String(publicPort)}\n`)
}

const invokedAsStackProcess =
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (invokedAsStackProcess) {
  await start()
} else {
  test('the real-stack harness keeps test faults explicitly gated', async () => {
    expect(testFaultToken.length).toBeGreaterThanOrEqual(32)
    expect(selectedRuntime(['postgres'])).toEqual([
      runtimePreflight,
      ['--exec', '--', 'postgres'],
    ])
  })
}
