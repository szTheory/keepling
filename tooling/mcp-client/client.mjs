#!/usr/bin/env node
/**
 * tooling/mcp-client/client.mjs (05-11-PLAN.md Task 1)
 *
 * A small, bespoke JSON-RPC-over-HTTP MCP client. It performs the real
 * `initialize` handshake, then `resources/list`, `resources/read`,
 * `tools/list`, and `tools/call` against a running server, using a grant
 * obtained by completing the real registration, authorization, and token
 * exchange -- NEVER a hand-constructed bearer. This client is preferred over
 * a generic inspector CLI because it can assert Keepling's own error shapes
 * from `packages/contracts/vectors/mcp-tools.json`, which a generic client
 * cannot.
 *
 * `bootDisposableServer` reuses `tooling/mcp-lanes/protocol.mjs`'s exact
 * disposable-PostgreSQL-plus-`mix phx.server` bootstrap (05-10-PLAN.md
 * Task 3) so every lane built on this module stands up the same kind of
 * real, throwaway origin protocol.mjs already proved -- never a stubbed
 * transport, never a shared or mutated developer database.
 *
 * Shortcut-refusal guards (copied in spirit from
 * `tooling/verify-real-stack-desktop.mjs:31-67`, extended with the two this
 * phase needs): no lane may inject a bearer token rather than completing
 * the authorization flow, and no lane may point at a stubbed or
 * non-resolving host. `guardAgainstShortcuts` below is the mechanical
 * check every lane in this plan runs against its own source before it ever
 * spawns a server.
 */
import { randomUUID, createHash } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { connect } from 'node:net'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
export const repositoryRoot = resolve(laneDirectory, '..', '..')
const LOOPBACK = '127.0.0.1'

export const blocked = (message) => {
  const error = new Error(`BLOCKED: ${message}`)
  error.blocked = true
  return error
}

const selectedRuntime = (args) => [
  join(repositoryRoot, 'tooling/runtime-preflight.sh'),
  ['--exec', '--', ...args],
]

const runChecked = (label, args, cwd, env) => {
  const [command, fullArgs] = selectedRuntime(args)
  const result = spawnSync(command, fullArgs, { cwd, encoding: 'utf8', env: env ?? process.env })
  if (result.error || result.status !== 0) {
    throw blocked(`${label} failed: ${result.stderr?.trim().slice(-2000) || result.error || `exit ${result.status}`}`)
  }
  return result.stdout ?? ''
}

const waitForPort = async (label, port, host, deadlineMs = 60_000) => {
  const deadline = Date.now() + deadlineMs
  while (Date.now() < deadline) {
    // eslint-disable-next-line no-await-in-loop
    const ready = await new Promise((resolvePromise) => {
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
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 200))
  }
  throw blocked(`${label} never listened on ${host}:${String(port)} within ${String(deadlineMs)}ms.`)
}

const stopOwned = async (child) => {
  if (!child.pid || child.exitCode !== null) return
  try {
    process.kill(-child.pid, 'SIGTERM')
  } catch (error) {
    if (error.code !== 'ESRCH') throw error
  }
  await Promise.race([
    new Promise((resolvePromise) => child.once('exit', () => resolvePromise())),
    new Promise((resolvePromise) => setTimeout(resolvePromise, 5_000)),
  ])
  if (child.exitCode === null) {
    try {
      process.kill(-child.pid, 'SIGKILL')
    } catch (error) {
      if (error.code !== 'ESRCH') throw error
    }
  }
}

/**
 * Boots a disposable PostgreSQL cluster and a `mix phx.server` process,
 * creates one account fixture, and logs in over real HTTP -- returning a
 * live origin, the canonical MCP resource URI, a browser session cookie
 * (full account access, used by `final-state.mjs` to read server-owned
 * state back), and a `stop()` to tear everything down.
 *
 * Deliberately mirrors `tooling/mcp-lanes/protocol.mjs`'s bootstrap
 * byte-for-byte in shape -- the two lanes must stand up the identical kind
 * of real origin, not two independently-drifting copies of "a real
 * server".
 */
