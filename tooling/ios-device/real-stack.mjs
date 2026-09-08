/**
 * THE single definition of "a real backend behind a recording proxy" for
 * every iOS lane (04-18-PLAN.md Task 1).
 *
 * Extracted verbatim from `tooling/verify-real-stack-ios.mjs`, which grew
 * it first and which now imports it. The extraction exists for the same
 * reason that file refuses to copy `apps/web/e2e/support/backend.ts` into
 * a `.mjs` twin: a second, drifting definition of "a real server" is the
 * failure this whole gate is built to prevent, and there are now THREE
 * callers (the server-half measurement, the simulator lane, and the device
 * lane) rather than one.
 *
 * IMPORTANT -- callers must re-exec with `--experimental-strip-types`
 * before importing this module. It pulls in the shared TypeScript backend
 * harness, and Node 22 cannot load that without the flag. Every entry
 * script does the re-exec itself rather than making a human remember it.
 *
 * WHY A RECORDING PROXY AND NOT CLIENT-SIDE ASSERTIONS
 * ---------------------------------------------------
 * Every adversarial claim in this phase is a claim about what the SERVER
 * received and did. A client-side assertion can only report what the
 * client believes it sent, and the whole class of bug worth catching --
 * a duplicate the client thinks it suppressed but the server accepted
 * twice -- is invisible from that side. So the proxy pipes real bytes to
 * real Phoenix, pipes the real answer back, and records arrival ORDER,
 * bodies, and statuses. It never answers on the server's behalf and never
 * synthesises a response.
 *
 * It is also the injection point: authentication expiry, duplicate replay,
 * and structured conflict are driven by what the proxy does to a FORWARDED
 * request (adding the server's own `x-keepling-test-fault` header), never
 * by a client-side stub.
 */
