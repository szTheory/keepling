#!/usr/bin/env node
/**
 * tooling/cross-adapter/scenario-report.mjs (05-12-PLAN.md Task 1)
 *
 * The evidence contract every cross-adapter leg obeys. Each leg, for each
 * scenario it drives, emits one line beginning `CROSS_ADAPTER_SCENARIO`
 * carrying: the run identifier, the leg name, the scenario name, a
 * SERVER-OBSERVED result code, a conflict shape (when the scenario produced
 * one), the identity of the activity fact the server recorded, and the
 * final revision of the affected task. Every value is read back from the
 * server's own APIs after the action -- never reported from the leg's own
 * memory of what it sent. A client-side assertion can only report what the
 * client believes it sent; that is exactly the class of evidence D-27
 * refuses.
 *
 * `parseScenarioLines` and `compareLegs` implement the cross-leg equality
 * check: a scenario present in some legs and absent from others is a
 * failure, not a partial pass (Task 1's action text).
 */
import { strict as assert } from 'node:assert'
import process from 'node:process'
import { test } from 'node:test'

const LINE_PREFIX = 'CROSS_ADAPTER_SCENARIO'

const LINE_RE = new RegExp(
  `^${LINE_PREFIX} run_id=(\\S+) input_digest=(\\S+) leg=(\\S+) scenario=(\\S+) result_code=(\\S+) conflict_shape=(\\S+) activity_fact=(\\S+) final_revision=(\\S+)$`,
)

/**
 * Formats one scenario's evidence line. Every field here MUST already be a
 * value read back from the server -- this function does no reading itself,
 * it only serializes what the caller already observed.
 */
export const formatScenarioLine = ({
  activityFact,
  conflictShape,
  finalRevision,
  inputDigest,
  leg,
  resultCode,
  runId,
  scenario,
}) => {
  for (const [name, value] of Object.entries({ activityFact, conflictShape, leg, resultCode, runId, scenario })) {
    if (typeof value !== 'string' || value.length === 0 || /\s/.test(value)) {
      throw new Error(`formatScenarioLine: ${name} must be a non-empty, whitespace-free string, got ${JSON.stringify(value)}`)
    }
  }
  if (typeof inputDigest !== 'string' || inputDigest.length === 0) {
    throw new Error(`formatScenarioLine: inputDigest must be a non-empty string, got ${JSON.stringify(inputDigest)}`)
  }
  if (!Number.isFinite(finalRevision)) {
    throw new Error(`formatScenarioLine: finalRevision must be a finite number, got ${JSON.stringify(finalRevision)}`)
  }
  return `${LINE_PREFIX} run_id=${runId} input_digest=${inputDigest} leg=${leg} scenario=${scenario} result_code=${resultCode} conflict_shape=${conflictShape} activity_fact=${activityFact} final_revision=${String(finalRevision)}`
}

/**
 * Parses every `CROSS_ADAPTER_SCENARIO` line out of arbitrary text (a
 * leg's stdout, typically). Throws on a line that starts with the prefix
 * but does not match the expected shape -- there is no "assume it parsed"
 * fallback, matching `exUnitSummary`'s own rule in `verify-mcp-phase.mjs`.
 */
export const parseScenarioLines = (text) => {
  if (typeof text !== 'string') throw new Error('parseScenarioLines: no text to parse')
  const entries = []
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim()
    if (!line.startsWith(LINE_PREFIX)) continue
    const match = line.match(LINE_RE)
    if (!match) throw new Error(`unparseable ${LINE_PREFIX} line: ${line}`)
    const [, runId, inputDigest, leg, scenario, resultCode, conflictShape, activityFact, finalRevisionRaw] = match
    const finalRevision = Number(finalRevisionRaw)
    if (!Number.isFinite(finalRevision)) throw new Error(`non-numeric final_revision in line: ${line}`)
    entries.push({ activityFact, conflictShape, finalRevision, inputDigest, leg, resultCode, runId, scenario })
  }
  return entries
}

