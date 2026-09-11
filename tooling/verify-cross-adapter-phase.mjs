#!/usr/bin/env node
/**
 * tooling/verify-cross-adapter-phase.mjs (05-12-PLAN.md Task 1, D-27)
 *
 * SRV-02's completion proof. Starts exactly ONE real Phoenix/PostgreSQL
 * instance through the same bootstrap `tooling/mcp-client/client.mjs`
 * already proved (05-11), computes ONE `inputDigestFor` over the server
 * source tree, mints ONE run identifier, and runs each adapter leg
 * (`tooling/cross-adapter/legs.mjs`) against that single instance in
 * sequence -- slow/precondition-gated legs first, so an unavailable
 * packaged build or simulator is discovered in seconds. Every leg's
 * evidence carries the SAME run identifier and the SAME input digest; a
 * mismatch fails the run, because that is what "one server revision" means
 * operationally.
 *
 * A leg that cannot run throws a `BLOCKED:`-prefixed error and BLOCKS the
 * lane -- never substituted with a fixture, a cached artifact, or another
 * leg's evidence (the fourth vacuity mode research named). This command can
 * never exit 0 while any leg is blocked or while cross-leg evidence
 * disagrees.
 */
import { randomUUID } from 'node:crypto'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'
import { bootDisposableServer, guardAgainstShortcuts, obtainGrant } from './mcp-client/client.mjs'
import { inputDigestFor } from './verify-mcp-phase.mjs'
import { compareLegs, formatScenarioLine, parseScenarioLines } from './cross-adapter/scenario-report.mjs'
import { LEG_ORDER, SHARED_SCENARIOS, runElectronLeg, runIphoneLeg, runMcpLeg, runWebApiLeg } from './cross-adapter/legs.mjs'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(laneDirectory, '..')

// Guard-refusal: this lane's own leg modules must never take a shortcut
// (a stubbed fetch, a non-resolving placeholder host, a hand-injected
// bearer, or a test-only sync mode). Checked at every invocation, not just
// once at authoring time -- copied from
// `tooling/verify-real-stack-desktop.mjs:31-67` and extended per
// client.mjs's own MCP-specific guard.
const GUARDED_FILES = [
  join(repositoryRoot, 'tooling', 'cross-adapter', 'legs.mjs'),
  join(repositoryRoot, 'tooling', 'verify-cross-adapter-phase.mjs'),
  join(repositoryRoot, 'tooling', 'cross-adapter', 'electron-driver.mjs'),
  join(repositoryRoot, 'tooling', 'cross-adapter', 'iphone-driver.mjs'),
]

const TRACKED_INPUT_PATHS = [
  'tooling/verify-cross-adapter-phase.mjs',
  'tooling/cross-adapter/legs.mjs',
  'tooling/cross-adapter/scenario-report.mjs',
  'tooling/cross-adapter/electron-driver.mjs',
  'tooling/cross-adapter/iphone-driver.mjs',
  'tooling/mcp-client/client.mjs',
  'tooling/mcp-client/final-state.mjs',
  'apps/server/lib/keepling/application/commands.ex',
  'apps/server/lib/keepling_web/controllers/command_controller.ex',
  'apps/server/lib/keepling_web/mcp/tools.ex',
]

const runners = { electron: runElectronLeg, iphone: runIphoneLeg, 'web-api': runWebApiLeg, mcp: runMcpLeg }

const dryRun = () => {
  const runId = randomUUID()
  console.log(`CROSS_ADAPTER_DRY_RUN run_id=${runId} legs=${LEG_ORDER.join(',')} scenarios=${SHARED_SCENARIOS.join(',')}`)
  console.log(`CROSS_ADAPTER_DRY_RUN leg_count=${LEG_ORDER.length}`)
  if (LEG_ORDER.length < 4) {
    console.error('CROSS_ADAPTER_DRY_RUN failed: fewer than four adapter legs are declared')
    process.exit(1)
  }
  console.log('CROSS_ADAPTER_DRY_RUN: ok (no server started, no leg executed)')
}

