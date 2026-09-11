#!/usr/bin/env node
/**
 * cross-adapter lane (05-12-PLAN.md Task 2, D-27): wraps
 * `tooling/verify-cross-adapter-phase.mjs` as a lane under the plan 05-10
 * gate, so its case count and BLOCKED status are published by the same
 * runner as every other lane, with the same counting rules.
 *
 * Publishes `cases = scenarios_per_leg * legs_ran` on a passing run (the
 * total genuinely-compared scenario evidence lines), and throws a
 * `BLOCKED:`-prefixed error when the orchestrator itself reported any leg
 * BLOCKED -- never a silent pass, matching every other lane's contract.
 */
import process from 'node:process'

const parseCrossAdapterOutput = (stdout, stderr) => {
  const combined = `${stdout}\n${stderr}`
  const blockedLine = combined.split('\n').find((line) => line.startsWith('CROSS_ADAPTER_PHASE_GATE: BLOCKED'))
  if (blockedLine) throw new Error(`BLOCKED: ${blockedLine}`)

  const summaryLine = combined.split('\n').find((line) => line.startsWith('CROSS_ADAPTER_SUMMARY'))
  if (!summaryLine) {
    throw new Error(`cross-adapter lane never reported a CROSS_ADAPTER_SUMMARY evidence line${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
  }

  const fields = Object.fromEntries(
    summaryLine
      .split(' ')
      .slice(1)
      .map((pair) => pair.split('='))
      .filter(([key]) => Boolean(key)),
  )

  const legsRan = Number(fields.legs_ran)
  const legsTotal = Number(fields.legs_total)
  const legsBlocked = Number(fields.legs_blocked)
  const legsFailed = Number(fields.legs_failed)
  const scenariosPerLeg = Number(fields.scenarios_per_leg)
  const comparisonOk = fields.comparison_ok === 'true'

  if (![legsRan, legsTotal, legsBlocked, legsFailed, scenariosPerLeg].every(Number.isFinite)) {
    throw new Error(`cross-adapter lane's CROSS_ADAPTER_SUMMARY line is missing a numeric field: ${summaryLine}`)
  }

  if (legsBlocked > 0) {
    throw new Error(`BLOCKED: ${legsBlocked} of ${legsTotal} cross-adapter leg(s) cannot run yet (see CROSS_ADAPTER_LEG_BLOCKED lines above)`)
  }
  if (legsFailed > 0 || !comparisonOk || legsRan !== legsTotal) {
    throw new Error(`cross-adapter lane did not pass cleanly: ${summaryLine}`)
  }

  return legsRan * scenariosPerLeg
}

export default function crossAdapterLane({ repositoryRoot }) {
  return {
    args: ['tooling/verify-cross-adapter-phase.mjs'],
    command: process.execPath,
    cwd: repositoryRoot,
    name: 'cross-adapter',
    parse: parseCrossAdapterOutput,
    trackedInputPaths: [
      'tooling/verify-cross-adapter-phase.mjs',
      'tooling/cross-adapter/legs.mjs',
      'tooling/cross-adapter/scenario-report.mjs',
      'tooling/mcp-client/client.mjs',
      'tooling/mcp-client/final-state.mjs',
    ],
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.error('cross-adapter.mjs is a lane definition module for tooling/verify-mcp-phase.mjs, not a standalone entry point.')
  console.error('Run: node tooling/verify-mcp-phase.mjs --lane cross-adapter')
  process.exitCode = 1
}

export { parseCrossAdapterOutput }