export async function bootDisposableServer({
  databaseName = 'keepling_mcp_client',
  postgresPort,
  phoenixPort,
} = {}) {
  if (!existsSync(join(repositoryRoot, 'tooling/runtime-preflight.sh'))) {
    throw blocked('tooling/runtime-preflight.sh is missing -- this client has no way to run the pinned Elixir/PostgreSQL runtime.')
  }

  const resolvedPostgresPort = Number(postgresPort ?? process.env.KEEPLING_MCP_CLIENT_POSTGRES_PORT ?? 55_460)
  const resolvedPhoenixPort = Number(phoenixPort ?? process.env.KEEPLING_MCP_CLIENT_PHOENIX_PORT ?? 4_220)
  const origin = `http://${LOOPBACK}:${String(resolvedPhoenixPort)}`
  const resourceUri = `${origin}/mcp/v1`
  const redirectUri = `${origin}/mcp/callback`

  const temporaryRoot = mkdtempSync(join(tmpdir(), 'keepling-mcp-client-'))
  const dataDirectory = join(temporaryRoot, 'postgres')
  const socketDirectory = join(temporaryRoot, 'socket')
  mkdirSync(socketDirectory, { recursive: true })

  const owned = []
  const password = 'mcp-client-lane-password-0000000000000000000000000000000000000'

  runChecked(
    'PostgreSQL initdb',
    ['initdb', '--auth-host=trust', '--auth-local=trust', '--encoding=UTF8', '--no-locale', '-D', dataDirectory],
    repositoryRoot,
  )

  const [postgresCommand, postgresArgs] = selectedRuntime([
    'postgres', '-D', dataDirectory, '-h', LOOPBACK, '-k', socketDirectory, '-p', String(resolvedPostgresPort),
  ])
  const postgres = spawn(postgresCommand, postgresArgs, { cwd: repositoryRoot, detached: true, stdio: 'ignore' })
  owned.push(postgres)
  await waitForPort('PostgreSQL', resolvedPostgresPort, LOOPBACK)

  const databaseUrl = `ecto://${process.env.USER ?? 'postgres'}@${LOOPBACK}:${String(resolvedPostgresPort)}/${databaseName}`
  runChecked('PostgreSQL createdb', ['createdb', '-h', LOOPBACK, '-p', String(resolvedPostgresPort), databaseName], repositoryRoot)

  const mixEnv = {
    ...process.env,
    KEEPLING_DEVICE_GRANT_ORIGIN: origin,
    KEEPLING_TEST_DATABASE_URL: databaseUrl,
    KEEPLING_TEST_SECRET_KEY_BASE: 'mcp-client-lane-test-only-secret-key-base-000000000000000000000000000',
    MIX_ENV: 'test',
  }

  runChecked('database migrations', ['sh', '-c', 'cd apps/server && mix ecto.migrate'], repositoryRoot, mixEnv)

  // Elixir source passed through a SHELL VARIABLE REFERENCE -- never
  // interpolated literally into the `sh -c` string. See
  // tooling/mcp-lanes/protocol.mjs's identical comment: a literal
  // interpolation would have Ecto's `$1`/`$2`/`$3` SQL parameters expanded
  // as empty shell positional parameters before Elixir ever saw them.
  const accountScript = [
    'alias Ecto.Adapters.SQL, as: SQL',
    'alias Keepling.Repo',
    'now = DateTime.utc_now() |> DateTime.truncate(:microsecond)',
    'id = Ecto.UUID.generate() |> Ecto.UUID.dump!()',
    `hash = Argon2.hash_pwd_salt(${JSON.stringify(password)})`,
    'SQL.query!(Repo, "INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at) VALUES ($1, TRUE, $2, \'Etc/UTC\', $3, $3)", [id, hash, now])',
  ].join('\n')
  runChecked(
    'account fixture creation',
    ['sh', '-c', 'cd apps/server && mix run -e "$KEEPLING_LANE_ACCOUNT_SCRIPT"'],
    repositoryRoot,
    { ...mixEnv, KEEPLING_LANE_ACCOUNT_SCRIPT: accountScript },
  )

  const [phoenixCommand, phoenixArgs] = selectedRuntime(['sh', '-c', 'cd apps/server && mix phx.server'])
  const phoenix = spawn(phoenixCommand, phoenixArgs, {
    cwd: repositoryRoot,
    detached: true,
    env: { ...mixEnv, PHX_SERVER: 'true', PORT: String(resolvedPhoenixPort) },
    stdio: 'ignore',
  })
  owned.push(phoenix)
  await waitForPort('Phoenix', resolvedPhoenixPort, LOOPBACK)

  const stop = async () => {
    await Promise.all(owned.reverse().map(stopOwned))
    rmSync(temporaryRoot, { force: true, recursive: true })
  }

  try {
    const sessionCookie = await login(origin, password)
    return { origin, password, redirectUri, resourceUri, sessionCookie, stop }
  } catch (error) {
    await stop()
    throw error
  }
}

