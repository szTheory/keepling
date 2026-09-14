#!/usr/bin/env node
/**
 * Runs the four SERVER-DRIVEN scenarios of D-22 Criterion 2 through the
 * real Swift client against real Phoenix on real PostgreSQL, behind the
 * recording proxy (04-18-PLAN.md Tasks 3-4).
 *
 * One runner, two destinations. `--destination` selects the simulator
 * (loopback, where the app's own transport guard admits `127.0.0.1` by
 * literal host match and no certificate question arises) or a physical
 * iPhone over the tailnet. The SCENARIOS and the assertions are identical
 * either way -- that is the whole reason they live in a hosted unit-test
 * bundle rather than a UI test.
 *
 * WHAT THIS RUNNER OWNS AND WHAT THE SWIFT SUITE OWNS
 * ---------------------------------------------------
 * This runner owns everything that must be true BEFORE a client exists: a
 * real backend, a real device-grant credential obtained through the real
 * RFC 8252 PKCE flow, and a second credential the real server has actually
 * REVOKED. The Swift suite owns the client behaviour. The proxy owns the
 * record, and the assertions below read that record -- never a client's
 * report of itself.
 */
import { spawn, spawnSync } from 'node:child_process' // spawnSync: re-exec only, before the proxy exists
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..', '..')

// Node 22 needs `--experimental-strip-types` to reach the shared TypeScript
// backend harness through the stack module. Re-exec once rather than making
// every caller remember a flag.
if (!process.execArgv.includes('--experimental-strip-types')) {
  const relaunch = spawnSync(
    process.execPath,
    ['--experimental-strip-types', '--no-warnings', import.meta.filename, ...process.argv.slice(2)],
    { stdio: 'inherit' },
  )
  process.exit(relaunch.status ?? 1)
}

const { createClient, issueDeviceGrant, startRecordingStack } = await import(
  `${repositoryRoot}/tooling/ios-device/real-stack.mjs`
)

const argumentValue = (name, fallback) => {
  const index = process.argv.indexOf(name)
  return index === -1 ? fallback : process.argv[index + 1]
}

/**
 * `--device` resolves the attached iPhone's HARDWARE UDID, which is the
 * identifier space `xcodebuild -destination` speaks. The CoreDevice
 * identifier is a DIFFERENT space and belongs only to `devicectl`;
 * `resolve-devices.mjs` refuses to run if the two are ever equal, so
 * neither can be handed to the wrong tool from here (T-04-16-02).
 */
const destination = process.argv.includes('--device')
  ? `platform=iOS,id=${(await import(`${repositoryRoot}/tooling/ios-device/resolve-devices.mjs`)).resolveDevice().hardwareUdid}`
  : argumentValue('--destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest')

/**
 * `--tls-tailnet` is how a PHYSICAL iPhone reaches this proxy.
 *
 * Not a LAN address: Apple TN3179 gates every outgoing TCP connection to a
 * local network address behind a privilege that cannot be granted by MDM or
 * any tool and resets when the app is deleted -- an irreducible human tap.
 * A tailnet address rides a VPN interface, which TN3179 excludes from the
 * definition of a local network, and `tailscale cert` issues a real
 * Let's Encrypt certificate for it. The phone therefore validates with the
 * SHIPPING trust path and the app needs no test-only trust code at all.
 * See `tooling/ios-device/tailnet.mjs` for the full reasoning.
 */
const useTailnet = process.argv.includes('--tls-tailnet')
let bindHost = argumentValue('--bind-host', '127.0.0.1')
let advertiseHost = argumentValue('--advertise-host', '127.0.0.1')
let tls = null
let displayHost = advertiseHost

