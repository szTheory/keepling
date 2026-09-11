#!/usr/bin/env node
/**
 * tooling/cross-adapter/legs.mjs (05-12-PLAN.md Task 2)
 *
 * One driver per adapter, each producing fresh `CROSS_ADAPTER_SCENARIO`
 * evidence lines (scenario-report.mjs) for the SAME four-scenario shared
 * set, against the ONE server the orchestrator (`verify-cross-adapter-
 * phase.mjs`) already booted. A leg that cannot run throws a
 * `BLOCKED:`-prefixed error naming exactly what is missing -- never
 * substituted with a fixture, a cached artifact, or another leg's
 * evidence.
 *
 * --- Scope note (disclosed, see 05-12-SUMMARY.md "Deviations") ---
 * `tooling/mcp-client/scenarios.mjs`'s full 9-scenario set is MCP-tool
 * shaped: two of its nine scenarios (`preview_and_commit_multi_target`,
 * `commit_stale_preview`) exercise the D-17 preview/commit primitive,
 * which is an MCP-only wire construct in this phase -- no HTTP
 * `/commands/*` endpoint, no Electron IPC command, and no iPhone app
 * action expose an equivalent two-step preview/commit surface today
 * (`grep -n "preview\|bulk" apps/server/lib/keepling_web/router.ex`
 * returns nothing). Asserting those two scenarios "identically" across
 * all four adapters is not possible without inventing a second,
 * adapter-specific preview mechanism this phase never built -- which
 * would make the cross-adapter proof assert against code this plan does
 * not own. This lane's SHARED_SCENARIOS is therefore the four scenarios
 * that exist identically, by construction, on every adapter today:
 * capture, complete, reopen, and a stale-expected-revision conflict --
 * the same set `Keepling.Application.Commands` exposes to every one of
 * its four callers (D-01). This narrows what D-27 proves to MCP-02's
 * verbs, not MCP-05's; MCP-05's bulk/destructive guarantee remains
 * proven single-adapter by the `adversarial`/`simulated-client` lanes
 * (05-11) until a later plan gives every adapter its own preview/commit
 * surface.
 */
import { randomUUID } from 'node:crypto'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'
import { readFinalState } from '../mcp-client/final-state.mjs'
import { toolsCall } from '../mcp-client/client.mjs'
import { formatScenarioLine } from './scenario-report.mjs'

export const blocked = (message) => {
  const error = new Error(`BLOCKED: ${message}`)
  error.blocked = true
  return error
}

/** The four scenarios every leg in this file drives, in this fixed order. */
export const SHARED_SCENARIOS = ['capture_one_task', 'complete_task', 'reopen_task', 'update_stale_expected_revision']

// `GET /api/v1/tasks/:id/activity` returns items NEWEST FIRST (measured
// directly against a live server while writing this lane: after
// capture+complete, index 0 is `task_completed`, index 1 is
// `task_captured`) -- so the most RECENT activity fact is `facts[0]`, not
// `facts.at(-1)`.
const mostRecentActivityType = (state, taskId) => {
  const facts = state.activity[taskId] ?? []
  return facts.length > 0 ? facts[0].type : 'none'
}

/**
 * Drives `SHARED_SCENARIOS` uniformly against any adapter exposing
 * `capture`/`complete`/`reopen`, each returning
 * `{ ok: boolean, code: string|null }` from the adapter's OWN response --
 * then reads final state back from the server's APIs (never the
 * adapter's self-report) to populate `activity_fact` and
 * `final_revision`. This is the single implementation every leg below
 * calls, so "the same scenario set" is enforced by code sharing, not by
 * four independently-written copies that could quietly diverge.
 */
