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

const destination = argumentValue('--destination', 'platform=iOS Simulator,name=iPhone 17,OS=latest')
const bindHost = argumentValue('--bind-host', '127.0.0.1')
const advertiseHost = argumentValue('--advertise-host', '127.0.0.1')

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
  stack = await startRecordingStack({ bindHost })

  // ---- A real credential, through the real authorization flow.
  const browser = createClient(stack.loopbackURL)
  await browser.signIn()
  const active = await issueDeviceGrant(browser, { installationId: `lane-active-${Date.now()}` })

  // ---- A second credential the real server has genuinely revoked. Not a
  // malformed token and not an empty header: the exact credential a
  // signed-out or remotely revoked phone still holds on disk.
  const revokedInstallation = `lane-revoked-${Date.now()}`
  const doomed = await issueDeviceGrant(browser, { installationId: revokedInstallation })
  const revoke = await fetch(new URL(`/api/v1/device-grants/${revokedInstallation}`, stack.loopbackURL), {
    headers: { accept: 'application/json', authorization: `Bearer ${doomed.accessToken}` },
    method: 'DELETE',
  })
  if (revoke.status !== 200 && revoke.status !== 204) {
    fail(`the real server refused to revoke the device grant under test: ${revoke.status} ${await revoke.text()}`)
  }

  const baseURL = stack.baseURL(advertiseHost)
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

  const derivedData = join(repositoryRoot, '.artifacts/ios/DerivedData-server-driven')
  await runChecked('build-for-testing', [
    'build-for-testing',
    '-project', 'apps/ios/Keepling.xcodeproj',
    '-scheme', 'Keepling',
    '-destination', destination,
    '-destination-timeout', '300',
    '-derivedDataPath', derivedData,
    ...(process.argv.includes('--allow-provisioning-updates') ? ['-allowProvisioningUpdates'] : []),
  ])

  const [xctestrun] = readdirSync(join(derivedData, 'Build/Products'))
    .filter((name) => name.endsWith('.xctestrun'))
    .map((name) => join(derivedData, 'Build/Products', name))
  if (!xctestrun) fail('build-for-testing produced no .xctestrun file')

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
      const feed = await fetch(new URL('/api/v1/sync?limit=50', stack.loopbackURL), {
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
    `IOS_SERVER_DRIVEN scenarios=4 destination=${JSON.stringify(destination)} ` +
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