/**
 * Cross-leg equality check (Task 1's central assertion). `expectedLegs`
 * names every leg that is required to have produced evidence for a
 * scenario to count -- a scenario missing from any of them is a failure,
 * never a partial pass. Also asserts every entry carries the SAME run_id
 * and input_digest: a mismatch means the legs did not run against "one
 * server revision", which is what this whole lane exists to prove.
 */
export const compareLegs = (entries, expectedLegs) => {
  const violations = []
  if (!Array.isArray(entries) || entries.length === 0) {
    return { ok: false, violations: ['no evidence lines to compare'] }
  }
  if (!Array.isArray(expectedLegs) || expectedLegs.length === 0) {
    throw new Error('compareLegs: expectedLegs must be a non-empty array')
  }

  const runIds = new Set(entries.map((entry) => entry.runId))
  if (runIds.size > 1) violations.push(`entries carry more than one run_id: ${[...runIds].sort().join(',')}`)

  const digests = new Set(entries.map((entry) => entry.inputDigest))
  if (digests.size > 1) violations.push(`entries carry more than one input_digest: ${[...digests].sort().join(',')}`)

  const byScenario = new Map()
  for (const entry of entries) {
    if (!byScenario.has(entry.scenario)) byScenario.set(entry.scenario, [])
    byScenario.get(entry.scenario).push(entry)
  }

  for (const [scenario, group] of [...byScenario.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const legsPresent = new Set(group.map((entry) => entry.leg))
    const missingLegs = expectedLegs.filter((leg) => !legsPresent.has(leg))
    if (missingLegs.length > 0) {
      violations.push(`scenario ${scenario} missing from leg(s): ${missingLegs.sort().join(',')}`)
      continue
    }
    const [first, ...rest] = group
    const FIELDS = [
      ['resultCode', 'result_code'],
      ['conflictShape', 'conflict_shape'],
      ['activityFact', 'activity_fact'],
      ['finalRevision', 'final_revision'],
    ]
    for (const entry of rest) {
      for (const [field, label] of FIELDS) {
        if (entry[field] !== first[field]) {
          violations.push(
            `scenario ${scenario}: ${label} differs (${first.leg}=${String(first[field])}, ${entry.leg}=${String(entry[field])})`,
          )
        }
      }
    }
  }

  return { ok: violations.length === 0, violations }
}

// --- Self-tests (`node --test tooling/cross-adapter/scenario-report.mjs`) ---
//
// Guarded behind the main-module check so IMPORTING this file (every leg
// and the orchestrator do) never re-runs its own test suite as a side
// effect -- `node:test`'s `test()` schedules and reports its cases on
// process exit regardless of caller, so an unguarded call here would print
// TAP output on every `node tooling/verify-cross-adapter-phase.mjs`
// invocation, not only under `node --test`.
const isMainModule = import.meta.url === `file://${process.argv[1]}`

if (isMainModule) {
test('formatScenarioLine round-trips through parseScenarioLines', () => {
  const line = formatScenarioLine({
    activityFact: 'task_captured',
    conflictShape: 'none',
    finalRevision: 1,
    inputDigest: 'deadbeef',
    leg: 'mcp',
    resultCode: 'ok',
    runId: 'run-1',
    scenario: 'capture_one_task',
  })
  const [parsed] = parseScenarioLines(line)
  assert.equal(parsed.leg, 'mcp')
  assert.equal(parsed.scenario, 'capture_one_task')
  assert.equal(parsed.resultCode, 'ok')
  assert.equal(parsed.finalRevision, 1)
})

test('parseScenarioLines throws on an unparseable CROSS_ADAPTER_SCENARIO line', () => {
  assert.throws(() => parseScenarioLines('CROSS_ADAPTER_SCENARIO this is not the right shape'), /unparseable/)
})

test('parseScenarioLines ignores unrelated lines', () => {
  const text = 'some unrelated log line\nCROSS_ADAPTER_SCENARIO run_id=r input_digest=d leg=mcp scenario=s result_code=ok conflict_shape=none activity_fact=task_captured final_revision=1\nanother line'
  const entries = parseScenarioLines(text)
  assert.equal(entries.length, 1)
})

test('compareLegs passes when every leg agrees on every scenario', () => {
  const entries = [
    { activityFact: 'task_captured', conflictShape: 'none', finalRevision: 1, inputDigest: 'd', leg: 'mcp', resultCode: 'ok', runId: 'r', scenario: 'capture_one_task' },
    { activityFact: 'task_captured', conflictShape: 'none', finalRevision: 1, inputDigest: 'd', leg: 'web-api', resultCode: 'ok', runId: 'r', scenario: 'capture_one_task' },
  ]
  const verdict = compareLegs(entries, ['mcp', 'web-api'])
  assert.equal(verdict.ok, true)
  assert.deepEqual(verdict.violations, [])
})

test('compareLegs fails when a scenario is missing from one leg', () => {
  const entries = [
    { activityFact: 'task_captured', conflictShape: 'none', finalRevision: 1, inputDigest: 'd', leg: 'mcp', resultCode: 'ok', runId: 'r', scenario: 'capture_one_task' },
  ]
  const verdict = compareLegs(entries, ['mcp', 'web-api'])
  assert.equal(verdict.ok, false)
  assert.ok(verdict.violations.some((v) => v.includes('missing from leg(s): web-api')))
})

test('compareLegs fails on a differing conflict shape between legs', () => {
  const entries = [
    { activityFact: 'task_captured', conflictShape: 'task_edit_conflict', finalRevision: 1, inputDigest: 'd', leg: 'mcp', resultCode: 'refused:task_edit_conflict', runId: 'r', scenario: 'update_stale_expected_revision' },
    { activityFact: 'task_captured', conflictShape: 'edit_conflict', finalRevision: 1, inputDigest: 'd', leg: 'web-api', resultCode: 'refused:edit_conflict', runId: 'r', scenario: 'update_stale_expected_revision' },
  ]
  const verdict = compareLegs(entries, ['mcp', 'web-api'])
  assert.equal(verdict.ok, false)
  assert.ok(verdict.violations.some((v) => v.includes('conflict_shape differs')))
})

test('compareLegs fails when entries carry more than one run_id or input_digest', () => {
  const entries = [
    { activityFact: 'task_captured', conflictShape: 'none', finalRevision: 1, inputDigest: 'd1', leg: 'mcp', resultCode: 'ok', runId: 'r1', scenario: 'capture_one_task' },
    { activityFact: 'task_captured', conflictShape: 'none', finalRevision: 1, inputDigest: 'd2', leg: 'web-api', resultCode: 'ok', runId: 'r2', scenario: 'capture_one_task' },
  ]
  const verdict = compareLegs(entries, ['mcp', 'web-api'])
  assert.equal(verdict.ok, false)
  assert.ok(verdict.violations.some((v) => v.includes('more than one run_id')))
  assert.ok(verdict.violations.some((v) => v.includes('more than one input_digest')))
})

test('compareLegs reports no evidence when given zero entries', () => {
  const verdict = compareLegs([], ['mcp', 'web-api'])
  assert.equal(verdict.ok, false)
  assert.deepEqual(verdict.violations, ['no evidence lines to compare'])
})
}

if (isMainModule && process.argv.includes('--print-format-example')) {
  console.log(
    formatScenarioLine({
      activityFact: 'task_captured',
      conflictShape: 'none',
      finalRevision: 1,
      inputDigest: 'example',
      leg: 'mcp',
      resultCode: 'ok',
      runId: 'example-run',
      scenario: 'capture_one_task',
    }),
  )
}
