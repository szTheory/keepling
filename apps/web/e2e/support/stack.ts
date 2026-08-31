import { spawn, type ChildProcess } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { mkdir, mkdtemp, rm } from 'node:fs/promises'
import { createServer, request, type Server } from 'node:http'
import { connect } from 'node:net'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { expect, test } from '@playwright/test'

type OwnedChild = {
  child: ChildProcess
  label: string
}

const supportDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(supportDirectory, '../../../..')
const webRoot = join(repositoryRoot, 'apps/web')
const runtimePreflight = join(repositoryRoot, 'tooling/runtime-preflight.sh')
const host = process.env.KEEPLING_E2E_HOST ?? '127.0.0.1'

if (host !== '127.0.0.1') {
  throw new Error('Keepling test services must bind only to 127.0.0.1')
}

const configuredPort = (name: string, fallback: string) => {
  const value = Number(process.env[name] ?? fallback)
  if (!Number.isInteger(value) || value < 1024 || value > 65_535) {
    throw new Error(`${name} must be an integer from 1024 through 65535`)
  }
  return value
}

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

const selectedRuntime = (args: string[]) => [
  runtimePreflight,
  ['--exec', '--', ...args],
] as const

const commandEnvironment = (databaseUrl: string) => ({
  ...process.env,
  KEEPLING_E2E_SEED: 'phase-1',
  KEEPLING_ENABLE_TEST_FAULTS: '1',
  KEEPLING_TEST_DATABASE_URL: databaseUrl,
  KEEPLING_TEST_FAULT_TOKEN: testFaultToken,
  KEEPLING_TEST_SECRET_KEY_BASE:
    process.env.KEEPLING_TEST_SECRET_KEY_BASE ?? randomBytes(64).toString('hex'),
  MIX_ENV: 'test',
  PHX_SERVER: 'true',
  PORT: String(phoenixPort),
})

const runChecked = async (
  label: string,
  command: string,
  args: string[],
  cwd: string,
  env = process.env,
) =>
  new Promise<void>((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd, env, stdio: 'inherit' })
    child.once('error', reject)
    child.once('exit', (code, signal) => {
      if (code === 0) {
        resolvePromise()
        return
      }
      reject(new Error(`${label} exited with ${signal ?? `code ${String(code)}`}`))
    })
  })

const spawnOwned = (
  label: string,
  command: string,
  args: string[],
  cwd: string,
  env = process.env,
) => {
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

const waitForPort = async (label: string, port: number) => {
  const deadline = Date.now() + 60_000
  while (Date.now() < deadline) {
    const ready = await new Promise<boolean>((resolvePromise) => {
      const socket = connect({ host, port })
      socket.setTimeout(500)
      socket.once('connect', () => {
        socket.destroy()
        resolvePromise(true)
      })
      socket.once('error', () => resolvePromise(false))
      socket.once('timeout', () => {
        socket.destroy()
        resolvePromise(false)
      })
    })
    if (ready) return
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 100))
  }
  throw new Error(`${label} did not listen on ${host}:${String(port)}`)
}

const stopOwnedProcess = async ({ child, label }: OwnedChild) => {
  if (!child.pid || child.exitCode !== null) return
  try {
    process.kill(-child.pid, 'SIGTERM')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ESRCH') throw error
  }
  await Promise.race([
    new Promise<void>((resolvePromise) => child.once('exit', () => resolvePromise())),
    new Promise<void>((resolvePromise) => setTimeout(resolvePromise, 5_000)),
  ])
  if (child.exitCode === null) {
    try {
      process.kill(-child.pid, 'SIGKILL')
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ESRCH') throw error
    }
  }
  process.stderr.write(`Stopped owned ${label} process group ${String(child.pid)}\n`)
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
  const dataDirectory = join(temporaryRoot, 'postgres')
  const socketDirectory = join(temporaryRoot, 'socket')
  await mkdir(socketDirectory)

  const [preflight, initdbArgs] = selectedRuntime([
    'initdb',
    '--auth-host=trust',
    '--auth-local=trust',
    '--encoding=UTF8',
    '--no-locale',
    '-D',
    dataDirectory,
  ])
  await runChecked('PostgreSQL initdb', preflight, initdbArgs, repositoryRoot)

  const [, postgresArgs] = selectedRuntime([
    'postgres',
    '-D',
    dataDirectory,
    '-h',
    host,
    '-k',
    socketDirectory,
    '-p',
    String(postgresPort),
  ])
  spawnOwned('PostgreSQL', preflight, postgresArgs, repositoryRoot)
  await waitForPort('PostgreSQL', postgresPort)

  const databaseUser = encodeURIComponent(userInfo().username)
  const databaseUrl = `ecto://${databaseUser}@${host}:${String(postgresPort)}/keepling_e2e`
  const env = commandEnvironment(databaseUrl)
  const [, createdbArgs] = selectedRuntime([
    'createdb',
    '-h',
    host,
    '-p',
    String(postgresPort),
    'keepling_e2e',
  ])
  await runChecked('PostgreSQL createdb', preflight, createdbArgs, repositoryRoot, env)

  for (const [label, mixCommand] of [
    ['database migrations', 'cd apps/server && mix ecto.migrate'],
    ['deterministic seed', 'cd apps/server && mix run priv/repo/seeds.exs'],
  ] as const) {
    const [, args] = selectedRuntime(['sh', '-c', mixCommand])
    await runChecked(label, preflight, args, repositoryRoot, env)
  }

  const [, phoenixArgs] = selectedRuntime([
    'sh',
    '-c',
    'cd apps/server && mix phx.server',
  ])
  spawnOwned('Phoenix', preflight, phoenixArgs, repositoryRoot, env)
  await waitForPort('Phoenix', phoenixPort)

  spawnOwned(
    'Vite',
    'pnpm',
    ['exec', 'vite', '--host', host, '--port', String(vitePort), '--strictPort'],
    webRoot,
    env,
  )
  await waitForPort('Vite', vitePort)

  proxyServer = createServer((incoming, outgoing) => {
    const apiRequest = incoming.url === '/api' || incoming.url?.startsWith('/api/')
    const targetPort = apiRequest ? phoenixPort : vitePort
    const upstream = request(
      {
        headers: { ...incoming.headers, host: `${host}:${String(targetPort)}` },
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
