#!/usr/bin/env node
/**
 * tooling/cross-adapter/iphone-driver.mjs (06-05-PLAN.md Task 3)
 *
 * The live iPhone leg: drives the SAME four shared scenarios through the
 * real Swift client -- the exact `KeeplingSyncAdapter` and
 * `OutboundCommands` production code the shipped app uses -- against the
 * real server this lane already booted, over a real device-grant bearer
 * obtained through the real RFC 8252 PKCE flow.
 *
 * WHY THIS IS AN XCTEST BUNDLE, NOT A UI AUTOMATION SCRIPT
 * ----------------------------------------------------------
 * `runSharedScenarioSet` calls `capture`/`complete`/`reopen`/`staleUpdate`
 * as separate, independently-awaited steps -- exactly what the Electron
 * driver's long-lived Playwright session gives it for free. A real iOS
 * client has no equivalent always-on remote-control surface without
 * adding one to the shipped app, which this plan's own hard constraint
 * forbids. So each call here is instead ONE
 * `xcodebuild test-without-building -only-testing:...` invocation against
 * a bundle built ONCE up front (mirroring
 * `tooling/ios-device/server-driven-run.mjs`'s own build-for-testing /
 * test-without-building split), with parameters threaded through the SAME
 * `.xctestrun`-injected `KEEPLING_LANE_*` environment variables that
 * runner already uses. The two new test methods it drives
 * (`ServerDrivenTests.testCrossAdapterCapture` /
 * `.testCrossAdapterLifecycle`, added by this same task) live in the
 * EXISTING `KeeplingCoreTests` bundle -- a test target, never the shipped
 * application -- and call only production `Application`-layer code
 * (`OutboundCommands`, `KeeplingSyncAdapter`), exactly like every other
 * method already in that file.
 *
 * Slower than the other three legs (each scenario call pays a real
 * `xcodebuild test-without-building` invocation) but no less real: no
 * stubbed fetch, no test-only affordance in `apps/ios/Keepling` itself,
 * and the same server-observed comparison every other leg uses.
 */
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { readdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawn } from 'node:child_process'
import { blocked } from '../mcp-client/client.mjs'

const repositoryRoot = resolve(import.meta.dirname, '..', '..')

const LOCKED_DEVICE_PATTERN = /could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i

/** Runs a child process without blocking the event loop -- this driver's own event loop needs to stay free for `fetch` calls to the real server between xcodebuild invocations. */
const run = (command, args) =>
  new Promise((resolvePromise) => {
    const child = spawn(command, args, { cwd: repositoryRoot })
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', (chunk) => {
      stdout += chunk
    })
    child.stderr?.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('close', (status) => resolvePromise({ status, stderr, stdout }))
  })

/**
 * Drives the real RFC 8252 authorization-code-with-PKCE flow against the
 * real server this lane already booted, using the harness's own
 * already-authenticated session to play the browser half -- mirroring
 * `tooling/ios-device/real-stack.mjs`'s `issueDeviceGrant` exactly (same
 * `client_id`, same `redirect_uri`, same closed parameter set), because
 * the point is to obtain the credential the real app would obtain, not a
 * test-only token minted down some side path.
 */