if (useTailnet) {
  // MEASURED DEFECT this try/catch repairs: every statement in this block
  // runs BEFORE the `try` at the bottom of the file that turns an
  // `isBlocked` error into a `BLOCKED:` marker line. The tailnet preflight
  // is precisely where blocked conditions are DETECTED -- an offline peer,
  // an unissuable certificate -- so the one place that raises them was the
  // one place that could not report them. An offline phone therefore
  // escaped as an uncaught exception, printed Node's stack-trace format
  // instead of the marker `tooling/ios-lanes/server-driven-device.mjs`
  // scans for, and the gate recorded `status=FAIL cases=0`.
  //
  // That is the anti-vacuity contract (D-24/D-25) broken in its less
  // obvious direction. The rule that a blocked lane must never read as
  // PASSED has a mirror: it must never read as FAILED either. A FAIL is a
  // claim that the code under test is wrong, and "Tailscale is toggled off
  // on the phone" is not a claim about this codebase at all. Recording it
  // as one sends the next reader to debug the wrong layer -- the exact
  // failure mode the comment below already warns about, reproduced one
  // level up.
  try {
    const { issueTailnetCertificate, redactFQDN, requireOnlineIOSPeer, tailnetFQDN } = await import(
      `${repositoryRoot}/tooling/ios-device/tailnet.mjs`
    )
    // Peer first, certificate second: a phone that is not on the tailnet
    // produces a connection timeout later that looks exactly like a
    // certificate problem, and this phase has already lost enough time to
    // failures that pointed at the wrong layer.
    requireOnlineIOSPeer()
    const fqdn = tailnetFQDN()
    tls = issueTailnetCertificate(fqdn)
    // Every interface, so the tailnet one is included. Phoenix and PostgreSQL
    // stay on loopback exactly as the shared harness requires.
    bindHost = '0.0.0.0'
    advertiseHost = fqdn
    // The MagicDNS name embeds the tailnet name, which identifies the
    // account. This repository may become open source and its lane output is
    // read into committed evidence, so what gets PRINTED is redacted while
    // what gets DIALLED is the real name.
    displayHost = redactFQDN(fqdn)
  } catch (error) {
    // Same two branches, same marker, same exit code as the handler at the
    // bottom of this file. Deliberately duplicated rather than factored out:
    // there is no `stack` to stop here (nothing has started yet), and the
    // shape that matters -- `BLOCKED: ` at the start of a line -- is what
    // the lane parser keys on.
    if (error?.isBlocked) {
      console.error(`BLOCKED: ${error.message}`)
    } else {
      console.error(`iOS server-driven lane failed: ${error instanceof Error ? error.message : String(error)}`)
    }
    process.exit(1)
  }
}

const fail = (message) => {
  throw new Error(message)
}

/**
 * Runs a child process WITHOUT blocking Node's event loop.
 *
 * `spawnSync` would be simpler and is wrong here, load-bearingly so. This
 * process IS the recording proxy: the HTTP server the client under test
 * connects to runs on this event loop. `spawnSync` blocks that loop for the
 * entire life of the child, so for the whole duration of an `xcodebuild
 * test` run the proxy can neither accept a connection nor answer one. Every
 * request from the client times out (NSURLErrorDomain -1001), and the
 * recorded arrival count is ZERO -- not because the client failed to send,
 * but because nothing was ever there to listen. Measured: the first version
 * of this runner used `spawnSync` and produced exactly that, including a
 * timeout on the lane's own control-channel call.
 *
 * A lane that measures reachability while holding its own listener shut is
 * not measuring reachability. Every child here is spawned asynchronously.
 */
const run = (command, args, options = {}) =>
  new Promise((resolvePromise) => {
    const child = spawn(command, args, { cwd: repositoryRoot, ...options })
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', (chunk) => { stdout += chunk })
    child.stderr?.on('data', (chunk) => { stderr += chunk })
    child.on('close', (status) => resolvePromise({ status, stdout, stderr }))
  })

