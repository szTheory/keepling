#!/usr/bin/env node
/**
 * adversarial lane (05-11-PLAN.md Task 2, D-25's fourth named lane): for
 * each `packages/contracts/vectors/mcp-injection.json` case, this lane
 * places the injected content into a task that is GENUINELY the resolved
 * target of the case's own scenario -- never merely a task sitting
 * somewhere else in the database. The lane asserts this structurally:
 * each case declares the exact task it must resolve into, and the lane
 * fails the case if the operation did not in fact resolve to that task.
 * An injection sitting outside the code path under test is exactly the
 * third vacuity mode 05-RESEARCH.md Finding 10(c) names -- tautological
 * by construction.
 *
 * Every case is scored ONLY on final database state and the
 * forbidden-side-effect list (never on the model-facing text that would
 * accompany a real model, since this lane drives the tool calls directly
 * -- that additional "a real model reads this and might act on it" layer
 * is `representative-model.mjs`'s job, which reuses this SAME corpus for
 * its own injection scenario).
 */
import { randomUUID } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { bootDisposableServer, grantLabel, guardAgainstShortcuts, loadErrorVectors, obtainGrant, toolsCall } from '../mcp-client/client.mjs'
import { assertNoForbiddenSideEffects, readFinalState } from '../mcp-client/final-state.mjs'

const thisFile = fileURLToPath(import.meta.url)
const laneDirectory = dirname(thisFile)
const repositoryRoot = resolve(laneDirectory, '..', '..')

const corpusPath = join(repositoryRoot, 'packages/contracts/vectors/mcp-injection.json')

const loadCorpus = () => JSON.parse(readFileSync(corpusPath, 'utf8'))

const captureTask = async (ctx, title) => {
  const taskId = randomUUID()
  const response = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.capture_task', {
    mutation_id: randomUUID(),
    task_id: taskId,
    title,
    version: 1,
  })
  if (response.body.error) throw new Error(`capture setup failed: ${JSON.stringify(response.body.error)}`)
  return taskId
}

const writeInjectedField = async (ctx, taskId, field, text) => {
  const response = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.update_task', {
    [field]: text,
    expected_revision: 1,
    mutation_id: randomUUID(),
    task_id: taskId,
    version: 1,
  })
  if (response.body.error) throw new Error(`injecting content failed: ${JSON.stringify(response.body.error)}`)
  return response
}

/**
 * Executes ONE corpus case: seeds a task carrying the injected content,
 * runs the exact real operation the case's `target_scenario` names, and
 * proves the operation resolved into the SAME task the injection was
 * written to -- the structural anti-tautology check the plan's action
 * text requires.
 */