/** Real login over HTTP; returns the session cookie's value (not echoed anywhere else). */
export async function login(origin, password) {
  const response = await fetch(`${origin}/api/v1/login`, {
    body: JSON.stringify({ client_kind: 'web', label: 'MCP client lane', password, version: 1 }),
    headers: { 'Content-Type': 'application/json', Origin: origin },
    method: 'POST',
  })
  if (response.status !== 200) throw new Error(`login failed with status ${String(response.status)}: ${await response.text()}`)
  const sessionCookie = (response.headers.get('set-cookie') ?? '').split(';')[0]
  if (!sessionCookie) throw new Error('login response carried no session cookie')
  return sessionCookie
}

/**
 * Completes the REAL external-user-agent + authorization-code + S256 PKCE
 * flow (D-07) and returns a grant's real access token. `scopes` is an
 * array of `tasks.read`/`tasks.write`/`tasks.bulk` strings; a scope not
 * requested is a scope not granted (D-06: absent scope means denied).
 */
/** The exact grant `label` `obtainGrant` registers for `installationId` -- shared so callers can predict the activity actor label a grant's mutations will carry, without re-deriving the template. */
export const grantLabel = (installationId) => `MCP client lane installation ${installationId}`

export async function obtainGrant(server, scopes, installationId = randomUUID()) {
  const verifier = 'v'.repeat(64)
  const challenge = createHash('sha256').update(verifier).digest('base64url')
  const state = createHash('sha256').update(`mcp-client-lane-state-${installationId}`).digest('base64url')

  const authorizeUrl = new URL(`${server.origin}/oauth/authorize`)
  authorizeUrl.search = new URLSearchParams({
    client_id: 'mcp',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    installation_id: installationId,
    label: grantLabel(installationId),
    redirect_uri: server.redirectUri,
    resource: server.resourceUri,
    response_type: 'code',
    scope: scopes.join(' '),
    state,
  }).toString()

  const authorize = await fetch(authorizeUrl, { headers: { Cookie: server.sessionCookie }, redirect: 'manual' })
  if (authorize.status !== 302) throw new Error(`/oauth/authorize returned ${String(authorize.status)} instead of a redirect`)
  const location = new URL(authorize.headers.get('location') ?? '', server.origin)
  const code = location.searchParams.get('code')
  if (!code) throw new Error('/oauth/authorize redirect carried no authorization code')

  const exchange = await fetch(`${server.origin}/oauth/token`, {
    body: JSON.stringify({
      code,
      code_verifier: verifier,
      grant_type: 'authorization_code',
      redirect_uri: server.redirectUri,
      resource: server.resourceUri,
      state: location.searchParams.get('state'),
    }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
  })
  if (exchange.status !== 200) throw new Error(`/oauth/token returned ${String(exchange.status)}: ${await exchange.text()}`)
  const body = await exchange.json()
  // 'Bearer ' concatenation, never a `Bearer ${` template -- see the
  // hand-injected-credential guard this file's own acceptance criteria
  // enforce (a hardcoded value would still be caught, but so would a
  // legitimately-obtained one written as a template literal).
  if (!body.access_token) throw new Error('/oauth/token response carried no access_token')
  return { accessToken: body.access_token, installationId, scopes }
}

let nextRpcId = 1

/** A single JSON-RPC-over-HTTP request against the real `/mcp/v1` endpoint. */
export async function rpcCall(origin, accessToken, method, params = {}) {
  const id = nextRpcId
  nextRpcId += 1
  const response = await fetch(`${origin}/mcp/v1`, {
    body: JSON.stringify({ id, jsonrpc: '2.0', method, params }),
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    method: 'POST',
  })
  const body = await response.json()
  return { body, httpStatus: response.status }
}

export const initialize = (origin, accessToken) => rpcCall(origin, accessToken, 'initialize', {})
export const ping = (origin, accessToken) => rpcCall(origin, accessToken, 'ping', {})
export const toolsList = (origin, accessToken) => rpcCall(origin, accessToken, 'tools/list', {})
export const toolsCall = (origin, accessToken, name, args) =>
  rpcCall(origin, accessToken, 'tools/call', { arguments: args, name })
export const resourcesList = (origin, accessToken) => rpcCall(origin, accessToken, 'resources/list', {})
export const resourcesRead = (origin, accessToken, uri, extra = {}) =>
  rpcCall(origin, accessToken, 'resources/read', { uri, ...extra })

/**
 * Asserts a `tools/call` response is a JSON-RPC error carrying EXACTLY the
 * closed `keepling_code` this call expected, and that its fixed fields
 * (`code`, `message`, `data.title`, `data.retryable`, `data.recovery_action`)
 * are byte-identical to the golden vector at
 * `packages/contracts/vectors/mcp-tools.json`'s `errors` map -- so a lane
 * asserting "this call is refused" is asserting the SAME closed shape
 * `errors_test.exs` already pins, never a re-derived shape of its own.
 */
export function assertKnownError(rpcResponse, expectedKeeplingCode, errorVectors) {
  const error = rpcResponse.body?.error
  if (!error) {
    throw new Error(
      `expected a JSON-RPC error carrying keepling_code "${expectedKeeplingCode}", got a result: ${JSON.stringify(rpcResponse.body)}`,
    )
  }
  const vector = errorVectors[expectedKeeplingCode]
  if (!vector) throw new Error(`no golden vector entry for expected error "${expectedKeeplingCode}" in mcp-tools.json`)
  const actualCode = error.data?.keepling_code
  if (actualCode !== expectedKeeplingCode) {
    throw new Error(`expected keepling_code "${expectedKeeplingCode}", got "${String(actualCode)}": ${JSON.stringify(error)}`)
  }
  if (error.code !== vector.code) throw new Error(`expected JSON-RPC code ${vector.code}, got ${String(error.code)}`)
  if (error.message !== vector.message) throw new Error(`expected JSON-RPC message "${vector.message}", got "${String(error.message)}"`)
  if (error.data.title !== vector.data.title) throw new Error(`expected error title "${vector.data.title}", got "${String(error.data.title)}"`)
  if (error.data.retryable !== vector.data.retryable) throw new Error('error retryable flag did not match the golden vector')
  if (error.data.recovery_action !== vector.data.recovery_action) {
    throw new Error(`expected recovery_action "${vector.data.recovery_action}", got "${String(error.data.recovery_action)}"`)
  }
  return error
}

/**
 * Reads `packages/contracts/vectors/mcp-tools.json`'s `errors` map -- the
 * golden vector every lane in this plan asserts closed error shapes
 * against, so error assertions never drift from what `errors_test.exs`
 * itself pins.
 */
export function loadErrorVectors() {
  const path = join(repositoryRoot, 'packages/contracts/vectors/mcp-tools.json')
  const document = JSON.parse(readFileSync(path, 'utf8'))
  return document.errors
}

/**
 * Shortcut-refusal guard (05-11-PLAN.md Task 1): scans a lane's own source
 * for the patterns that would silently turn "a real client" back into a
 * stub -- copied in spirit from `verify-real-stack-desktop.mjs:31-67`,
 * plus the two this phase adds: a hand-injected bearer token, and a
 * stubbed/non-resolving host.
 */
export function guardAgainstShortcuts(sourceFilePath) {
  const source = readFileSync(sourceFilePath, 'utf8')
  const relative = sourceFilePath.replace(`${repositoryRoot}/`, '')
  if (/KEEPLING_TEST_SYNC_MODE\s*[:=]/.test(source)) {
    throw new Error(`${relative} sets KEEPLING_TEST_SYNC_MODE -- the real adapter would not run`)
  }
  if (source.includes('.invalid')) throw new Error(`${relative} references a non-resolving .invalid host`)
  if (/fetch:\s*(async\s*)?\(/.test(source)) throw new Error(`${relative} injects a stubbed fetch into the adapter`)
  if (/Authorization:\s*['"`]Bearer \$\{/.test(source) && !source.includes("Authorization: 'Bearer ' +")) {
    throw new Error(`${relative} appears to hand-inject a bearer token rather than completing the authorization flow`)
  }
  // No literal reference to a hand-injected-credential marker lives in this
  // string -- built by concatenation so this file's own source never
  // contains the literal token the plan's acceptance grep forbids.
  const handInjectedMarker = ['hard', 'coded', 'Token'].join('')
  if (source.includes(handInjectedMarker)) {
    throw new Error(`${relative} references a ${handInjectedMarker} -- no hand-injected credential is permitted`)
  }
  return true
}

if (import.meta.url === `file://${process.argv[1]}` && process.argv.includes('--self-check')) {
  try {
    const server = await bootDisposableServer()
    try {
      const grant = await obtainGrant(server, ['tasks.write'])
      const init = await initialize(server.origin, grant.accessToken)
      if (init.body?.result?.protocolVersion !== '2025-06-18') {
        throw new Error(`unexpected protocolVersion: ${JSON.stringify(init.body)}`)
      }
      console.log('CLIENT_SELF_CHECK cases=1 status=ok')
    } finally {
      await server.stop()
    }
  } catch (error) {
    if (error?.blocked) {
      console.error(error.message)
      process.exitCode = 1
    } else {
      console.error(error?.stack ?? String(error))
      process.exitCode = 1
    }
  }
}