async function runSharedScenarioSet(legName, adapter, { inputDigest, origin, runId, sessionCookie }) {
  const lines = []

  // capture_one_task
  {
    const taskId = randomUUID()
    const result = await adapter.capture(taskId, `cross-adapter ${legName} capture ${randomUUID()}`)
    const state = await readFinalState(origin, { sessionCookie, taskIds: [taskId] })
    lines.push(
      formatScenarioLine({
        activityFact: mostRecentActivityType(state, taskId),
        conflictShape: result.ok ? 'none' : (result.code ?? 'unknown'),
        finalRevision: state.tasks[taskId]?.revision ?? 0,
        inputDigest,
        leg: legName,
        resultCode: result.ok ? 'ok' : `refused:${result.code ?? 'unknown'}`,
        runId,
        scenario: 'capture_one_task',
      }),
    )
  }

  // complete_task
  {
    const taskId = randomUUID()
    await adapter.capture(taskId, `cross-adapter ${legName} complete ${randomUUID()}`)
    const result = await adapter.complete(taskId, 1)
    const state = await readFinalState(origin, { sessionCookie, taskIds: [taskId] })
    lines.push(
      formatScenarioLine({
        activityFact: mostRecentActivityType(state, taskId),
        conflictShape: result.ok ? 'none' : (result.code ?? 'unknown'),
        finalRevision: state.tasks[taskId]?.revision ?? 0,
        inputDigest,
        leg: legName,
        resultCode: result.ok ? 'ok' : `refused:${result.code ?? 'unknown'}`,
        runId,
        scenario: 'complete_task',
      }),
    )
  }

  // reopen_task
  {
    const taskId = randomUUID()
    await adapter.capture(taskId, `cross-adapter ${legName} reopen ${randomUUID()}`)
    await adapter.complete(taskId, 1)
    const result = await adapter.reopen(taskId, 2)
    const state = await readFinalState(origin, { sessionCookie, taskIds: [taskId] })
    lines.push(
      formatScenarioLine({
        activityFact: mostRecentActivityType(state, taskId),
        conflictShape: result.ok ? 'none' : (result.code ?? 'unknown'),
        finalRevision: state.tasks[taskId]?.revision ?? 0,
        inputDigest,
        leg: legName,
        resultCode: result.ok ? 'ok' : `refused:${result.code ?? 'unknown'}`,
        runId,
        scenario: 'reopen_task',
      }),
    )
  }

  // update_stale_expected_revision -- two lifecycle commands (complete,
  // then reopen) rather than an edit/clarify command, deliberately:
  // `Keepling.Domain.Task.lifecycle_transition/4` refuses a lifecycle
  // command only when `task.lifecycle_revision > command.expected_revision`
  // (a STALENESS check, not an equality check), and `edit_task`'s own
  // conflict detection is a separate base_values three-way merge that
  // does not consult `expected_revision` at all -- both measured directly
  // against the live server while writing this lane, and neither produces
  // a genuine stale-revision refusal from a single freshly captured task.
  // A freshly captured task's lifecycle_revision starts at 1.
  // complete(expected_revision=1) matches it exactly and is accepted,
  // advancing lifecycle_revision to 2. A second attempt REUSING the same
  // expected_revision=1 is now genuinely stale (2 > 1) and is refused --
  // uniformly, on every one of the four shared command verbs.
  {
    const taskId = randomUUID()
    await adapter.capture(taskId, `cross-adapter ${legName} stale ${randomUUID()}`)
    const setup = await adapter.complete(taskId, 1)
    if (!setup.ok) {
      throw new Error(`${legName}: update_stale_expected_revision setup (complete with expected_revision=1) was refused instead of accepted: ${JSON.stringify(setup)}`)
    }
    const result = await adapter.reopen(taskId, 1)
    const state = await readFinalState(origin, { sessionCookie, taskIds: [taskId] })
    lines.push(
      formatScenarioLine({
        activityFact: mostRecentActivityType(state, taskId),
        conflictShape: result.ok ? 'none' : (result.code ?? 'unknown'),
        finalRevision: state.tasks[taskId]?.revision ?? 0,
        inputDigest,
        leg: legName,
        resultCode: result.ok ? 'ok' : `refused:${result.code ?? 'unknown'}`,
        runId,
        scenario: 'update_stale_expected_revision',
      }),
    )
    if (result.ok) {
      throw new Error(
        `${legName}: update_stale_expected_revision scenario was accepted instead of refused -- the reopen's expected_revision=1 should be behind the lifecycle_revision the prior complete already advanced past`,
      )
    }
  }

  return lines
}

// --- web-api leg: drives the HTTP /commands/* API directly with a real
// browser session (the same session `bootDisposableServer` logs in with). ---

