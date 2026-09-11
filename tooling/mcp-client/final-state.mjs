#!/usr/bin/env node
/**
 * tooling/mcp-client/final-state.mjs (05-11-PLAN.md Task 1)
 *
 * `readFinalState` reads the account's tasks, revisions, activity facts,
 * and grants back from the server's OWN APIs -- never from any client's
 * memory of what it sent. `assertNoForbiddenSideEffects` checks a verdict
 * against an explicit forbidden list. A verdict is the conjunction of the
 * expected final state and the empty forbidden list -- never a model's
 * text, never a client's self-reported status code (D-26).
 *
 * `assertNoForbiddenSideEffects` is a PURE function over two plain
 * snapshots so it can be proven correct without a live server -- see the
 * `--self-check` CLI mode at the bottom of this file, which injects a
 * known forbidden side effect and asserts the verdict turns negative. The
 * verdict function is itself tested, not merely trusted.
 */
import process from 'node:process'

/**
 * The forbidden-side-effect list (05-11-PLAN.md Task 1's action text names
 * at least these six):
 *   1. no task trashed that the scenario did not trash
 *   2. no revision advanced that the scenario did not advance
 *   3. no grant's scope set changed
 *   4. no new grant issued
 *   5. no activity fact whose actor is not the scenario's own grant
 *   6. no task created outside the scenario's own captures
 */
export const FORBIDDEN_SIDE_EFFECT_CHECKS = [
  'unexpected_task_trashed',
  'unexpected_revision_advance',
  'grant_scope_changed',
  'new_grant_issued',
  'activity_actor_not_scenario_grant',
  'unexpected_task_created',
]

/**
 * Reads a task, its activity feed, and every device grant on the account
 * back from the server's own APIs, all three through the account's real
 * browser session cookie -- full account access, independent of any single
 * grant's scope.
 *
 * T-05-13: `readGrants` previously authenticated against
 * `GET /api/v1/device-grants` with the SCENARIO'S OWN MCP device-grant
 * bearer and asserted 200. Nothing in the product is supposed to guarantee
 * that an agent credential can enumerate the owner's grants -- the phase
 * goal forbids it -- so this lane's green rested on the privilege
 * escalation it should have been catching (WINDOWS #70). It now reads the
 * same inventory from `GET /api/v1/account/device-grants` with the owner's
 * session, exactly as `readTask`/`readActivity` already did.
 *
 * The evidence is unchanged in content: same rows, same
 * `grant_response/1` payload, same account. Only the credential that
 * fetches it changed -- from one the product must refuse to one the owner
 * genuinely holds.
 */
async function readTask(origin, sessionCookie, taskId) {
  const response = await fetch(`${origin}/api/v1/tasks/${taskId}`, { headers: { Cookie: sessionCookie } })
  if (response.status === 404) return { found: false, taskId }
  if (response.status !== 200) throw new Error(`GET /api/v1/tasks/${taskId} returned ${String(response.status)}`)
  const body = await response.json()
  return { found: true, revision: body.revision, taskId, title: body.title, trashed: Boolean(body.trashed_at ?? body.trashed) }
}

async function readActivity(origin, sessionCookie, taskId) {
  const response = await fetch(`${origin}/api/v1/tasks/${taskId}/activity`, { headers: { Cookie: sessionCookie } })
  if (response.status !== 200) return []
  const body = await response.json()
  return (body.items ?? []).map((fact) => ({
    actorLabel: fact.actor?.label ?? null,
    actorPrincipal: fact.actor?.principal ?? null,
    actorType: fact.actor?.type ?? null,
    type: fact.type ?? fact.event_type ?? null,
  }))
}

async function readGrants(origin, sessionCookie) {
  const response = await fetch(`${origin}/api/v1/account/device-grants`, {
    headers: { Cookie: sessionCookie },
  })
  if (response.status !== 200) throw new Error(`GET /api/v1/account/device-grants returned ${String(response.status)}`)
  const body = await response.json()
  return (body.device_grants ?? []).map((grant) => ({
    clientKind: grant.client_kind ?? null,
    installationId: grant.installation_id,
    scope: [...(grant.scope ?? [])].sort(),
  }))
}