import { createServer as createHttpServer, request as httpRequest } from 'node:http'
import { createServer as createHttpsServer } from 'node:https'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { networkInterfaces, tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..', '..')
const LOOPBACK = '127.0.0.1'

export const DEFAULT_PHOENIX_PORT = Number(process.env.KEEPLING_IOS_E2E_PHOENIX_PORT ?? 4112)
export const DEFAULT_POSTGRES_PORT = Number(process.env.KEEPLING_IOS_E2E_POSTGRES_PORT ?? 55443)

/**
 * The address another host can actually reach this Mac at.
 *
 * MEASURED DEFECT this replaces (04-18-PLAN.md Task 1): the previous
 * implementation returned the FIRST non-`lo0` IPv4 that `networkInterfaces()`
 * happened to enumerate. On a Mac carrying a VPN (`utun*`), Docker
 * (`bridge100`), or a tethered device, that is routinely the wrong
 * interface -- and the phone then dials an address that does not route
 * here. The symptom is ZERO proxy arrivals, which is indistinguishable
 * from a certificate-trust failure and sends a reader debugging the wrong
 * layer entirely.
 *
 * The default route is the interface that actually carries traffic off
 * this machine, so ask the routing table rather than guessing from an
 * enumeration order that is not even documented as stable.
 *
 * Exported and overridable on purpose: the DEVICE lane deliberately wants
 * the TAILNET address rather than this one (a tailnet address rides a VPN
 * interface, which is exactly what Apple TN3179 excludes from the
 * definition of a local network -- see 04-18-PLAN.md).
 */
export const defaultRouteAddress = () => {
  const route = spawnSync('route', ['-n', 'get', 'default'], { encoding: 'utf8' })
  const interfaceName = (route.stdout ?? '').match(/interface:\s*(\S+)/)?.[1]
  if (interfaceName) {
    for (const address of networkInterfaces()[interfaceName] ?? []) {
      if (address.family === 'IPv4' && !address.internal) return address.address
    }
  }
  // Only if the routing table told us nothing usable. Still skips loopback.
  for (const [name, addresses] of Object.entries(networkInterfaces())) {
    if (name === 'lo0') continue
    for (const address of addresses ?? []) {
      if (address.family === 'IPv4' && !address.internal) return address.address
    }
  }
  return null
}

/**
 * A self-signed certificate that a TLS client could at least attempt to
 * evaluate.
 *
 * MEASURED DEFECT this replaces: the previous certificate was generated
 * with `-subj /CN=keepling-lane` and NO subjectAltName. Apple platforms
 * dropped CommonName fallback entirely at iOS 13, so that certificate
 * could never have been accepted down ANY path -- including the paths a
 * later plan might reach for. It is also why the old TLS probe's result
 * ("the phone rejected the certificate") was correct but proved less than
 * it appeared to: a SAN-less certificate is refused before trust policy
 * is even consulted.
 *
 * This is used ONLY by the self-signed reachability probe. The device lane
 * uses a genuinely publicly-trusted certificate from `tailscale cert`, so
 * that the phone validates it with the SHIPPING trust path and no
 * test-only trust code is needed anywhere in the app.
 */
export const makeSelfSignedCertificate = (address) => {
  const pem = execFileSync(
    'openssl',
    [
      'req', '-x509',
      '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
      '-nodes', '-sha256',
      '-days', '2',
      '-subj', `/CN=${address}`,
      '-addext', `subjectAltName=IP:${address}`,
      '-addext', 'extendedKeyUsage=serverAuth',
      '-addext', 'basicConstraints=critical,CA:FALSE',
      '-addext', 'keyUsage=critical,digitalSignature,keyEncipherment',
      '-keyout', '-', '-out', '-',
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  )
  const key = pem.match(/-----BEGIN PRIVATE KEY-----[\s\S]+?-----END PRIVATE KEY-----/)?.[0]
  const cert = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/)?.[0]
  if (!key || !cert) throw new Error('openssl produced no usable key/certificate pair for the lane probe')
  return { cert: `${cert}\n`, key: `${key}\n` }
}

/**
 * The recording forwarding proxy. Records ARRIVAL ORDER, not just
 * presence: "the server received these two in this order" is a different
 * and stronger claim than "the server received these", and
 * settle-exactly-once needs the stronger one.
 */
const createRecordingProxy = ({ upstreamPort, tls, controlToken }) => {
  const records = []
  /** @type {Array<{ match: (path: string) => boolean, header: string, value: string, remaining: number }>} */
  const injections = []

  const handler = (incoming, outgoing) => {
    // ---- Harness control channel, handled BEFORE anything is forwarded.
    //
    // The four scenarios each need a DIFFERENT fault armed immediately
    // before they run, and the test that runs them lives on the phone. Path
    // matching alone cannot separate them -- every command push hits the
    // same endpoint -- and body matching is impossible here because the
    // injection decision is made at request start, before the body has
    // streamed in.
    //
    // So the test arms its own scenario over this channel. That is the test
    // coordinating the harness, which is categorically different from the
    // test manufacturing the evidence: nothing here answers on the server's
    // behalf, and every assertion still reads what the REAL server did with
    // the REAL bytes. The control paths are reserved under `/__lane/`, are
    // never forwarded upstream, and are never recorded as arrivals -- so a
    // control call can never be mistaken for a command the server received.
    if ((incoming.url ?? '').startsWith('/__lane/')) {
      const url = new URL(incoming.url, 'http://lane.invalid')
      if (url.pathname === '/__lane/arm') {
        const fault = url.searchParams.get('fault')
        const pathFragment = url.searchParams.get('path') ?? '/api/v1/commands/'
        const times = Number(url.searchParams.get('times') ?? 1)
        injections.push({
          header: 'x-keepling-test-fault',
          match: (path) => path.includes(pathFragment),
          remaining: times,
          token: controlToken,
          tokenHeader: 'x-keepling-test-fault-token',
          value: fault,
        })
        outgoing.writeHead(200, { 'content-type': 'application/json' })
        outgoing.end(JSON.stringify({ armed: fault, path: pathFragment, times }))
        return
      }
      if (url.pathname === '/__lane/disarm') {
        injections.length = 0
        outgoing.writeHead(200, { 'content-type': 'application/json' })
        outgoing.end('{"disarmed":true}')
        return
      }
      outgoing.writeHead(404, { 'content-type': 'application/json' })
      outgoing.end('{"error":"unknown lane control path"}')
      return
    }

    const chunks = []
    incoming.on('data', (chunk) => chunks.push(chunk))
    const record = {
      arrivalOrder: records.length,
      body: null,
      injected: null,
      method: incoming.method,
      path: incoming.url ?? '',
      receivedAt: Date.now(),
      status: null,
    }
    records.push(record)

    // The `Host` header is forwarded UNCHANGED. Rewriting it to the
    // upstream's own address breaks the server's origin check:
    // `require_trusted_origin` compares `Origin` against
    // `scheme://<host header>`, so a rewritten host makes every
    // browser-class request 403 (measured during 04-16's execution).
    const headers = { ...incoming.headers }
    const injection = injections.find((rule) => rule.remaining > 0 && rule.match(record.path))
    if (injection) {
      // Server-side injection: the FORWARDED request carries the fault
      // header, so the real server produces the real refusal. The client
      // is never told anything the server did not say.
      headers[injection.header] = injection.value
      headers[injection.tokenHeader] = injection.token
      injection.remaining -= 1
      record.injected = injection.value
    }

    const upstream = httpRequest(
      { headers, host: LOOPBACK, method: incoming.method, path: record.path, port: upstreamPort },
      (response) => {
        record.status = response.statusCode ?? 502
        outgoing.writeHead(response.statusCode ?? 502, response.headers)
        response.pipe(outgoing)
      },
    )
    upstream.once('error', () => outgoing.destroy())
    incoming.on('end', () => {
      record.body = Buffer.concat(chunks).toString('utf8')
    })
    incoming.pipe(upstream)
  }

  const server = tls ? createHttpsServer({ cert: tls.cert, key: tls.key }, handler) : createHttpServer(handler)

  return {
    inject: ({ match, value, token, times = 1 }) => {
      injections.push({
        header: 'x-keepling-test-fault',
        match,
        remaining: times,
        token,
        tokenHeader: 'x-keepling-test-fault-token',
        value,
      })
    },
    /**
     * Binds on port 0 by default and reports the port the OS actually
     * assigned.
     *
     * MEASURED DEFECT this replaces: the proxy used a FIXED port, and the
     * old `refuseHeldPorts()` aborted the whole lane and instructed the
     * developer to find and kill PIDs by hand whenever a previous run had
     * died without shutting down. That was the second most frequent human
     * touchpoint in this gate, and it fired precisely when someone was
     * already debugging something else.
     */
    listen: (host, port = 0) =>
      new Promise((resolvePromise, reject) => {
        server.once('error', reject)
        server.listen(port, host, () => resolvePromise(server.address().port))
      }),
    records,
    close: () =>
      new Promise((resolvePromise) => {
        server.closeAllConnections()
        server.close(() => resolvePromise())
      }),
  }
}

/** A real browser-class client against the real server, through the proxy. */
export const createClient = (base) => ({
  cookie: '',
  csrfToken: '',
  async request(path, init = {}) {
    const response = await fetch(new URL(path, base), {
      ...init,
      headers: {
        accept: 'application/json',
        origin: base,
        ...(this.cookie === '' ? {} : { cookie: this.cookie }),
        ...(this.csrfToken === '' ? {} : { 'x-csrf-token': this.csrfToken }),
        ...(init.headers ?? {}),
      },
      redirect: 'manual',
    })
    const set = response.headers.getSetCookie?.() ?? []
    if (set.length > 0) this.cookie = set.map((value) => value.split(';')[0]).join('; ')
    return response
  },
  async signIn() {
    const session = await this.request('/api/v1/test/session', {
      body: '{}',
      headers: { 'content-type': 'application/json' },
      method: 'POST',
    })
    if (session.status !== 200) throw new Error(`the real server refused a session: ${session.status}`)
    this.csrfToken = (await session.json()).csrf_token
  },
})

/**
 * Drives the real RFC 8252 authorization-code-with-PKCE flow against the
 * real server and returns a genuine device-grant bearer credential.
 *
 * Mirrors `DeviceGrantClient.beginAuthorization` exactly -- same client_id,
 * same closed parameter set, same S256 challenge derivation -- because the
 * point is to obtain the credential the APP would obtain, not a
 * test-only token minted down some side path. If this drifts from the
 * Swift side, the lane stops proving what it claims to prove.
 *
 * `client` must already hold an authenticated browser session: the
 * authorize endpoint is what turns a signed-in human into a device grant,
 * and it is the only step in the flow a native app delegates to a browser.
 */
export const issueDeviceGrant = async (client, { installationId, label = 'Keepling lane' } = {}) => {
  const verifier = randomBytes(32).toString('base64url')
  const state = randomBytes(32).toString('base64url')
  const challenge = createHash('sha256').update(verifier).digest('base64url')
  // The iPhone's callback is distinguished from the desktop's by HOST, not
  // by scheme: `keepling://ios/auth/callback`, not `keepling://auth/callback`
  // (apps/server/config/runtime.exs, :device_grants redirect_uris). The
  // server allowlists them separately and refuses anything else with a
  // generic invalid_authorization_request, so getting this wrong reads as
  // "the flow is broken" rather than "the URI is the desktop's".
  const redirectURI = 'keepling://ios/auth/callback'

  const query = new URLSearchParams({
    client_id: 'iphone',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    installation_id: installationId ?? randomUUID(),
    label,
    redirect_uri: redirectURI,
    response_type: 'code',
    state,
  })
  const authorize = await client.request(`/oauth/authorize?${query}`)
  if (authorize.status !== 302 && authorize.status !== 200) {
    throw new Error(`the real server refused to authorize a device grant: ${authorize.status} ${await authorize.text()}`)
  }
  // The authorization result is a redirect BACK to the native callback URL,
  // exactly as it would be for the app. Read the code out of it rather than
  // out of any server-internal structure.
  const location = authorize.headers.get('location') ?? ''
  const callback = new URL(location, redirectURI)
  const code = callback.searchParams.get('code')
  const returnedState = callback.searchParams.get('state')
  if (!code) throw new Error(`the authorize redirect carried no code: ${location}`)
  if (returnedState !== state) throw new Error('the authorize redirect returned a different state than was sent')

  const exchange = await client.request('/oauth/token', {
    body: JSON.stringify({
      code,
      code_verifier: verifier,
      grant_type: 'authorization_code',
      redirect_uri: redirectURI,
      state,
    }),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
  })
  if (exchange.status !== 200) {
    throw new Error(`the real server refused the code exchange: ${exchange.status} ${await exchange.text()}`)
  }
  const issued = await exchange.json()
  const accessToken = issued.access_token ?? issued.accessToken
  if (!accessToken) throw new Error(`the token response carried no access token: ${JSON.stringify(issued)}`)
  return { accessToken, raw: issued, refreshToken: issued.refresh_token ?? issued.refreshToken }
}

export const postCommand = (client, path, command) =>
  client.request(path, { body: JSON.stringify(command), headers: { 'content-type': 'application/json' }, method: 'POST' })

/**
 * Kills only the processes THIS lane's previous run leaked, identified by
 * this repository's own temporary prefix, and only on the two ports that
 * genuinely cannot float (PostgreSQL and Phoenix are addressed by the
 * shared harness before the proxy exists). Replaces the old
 * abort-and-demand-a-human path.
 *
 * Deliberately narrow: it never kills a process it cannot attribute to a
 * `kios-` temporary root, so an unrelated PostgreSQL a developer is using
 * for something else is left alone rather than silently destroyed.
 */
const reapStaleBackends = (ports) => {
  const reaped = []
  for (const port of ports) {
    const held = spawnSync('lsof', ['-ti', `tcp:${port}`], { encoding: 'utf8' })
    for (const pid of (held.stdout ?? '').split('\n').filter(Boolean)) {
      const commandLine = spawnSync('ps', ['-o', 'command=', '-p', pid], { encoding: 'utf8' }).stdout ?? ''
      if (!commandLine.includes('kios-')) {
        throw new Error(
          `port ${port} is held by pid ${pid}, which this lane cannot attribute to one of its own previous ` +
            `runs (no 'kios-' temporary root in its command line). Refusing to kill it -- this lane will ` +
            `never attach to, or destroy, a server it did not start. Command: ${commandLine.trim()}`,
        )
      }
      spawnSync('kill', ['-9', pid])
      reaped.push(`${pid}@${port}`)
    }
  }
  return reaped
}

/**
 * Waits until the real backend has finished starting.
 *
 * Without this a caller can launch a client before Phoenix is listening,
 * and the result is zero proxy arrivals -- which looks exactly like a
 * transport or trust failure and has already cost this phase debugging
 * time down the wrong path. Readiness is asserted, not slept on.
 *
 * Deliberately polls the UPSTREAM Phoenix on loopback rather than going
 * through the proxy. Two reasons, and the second is the load-bearing one:
 * the question being answered here is precisely "has the backend finished
 * starting", and mixing the proxy into it would conflate a slow boot with
 * a transport failure -- the exact conflation this gate keeps making. And
 * when the proxy terminates TLS with a certificate issued for a tailnet
 * name, a loopback probe through it would fail hostname validation for
 * reasons that have nothing to do with readiness.
 */
const awaitReadiness = async (base, attempts = 60) => {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const probe = await fetch(new URL('/api/v1/test/session', base), {
        body: '{}',
        headers: { accept: 'application/json', 'content-type': 'application/json', origin: base },
        method: 'POST',
      })
      if (probe.status < 500) return
    } catch {
      // Not listening yet.
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 500))
  }
  throw new Error(`the real backend never answered through the proxy at ${base} -- it did not finish starting`)
}

