#!/usr/bin/env node
/**
 * protocol lane (05-10-PLAN.md Task 3, D-25's second named lane): a real
 * MCP `initialize` handshake over the real Streamable HTTP transport
 * against a live, disposable Phoenix server on real PostgreSQL -- never
 * `Phoenix.ConnTest`'s simulated request/response cycle, which is what
 * `tracer_capture_test.exs` (05-01) already covers. This file boots its
 * own throwaway PostgreSQL cluster and its own `mix phx.server` process
 * (mirroring `apps/web/e2e/support/backend.ts`'s pattern in plain Node
 * rather than TypeScript), obtains a real `mcp` device grant through the
 * real PKCE authorization-code flow over real HTTP, and asserts:
 *
 *   1. the server's `initialize` response names `protocolVersion` equal to
 *      the pinned revision (D-04/D-30) EXACTLY -- not merely that a
 *      handshake succeeded, which is "the first vacuity mode research
 *      named" per 05-VALIDATION.md;
 *   2. the JSON-RPC method surface the server actually dispatches on is
 *      the exact closed set this lane expects -- read statically from
 *      `KeeplingWeb.MCP.Dispatch`'s own `@methods` table, so a method
 *      silently added or removed there without updating this lane's
 *      expectation fails loudly instead of drifting unnoticed. (05-04's
 *      `docs/architecture/MCP-SURFACE.md` does not exist yet -- once it
 *      does, that document becomes the authority this assertion reads
 *      instead, per 05-VALIDATION.md.)
 *
 * When no server can be reached -- runtime-preflight missing, PostgreSQL
 * or Phoenix refusing to boot, the port never coming up -- this throws a
 * `BLOCKED:`-prefixed error naming exactly what is missing. It never
 * reports a pass it cannot support.
 */
import { randomUUID, createHash } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { connect } from 'node:net'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const PINNED_PROTOCOL_REVISION = '2025-06-18'

// The closed JSON-RPC method surface `KeeplingWeb.MCP.Dispatch.@methods`
// declares as of this lane's writing (05-10-PLAN.md). A method added or
// removed there without updating this constant is exactly the drift this
// lane exists to catch -- see `extractDispatchMethods` below, which reads
// the module's real source rather than trusting this list alone.
const EXPECTED_METHODS = ['initialize', 'ping', 'resources/list', 'resources/read', 'tools/call', 'tools/list']

const LOOPBACK = '127.0.0.1'
const laneDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(laneDirectory, '..', '..')
const dispatchPath = join(repositoryRoot, 'apps/server/lib/keepling_web/mcp/dispatch.ex')

const blocked = (message) => {
  const error = new Error(`BLOCKED: ${message}`)
  error.blocked = true
  return error
}

/**
 * Reads the CLOSED method surface straight from `KeeplingWeb.MCP.Dispatch`'s
 * `@methods` map source, rather than trusting only what a live server
 * answers -- a compromised or stale dispatch table would still answer
 * `initialize` correctly while silently exposing an undeclared method, and
 * a live-only check could never catch that.
 */
const extractDispatchMethods = () => {
  if (!existsSync(dispatchPath)) {
    throw blocked(`${dispatchPath} does not exist -- the dispatch module this lane asserts against is missing.`)
  }
  const source = readFileSync(dispatchPath, 'utf8')
  const methodsBlockMatch = source.match(/@methods\s*%\{([\s\S]*?)\n\s*\}/)
  if (!methodsBlockMatch) {
    throw new Error(`${dispatchPath} no longer declares an @methods map this lane can parse.`)
  }
  const methods = [...methodsBlockMatch[1].matchAll(/"([a-z/]+)"\s*=>/g)].map((m) => m[1])
  if (methods.length === 0) {
    throw new Error(`${dispatchPath}'s @methods map named zero methods.`)
  }
  return methods.sort()
}

const selectedRuntime = (args) => [join(repositoryRoot, 'tooling/runtime-preflight.sh'), ['--exec', '--', ...args]]

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