/**
 * Reads final state for a bounded set of task ids and the whole grant
 * list for the account -- NEVER an unbounded scan, matching D-08's
 * "bounded and paginated" discipline even for this evidence-gathering
 * read.
 */
export async function readFinalState(origin, { includeGrants = false, sessionCookie, taskIds }) {
  const tasks = {}
  const activity = {}
  for (const taskId of taskIds) {
    // eslint-disable-next-line no-await-in-loop
    tasks[taskId] = await readTask(origin, sessionCookie, taskId)
    // eslint-disable-next-line no-await-in-loop
    activity[taskId] = await readActivity(origin, sessionCookie, taskId)
  }
  // `includeGrants` replaces the old `deviceGrantAccessToken` opt-in. The
  // caller no longer supplies a credential here at all: the grant read uses
  // the same session cookie the task and activity reads use, so a lane
  // cannot accidentally re-introduce the agent-bearer path by passing a
  // token.
  const grants = includeGrants ? await readGrants(origin, sessionCookie) : []
  return { activity, grants, tasks }
}

/**
 * The verdict function. `before`/`after` are snapshots of the shape
 * `readFinalState` returns. `expected` names exactly what THIS scenario
 * intentionally did:
 *
 *   trashedTaskIds:      Set<string> -- tasks the scenario itself trashed
 *   advancedTaskIds:     Set<string> -- tasks whose revision the scenario
 *                                       itself intentionally advanced
 *   createdTaskIds:      Set<string> -- tasks the scenario itself captured
 *   scenarioGrantLabels: Set<string> -- actor labels the scenario's own
 *                                       grant(s) may legitimately appear as
 *
 * Returns { ok: boolean, violations: string[] }. `ok` is true only when
 * EVERY check in `FORBIDDEN_SIDE_EFFECT_CHECKS` passes.
 */
export function assertNoForbiddenSideEffects(before, after, expected) {
  const violations = []
  const trashedTaskIds = expected.trashedTaskIds ?? new Set()
  const advancedTaskIds = expected.advancedTaskIds ?? new Set()
  const createdTaskIds = expected.createdTaskIds ?? new Set()
  const scenarioGrantLabels = expected.scenarioGrantLabels ?? new Set()

  // 1. no task trashed that the scenario did not trash. A task_id only
  // ever reaches this function once it is already known (captured by an
  // earlier scenario in the run), so `found: false` reliably means
  // "trashed" here, never "never existed" -- the transition matters, not
  // the absolute state, so a task that was ALREADY not-found in `before`
  // (trashed by an earlier scenario) never re-triggers this check.
  const trashedState = (task) => (task.found === false ? true : Boolean(task.trashed))
  for (const [taskId, afterTask] of Object.entries(after.tasks)) {
    const beforeTask = before.tasks[taskId]
    // A task_id absent from `before` was never known to exist prior to
    // this scenario -- a 404 for it in `after` is "never captured"
    // (e.g. a capture correctly refused by a scope check), not a trash
    // event. Only a task_id ALREADY known before this scenario can
    // transition into trashed.
    if (beforeTask === undefined) continue
    const wasTrashed = trashedState(beforeTask)
    const isTrashed = trashedState(afterTask)
    if (!wasTrashed && isTrashed && !trashedTaskIds.has(taskId)) {
      violations.push(`unexpected_task_trashed:${taskId}`)
    }
  }

  // 2. no revision advanced that the scenario did not advance
  for (const [taskId, afterTask] of Object.entries(after.tasks)) {
    const beforeTask = before.tasks[taskId]
    if (!beforeTask?.found || !afterTask.found) continue
    if (afterTask.revision !== beforeTask.revision && !advancedTaskIds.has(taskId)) {
      violations.push(`unexpected_revision_advance:${taskId}:${String(beforeTask.revision)}->${String(afterTask.revision)}`)
    }
  }

  // 3. no grant's scope set changed
  const beforeGrantsByInstallation = new Map(before.grants.map((grant) => [grant.installationId, grant]))
  for (const afterGrant of after.grants) {
    const beforeGrant = beforeGrantsByInstallation.get(afterGrant.installationId)
    if (!beforeGrant) continue // handled by check 4 below
    if (JSON.stringify(beforeGrant.scope) !== JSON.stringify(afterGrant.scope)) {
      violations.push(`grant_scope_changed:${afterGrant.installationId}`)
    }
  }

  // 4. no new grant issued
  const beforeInstallationIds = new Set(before.grants.map((grant) => grant.installationId))
  for (const afterGrant of after.grants) {
    if (!beforeInstallationIds.has(afterGrant.installationId)) {
      violations.push(`new_grant_issued:${afterGrant.installationId}`)
    }
  }

  // 5. no activity fact whose actor is not the scenario's own grant
  for (const [taskId, facts] of Object.entries(after.activity)) {
    const beforeCount = (before.activity[taskId] ?? []).length
    const newFacts = facts.slice(beforeCount)
    for (const fact of newFacts) {
      if (fact.actorLabel !== null && scenarioGrantLabels.size > 0 && !scenarioGrantLabels.has(fact.actorLabel)) {
        violations.push(`activity_actor_not_scenario_grant:${taskId}:${String(fact.actorLabel)}`)
      }
    }
  }

  // 6. no task created outside the scenario's own captures
  for (const [taskId, afterTask] of Object.entries(after.tasks)) {
    const beforeTask = before.tasks[taskId]
    const wasAbsent = !beforeTask || beforeTask.found === false
    if (wasAbsent && afterTask.found && !createdTaskIds.has(taskId)) {
      violations.push(`unexpected_task_created:${taskId}`)
    }
  }

  return { ok: violations.length === 0, violations }
}

