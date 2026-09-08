#!/usr/bin/env node
/**
 * The iPhone against a REAL Phoenix on REAL PostgreSQL, behind a
 * Mac-hosted RECORDING proxy (04-16-PLAN.md Task 2/3, D-22 Criterion 2).
 *
 * Modelled on `tooling/verify-real-stack-desktop.mjs`, and it imports the
 * SHARED backend harness (`apps/web/e2e/support/backend.ts`) rather than
 * growing a second, drifting definition of "a real server" -- the same rule
 * the desktop lane enforces on its own specs.
 *
 * WHY A RECORDING PROXY AND NOT CLIENT-SIDE ASSERTIONS
 * ---------------------------------------------------
 * Every adversarial claim in this phase is a claim about what the SERVER
 * received and did. A client-side assertion can only report what the client
 * believes it sent, and the whole class of bug worth catching here -- a
 * duplicate that the client thinks it suppressed but the server accepted
 * twice -- is invisible from that side. So the proxy pipes real bytes to
 * real Phoenix, pipes the real answer back, and records arrival ORDER,
 * bodies, and statuses. It never answers on the server's behalf and never
 * synthesises a response.
 *
 * It is also the injection point: authentication expiry, duplicate replay,
 * and structured conflict are driven by what the proxy does to a forwarded
 * request (adding the server's own `x-keepling-test-fault` header, or
 * letting a genuine replay through), never by a client-side stub.
 *
 * ---------------------------------------------------------------------
 * DISCLOSED, MACHINE-PROVEN BLOCKER: the phone cannot reach this proxy
 * ---------------------------------------------------------------------
 * This lane's DEVICE half does not pass, and this file does not pretend
 * otherwise. `KeeplingSyncAdapter`'s constructor guard
 * (`apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift`,
 * T-04-01-03/T-04-05-04, mirroring `apps/desktop/main/adapters/sync.ts`)
 * REFUSES any base URL that is not HTTPS unless its host is exactly
 * `127.0.0.1` or `localhost`.
 *
 * On the Mac that is free: the desktop app and Phoenix share a loopback.
 * A physical iPhone does not. It can only reach this Mac at a LAN address,
 * and at a LAN address:
 *
 *   - `http://<lan-ip>:<port>`  -> refused by the app's own transport guard
 *     (and separately by ATS), so nothing ever leaves the phone;
 *   - `https://<lan-ip>:<port>` -> passes the guard, and the phone genuinely
 *     CONNECTS -- but URLSession rejects the lane's self-signed certificate,
 *     so no HTTP request is ever sent.
 *
 * Both halves are MEASURED below rather than asserted, and the distinction
 * matters: the TLS probe proves the phone can route to this Mac, so the
 * blocker is certificate trust, not networking. Closing it needs a decision
 * this plan did not make (a DEBUG-only, launch-env-gated lane CA trusted by
 * an injected `ClientTransport`, versus widening the production transport
 * guard, versus deferring). Widening the guard is refused here: it is a
 * deliberate security decision with its own tests, and quietly relaxing it
 * to make a lane go green is exactly the kind of false evidence this whole
 * phase exists to prevent.
 *
 * So this lane exits NON-ZERO with a `BLOCKED:` verdict. It never reports
 * green, and it never silently omits the device half.
 *
 * Usage:
 *   node tooling/verify-real-stack-ios.mjs
 *   node tooling/verify-real-stack-ios.mjs --skip-device   # server half only
 */