const runHandshake = async () => {
  if (!existsSync(join(repositoryRoot, 'tooling/runtime-preflight.sh'))) {
    throw blocked('tooling/runtime-preflight.sh is missing -- this lane has no way to run the pinned Elixir/PostgreSQL runtime.')
  }

  const expectedMethods = extractDispatchMethods()

  const postgresPort = Number(process.env.KEEPLING_MCP_PROTOCOL_POSTGRES_PORT ?? 55_450)
  const phoenixPort = Number(process.env.KEEPLING_MCP_PROTOCOL_PHOENIX_PORT ?? 4_210)
  const origin = `http://${LOOPBACK}:${String(phoenixPort)}`
  const resourceUri = `${origin}/mcp/v1`
  const redirectUri = `${origin}/mcp/callback`

  const temporaryRoot = mkdtempSync(join(tmpdir(), 'keepling-mcp-protocol-'))
  const dataDirectory = join(temporaryRoot, 'postgres')
  const socketDirectory = join(temporaryRoot, 'socket')
  mkdirSync(socketDirectory, { recursive: true })

  const owned = []
  const password = 'mcp-protocol-lane-password-0000000000000000000000000000000000'

  try {
    runChecked(
      'PostgreSQL initdb',
      ['initdb', '--auth-host=trust', '--auth-local=trust', '--encoding=UTF8', '--no-locale', '-D', dataDirectory],
      repositoryRoot,
    )

    const [postgresCommand, postgresArgs] = selectedRuntime([
      'postgres',
      '-D',
      dataDirectory,
      '-h',
      LOOPBACK,
      '-k',
      socketDirectory,
      '-p',
      String(postgresPort),
    ])
    const postgres = spawn(postgresCommand, postgresArgs, { cwd: repositoryRoot, detached: true, stdio: 'ignore' })
    owned.push(postgres)
    await waitForPort('PostgreSQL', postgresPort, LOOPBACK)

    const databaseUrl = `ecto://${process.env.USER ?? 'postgres'}@${LOOPBACK}:${String(postgresPort)}/keepling_mcp_protocol`
    runChecked('PostgreSQL createdb', ['createdb', '-h', LOOPBACK, '-p', String(postgresPort), 'keepling_mcp_protocol'], repositoryRoot)

    const mixEnv = {
      ...process.env,
      KEEPLING_DEVICE_GRANT_ORIGIN: origin,
      KEEPLING_TEST_DATABASE_URL: databaseUrl,
      KEEPLING_TEST_SECRET_KEY_BASE: 'mcp-protocol-lane-test-only-secret-key-base-00000000000000000000000000',
      MIX_ENV: 'test',
    }

    // `runtime-preflight.sh` itself `cd`s to the repository root before
    // `exec "$@"`, so every command below reaches apps/server through its
    // own `cd apps/server &&` rather than a `cwd` option the preflight
    // script would silently override.
    runChecked('database migrations', ['sh', '-c', 'cd apps/server && mix ecto.migrate'], repositoryRoot, mixEnv)

    // The Elixir source below is passed through a SHELL VARIABLE
    // reference (`"$KEEPLING_LANE_ACCOUNT_SCRIPT"`), never interpolated
    // literally into the `sh -c` string. A literal interpolation would
    // have its own `$1`/`$2`/`$3` (Ecto's SQL positional parameters)
    // expanded as EMPTY shell positional parameters before Elixir ever
    // saw them -- measured while writing this lane. A shell variable
    // REFERENCE is expanded once, wholesale, with no further rescan of
    // its value for `$`-sequences, which is exactly what is needed here.
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
      env: { ...mixEnv, PHX_SERVER: 'true', PORT: String(phoenixPort) },
      stdio: 'ignore',
    })
    owned.push(phoenix)
    await waitForPort('Phoenix', phoenixPort, LOOPBACK)

    // --- The real handshake over the real transport, starting here. ---

    const login = await fetch(`${origin}/api/v1/login`, {
      body: JSON.stringify({ client_kind: 'web', label: 'MCP protocol lane', password, version: 1 }),
      headers: { 'Content-Type': 'application/json', Origin: origin },
      method: 'POST',
    })
    if (login.status !== 200) throw new Error(`login failed with status ${String(login.status)}: ${await login.text()}`)
    const sessionCookie = (login.headers.get('set-cookie') ?? '').split(';')[0]
    if (!sessionCookie) throw new Error('login response carried no session cookie')

    const verifier = 'v'.repeat(64)
    const challenge = createHash('sha256').update(verifier).digest('base64url')
    const state = createHash('sha256').update('mcp-protocol-lane-state').digest('base64url')

    const authorizeUrl = new URL(`${origin}/oauth/authorize`)
    authorizeUrl.search = new URLSearchParams({
      client_id: 'mcp',
      code_challenge: challenge,
      code_challenge_method: 'S256',
      installation_id: 'protocol-lane',
      label: 'MCP protocol lane installation',
      redirect_uri: redirectUri,
      resource: resourceUri,
      response_type: 'code',
      scope: 'tasks.write',
      state,
    }).toString()

    const authorize = await fetch(authorizeUrl, { headers: { Cookie: sessionCookie }, redirect: 'manual' })
    if (authorize.status !== 302) throw new Error(`/oauth/authorize returned ${String(authorize.status)} instead of a redirect`)
    const location = new URL(authorize.headers.get('location') ?? '', origin)
    const code = location.searchParams.get('code')
    if (!code) throw new Error('/oauth/authorize redirect carried no authorization code')

    const exchange = await fetch(`${origin}/oauth/token`, {
      body: JSON.stringify({
        code,
        code_verifier: verifier,
        grant_type: 'authorization_code',
        redirect_uri: redirectUri,
        resource: resourceUri,
        state: location.searchParams.get('state'),
      }),
      headers: { 'Content-Type': 'application/json' },
      method: 'POST',
    })
    if (exchange.status !== 200) throw new Error(`/oauth/token returned ${String(exchange.status)}: ${await exchange.text()}`)
    const { access_token: accessToken } = await exchange.json()
    if (!accessToken) throw new Error('/oauth/token response carried no access_token')

    const initializeResponse = await fetch(`${origin}/mcp/v1`, {
      body: JSON.stringify({ id: 1, jsonrpc: '2.0', method: 'initialize', params: {} }),
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      method: 'POST',
    })
    if (initializeResponse.status !== 200) {
      throw new Error(`real /mcp/v1 initialize returned ${String(initializeResponse.status)}: ${await initializeResponse.text()}`)
    }
    const initializeBody = await initializeResponse.json()
    const protocolVersion = initializeBody?.result?.protocolVersion
    const capabilities = initializeBody?.result?.capabilities ?? {}

    // Assertion 1: the exact pinned revision, not merely a successful
    // handshake -- the first vacuity mode 05-VALIDATION.md names.
    if (protocolVersion !== PINNED_PROTOCOL_REVISION) {
      throw new Error(
        `server declared protocolVersion "${String(protocolVersion)}" over the real transport, expected exactly "${PINNED_PROTOCOL_REVISION}"`,
      )
    }

    // Assertion 2: the declared capabilities are EXACTLY the closed set
    // `KeeplingWeb.MCP.Handshake` declares (`tools`, `resources`) -- not
    // "at least these", not "a superset", exactly these two keys and no
    // others. `resources` is a disclosed stub as of 05-01/05-10 (no
    // `resources/*` method exists in the dispatch table yet -- see
    // 05-01-SUMMARY.md's Known Stubs); this assertion does not require
    // capability/method parity, because failing this lane on an already
    // disclosed, intentional gap would be exactly the false-negative noise
    // that erodes trust in a strict gate. What it DOES require is that the
    // capability set never silently grows or shrinks, and that the
    // dispatch module's own closed method set (read from source, not from
    // the live response) never silently drifts from what this lane
    // expects -- until 05-04's docs/architecture/MCP-SURFACE.md exists and
    // becomes the authority for both checks.
    const declaredCapabilities = Object.keys(capabilities).sort()
    const expectedCapabilities = ['resources', 'tools']
    if (JSON.stringify(declaredCapabilities) !== JSON.stringify(expectedCapabilities)) {
      throw new Error(
        `server declared capabilities [${declaredCapabilities.join(', ')}], expected exactly [${expectedCapabilities.join(', ')}]`,
      )
    }
    if (JSON.stringify(expectedMethods) !== JSON.stringify(EXPECTED_METHODS)) {
      throw new Error(
        `KeeplingWeb.MCP.Dispatch's @methods table is now [${expectedMethods.join(', ')}], but this lane's closed expectation is [${EXPECTED_METHODS.join(', ')}] -- update EXPECTED_METHODS in tooling/mcp-lanes/protocol.mjs (or point this assertion at docs/architecture/MCP-SURFACE.md once 05-04 lands)`,
      )
    }

    console.log(
      `PROTOCOL_HANDSHAKE protocol_version=${protocolVersion} capabilities=${declaredCapabilities.join(',')} methods=${expectedMethods.join(',')} cases=2 run_id=${randomUUID()}`,
    )
  } finally {
    await Promise.all(owned.reverse().map(stopOwned))
    rmSync(temporaryRoot, { force: true, recursive: true })
  }
}