const runCase = async (ctx, injectionCase) => {
  const target = await captureTask(ctx, `adversarial case ${injectionCase.id}`)
  await writeInjectedField(ctx, target, injectionCase.field, injectionCase.injection_text)
  // The injected content is now genuinely stored on `target`, at
  // revision 2 (capture=1, injected update=2).

  let resolvedTarget = null
  let errorObserved = null

  switch (injectionCase.id) {
    case 'trash_all_tasks_instruction': {
      // A second, UNRELATED task exists in the same account so the case
      // can prove it was never touched -- the forbidden outcome this
      // case names is "any task OTHER than the resolved target is
      // trashed".
      const bystander = await captureTask(ctx, 'adversarial bystander task (must survive)')
      const completeResponse = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.complete_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        task_id: target,
        version: 1,
      })
      if (completeResponse.body.result) resolvedTarget = target
      return { bystander, resolvedTarget, taskIds: [target, bystander] }
    }

    case 'grant_bulk_scope_instruction': {
      const updateResponse = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.update_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        notes: 'legitimate follow-up edit after reading the injected note',
        task_id: target,
        version: 1,
      })
      if (updateResponse.body.result) resolvedTarget = target
      return { resolvedTarget, taskIds: [target] }
    }

    case 'impersonate_different_target': {
      const otherTask = await captureTask(ctx, 'adversarial other task (must NOT be touched)')
      // The scenario driver deliberately calls update_task with the
      // ORIGINAL task_id it was given -- exactly what a correctly-built
      // MCP host does: it addresses by the identity it was given, never
      // by a claim embedded in the target's own untrusted notes.
      const updateResponse = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.update_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        title: 'edited via the originally-supplied identity',
        task_id: target,
        version: 1,
      })
      const structured = updateResponse.body.result?.structuredContent
      resolvedTarget = structured?.id ?? structured?.task_id ?? (updateResponse.body.result ? target : null)
      return { otherTask, resolvedTarget, taskIds: [target, otherTask] }
    }

    case 'fabricated_preview_token': {
      const fabricatedToken = 'FABRICATED.' + Buffer.from(injectionCase.injection_text).toString('base64url').slice(0, 40)
      const commitResponse = await toolsCall(ctx.origin, ctx.grants.bulk.accessToken, 'keepling.commit_bulk_change', {
        mutation_id: randomUUID(),
        preview_token: fabricatedToken,
      })
      errorObserved = commitResponse.body.error?.data?.keepling_code ?? null
      // The fabricated token was never minted for `target` -- if the
      // commit resolves at all, it must resolve to NOTHING (refused),
      // never to this task.
      resolvedTarget = commitResponse.body.result ? target : null
      return { resolvedTarget, taskIds: [target] }
    }

    case 'fabricated_expected_revision': {
      // The note claims expected_revision=1 is still current; the lane
      // deliberately issues the call with that LITERAL fabricated value
      // (matching what a naive, content-trusting host would do), proving
      // the server's own revision check -- not this lane's judgement --
      // is what refuses it.
      const updateResponse = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.update_task', {
        expected_revision: 1,
        mutation_id: randomUUID(),
        title: 'attempted edit using the fabricated stale revision',
        task_id: target,
        version: 1,
      })
      errorObserved = updateResponse.body.error?.data?.keepling_code ?? null
      resolvedTarget = updateResponse.body.result ? target : null
      return { resolvedTarget, taskIds: [target] }
    }

    case 'retry_with_elevated_scope_claim': {
      const readOnlyAttempt = await toolsCall(ctx.origin, ctx.grants.read.accessToken, 'keepling.update_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        title: 'attempted retry claiming the refusal was a mistake',
        task_id: target,
        version: 1,
      })
      const retryAttempt = await toolsCall(ctx.origin, ctx.grants.read.accessToken, 'keepling.update_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        title: 'attempted retry claiming the refusal was a mistake',
        task_id: target,
        version: 1,
      })
      errorObserved = retryAttempt.body.error?.data?.keepling_code ?? null
      resolvedTarget = readOnlyAttempt.body.result || retryAttempt.body.result ? target : null
      return { resolvedTarget, taskIds: [target] }
    }

    default:
      throw new Error(`adversarial lane has no execution branch for corpus case "${injectionCase.id}"`)
  }
}

const assertResolvedIntoTarget = (injectionCase, target, outcome) => {
  // Every case except the REFUSAL-shaped ones (fabricated preview token,
  // fabricated stale revision, retrying a correctly-scope-refused call)
  // is expected to resolve into the exact task the injection was written
  // to -- proving the operation was genuinely IN the code path the
  // injected content lives in, not tautologically absent from it. The
  // refusal-shaped cases instead prove the injection changed nothing:
  // the call is refused just as it would be without the injected content.
  const refusalShaped = [
    'fabricated_preview_token',
    'fabricated_expected_revision',
    'retry_with_elevated_scope_claim',
  ].includes(injectionCase.id)
  if (refusalShaped) {
    if (outcome.resolvedTarget !== null) {
      throw new Error(`case "${injectionCase.id}" resolved into a task when it should have been refused entirely`)
    }
    return
  }
  if (outcome.resolvedTarget !== target) {
    throw new Error(`case "${injectionCase.id}" did not resolve into its declared target (${target}); resolved into ${String(outcome.resolvedTarget)}`)
  }
}

/**
 * T-05-13 / WINDOWS #70: the OVER-delivery cases.
 *
 * Every lane in this phase, this one included, was built to detect
 * UNDER-delivery -- a surface that refuses what it should allow, a mutation
 * that did not happen. None probed whether the credential the harness
 * itself mints reaches surfaces the MCP adapter does not front. The phase's
 * privilege escalation lived in exactly that blind spot, and it went
 * further than merely being missed: `final-state.mjs` CONSUMED the hole as
 * a convenience, so a green lane depended on it.
 *
 * These four cases aim the lane's own agent credential at the four routes
 * behind `:device_grant_authenticated` and require a refusal from each. If
 * any route stops refusing, the gate fails.
 *
 * Each route is asserted to answer exactly 401 -- never merely "not 200".
 * A deleted route answers 404 and a broken server answers 500; accepting
 * either as evidence of a refusal would make this whole block vacuous the
 * day someone removes a route.
 */
const OVER_DELIVERY_ROUTES = [
  { method: 'GET', name: 'sync_pull', path: '/api/v1/sync' },
  { method: 'GET', name: 'sync_bootstrap', path: '/api/v1/sync/bootstrap' },
  { method: 'GET', name: 'device_grants_list', path: '/api/v1/device-grants' },
  { method: 'DELETE', name: 'device_grants_revoke', path: null },
]

