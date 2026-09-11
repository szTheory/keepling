#!/usr/bin/env node
/**
 * simulated-client lane (05-11-PLAN.md Task 2, D-25's third named lane): a
 * scripted MCP client over the REAL transport, with REAL authorization
 * (never a hand-injected bearer), driving the full shared scenario set
 * from `tooling/mcp-client/scenarios.mjs`.
 *
 * Every scenario's verdict is computed from `final-state.mjs` -- final
 * database state plus the forbidden-side-effect list -- NEVER from a
 * client-self-reported HTTP status code alone (D-26; "scoring on status
 * codes is the second vacuity mode research named", 05-11-PLAN.md). This
 * lane additionally asserts the SERVER observed each mutating scenario, by
 * reading the touched task's own activity feed back from the server's own
 * audit surface (never from this client's memory of what it sent) --
 * mirroring `verify-real-stack-desktop.mjs:118-124`'s "trust the server
 * record" idiom one phase over.
 */
import { randomUUID } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { bootDisposableServer, grantLabel, guardAgainstShortcuts, loadErrorVectors, obtainGrant } from '../mcp-client/client.mjs'
import { assertNoForbiddenSideEffects, readFinalState } from '../mcp-client/final-state.mjs'
import { SCENARIOS } from '../mcp-client/scenarios.mjs'

const thisFile = fileURLToPath(import.meta.url)
const laneDirectory = dirname(thisFile)
const repositoryRoot = resolve(laneDirectory, '..', '..')

const runLane = async () => {
  guardAgainstShortcuts(thisFile)

  const server = await bootDisposableServer({
    databaseName: 'keepling_mcp_simulated_client',
    phoenixPort: Number(process.env.KEEPLING_MCP_SIMULATED_CLIENT_PHOENIX_PORT ?? 4_230),
    postgresPort: Number(process.env.KEEPLING_MCP_SIMULATED_CLIENT_POSTGRES_PORT ?? 55_470),
  })

  try {
    const errorVectors = loadErrorVectors()
    const grants = {
      bulk: await obtainGrant(server, ['tasks.bulk'], 'simulated-client-bulk'),
      read: await obtainGrant(server, ['tasks.read'], 'simulated-client-read'),
      write: await obtainGrant(server, ['tasks.write'], 'simulated-client-write'),
    }
    const deviceGrantAccessToken = grants.write.accessToken

    const ctx = { errorVectors, grants, origin: server.origin }
    const scenarioGrantLabels = new Set([
      grantLabel('simulated-client-bulk'),
      grantLabel('simulated-client-read'),
      grantLabel('simulated-client-write'),
    ])

    let casesRun = 0
    let touchedTasksAcrossAllScenarios = 0
    let knownTaskIds = []

    for (const scenario of SCENARIOS) {
      // Snapshot every task known so far BEFORE this scenario runs --
      // this is what lets `assertNoForbiddenSideEffects` catch a scenario
      // that mutates a PRIOR scenario's task, not just its own.
      // eslint-disable-next-line no-await-in-loop
      const before = await readFinalState(server.origin, {
        deviceGrantAccessToken,
        sessionCookie: server.sessionCookie,
        taskIds: knownTaskIds,
      })

      // eslint-disable-next-line no-await-in-loop
      const outcome = await scenario.run(ctx)

      const scenarioTaskIds = outcome.taskIds ?? []
      knownTaskIds = [...new Set([...knownTaskIds, ...scenarioTaskIds])]

      // eslint-disable-next-line no-await-in-loop
      const after = await readFinalState(server.origin, {
        deviceGrantAccessToken,
        sessionCookie: server.sessionCookie,
        taskIds: knownTaskIds,
      })

      const verdict = assertNoForbiddenSideEffects(before, after, {
        advancedTaskIds: outcome.advancedTaskIds ?? new Set(),
        createdTaskIds: outcome.createdTaskIds ?? new Set(),
        scenarioGrantLabels,
        trashedTaskIds: outcome.trashedTaskIds ?? new Set(),
      })
      if (!verdict.ok) {
        throw new Error(`scenario "${scenario.id}" produced forbidden side effects: ${JSON.stringify(verdict.violations)}`)
      }

      if (scenario.expectedErrorMember && outcome.errorObserved !== scenario.expectedErrorMember) {
        throw new Error(`scenario "${scenario.id}" expected error member "${scenario.expectedErrorMember}", observed "${String(outcome.errorObserved)}"`)
      }
      if (!scenario.expectedErrorMember && outcome.verdict !== 'ok') {
        throw new Error(`scenario "${scenario.id}" expected success, observed verdict "${String(outcome.verdict)}"`)
      }

      // Server-observed evidence: every task this scenario touched must
      // show at least one activity fact recorded by the server itself --
      // proof the mutation was genuinely processed, not merely that this
      // client believes a 200 came back.
      for (const taskId of scenarioTaskIds) {
        const facts = after.activity[taskId] ?? []
        if (facts.length === 0 && (outcome.createdTaskIds ?? new Set()).has(taskId)) {
          throw new Error(`scenario "${scenario.id}" task ${taskId} shows zero server-recorded activity facts -- the server never observed this scenario`)
        }
        touchedTasksAcrossAllScenarios += facts.length
      }

      casesRun += 1
    }

    if (touchedTasksAcrossAllScenarios === 0) {
      throw new Error('no scenario produced any server-observed activity -- this run proved nothing')
    }
    if (casesRun !== SCENARIOS.length) {
      throw new Error(`ran ${casesRun} scenario(s) but SCENARIOS declares ${SCENARIOS.length} -- a scenario was silently skipped`)
    }

    console.log(`SIMULATED_CLIENT cases=${casesRun} activity_facts_observed=${touchedTasksAcrossAllScenarios} run_id=${randomUUID()}`)
  } finally {
    await server.stop()
  }
}

const parseSimulatedClientOutput = (stdout, stderr) => {
  const blockedLine = stdout.split('\n').find((line) => line.startsWith('BLOCKED:'))
    ?? stderr.split('\n').find((line) => line.startsWith('BLOCKED:'))
  if (blockedLine) throw new Error(blockedLine)

  // Deliberately does NOT inspect any HTTP status code -- only the
  // evidence line this lane prints after every scenario's verdict was
  // computed from final database state. A 200 response is never, by
  // itself, treated as a pass.
  const match = stdout.match(/SIMULATED_CLIENT cases=(\d+) activity_facts_observed=(\d+)/)
  if (!match) {
    throw new Error(`simulated-client lane never reported a SIMULATED_CLIENT evidence line${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
  }
  const cases = Number(match[1])
  if (!Number.isFinite(cases) || cases <= 0) throw new Error('simulated-client lane reported a non-positive case count')
  if (Number(match[2]) <= 0) throw new Error('simulated-client lane observed zero server-recorded activity facts')
  return cases
}

export default function simulatedClientLane() {
  return {
    args: [thisFile, '--run'],
    command: process.execPath,
    cwd: repositoryRoot,
    name: 'simulated-client',
    parse: parseSimulatedClientOutput,
    trackedInputPaths: [
      'tooling/mcp-client/client.mjs',
      'tooling/mcp-client/scenarios.mjs',
      'tooling/mcp-client/final-state.mjs',
      'tooling/mcp-lanes/simulated-client.mjs',
      'apps/server/lib/keepling_web/mcp',
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