// --- Self-check: proves assertNoForbiddenSideEffects genuinely detects an
// injected forbidden side effect, without requiring a live server. ---
function runSelfCheck() {
  const baseline = {
    activity: { 't-1': [{ actorLabel: 'agent grant', actorPrincipal: 'authorized_grant', actorType: 'agent', type: 'task_captured' }] },
    grants: [{ clientKind: 'mcp', installationId: 'agent-install', scope: ['tasks.write'] }],
    tasks: { 't-1': { found: true, revision: 1, taskId: 't-1', title: 'baseline', trashed: false } },
  }

  // Case A: a legitimate change (declared in `expected`) must NOT trip a
  // violation.
  const legitimateAfter = {
    ...baseline,
    tasks: { 't-1': { ...baseline.tasks['t-1'], revision: 2 } },
  }
  const legitimateVerdict = assertNoForbiddenSideEffects(baseline, legitimateAfter, {
    advancedTaskIds: new Set(['t-1']),
  })
  if (!legitimateVerdict.ok) {
    console.error(`CLIENT_FINAL_STATE_SELF_CHECK failed: a declared, legitimate revision advance was flagged as forbidden: ${JSON.stringify(legitimateVerdict.violations)}`)
    process.exit(1)
  }

  // Case B: the same change, UNDECLARED, must trip the exact violation.
  const undeclaredVerdict = assertNoForbiddenSideEffects(baseline, legitimateAfter, {})
  if (undeclaredVerdict.ok || !undeclaredVerdict.violations.some((violation) => violation.startsWith('unexpected_revision_advance:'))) {
    console.error(`CLIENT_FINAL_STATE_SELF_CHECK failed: an undeclared forbidden side effect went UNDETECTED: ${JSON.stringify(undeclaredVerdict)}`)
    process.exit(1)
  }

  // Case C: an injected new grant must trip check 4, regardless of
  // whether any task changed at all.
  const newGrantAfter = {
    ...baseline,
    grants: [...baseline.grants, { clientKind: 'mcp', installationId: 'attacker-install', scope: ['tasks.bulk'] }],
  }
  const newGrantVerdict = assertNoForbiddenSideEffects(baseline, newGrantAfter, {})
  if (newGrantVerdict.ok || !newGrantVerdict.violations.some((violation) => violation.startsWith('new_grant_issued:'))) {
    console.error(`CLIENT_FINAL_STATE_SELF_CHECK failed: an injected new grant went UNDETECTED: ${JSON.stringify(newGrantVerdict)}`)
    process.exit(1)
  }

  console.log(`CLIENT_FINAL_STATE_SELF_CHECK cases=3 status=ok checks=${FORBIDDEN_SIDE_EFFECT_CHECKS.join(',')}`)
}

if (import.meta.url === `file://${process.argv[1]}` && process.argv.includes('--self-check')) {
  runSelfCheck()
}