const runChecked = async (label, args) => {
  const result = await run('xcodebuild', args)
  if (result.status !== 0) {
    const errors = [...`${result.stdout ?? ''}\n${result.stderr ?? ''}`.matchAll(/^(.*error:.*)$/gm)]
      .map((match) => match[1])
      .slice(0, 8)
    fail(`${label} failed${errors.length > 0 ? `: ${errors.join(' | ')}` : ''}`)
  }
  return result
}

let stack

try {
  stack = await startRecordingStack({ bindHost, tls })

  // The harness dials the SAME URL it will hand the phone, not loopback.
  //
  // MEASURED: with TLS on, `stack.loopbackURL` is `https://127.0.0.1:<port>`,
  // and the tailnet certificate is issued for the MagicDNS NAME -- so Node's
  // own fetch rejected it on hostname mismatch and the lane died with a bare
  // "fetch failed" eight seconds in, before the build, pointing at nothing.
  // Using one URL for both also means the harness proves the phone's route
  // works before spending several minutes building for it.
  const harnessURL = stack.baseURL(advertiseHost)

  // ---- A real credential, through the real authorization flow.
  // Declared origin uses the scheme PHOENIX sees, not the one dialled --
  // the proxy terminates TLS and forwards over plain HTTP. See
  // `createClient` for why this is a harness-only concern.
  const browser = createClient(harnessURL, { origin: harnessURL.replace(/^https:/, 'http:') })
  await browser.signIn()
  const active = await issueDeviceGrant(browser, { installationId: `lane-active-${Date.now()}` })

  // ---- A second credential the real server has genuinely revoked. Not a
  // malformed token and not an empty header: the exact credential a
  // signed-out or remotely revoked phone still holds on disk.
  const revokedInstallation = `lane-revoked-${Date.now()}`
  const doomed = await issueDeviceGrant(browser, { installationId: revokedInstallation })
  const revoke = await fetch(new URL(`/api/v1/device-grants/${revokedInstallation}`, harnessURL), {
    headers: { accept: 'application/json', authorization: `Bearer ${doomed.accessToken}` },
    method: 'DELETE',
  })
  if (revoke.status !== 200 && revoke.status !== 204) {
    fail(`the real server refused to revoke the device grant under test: ${revoke.status} ${await revoke.text()}`)
  }

  const baseURL = harnessURL
  const arrivalsBefore = stack.records.length

  // HOW THE LANE ENVIRONMENT REACHES THE TESTS
  // ------------------------------------------
  // MEASURED: `TEST_RUNNER_`-prefixed build-setting overrides on
  // `xcodebuild test` do NOT reach a HOSTED UNIT-TEST bundle. That prefix
  // is the mechanism for a UI-test RUNNER process; a hosted unit-test
  // bundle is injected into the app under test and never sees it. Passing
  // them produced four tests that ran and reported "had no lane
  // environment" -- correctly, since they had none.
  //
  // The mechanism that does work on BOTH destinations is the `.xctestrun`
  // file: build once, write the variables into the test target's own
  // `EnvironmentVariables` dictionary, then run without rebuilding. This
  // also means the credential never appears in a process argument list,
  // which `ps` would expose to every user on the machine.
  // A locked phone, named in seconds rather than after a 300-second
  // destination timeout. No-op on the simulator, which cannot be locked.
  if (!destination.includes('Simulator')) {
    const { probeLockState, LOCKED_MESSAGE } = await import(`${repositoryRoot}/tooling/ios-device/lock-probe.mjs`)
    const { resolveDevice } = await import(`${repositoryRoot}/tooling/ios-device/resolve-devices.mjs`)
    if (probeLockState({ devicectlIdentifier: resolveDevice().devicectlIdentifier }).locked) {
      const blocked = new Error(LOCKED_MESSAGE)
      blocked.isBlocked = true
      throw blocked
    }
  }

  // One derived-data tree PER PLATFORM. Sharing one tree between the two
  // destinations is what made `server-driven-sim` fail reproducibly inside
  // the full gate while passing standalone: `Build/Products` accumulated an
  // `.xctestrun` from BOTH platforms, and the selection below took the first
  // one by name. `iphoneos` sorts before `iphonesimulator`, so once the
  // device lane had run, the simulator lane launched the DEVICE-built app on
  // the simulator and died with "Launchd job spawn failed" -- an error that
  // names nothing about the real cause.
  const platform = destination.includes('iOS Simulator') ? 'iphonesimulator' : 'iphoneos'
  const derivedData = join(repositoryRoot, `.artifacts/ios/DerivedData-server-driven-${platform}`)
  await runChecked('build-for-testing', [
    'build-for-testing',
    '-project', 'apps/ios/Keepling.xcodeproj',
    '-scheme', 'Keepling',
    '-destination', destination,
    '-destination-timeout', '300',
    '-derivedDataPath', derivedData,
    ...(process.argv.includes('--allow-provisioning-updates') ? ['-allowProvisioningUpdates'] : []),
  ])

  // Belt as well as braces: even inside a per-platform tree, select the
  // `.xctestrun` whose name carries THIS destination's platform, and refuse
  // an ambiguous choice rather than silently taking the first. A run that
  // picks the wrong one does not fail with a wrong-platform message -- it
  // fails deep inside the simulator with a launchd spawn error.
  const products = readdirSync(join(derivedData, 'Build/Products')).filter((name) => name.endsWith('.xctestrun'))
  const matching = products.filter((name) => name.includes(platform))
  if (matching.length === 0) {
    fail(
      `build-for-testing produced no ${platform} .xctestrun file` +
        (products.length > 0 ? ` (found only: ${products.join(', ')})` : ''),
    )
  }
  if (matching.length > 1) fail(`build-for-testing produced ${matching.length} ${platform} .xctestrun files: ${matching.join(', ')}`)
  const xctestrun = join(derivedData, 'Build/Products', matching[0])

  for (const [key, value] of Object.entries({
    KEEPLING_LANE_BASE_URL: baseURL,
    KEEPLING_LANE_BEARER: active.accessToken,
    KEEPLING_LANE_REVOKED_BEARER: doomed.accessToken,
  })) {
    const written = await run('plutil', [
      '-replace', `KeeplingCoreTests.EnvironmentVariables.${key}`, '-string', value, xctestrun,
    ])
    if (written.status !== 0) fail(`could not write ${key} into the .xctestrun: ${written.stderr}`)
  }

  const test = await run('xcodebuild', [
    'test-without-building',
    '-xctestrun', xctestrun,
    '-destination', destination,
    '-destination-timeout', '300',
    '-only-testing:KeeplingCoreTests/ServerDrivenTests',
  ])
  const output = `${test.stdout ?? ''}\n${test.stderr ?? ''}`

  if (/could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i.test(output)) {
    const blocked = new Error(
      'the iPhone is LOCKED, so no app could be launched and this lane could learn nothing. Unlock it and ' +
        're-run. (Set Auto-Lock to Never and keep the phone on power -- this is the one condition in this ' +
        'gate whose remedy is a human hand, and that setting removes it permanently.)',
    )
    blocked.isBlocked = true
    throw blocked
  }
  // `test-without-building` prints `** TEST EXECUTE SUCCEEDED **`, NOT the
  // `** TEST SUCCEEDED **` that plain `xcodebuild test` prints. Accepting
  // only the latter made a run in which all four scenarios passed report as
  // a failure -- which is the safe direction to be wrong in, but still wrong.
  if (!/\*\* TEST (EXECUTE )?SUCCEEDED \*\*/.test(output)) {
    // Persist the WHOLE run. The one-line extraction below is a summary for
    // a reader skimming lane output, and a summary of a failing device run
    // is exactly the wrong thing to be left holding at 2am -- xcodebuild's
    // real diagnostics are hundreds of lines and are gone once the lane
    // exits.
    const logPath = join(repositoryRoot, '.artifacts/ios/server-driven-last-run.log')
    mkdirSync(join(repositoryRoot, '.artifacts/ios'), { recursive: true })
    writeFileSync(logPath, output)
    console.error(`full xcodebuild output: ${logPath}`)

    // Dump the sync feed the client was trying to read.
    //
    // A decode failure names an INDEX into `changes` and nothing about the
    // content, so without the page itself the only way to identify the
    // offending payload is to guess from the order of the union's variant
    // errors -- which is exactly as unreliable as it sounds. Fetching the
    // page the client just choked on turns that guess into a lookup.
    try {
      const feed = await fetch(new URL('/api/v1/sync?limit=50', harnessURL), {
        headers: { accept: 'application/json', authorization: `Bearer ${active.accessToken}` },
      })
      const page = await feed.json()
      const feedPath = join(repositoryRoot, '.artifacts/ios/server-driven-last-feed.json')
      writeFileSync(feedPath, JSON.stringify(page, null, 2))
      const kinds = (page.changes ?? []).map((change, index) => `${index}:${change.kind}`).join(' ')
      console.error(`sync feed the client was reading (${(page.changes ?? []).length} changes): ${kinds}`)
      console.error(`full feed: ${feedPath}`)
    } catch (feedError) {
      console.error(`could not read the sync feed back for diagnosis: ${feedError.message}`)
    }
    const executed = [...output.matchAll(/Executed (\d+) tests?,\s*with(?:\s+\d+\s+tests?\s+skipped\s+and)?\s*(\d+) failures?/g)]
    const failing = [...output.matchAll(/^(.*\.swift:\d+.*error:.*)$/gm)].map((m) => m[1]).slice(0, 10)
    fail(
      `the server-driven suite did not succeed on ${destination}. ` +
        `Executed summaries: ${executed.map((m) => `${m[1]}/${m[2]}f`).join(', ') || 'none'}. ` +
        (failing.length > 0 ? `First failures: ${failing.join(' | ')}` : ''),
    )
  }

  // ---- Assertions on what the SERVER received, not on what the client said.
  const arrivals = stack.records.slice(arrivalsBefore)
  const commandArrivals = arrivals.filter((record) => record.path.includes('/api/v1/commands/'))
  if (commandArrivals.length === 0) {
    fail(
      'the suite reported success but the recording proxy observed ZERO command arrivals from the client. ' +
        'Nothing was proven against the real server -- this is precisely the hollow-evidence outcome the ' +
        'anti-vacuity contract exists to refuse.',
    )
  }
  const injected = arrivals.filter((record) => record.injected !== null)
  if (injected.length === 0) fail('the proxy recorded no injected request -- the fault injection point is inert')

  const refusals = commandArrivals.filter((record) => record.status === 401 || record.status === 409)
  if (refusals.length === 0) {
    fail('the proxy recorded no 401 or 409 -- the client never actually met a server refusal')
  }

  const order = commandArrivals.map((record) => `${record.path.split('/').pop()}:${record.status}`)
  console.log(
    `IOS_SERVER_DRIVEN scenarios=4 destination=${JSON.stringify(destination)} host=${displayHost} ` +
      `transport=${tls ? 'https-publicly-trusted' : 'http-loopback'} ` +
      `command_arrivals=${commandArrivals.length} injected=${injected.length} refusals=${refusals.length}`,
  )
  console.log(`IOS_SERVER_DRIVEN_ORDER ${order.join(' -> ')}`)
  await stack.stop()
  process.exit(0)
} catch (error) {
  if (stack) await stack.stop()
  if (error?.isBlocked) {
    console.error(`BLOCKED: ${error.message}`)
  } else {
    console.error(`iOS server-driven lane failed: ${error instanceof Error ? error.message : String(error)}`)
  }
  process.exit(1)
}