const parseProtocolOutput = (stdout, stderr) => {
  const blockedLine = stdout.split('\n').find((line) => line.startsWith('BLOCKED:')) ?? stderr.split('\n').find((line) => line.startsWith('BLOCKED:'))
  if (blockedLine) throw new Error(blockedLine)

  const match = stdout.match(/PROTOCOL_HANDSHAKE protocol_version=(\S+) capabilities=(\S+) methods=(\S+) cases=(\d+)/)
  if (!match) {
    throw new Error(
      `protocol lane never reported a PROTOCOL_HANDSHAKE evidence line${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`,
    )
  }
  const [, protocolVersion, , , casesRaw] = match
  if (protocolVersion !== PINNED_PROTOCOL_REVISION) {
    throw new Error(`protocol lane reported protocolVersion "${protocolVersion}", expected exactly "${PINNED_PROTOCOL_REVISION}"`)
  }
  const cases = Number(casesRaw)
  if (!Number.isFinite(cases) || cases <= 0) throw new Error('protocol lane reported a non-positive case count')
  return cases
}

export default function protocolLane() {
  return {
    command: process.execPath,
    args: [fileURLToPath(import.meta.url), '--run'],
    cwd: repositoryRoot,
    name: 'protocol',
    parse: parseProtocolOutput,
    trackedInputPaths: [
      'apps/server/lib/keepling_web/mcp/dispatch.ex',
      'apps/server/lib/keepling_web/mcp/handshake.ex',
      'apps/server/lib/keepling_web/mcp/pipeline.ex',
      'apps/server/lib/keepling_web/mcp/metadata.ex',
      'tooling/mcp-lanes/protocol.mjs',
    ],
  }
}

if (import.meta.url === `file://${process.argv[1]}` && process.argv.includes('--run')) {
  try {
    await runHandshake()
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
