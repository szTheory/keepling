import { spawn, type ChildProcess } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { connect } from 'node:net'
import { userInfo } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

/**
 * The REAL Keepling backend -- real PostgreSQL, real migrations, the real
 * deterministic seed, and a real Phoenix server -- factored out of
 * `stack.ts` so more than one lane can prove against it.
 *
 * This file was extracted, not copied. `stack.ts` (the web lane's browser
 * stack) imports it and adds only the pieces a BROWSER needs on top: Vite
 * and the single-origin proxy. `apps/desktop/test/packaged/real-stack-sync.spec.ts`
 * imports it and adds nothing -- the packaged Mac app IS the client. Keeping
 * one implementation is the point: a desktop lane with its own copy would
 * drift away from the harness the web lane proves against, and then "real
 * server" would mean two different things in one repository.
 *
 * Nothing here binds anywhere but loopback, and nothing here is a fixture
 * or a stub: every process started below is the real executable, selected
 * through `tooling/runtime-preflight.sh` so the versions are the pinned ones.
 */

type OwnedChild = {
  child: ChildProcess
  label: string
}

const supportDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(supportDirectory, '../../../..')
const runtimePreflight = join(repositoryRoot, 'tooling/runtime-preflight.sh')

const LOOPBACK_HOST = '127.0.0.1'

const resolvedHost = (): string => {
  const host = process.env.KEEPLING_E2E_HOST ?? LOOPBACK_HOST
  if (host !== LOOPBACK_HOST) {
    throw new Error('Keepling test services must bind only to 127.0.0.1')
  }
  return host
}

const configuredPort = (name: string, fallback: string) => {
  const value = Number(process.env[name] ?? fallback)
  if (!Number.isInteger(value) || value < 1024 || value > 65_535) {
    throw new Error(`${name} must be an integer from 1024 through 65535`)
  }
  return value
}

const selectedRuntime = (args: string[]) => [
  runtimePreflight,
  ['--exec', '--', ...args],
] as const

const runChecked = async (
  label: string,
  command: string,
  args: string[],
  cwd: string,
  env: NodeJS.ProcessEnv = process.env,
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

const waitForPort = async (label: string, port: number, host = resolvedHost()) => {
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

type BackendOptions = {
  /**
   * Called when a backend process exits on its own. A backend that dies is
   * never a lane that silently degrades to "no server": both callers turn
   * this into a loud failure.
   */
  onUnexpectedExit: (reason: string) => void
  faultToken: string
  /**
   * Appended to as each process starts, so a caller can stop a partially
   * started backend. A failure part-way through must never leak a running
   * PostgreSQL.
   */
  ownedChildren?: OwnedChild[]
  phoenixPort: number
  postgresPort: number
  secretKeyBase: string
  temporaryRoot: string
  /**
   * The port the server believes it is published on. It derives the
   * `origin`/`issuer` namespace fields, which are SERVER-DERIVED ONLY --
   * this is deployment configuration, never client input.
   */
  urlPort?: number
}

type Backend = {
  databaseUrl: string
  environment: NodeJS.ProcessEnv
  ownedChildren: OwnedChild[]
  phoenixPort: number
}

const startBackend = async (options: BackendOptions): Promise<Backend> => {
  const host = resolvedHost()
  const ownedChildren = options.ownedChildren ?? []

  const spawnOwned = (
    label: string,
    command: string,
    args: string[],
    cwd: string,
    env: NodeJS.ProcessEnv = process.env,
  ) => {
    const child = spawn(command, args, { cwd, detached: true, env, stdio: 'inherit' })
    ownedChildren.push({ child, label })
    child.once('exit', (code, signal) => {
      options.onUnexpectedExit(`${label} exited with ${signal ?? `code ${String(code)}`}`)
    })
    return child
  }

  const dataDirectory = join(options.temporaryRoot, 'postgres')
  const socketDirectory = join(options.temporaryRoot, 'socket')
  await mkdir(socketDirectory, { recursive: true })

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
    String(options.postgresPort),
  ])
  spawnOwned('PostgreSQL', preflight, postgresArgs, repositoryRoot)
  await waitForPort('PostgreSQL', options.postgresPort, host)

  const databaseUser = encodeURIComponent(userInfo().username)
  const databaseUrl = `ecto://${databaseUser}@${host}:${String(options.postgresPort)}/keepling_e2e`
  const environment: NodeJS.ProcessEnv = {
    ...process.env,
    KEEPLING_E2E_SEED: 'phase-1',
    KEEPLING_ENABLE_TEST_FAULTS: '1',
    KEEPLING_TEST_DATABASE_URL: databaseUrl,
    KEEPLING_TEST_FAULT_TOKEN: options.faultToken,
    KEEPLING_TEST_SECRET_KEY_BASE: options.secretKeyBase,
    MIX_ENV: 'test',
    PHX_SERVER: 'true',
    PORT: String(options.phoenixPort),
    PHX_URL_PORT: String(options.urlPort ?? options.phoenixPort),
  }

  const [, createdbArgs] = selectedRuntime([
    'createdb',
    '-h',
    host,
    '-p',
    String(options.postgresPort),
    'keepling_e2e',
  ])
  await runChecked('PostgreSQL createdb', preflight, createdbArgs, repositoryRoot, environment)

  for (const [label, mixCommand] of [
    ['database migrations', 'cd apps/server && mix ecto.migrate'],
    ['deterministic seed', 'cd apps/server && mix run priv/repo/seeds.exs'],
  ] as const) {
    const [, args] = selectedRuntime(['sh', '-c', mixCommand])
    await runChecked(label, preflight, args, repositoryRoot, environment)
  }

  const [, phoenixArgs] = selectedRuntime(['sh', '-c', 'cd apps/server && mix phx.server'])
  spawnOwned('Phoenix', preflight, phoenixArgs, repositoryRoot, environment)
  await waitForPort('Phoenix', options.phoenixPort, host)

  return { databaseUrl, environment, ownedChildren, phoenixPort: options.phoenixPort }
}

const stopBackend = async (ownedChildren: OwnedChild[]) => {
  await Promise.all([...ownedChildren].reverse().map(stopOwnedProcess))
}

export {
  LOOPBACK_HOST,
  configuredPort,
  repositoryRoot,
  resolvedHost,
  runChecked,
  runtimePreflight,
  selectedRuntime,
  startBackend,
  stopBackend,
  stopOwnedProcess,
  waitForPort,
}
export type { Backend, BackendOptions, OwnedChild }