async function issueIphoneDeviceGrant(origin, sessionCookie, installationId) {
  const verifier = randomBytes(32).toString('base64url')
  const state = randomBytes(32).toString('base64url')
  const challenge = createHash('sha256').update(verifier).digest('base64url')
  const redirectUri = 'keepling://ios/auth/callback'

  const query = new URLSearchParams({
    client_id: 'iphone',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    installation_id: installationId,
    label: 'cross-adapter iphone leg',
    redirect_uri: redirectUri,
    response_type: 'code',
    state,
  })
  const authorize = await fetch(`${origin}/oauth/authorize?${query.toString()}`, { headers: { Cookie: sessionCookie }, redirect: 'manual' })
  if (authorize.status !== 302) {
    throw new Error(`iphone-driver: /oauth/authorize returned ${String(authorize.status)} instead of a redirect`)
  }
  const location = new URL(authorize.headers.get('location') ?? '', redirectUri)
  const code = location.searchParams.get('code')
  if (!code) throw new Error('iphone-driver: /oauth/authorize redirect carried no code')
  if (location.searchParams.get('state') !== state) throw new Error('iphone-driver: /oauth/authorize redirect returned a mismatched state')

  const exchange = await fetch(`${origin}/oauth/token`, {
    body: JSON.stringify({ code, code_verifier: verifier, grant_type: 'authorization_code', redirect_uri: redirectUri, state }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
  })
  if (exchange.status !== 200) {
    throw new Error(`iphone-driver: /oauth/token returned ${String(exchange.status)}: ${await exchange.text()}`)
  }
  const body = await exchange.json()
  if (!body.access_token) throw new Error('iphone-driver: /oauth/token response carried no access_token')
  return body.access_token
}

/** Builds `KeeplingCoreTests` for testing ONCE and returns the produced `.xctestrun` path -- mirrors `tooling/ios-device/server-driven-run.mjs`'s own per-platform derived-data discipline. */
async function buildForTesting(destination) {
  const platform = destination.includes('Simulator') ? 'iphonesimulator' : 'iphoneos'
  const derivedData = join(repositoryRoot, `.artifacts/ios/DerivedData-cross-adapter-${platform}`)
  const result = await run('xcodebuild', [
    'build-for-testing',
    '-project', 'apps/ios/Keepling.xcodeproj',
    '-scheme', 'Keepling',
    '-destination', destination,
    '-destination-timeout', '300',
    '-derivedDataPath', derivedData,
  ])
  if (result.status !== 0) {
    const errors = [...`${result.stdout}\n${result.stderr}`.matchAll(/^(.*error:.*)$/gm)].map((match) => match[1]).slice(0, 8)
    throw new Error(`iphone-driver: build-for-testing failed${errors.length > 0 ? `: ${errors.join(' | ')}` : ''}`)
  }
  const productsDir = join(derivedData, 'Build/Products')
  const candidates = readdirSync(productsDir).filter((name) => name.endsWith('.xctestrun') && name.includes(platform))
  if (candidates.length !== 1) {
    throw new Error(`iphone-driver: expected exactly one ${platform} .xctestrun in ${productsDir}, found: ${candidates.join(', ') || 'none'}`)
  }
  return join(productsDir, candidates[0])
}

/** Writes lane parameters into the built `.xctestrun`'s `KeeplingCoreTests.EnvironmentVariables` dictionary -- the mechanism proven by `tooling/ios-device/server-driven-run.mjs` to actually reach a hosted unit-test bundle (`TEST_RUNNER_`-prefixed build settings do not). */
async function setLaneEnvironment(xctestrun, values) {
  for (const [key, value] of Object.entries(values)) {
    // eslint-disable-next-line no-await-in-loop
    const result = await run('plutil', ['-replace', `KeeplingCoreTests.EnvironmentVariables.${key}`, '-string', value, xctestrun])
    if (result.status !== 0) throw new Error(`iphone-driver: could not write ${key} into the .xctestrun: ${result.stderr}`)
  }
}

/** Runs exactly one test method and extracts its `IOS_CROSS_ADAPTER_RESULT` line. */
async function runScenarioTest(destination, xctestrun, testId) {
  const result = await run('xcodebuild', [
    'test-without-building',
    '-xctestrun', xctestrun,
    '-destination', destination,
    '-destination-timeout', '300',
    `-only-testing:${testId}`,
  ])
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`

  if (LOCKED_DEVICE_PATTERN.test(output)) {
    throw blocked(
      'the iPhone is LOCKED, so no app could be launched and this lane could learn nothing. Unlock it and re-run ' +
        '(see docs/testing/ios-dogfood.md).',
    )
  }
  if (!/\*\* TEST (EXECUTE )?SUCCEEDED \*\*/.test(output)) {
    throw new Error(`iphone-driver: ${testId} did not report TEST SUCCEEDED: ${output.slice(-2000)}`)
  }
  const match = output.match(/IOS_CROSS_ADAPTER_RESULT action=(\S+) task_id=(\S+) outcome=(\S+)/)
  if (!match) throw new Error(`iphone-driver: ${testId} reported no IOS_CROSS_ADAPTER_RESULT line`)
  return { action: match[1], outcome: match[3], taskId: match[2] }
}

/**
 * `KeeplingSyncAdapter`'s Storage-layer abstraction (`ServerRefusal.classify`,
 * consumed via `SyncAcknowledgement.Outcome`) deliberately collapses every
 * conflict-shaped problem code (`task_edit_conflict`, `task_lifecycle_conflict`,
 * `task_assignment_conflict`, `task_trash_conflict`) into ONE generic
 * `conflict` outcome -- by design, not a bug: the client only needs to know
 * content diverged, never which of the four wire codes produced it. For a
 * lifecycle command (`complete`/`reopen`), `task_lifecycle_conflict` is the
 * ONLY conflict code the server can emit (`Keepling.Domain.Task`'s
 * `lifecycle_transition/4` is the sole path that returns `{:error,
 * {:lifecycle_conflict, _}}` for these two command types), so reconstructing
 * it here from the known command type is a deterministic restatement of what
 * the wire actually said -- never an invented value -- and lets this leg's
 * evidence compare equal to the other three legs' wire-observed codes.
 */
const toOutcome = (result) => {
  const ok = result.outcome === 'accepted' || result.outcome === 'already_satisfied'
  if (ok) return { code: null, ok: true }
  if (result.outcome === 'conflict' && (result.action === 'complete' || result.action === 'reopen')) {
    return { code: 'task_lifecycle_conflict', ok: false }
  }
  return { code: result.outcome, ok: false }
}

/**
 * Builds and boots the real Swift-client leg once, returning the
 * four-function adapter `runSharedScenarioSet` calls, plus `teardown()`
 * for the caller to run in a `finally` block (a no-op here -- there is no
 * long-lived process to close, unlike the Electron leg's launched app).
 */
export async function createIphoneAdapter({ origin, sessionCookie }) {
  const destination = 'platform=iOS Simulator,name=iPhone 17,OS=latest'
  const installationId = `cross-adapter-iphone-${randomUUID()}`
  const accessToken = await issueIphoneDeviceGrant(origin, sessionCookie, installationId)
  const xctestrun = await buildForTesting(destination)
  // `KEEPLING_LANE_REVOKED_BEARER` is required by `laneEnvironment()`'s
  // presence check but unused by the cross-adapter test methods -- filled
  // with the same real token rather than a placeholder so a stray future
  // use of it is still a real credential, never a fabricated one.
  await setLaneEnvironment(xctestrun, {
    KEEPLING_LANE_BASE_URL: origin,
    KEEPLING_LANE_BEARER: accessToken,
    KEEPLING_LANE_REVOKED_BEARER: accessToken,
  })

  return {
    async capture(title) {
      await setLaneEnvironment(xctestrun, { KEEPLING_LANE_TASK_TITLE: title })
      const result = await runScenarioTest(destination, xctestrun, 'KeeplingCoreTests/ServerDrivenTests/testCrossAdapterCapture')
      return { ...toOutcome(result), taskId: result.taskId }
    },
    async complete(taskId, expectedRevision) {
      await setLaneEnvironment(xctestrun, {
        KEEPLING_LANE_EXPECTED_REVISION: String(expectedRevision),
        KEEPLING_LANE_TASK_ID: taskId,
        KEEPLING_LANE_TRANSITION: 'complete',
      })
      const result = await runScenarioTest(destination, xctestrun, 'KeeplingCoreTests/ServerDrivenTests/testCrossAdapterLifecycle')
      return toOutcome(result)
    },
    async reopen(taskId, expectedRevision) {
      await setLaneEnvironment(xctestrun, {
        KEEPLING_LANE_EXPECTED_REVISION: String(expectedRevision),
        KEEPLING_LANE_TASK_ID: taskId,
        KEEPLING_LANE_TRANSITION: 'reopen',
      })
      const result = await runScenarioTest(destination, xctestrun, 'KeeplingCoreTests/ServerDrivenTests/testCrossAdapterLifecycle')
      return toOutcome(result)
    },
    /**
     * Called with the ORIGINAL (now out-of-band-stale) `expectedRevision`
     * this same adapter's `capture` observed -- see
     * `legs.mjs`'s `update_stale_expected_revision` comment for why
     * `complete`, not `reopen`, is the verb that reaches the staleness
     * check.
     */
    async staleUpdate(taskId, expectedRevision) {
      await setLaneEnvironment(xctestrun, {
        KEEPLING_LANE_EXPECTED_REVISION: String(expectedRevision),
        KEEPLING_LANE_TASK_ID: taskId,
        KEEPLING_LANE_TRANSITION: 'complete',
      })
      const result = await runScenarioTest(destination, xctestrun, 'KeeplingCoreTests/ServerDrivenTests/testCrossAdapterLifecycle')
      return toOutcome(result)
    },
    async teardown() {},
  }
}