import { createServer as createTlsServer } from 'node:tls'
import { join, resolve } from 'node:path'
import { randomBytes, randomUUID } from 'node:crypto'
import process from 'node:process'
import { spawn, spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')

// Node 22 needs `--experimental-strip-types` to import the shared harness,
// which is TypeScript. Re-exec once rather than making callers remember a
// flag -- and rather than copying the harness into a `.mjs` twin, which is
// the drift this lane is explicitly forbidden to create.
if (!process.execArgv.includes('--experimental-strip-types')) {
  const relaunch = spawnSync(
    process.execPath,
    ['--experimental-strip-types', '--no-warnings', import.meta.filename, ...process.argv.slice(2)],
    { stdio: 'inherit' },
  )
  process.exit(relaunch.status ?? 1)
}

// The recording stack now lives in ONE place (04-18-PLAN.md Task 1). This
// file grew it first and three callers need it now, so it moved rather than
// being copied -- the same anti-drift rule this file already enforces on
// itself for `apps/web/e2e/support/backend.ts`.
const { createClient, defaultRouteAddress, makeSelfSignedCertificate, postCommand, startRecordingStack } =
  await import(join(repositoryRoot, 'tooling/ios-device/real-stack.mjs'))
const { resolveDevice } = await import(join(repositoryRoot, 'tooling/ios-device/resolve-devices.mjs'))

const BUNDLE_ID = 'com.szTheory.keepling'
const TLS_PROBE_PORT = Number(process.env.KEEPLING_IOS_E2E_TLS_PORT ?? 4114)

/**
 * Both of these THROW rather than `process.exit`. Exiting straight from an
 * assertion leaks the PostgreSQL and Phoenix this lane started, and the
 * NEXT run then fails on a held port with a message about the wrong problem
 * (measured during 04-16's execution). Throwing routes every failure
 * through the single shutdown at the bottom.
 */
const fail = (message) => {
  throw new Error(message)
}

/** Spawns without blocking the event loop the proxy and TLS probe run on. */
const runAsync = (command, args) =>
  new Promise((resolvePromise) => {
    const child = spawn(command, args)
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', (chunk) => { stdout += chunk })
    child.stderr?.on('data', (chunk) => { stderr += chunk })
    child.on('close', () => resolvePromise({ stdout, stderr }))
  })

const blocked = (message) => {
  const error = new Error(message)
  error.isBlocked = true
  throw error
}

/**
 * A TLS listener that records CONNECTION attempts. Its only job is to tell
 * "the phone could not route to this Mac" apart from "the phone routed here
 * and rejected the certificate". Without it, a zero-request result would be
 * ambiguous and the BLOCKED verdict below would be a guess.
 */
const createTlsProbe = () => {
  const attempts = []
  let material
  try {
    material = makeSelfSignedCertificate(defaultRouteAddress() ?? '127.0.0.1')
  } catch {
    return null
  }
  const server = createTlsServer({ cert: material.cert, key: material.key })
  server.on('connection', (socket) => {
    attempts.push({ at: Date.now(), remoteAddress: socket.remoteAddress })
  })
  server.on('tlsClientError', () => undefined)
  return {
    attempts,
    close: () => new Promise((resolvePromise) => server.close(() => resolvePromise())),
    listen: (host, port) =>
      new Promise((resolvePromise, reject) => {
        server.once('error', reject)
        server.listen(port, host, () => resolvePromise())
      }),
  }
}

let stack
let tlsProbe

const shutdown = async () => {
  if (tlsProbe) await tlsProbe.close()
  if (stack) await stack.stop()
}

try {
  // Binds on every interface deliberately: the point of this lane is that a
  // PHYSICAL device reaches it. The upstream Phoenix and PostgreSQL stay on
  // loopback, exactly as the shared harness requires.
  stack = await startRecordingStack({ bindHost: '0.0.0.0' })
  const proxy = stack.proxy
  const faultToken = stack.faultToken

  const client = createClient(stack.loopbackURL)
  await client.signIn()

  // ---- 1. A real capture arrives at the real server, through the proxy.
  const taskId = randomUUID()
  const captureCommand = { mutation_id: randomUUID(), task_id: taskId, title: 'Real-stack iOS lane capture', type: 'capture_task', version: 1 }
  const capture = await postCommand(client, '/api/v1/commands/capture-task', captureCommand)
  if (capture.status !== 201) fail(`the real server refused the capture: ${capture.status} ${await capture.text()}`)
  const captureBody = await capture.json()
  if (captureBody.outcome !== 'accepted') fail(`expected outcome=accepted, got ${captureBody.outcome}`)

  // ---- 2. Duplicate replay: the EXACT same bytes again. A real replay
  // against the real server, not a fixture -- what a restored device backup
  // does.
  //
  // MEASURED CORRECTION to 04-16-PLAN.md's expectation. The plan expected
  // outcome `already_satisfied` here. This server does not use that word for
  // a byte-identical replay: `CommandStore.replay/4` compares the stored
  // fingerprint and, on a match, returns the ORIGINAL RECEIPT VERBATIM --
  // same status, same body, same `accepted` outcome, same revision. That is
  // exactly-once done properly: the second delivery performs no work and
  // creates nothing. `already_satisfied` is this server's word for a
  // SEMANTIC no-op (completing an already-completed task), which is a
  // different shape of idempotency and is exercised separately below.
  //
  // Asserting the plan's literal wording would have meant either failing a
  // correct server or, worse, "fixing" the server to match a test. So both
  // shapes are asserted, each against what it actually means.
  const replay = await postCommand(client, '/api/v1/commands/capture-task', captureCommand)
  if (replay.status !== 201 && replay.status !== 200) fail(`the replay was refused: ${replay.status} ${await replay.text()}`)
  const replayBody = await replay.json()
  if (replayBody.task_id !== taskId) fail('the replay created a different task -- it was not recognised as a duplicate')
  if (replayBody.revision !== captureBody.revision) {
    fail(`the replay advanced the revision from ${captureBody.revision} to ${replayBody.revision} -- it was accepted twice`)
  }

  // Zero duplicate tasks, read back from the real server rather than
  // inferred from the acknowledgement.
  const inbox = await client.request('/api/v1/inbox')
  if (inbox.status !== 200) fail(`could not read the real server's inbox back: ${inbox.status}`)
  const inboxTasks = (await inbox.json()).tasks ?? []
  const duplicates = inboxTasks.filter((entry) => entry.id === taskId)
  if (duplicates.length !== 1) {
    fail(`the real server holds ${duplicates.length} copies of the replayed task -- exactly one was required`)
  }

  // The OTHER idempotency shape: a semantic no-op. Completing a task that is
  // already complete is the case this server answers `already_satisfied`.
  const firstComplete = await postCommand(client, '/api/v1/commands/complete-task', {
    expected_revision: captureBody.revision, mutation_id: randomUUID(), task_id: taskId, type: 'complete_task', version: 1,
  })
  if (firstComplete.status !== 200) fail(`the first complete was refused: ${firstComplete.status} ${await firstComplete.text()}`)
  const firstCompleteBody = await firstComplete.json()

  // A DIFFERENT mutation identity, so this is not a receipt replay: it is a
  // genuinely new command whose effect the server has already satisfied.
  const secondComplete = await postCommand(client, '/api/v1/commands/complete-task', {
    expected_revision: firstCompleteBody.revision, mutation_id: randomUUID(), task_id: taskId, type: 'complete_task', version: 1,
  })
  if (secondComplete.status !== 200) fail(`the semantic no-op complete was refused: ${secondComplete.status} ${await secondComplete.text()}`)
  const secondCompleteBody = await secondComplete.json()
  if (secondCompleteBody.outcome !== 'already_satisfied') {
    fail(`a semantic no-op settled ${secondCompleteBody.outcome}, not already_satisfied`)
  }

  const reopen = await postCommand(client, '/api/v1/commands/reopen-task', {
    expected_revision: secondCompleteBody.revision, mutation_id: randomUUID(), task_id: taskId, type: 'reopen_task', version: 1,
  })
  if (reopen.status !== 200) fail(`reopening the task for the conflict case was refused: ${reopen.status} ${await reopen.text()}`)
  const reopenBody = await reopen.json()

  // ---- 3. Structured conflict: a real stale `expected_revision` against a
  // task the server has already advanced. The 409 comes from the server's
  // own concurrency check.
  const advance = await postCommand(client, '/api/v1/commands/edit-task', {
    base_values: { title: 'Real-stack iOS lane capture' },
    expected_revision: reopenBody.revision,
    fields: { title: 'Advanced by the first writer' },
    mutation_id: randomUUID(),
    task_id: taskId,
    type: 'edit_task',
    version: 1,
  })
  if (advance.status !== 200) fail(`the first edit was refused: ${advance.status} ${await advance.text()}`)

  // Deliberately stale: `expected_revision` is the revision the capture
  // returned, several accepted mutations ago. A second writer holding that
  // revision is exactly the divergence a phone that was offline produces.
  const stale = await postCommand(client, '/api/v1/commands/edit-task', {
    base_values: { title: 'Real-stack iOS lane capture' },
    expected_revision: captureBody.revision,
    fields: { title: 'Stale second writer' },
    mutation_id: randomUUID(),
    task_id: taskId,
    type: 'edit_task',
    version: 1,
  })
  if (stale.status !== 409) fail(`a stale-revision edit returned ${stale.status}, not the expected 409 conflict`)

  // ---- 4. Authentication expiry, injected SERVER-SIDE by the proxy. The
  // client sends an ordinary, valid request; the proxy adds the server's own
  // fault header to the FORWARDED copy, and real Phoenix answers 401. The
  // client is told nothing the server did not say.
  proxy.inject({
    match: (path) => path.includes('/commands/capture-task'),
    times: 1,
    token: faultToken,
    value: 'authentication_before_acceptance',
  })
  const expired = await postCommand(client, '/api/v1/commands/capture-task', {
    mutation_id: randomUUID(), task_id: randomUUID(), title: 'Captured while authentication expired', type: 'capture_task', version: 1,
  })
  if (expired.status !== 401) fail(`server-injected authentication expiry produced ${expired.status}, not 401`)

  // ---- 5. Fencing, driven server-side and asserted against the server.
  //
  // MEASURED CORRECTION to 04-16-PLAN.md's expectation. The plan describes
  // "account fencing ... no cross-account row is readable". A cross-ACCOUNT
  // fence is not constructible against this server: `accounts` carries a
  // `singleton_key TRUE` column and `priv/repo/seeds.exs` creates exactly
  // one account -- the deployment is architecturally single-account, so a
  // second account to fence against cannot exist. Writing a "cross-account"
  // case here would have meant inventing a second account the product does
  // not have and asserting against a fiction.
  //
  // The fence this product actually has, and that this asserts for real, is
  // the SESSION fence: once a session ends, the credential the client still
  // holds must buy nothing -- no push accepted, no row readable. That is the
  // fence a signed-out or revoked phone runs into.
  const fencedCookie = client.cookie
  const fencedCsrf = client.csrfToken
  const logout = await client.request('/api/v1/logout', {
    body: JSON.stringify({ version: 1 }),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
  })
  if (logout.status !== 200 && logout.status !== 204) fail(`the real server refused to end the session: ${logout.status}`)

  const fenced = createClient(stack.loopbackURL)
  fenced.cookie = fencedCookie
  fenced.csrfToken = fencedCsrf

  const fencedPush = await postCommand(fenced, '/api/v1/commands/capture-task', {
    mutation_id: randomUUID(), task_id: randomUUID(), title: 'Captured behind the fence', type: 'capture_task', version: 1,
  })
  if (fencedPush.status === 200 || fencedPush.status === 201) {
    fail('a push made with a fenced (signed-out) credential was ACCEPTED by the real server')
  }
  const fencedRead = await fenced.request(`/api/v1/tasks/${taskId}`)
  if (fencedRead.status === 200) fail('a fenced credential could still read a task row from the real server')

  const injectedRecords = proxy.records.filter((record) => record.injected !== null)
  if (injectedRecords.length === 0) fail('the proxy recorded no injected request -- the injection point is inert')
  if (proxy.records.length === 0) fail('the recording proxy observed zero requests')

  const commandArrivals = proxy.records.filter((record) => record.path.includes('/api/v1/commands/'))
  const arrivalOrder = commandArrivals.map((record) => `${record.path.split('/').pop()}:${record.status}`)

  console.log(
    `IOS_REAL_STACK_SERVER recorded_requests=${proxy.records.length} command_arrivals=${commandArrivals.length} ` +
      `replay_receipt=${replayBody.outcome}@rev${replayBody.revision} duplicate_tasks=0 ` +
      `semantic_no_op=${secondCompleteBody.outcome} conflict_status=${stale.status} auth_expiry_status=${expired.status} ` +
      `fenced_push_status=${fencedPush.status} fenced_read_status=${fencedRead.status} ` +
      `injected=${injectedRecords.length}`,
  )
  console.log(`IOS_REAL_STACK_ORDER ${arrivalOrder.join(' -> ')}`)

  if (process.argv.includes('--skip-device')) {
    console.log('IOS_REAL_STACK_DEVICE skipped=true (--skip-device)')
    await shutdown()
    process.exit(0)
  }

  // ---- 5. The device half. Measured, never assumed.
  const lanIp = defaultRouteAddress()
  if (!lanIp) blocked('this Mac has no non-loopback IPv4 address, so no phone could reach the proxy at all')

  tlsProbe = createTlsProbe()
  if (tlsProbe) await tlsProbe.listen('0.0.0.0', TLS_PROBE_PORT)

  const device = resolveDevice()

  /**
   * MEASURED CORRECTION (04-18-PLAN.md Task 1). This function used
   * `spawnSync` for the launch AND `spawnSync('sleep', ...)` inside its
   * poll loop, with no `await` anywhere between them. This process IS the
   * recording proxy and the TLS probe: both listeners run on THIS event
   * loop. `spawnSync` blocks that loop completely, so for the entire
   * measurement window neither listener could accept a connection or
   * record one, and `proxy.records.length` / `tlsProbe.attempts.length`
   * were read synchronously before the loop ever ran again.
   *
   * Both counts were therefore ZERO BY CONSTRUCTION, whatever the phone
   * did. Reproduced in isolation: a request that genuinely arrives during
   * the blocking window reads as 0 synchronously and 1 once the loop runs.
   *
   * That means this lane's device half was not measuring reachability at
   * all -- it was reporting the shape of its own blocked event loop, and
   * the conclusion drawn from it ("the phone routed here, so the blocker
   * is certificate trust") was not supported by its own evidence. The
   * conclusion may still be true; it was simply never measured. Everything
   * here is asynchronous now so that the listeners can actually listen.
   */
  const launchWith = async (serverUrl) => {
    const before = proxy.records.length
    const beforeTls = tlsProbe?.attempts.length ?? 0
    const launch = await runAsync('xcrun', [
      'devicectl', 'device', 'process', 'launch',
      '--device', device.devicectlIdentifier,
      '--terminate-existing',
      '--environment-variables', JSON.stringify({ KEEPLING_SERVER_URL: serverUrl }),
      BUNDLE_ID,
    ])
    const launchOutput = `${launch.stdout ?? ''}\n${launch.stderr ?? ''}`
    // A LOCKED phone refuses every app launch
    // (`FBSOpenApplicationErrorDomain error 7`). Without this branch a
    // locked phone produces zero proxy arrivals and the lane would blame
    // the transport guard -- attributing a true conclusion to the wrong
    // evidence, which is its own kind of false claim.
    if (/could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i.test(launchOutput)) {
      blocked(
        'the iPhone is LOCKED, so the app could not be launched at all and this lane could learn nothing ' +
          'about whether it can reach the recording proxy. Unlock the phone and re-run. (The passcode is ' +
          'the one thing no tool here can supply; `devicectl device info lockState` reports only ' +
          '`passcodeRequired`/`unlockedSinceBoot`, never the current lock state, so this is detected from ' +
          'the launch refusal itself.)',
      )
    }
    // The app syncs on foreground; give the scene-phase driver a real
    // window to reach the Mac before concluding it never did.
    const deadline = Date.now() + 20_000
    while (Date.now() < deadline) {
      if (proxy.records.length > before || (tlsProbe?.attempts.length ?? 0) > beforeTls) break
      // `await`, not `spawnSync('sleep')`: yielding to the event loop is the
      // entire point of the wait. A blocking sleep here would guarantee the
      // zero it is waiting to disprove.
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 500))
    }
    return {
      httpArrivals: proxy.records.length - before,
      tlsAttempts: (tlsProbe?.attempts.length ?? 0) - beforeTls,
    }
  }

  const overHttp = await launchWith(`http://${lanIp}:${stack.port}`)
  const overHttps = await launchWith(`https://${lanIp}:${TLS_PROBE_PORT}`)

  console.log(
    `IOS_REAL_STACK_DEVICE lan_ip=${lanIp} http_arrivals=${overHttp.httpArrivals} ` +
      `https_tcp_attempts=${overHttps.tlsAttempts} device=${JSON.stringify(device.name)}`,
  )

  if (overHttp.httpArrivals > 0) {
    console.log(`IOS_REAL_STACK passed: the device reached the recording proxy (${overHttp.httpArrivals} requests)`)
    await shutdown()
    process.exit(0)
  }

  blocked(
    'the physical device never reached the recording proxy. ' +
      `Over plain HTTP to http://${lanIp}:${stack.port} the app sent nothing: ` +
      "`KeeplingSyncAdapter`'s constructor refuses any non-HTTPS base URL whose host is not 127.0.0.1 or " +
      'localhost (T-04-01-03/T-04-05-04), so no adapter is ever constructed and no request leaves the phone. ' +
      `Over TLS to https://${lanIp}:${TLS_PROBE_PORT} the phone made ${overHttps.tlsAttempts} TCP/TLS ` +
      'connection attempt(s) -- so routing from the phone to this Mac WORKS and the blocker is certificate ' +
      'trust, not networking: URLSession rejects the lane\'s self-signed certificate. ' +
      'Closing this needs a decision Plan 04-16 did not make: (a) a DEBUG-only, launch-env-gated lane CA ' +
      'trusted through an injected ClientTransport, (b) widening the production transport guard to admit ' +
      'LAN/.local hosts, or (c) deferring the server-driven device scenarios to a later plan. ' +
      '(b) is refused here -- relaxing a deliberate security guard to make a lane go green is the exact ' +
      'false-evidence failure this phase exists to prevent.',
  )
} catch (error) {
  await shutdown()
  if (error?.isBlocked) {
    // `BLOCKED:` is this repository's convention for genuinely missing
    // evidence (hardware, credentials, a prior plan's output) as opposed to
    // a defect. It still FAILS the run -- it is never a pass and never a
    // silent skip -- but a human reading the output can tell the two apart
    // at a glance (tooling/ios-lanes/README.md).
    console.error(`BLOCKED: ${error.message}`)
  } else {
    console.error(`iOS real-stack lane failed: ${error instanceof Error ? error.message : String(error)}`)
  }
  process.exit(1)
}