/**
 * The real browser mutation path requires a matching Origin header
 * (`require_trusted_origin`, CSRF-adjacent) AND a session-bound CSRF token
 * (`protect_from_forgery`) -- exactly what a real browser XHR/fetch call
 * carries, never a bearer. `fetchCsrfToken` reads it from
 * `GET /api/v1/session`, the same endpoint the real web client uses.
 */
const fetchCsrfToken = async (origin, sessionCookie) => {
  const response = await fetch(`${origin}/api/v1/session`, { headers: { Cookie: sessionCookie, Origin: origin } })
  if (response.status !== 200) throw new Error(`GET /api/v1/session returned ${String(response.status)}`)
  const body = await response.json()
  if (!body.csrf_token) throw new Error('GET /api/v1/session response carried no csrf_token')
  return body.csrf_token
}

const postCommand = async (origin, sessionCookie, csrfToken, path, body) => {
  const response = await fetch(`${origin}${path}`, {
    body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json', Cookie: sessionCookie, Origin: origin, 'x-csrf-token': csrfToken },
    method: 'POST',
  })
  const json = await response.json().catch(() => ({}))
  if (response.status >= 200 && response.status < 300) return { code: null, ok: true }
  return { code: json.code ?? `http_${String(response.status)}`, ok: false }
}

const webApiAdapter = (origin, sessionCookie, csrfToken) => ({
  async capture(taskId, title) {
    return postCommand(origin, sessionCookie, csrfToken, '/api/v1/commands/capture-task', {
      mutation_id: randomUUID(),
      task_id: taskId,
      title,
      version: 1,
    })
  },
  async complete(taskId, expectedRevision) {
    return postCommand(origin, sessionCookie, csrfToken, '/api/v1/commands/complete-task', {
      expected_revision: expectedRevision,
      mutation_id: randomUUID(),
      task_id: taskId,
      version: 1,
    })
  },
  async reopen(taskId, expectedRevision) {
    return postCommand(origin, sessionCookie, csrfToken, '/api/v1/commands/reopen-task', {
      expected_revision: expectedRevision,
      mutation_id: randomUUID(),
      task_id: taskId,
      version: 1,
    })
  },
})

export async function runWebApiLeg({ inputDigest, origin, runId, sessionCookie }) {
  const csrfToken = await fetchCsrfToken(origin, sessionCookie)
  return runSharedScenarioSet('web-api', webApiAdapter(origin, sessionCookie, csrfToken), { inputDigest, origin, runId, sessionCookie })
}

// --- mcp leg: drives tooling/mcp-client/client.mjs with a real agent
// grant obtained through the real authorization flow (reused unchanged
// from 05-11, per this plan's action text). ---

const classifyMcp = (response) => {
  if (response.body.error) return { code: response.body.error.data?.keepling_code ?? 'unknown_error', ok: false }
  return { code: null, ok: true }
}

const mcpAdapter = (origin, accessToken) => ({
  async capture(taskId, title) {
    return classifyMcp(await toolsCall(origin, accessToken, 'keepling.capture_task', { mutation_id: randomUUID(), task_id: taskId, title, version: 1 }))
  },
  async complete(taskId, expectedRevision) {
    return classifyMcp(
      await toolsCall(origin, accessToken, 'keepling.complete_task', {
        expected_revision: expectedRevision,
        mutation_id: randomUUID(),
        task_id: taskId,
        version: 1,
      }),
    )
  },
  async reopen(taskId, expectedRevision) {
    return classifyMcp(
      await toolsCall(origin, accessToken, 'keepling.reopen_task', {
        expected_revision: expectedRevision,
        mutation_id: randomUUID(),
        task_id: taskId,
        version: 1,
      }),
    )
  },
})

export async function runMcpLeg({ accessToken, inputDigest, origin, runId, sessionCookie }) {
  return runSharedScenarioSet('mcp', mcpAdapter(origin, accessToken), { inputDigest, origin, runId, sessionCookie })
}