const runLive = async () => {
  for (const file of GUARDED_FILES) guardAgainstShortcuts(file)

  const runId = randomUUID()
  const inputDigest = inputDigestFor(TRACKED_INPUT_PATHS)

  const postgresPort = Number(process.env.KEEPLING_CROSS_ADAPTER_POSTGRES_PORT ?? 55_480)
  const phoenixPort = Number(process.env.KEEPLING_CROSS_ADAPTER_PHOENIX_PORT ?? 4_240)

  console.log(`CROSS_ADAPTER_RUN_START run_id=${runId} input_digest=${inputDigest} legs=${LEG_ORDER.join(',')}`)

  const server = await bootDisposableServer({ databaseName: 'keepling_cross_adapter', phoenixPort, postgresPort })

  const legStatuses = {}
  const allLines = []
  const ranLegs = []

  try {
    // The MCP leg needs its own real grant, obtained once up front through
    // the real PKCE flow -- so the timed part of the mcp leg below is only
    // the scenario dispatch itself, matching how the other legs are timed.
    let mcpAccessToken = null
    try {
      const grant = await obtainGrant(server, ['tasks.write'])
      mcpAccessToken = grant.accessToken
    } catch (error) {
      legStatuses.mcp = { blocked: true, message: error?.blocked ? error.message : `BLOCKED: could not obtain an MCP grant: ${String(error?.message ?? error)}` }
    }

    for (const legName of LEG_ORDER) {
      const startedAt = Date.now()
      try {
        let lines
        if (legName === 'mcp') {
          if (mcpAccessToken === null) throw new Error(legStatuses.mcp?.message ?? 'BLOCKED: no MCP grant available')
          lines = await runMcpLeg({ accessToken: mcpAccessToken, inputDigest, origin: server.origin, runId, sessionCookie: server.sessionCookie })
        } else if (legName === 'web-api') {
          lines = await runWebApiLeg({ inputDigest, origin: server.origin, runId, sessionCookie: server.sessionCookie })
        } else {
          lines = await runners[legName]({ inputDigest, origin: server.origin, runId, sessionCookie: server.sessionCookie })
        }
        for (const line of lines) console.log(line)
        allLines.push(...parseScenarioLines(lines.join('\n')))
        ranLegs.push(legName)
        legStatuses[legName] = { blocked: false, durationMs: Date.now() - startedAt, scenarioCount: lines.length }
      } catch (error) {
        const durationMs = Date.now() - startedAt
        const message = error instanceof Error ? error.message : String(error)
        const isBlocked = Boolean(error?.blocked) || message.startsWith('BLOCKED:')
        legStatuses[legName] = { blocked: isBlocked, durationMs, error: message }
        if (isBlocked) {
          console.error(`CROSS_ADAPTER_LEG_BLOCKED leg=${legName} reason=${message}`)
        } else {
          console.error(`CROSS_ADAPTER_LEG_FAILED leg=${legName} error=${message}`)
        }
      }
    }
  } finally {
    await server.stop()
  }

  const blockedLegs = LEG_ORDER.filter((name) => legStatuses[name]?.blocked)
  const failedLegs = LEG_ORDER.filter((name) => !legStatuses[name]?.blocked && legStatuses[name]?.error)

  let comparison = { ok: ranLegs.length === LEG_ORDER.length, violations: [] }
  if (ranLegs.length > 0) {
    comparison = compareLegs(allLines, ranLegs)
  }

  console.log('')
  console.log(
    `CROSS_ADAPTER_SUMMARY run_id=${runId} input_digest=${inputDigest} legs_total=${LEG_ORDER.length} legs_ran=${ranLegs.length} legs_blocked=${blockedLegs.length} legs_failed=${failedLegs.length} scenarios_per_leg=${SHARED_SCENARIOS.length} comparison_ok=${String(comparison.ok)}`,
  )
  for (const legName of LEG_ORDER) {
    const status = legStatuses[legName]
    const word = status?.blocked ? 'BLOCKED' : status?.error ? 'FAILED' : 'PASS'
    console.log(`  ${word} leg=${legName} scenarios=${status?.scenarioCount ?? 0} duration_ms=${status?.durationMs ?? 0}${status?.error ? ` reason=${status.error}` : ''}`)
  }
  if (comparison.violations.length > 0) {
    console.log('CROSS_ADAPTER_COMPARISON_VIOLATIONS:')
    for (const violation of comparison.violations) console.log(`  - ${violation}`)
  }

  const overallOk = blockedLegs.length === 0 && failedLegs.length === 0 && comparison.ok && ranLegs.length === LEG_ORDER.length

  if (blockedLegs.length > 0) {
    console.error('')
    console.error(
      `CROSS_ADAPTER_PHASE_GATE: BLOCKED (${blockedLegs.length} leg(s) cannot run yet: ${blockedLegs.join(', ')}). This is disclosed, genuine missing evidence ` +
        '(a packaged build, an installed simulator app, or similar), not a code defect. The gate refuses to report success while it is missing, per D-25/D-26.',
    )
  }
  if (failedLegs.length > 0) {
    console.error(`CROSS_ADAPTER_PHASE_GATE: FAILED (${failedLegs.length} leg(s) genuinely errored: ${failedLegs.join(', ')})`)
  }
  if (!comparison.ok && ranLegs.length > 0) {
    console.error('CROSS_ADAPTER_PHASE_GATE: cross-leg comparison failed')
  }

  process.exit(overallOk ? 0 : 1)
}

const main = async () => {
  if (process.argv.includes('--dry-run')) {
    dryRun()
    return
  }
  await runLive()
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main()
}

export { dryRun, runLive }