/**
 * Starts real PostgreSQL and real Phoenix behind the recording proxy.
 *
 * `bindHost` is '127.0.0.1' for the simulator (which shares this Mac's
 * network stack, so loopback IS the proxy and the app's production
 * transport guard admits it by literal host match) and '0.0.0.0' when a
 * physical device must reach it.
 */
export const startRecordingStack = async ({
  bindHost = LOOPBACK,
  tls = null,
  phoenixPort = DEFAULT_PHOENIX_PORT,
  postgresPort = DEFAULT_POSTGRES_PORT,
  onUnexpectedExit,
} = {}) => {
  const { startBackend, stopBackend } = await import(join(repositoryRoot, 'apps/web/e2e/support/backend.ts'))

  const reaped = reapStaleBackends([postgresPort, phoenixPort])
  // Short prefix on purpose: PostgreSQL's Unix-domain socket path has a
  // 103-byte limit and macOS's per-user temporary directory already spends
  // most of it (the desktop lane records the same measurement).
  const temporaryRoot = mkdtempSync(join(tmpdir(), 'kios-'))
  const faultToken = randomBytes(32).toString('hex')
  const ownedChildren = []

  // The proxy binds FIRST, because `startBackend` needs the port the
  // server's own generated URLs will advertise, and that port is now
  // assigned by the OS rather than fixed.
  const proxy = createRecordingProxy({ controlToken: faultToken, tls, upstreamPort: phoenixPort })
  const port = await proxy.listen(bindHost, 0)
  const scheme = tls ? 'https' : 'http'

  const stop = async () => {
    await proxy.close()
    await stopBackend(ownedChildren)
    rmSync(temporaryRoot, { force: true, recursive: true })
  }

  try {
    await startBackend({
      faultToken,
      onUnexpectedExit:
        onUnexpectedExit ??
        ((reason) => console.error(`iOS real-stack: a backend process exited unexpectedly -- ${reason}`)),
      ownedChildren,
      phoenixPort,
      postgresPort,
      secretKeyBase: randomBytes(48).toString('base64'),
      temporaryRoot,
      urlPort: port,
    })
    await awaitReadiness(`http://${LOOPBACK}:${phoenixPort}`)
  } catch (error) {
    await stop()
    throw error
  }

  return {
    baseURL: (host) => `${scheme}://${host}:${port}`,
    faultToken,
    inject: proxy.inject,
    loopbackURL: `${scheme}://${LOOPBACK}:${port}`,
    port,
    proxy,
    reaped,
    records: proxy.records,
    stop,
  }
}