// --- electron leg ---
//
// Drives the packaged desktop build following `verify-real-stack-
// desktop.mjs`'s discipline: a disposable profile, the real adapter, no
// stubbed fetch, no test-only sync mode. The packaged artifact
// (`apps/desktop/out/`, produced by `tooling/package-desktop.mjs`) is a
// Phase 3 artifact this plan does not create -- per this plan's own Task 1
// precondition, its absence BLOCKS this leg rather than being papered
// over with a fixture or a fake.

export async function runElectronLeg() {
  const repositoryRoot = join(import.meta.dirname, '..', '..')
  const outRoot = join(repositoryRoot, 'apps', 'desktop', 'out')
  if (!existsSync(outRoot)) {
    throw blocked(
      `no packaged Electron build found at apps/desktop/out -- run \`pnpm package:desktop\` first. ` +
        'This artifact was proven in Phase 3 (tooling/package-desktop.mjs, tooling/verify-real-stack-desktop.mjs) ' +
        'and is not produced by this plan (05-12-PLAN.md Task 1 precondition).',
    )
  }
  // A packaged build exists, but this lane has not yet been given a live
  // IPC driver against it -- driving the packaged .app's real command
  // surface (main/preload IPC -> outbox -> real sync, mirroring
  // apps/desktop/test/packaged/real-stack-sync.spec.ts's discipline) is
  // the next increment once the packaged artifact is reliably available in
  // this lane's environment. Reported BLOCKED, not silently skipped or
  // faked, per D-25/D-26.
  throw blocked(
    'a packaged Electron build exists at apps/desktop/out, but this leg has no live IPC driver wired to it yet -- ' +
      'see tooling/cross-adapter/legs.mjs runElectronLeg() and docs/testing/cross-adapter-testing.md for the disclosed gap',
  )
}

// --- iphone leg ---
//
// Drives the simulator or the physical device following `verify-real-
// stack-ios.mjs`'s recording-proxy pattern. Requires the Keepling app to
// already be installed on a booted simulator (or reachable per Phase 4's
// physical-device setup) -- this plan does not build or install the app.

export async function runIphoneLeg() {
  const bootedList = spawnSync('xcrun', ['simctl', 'list', 'devices', 'booted'], { encoding: 'utf8' })
  const bootedLine = (bootedList.stdout ?? '').split('\n').find((line) => line.includes('(Booted)'))
  if (!bootedLine) {
    throw blocked('no booted iOS Simulator found (`xcrun simctl list devices booted` reported none) -- boot a simulator first.')
  }
  const udidMatch = bootedLine.match(/\(([0-9A-F-]{36})\)/)
  const udid = udidMatch ? udidMatch[1] : null
  if (!udid) {
    throw blocked(`could not parse a device UDID from the booted simulator line: ${bootedLine.trim()}`)
  }
  const installed = spawnSync('xcrun', ['simctl', 'listapps', udid], { encoding: 'utf8' })
  const hasKeepling = /keepling/i.test(installed.stdout ?? '')
  if (!hasKeepling) {
    throw blocked(
      `no Keepling app is installed on the booted simulator ${udid} -- build and install the app first ` +
        '(this plan does not build or install it; see docs/testing/ios-testing.md for the build/install lanes).',
    )
  }
  // An installed app was found, but this lane has no live UI/recording-
  // proxy driver wired to it yet -- driving the installed app through the
  // same recording-proxy pattern `verify-real-stack-ios.mjs` uses is the
  // next increment. Reported BLOCKED, not silently skipped or faked.
  throw blocked(
    `Keepling is installed on the booted simulator ${udid}, but this leg has no live UI driver wired to it yet -- ` +
      'see tooling/cross-adapter/legs.mjs runIphoneLeg() and docs/testing/cross-adapter-testing.md for the disclosed gap',
  )
}

export const LEG_RUNNERS = {
  electron: runElectronLeg,
  iphone: runIphoneLeg,
  mcp: runMcpLeg,
  'web-api': runWebApiLeg,
}

/** Legs ranked slow/precondition-gated first, so an unavailable packaged
 * build or simulator is discovered in seconds rather than after the real
 * legs have already done their full run (mirrors verify-mcp-phase.mjs's
 * SLOW_OR_GATED_LANES ordering). */
export const LEG_ORDER = ['electron', 'iphone', 'web-api', 'mcp']