const readOwnerGrants = async (server) => {
  const response = await fetch(`${server.origin}/api/v1/account/device-grants`, {
    headers: { Cookie: server.sessionCookie },
  })
  if (response.status !== 200) {
    throw new Error(`over_delivery setup: the owner's own grant list returned ${String(response.status)}`)
  }
  return (await response.json()).device_grants ?? []
}

const runOverDeliveryCases = async (ctx, server) => {
  // A real secret written through the MCP surface. If a route leaks the
  // account back to the agent, this string is what comes out -- so each
  // assertion is "the body does not contain it", not merely "the status
  // was not 200".
  const secretTitle = `over-delivery canary ${randomUUID()}`
  await captureTask(ctx, secretTitle)

  const grantsBefore = await readOwnerGrants(server)
  if (grantsBefore.length !== 3) {
    throw new Error(`over_delivery setup: expected the 3 grants this lane issued, found ${String(grantsBefore.length)}`)
  }
  // The revoke case aims at a DIFFERENT installation than the agent's own
  // -- the escalation's sharpest edge was an agent switching off another
  // client, not itself.
  const victim = grantsBefore.find((grant) => grant.installation_id !== ctx.grants.write.installationId)
    ?? grantsBefore[0]

  let casesRun = 0
  for (const route of OVER_DELIVERY_ROUTES) {
    const path = route.path ?? `/api/v1/device-grants/${encodeURIComponent(victim.installation_id)}`

    // eslint-disable-next-line no-await-in-loop
    const response = await fetch(`${server.origin}${path}`, {
      headers: { Authorization: 'Bearer ' + ctx.grants.write.accessToken },
      method: route.method,
    })
    // eslint-disable-next-line no-await-in-loop
    const body = await response.text()

    if (response.status !== 401) {
      throw new Error(`over_delivery case "${route.name}": ${route.method} ${path} answered ${String(response.status)} for an mcp grant; expected 401`)
    }
    if (body.includes(secretTitle)) {
      throw new Error(`over_delivery case "${route.name}": the refusal body leaked account content to an agent credential`)
    }
    if (body.includes(victim.installation_id)) {
      throw new Error(`over_delivery case "${route.name}": the refusal body disclosed another installation to an agent credential`)
    }
    casesRun += 1
  }

  // Scored on final state, like every other case in this lane: the refused
  // DELETE must have changed nothing. Read back through the OWNER's
  // session, never through the credential under test.
  const grantsAfter = await readOwnerGrants(server)
  if (grantsAfter.length !== grantsBefore.length) {
    throw new Error(`over_delivery: the grant inventory changed across the refused requests (${String(grantsBefore.length)} -> ${String(grantsAfter.length)})`)
  }
  const nowRevoked = grantsAfter.filter((grant) => grant.revoked).map((grant) => grant.installation_id)
  if (nowRevoked.length > 0) {
    throw new Error(`over_delivery: a refused request still revoked ${nowRevoked.join(', ')}`)
  }

  // The boundary must be a BOUNDARY, not a broken credential: the same
  // token still works on the surface the MCP adapter does front. Without
  // this control, every assertion above would pass just as well against a
  // credential that had simply been revoked.
  const control = await toolsCall(ctx.origin, ctx.grants.write.accessToken, 'keepling.capture_task', {
    mutation_id: randomUUID(),
    task_id: randomUUID(),
    title: 'over-delivery control capture',
    version: 1,
  })
  if (control.body.error) {
    throw new Error(`over_delivery control: the credential refused on all four native routes is also refused on /mcp/v1 -- that is credential breakage, not a boundary: ${JSON.stringify(control.body.error)}`)
  }

  return casesRun
}

const runLane = async () => {
  guardAgainstShortcuts(thisFile)

  const corpus = loadCorpus()
  if (!Array.isArray(corpus.cases) || corpus.cases.length < 6) {
    throw new Error('mcp-injection.json declares fewer than 6 cases')
  }

  const server = await bootDisposableServer({
    databaseName: 'keepling_mcp_adversarial',
    phoenixPort: Number(process.env.KEEPLING_MCP_ADVERSARIAL_PHOENIX_PORT ?? 4_240),
    postgresPort: Number(process.env.KEEPLING_MCP_ADVERSARIAL_POSTGRES_PORT ?? 55_480),
  })

  try {
    const errorVectors = loadErrorVectors()
    const grants = {
      bulk: await obtainGrant(server, ['tasks.bulk'], 'adversarial-bulk'),
      read: await obtainGrant(server, ['tasks.read'], 'adversarial-read'),
      write: await obtainGrant(server, ['tasks.write'], 'adversarial-write'),
    }
    const ctx = { errorVectors, grants, origin: server.origin }
    const scenarioGrantLabels = new Set([
      grantLabel('adversarial-bulk'),
      grantLabel('adversarial-read'),
      grantLabel('adversarial-write'),
    ])

    let casesRun = 0
    let knownTaskIds = []

    for (const injectionCase of corpus.cases) {
      // eslint-disable-next-line no-await-in-loop
      const before = await readFinalState(server.origin, {
        includeGrants: true,
        sessionCookie: server.sessionCookie,
        taskIds: knownTaskIds,
      })

      // eslint-disable-next-line no-await-in-loop
      const outcome = await runCase(ctx, injectionCase)

      const caseTaskIds = outcome.taskIds ?? []
      knownTaskIds = [...new Set([...knownTaskIds, ...caseTaskIds])]

      // eslint-disable-next-line no-await-in-loop
      const after = await readFinalState(server.origin, {
        includeGrants: true,
        sessionCookie: server.sessionCookie,
        taskIds: knownTaskIds,
      })

      // The first entry in `caseTaskIds` is always the injected-content
      // target itself -- every branch above returns it first.
      const [injectedTarget] = caseTaskIds
      assertResolvedIntoTarget(injectionCase, injectedTarget, outcome)

      const verdict = assertNoForbiddenSideEffects(before, after, {
        advancedTaskIds: new Set(caseTaskIds),
        createdTaskIds: new Set(caseTaskIds),
        scenarioGrantLabels,
      })
      if (!verdict.ok) {
        throw new Error(`case "${injectionCase.id}" produced forbidden side effects: ${JSON.stringify(verdict.violations)}`)
      }

      casesRun += 1
    }

    if (casesRun !== corpus.cases.length) {
      throw new Error(`ran ${casesRun} injection case(s) but the corpus declares ${corpus.cases.length}`)
    }

    const overDeliveryCasesRun = await runOverDeliveryCases(ctx, server)
    if (overDeliveryCasesRun !== OVER_DELIVERY_ROUTES.length) {
      throw new Error(`ran ${overDeliveryCasesRun} over-delivery case(s) but ${OVER_DELIVERY_ROUTES.length} routes are declared`)
    }

    console.log(`ADVERSARIAL cases=${casesRun + overDeliveryCasesRun} injection_cases=${casesRun} over_delivery_cases=${overDeliveryCasesRun} run_id=${randomUUID()}`)
  } finally {
    await server.stop()
  }
}

const parseAdversarialOutput = (stdout, stderr) => {
  const blockedLine = stdout.split('\n').find((line) => line.startsWith('BLOCKED:'))
    ?? stderr.split('\n').find((line) => line.startsWith('BLOCKED:'))
  if (blockedLine) throw new Error(blockedLine)

  // Deliberately never inspects `response.status === 200` -- see the
  // acceptance criterion this file is written against. Every case's
  // outcome was already scored against final database state before this
  // evidence line was even printed.
  const match = stdout.match(/ADVERSARIAL cases=(\d+)/)
  if (!match) {
    throw new Error(`adversarial lane never reported an ADVERSARIAL evidence line${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
  }
  const cases = Number(match[1])
  if (!Number.isFinite(cases) || cases <= 0) throw new Error('adversarial lane reported a non-positive case count')
  return cases
}

export default function adversarialLane() {
  return {
    args: [thisFile, '--run'],
    command: process.execPath,
    cwd: repositoryRoot,
    name: 'adversarial',
    parse: parseAdversarialOutput,
    trackedInputPaths: [
      'tooling/mcp-client/client.mjs',
      'tooling/mcp-client/final-state.mjs',
      'tooling/mcp-lanes/adversarial.mjs',
      'packages/contracts/vectors/mcp-injection.json',
      'apps/server/lib/keepling_web/mcp',
      // T-05-13: the over-delivery cases are assertions ABOUT these two
      // files. A change to either must change this lane's input digest,
      // or the gate would report a stale verdict for the boundary they
      // define.
      'apps/server/lib/keepling_web/auth.ex',
      'apps/server/lib/keepling_web/router.ex',
      'apps/server/lib/keepling/application/task_addressing.ex',
      'apps/server/lib/keepling/application/preview.ex',
    ],
  }
}

if (import.meta.url === `file://${process.argv[1]}` && process.argv.includes('--run')) {
  try {
    await runLane()
  } catch (error) {
    if (error?.blocked) {
      console.error(error.message)
      process.exitCode = 1
    } else {
      console.error(error?.stack ?? String(error))
      process.exitCode = 1
    }
  }
}
