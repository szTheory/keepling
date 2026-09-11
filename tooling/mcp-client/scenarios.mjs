#!/usr/bin/env node
/**
 * tooling/mcp-client/scenarios.mjs (05-11-PLAN.md Task 1)
 *
 * The shared semantic scenario set every lane in this plan (and 05-12's
 * cross-adapter lane) drives. Each scenario declares its `expectedFinalState`
 * (in `assertNoForbiddenSideEffects`'s `expected` shape) and its
 * `expectedErrorMember` (the closed `keepling_code` a refusal must carry,
 * or `null` for a scenario that succeeds). `run(ctx)` executes the
 * scenario against a live server through `client.mjs` and returns the
 * outcome; the caller (a lane) is responsible for reading final state
 * before and after and handing both to `assertNoForbiddenSideEffects`.
 *
 * `ctx` (constructed by each lane) carries:
 *   origin            -- the live server's HTTP origin
 *   grants             -- { write, read, bulk } access tokens/installations
 *                          (obtained via client.mjs's obtainGrant)
 *   errorVectors        -- client.mjs's loadErrorVectors() result
 *   call(scope, name, arguments)
 *                       -- a helper that dispatches tools/call with the
 *                          named grant's scope
 */
import { randomUUID } from 'node:crypto'
import { assertKnownError, toolsCall } from './client.mjs'

const dispatch = (ctx, scopeName, name, args) => toolsCall(ctx.origin, ctx.grants[scopeName].accessToken, name, args)

const captureTask = async (ctx, title) => {
  const mutationId = randomUUID()
  const taskId = randomUUID()
  const response = await dispatch(ctx, 'write', 'keepling.capture_task', {
    mutation_id: mutationId,
    task_id: taskId,
    title,
    version: 1,
  })
  if (response.body.error) throw new Error(`capture_task setup failed: ${JSON.stringify(response.body.error)}`)
  return { mutationId, response, taskId }
}

export const SCENARIOS = [
  {
    id: 'capture_one_task',
    expectedErrorMember: null,
    expectedFinalState: 'exactly one new task exists, holding the given title, at revision 1',
    name: 'capture one task',
    async run(ctx) {
      const { mutationId, response, taskId } = await captureTask(ctx, `scenario capture ${randomUUID()}`)
      return {
        createdTaskIds: new Set([taskId]),
        mutationId,
        taskIds: [taskId],
        verdict: response.body.result ? 'ok' : 'failed',
      }
    },
  },
  {
    id: 'complete_task',
    expectedErrorMember: null,
    expectedFinalState: 'the captured task transitions to completed and its revision advances',
    name: 'complete a captured task',
    async run(ctx) {
      const setup = await captureTask(ctx, 'scenario complete target')
      const response = await dispatch(ctx, 'write', 'keepling.complete_task', {
        expected_revision: 1,
        mutation_id: randomUUID(),
        task_id: setup.taskId,
        version: 1,
      })
      return {
        advancedTaskIds: new Set([setup.taskId]),
        createdTaskIds: new Set([setup.taskId]),
        taskIds: [setup.taskId],
        verdict: response.body.result ? 'ok' : 'failed',
      }
    },
  },
  {
    id: 'reopen_task',
    expectedErrorMember: null,
    expectedFinalState: 'the completed task transitions back to open and its revision advances again',
    name: 'reopen a completed task',
    async run(ctx) {
      const setup = await captureTask(ctx, 'scenario reopen target')
      await dispatch(ctx, 'write', 'keepling.complete_task', {
        expected_revision: 1,
        mutation_id: randomUUID(),
        task_id: setup.taskId,
        version: 1,
      })
      const response = await dispatch(ctx, 'write', 'keepling.reopen_task', {
        expected_revision: 2,
        mutation_id: randomUUID(),
        task_id: setup.taskId,
        version: 1,
      })
      return {
        advancedTaskIds: new Set([setup.taskId]),
        createdTaskIds: new Set([setup.taskId]),
        taskIds: [setup.taskId],
        verdict: response.body.result ? 'ok' : 'failed',
      }
    },
  },
  {
    id: 'update_stale_expected_revision',
    expectedErrorMember: 'task_edit_conflict',
    expectedFinalState: 'the task is refused with task_edit_conflict and its revision does not advance',
    name: 'update a task with a stale expected revision',
    async run(ctx) {
      const setup = await captureTask(ctx, 'scenario stale-revision target')
      const response = await dispatch(ctx, 'write', 'keepling.update_task', {
        expected_revision: 999,
        mutation_id: randomUUID(),
        task_id: setup.taskId,
        title: 'attempted stale edit',
        version: 1,
      })
      assertKnownError(response, 'task_edit_conflict', ctx.errorVectors)
      return {
        createdTaskIds: new Set([setup.taskId]),
        errorObserved: 'task_edit_conflict',
        taskIds: [setup.taskId],
        verdict: 'refused',
      }
    },
  },
  {
    id: 'address_by_phrase',
    expectedErrorMember: 'ambiguous_match',
    expectedFinalState: 'a phrase-addressed complete_task refuses with a bounded candidate set and zero mutation',
    name: 'address a task by phrase rather than identity',
    async run(ctx) {
      const shared = `phrase disambiguation ${randomUUID()}`
      const first = await captureTask(ctx, shared)
      const second = await captureTask(ctx, shared)
      const response = await dispatch(ctx, 'write', 'keepling.complete_task', {
        expected_revision: 1,
        mutation_id: randomUUID(),
        task_id: shared,
        version: 1,
      })
      assertKnownError(response, 'ambiguous_match', ctx.errorVectors)
      return {
        createdTaskIds: new Set([first.taskId, second.taskId]),
        errorObserved: 'ambiguous_match',
        taskIds: [first.taskId, second.taskId],
        verdict: 'refused',
      }
    },
  },
  {
    id: 'preview_and_commit_multi_target',
    expectedErrorMember: null,
    expectedFinalState: 'both previewed targets are trashed atomically and both revisions advance',
    name: 'preview and commit a multi-target bulk change',
    async run(ctx) {
      const first = await captureTask(ctx, 'scenario bulk target A')
      const second = await captureTask(ctx, 'scenario bulk target B')
      const previewMutationId = randomUUID()
      const preview = await dispatch(ctx, 'bulk', 'keepling.preview_bulk_change', {
        command: 'trash_task',
        mutation_id: previewMutationId,
        targets: [
          { expected_revision: 1, task_id: first.taskId },
          { expected_revision: 1, task_id: second.taskId },
        ],
      })
      if (preview.body.error) throw new Error(`preview setup failed: ${JSON.stringify(preview.body.error)}`)
      const previewToken = preview.body.result.structuredContent.preview_token
      const commit = await dispatch(ctx, 'bulk', 'keepling.commit_bulk_change', {
        mutation_id: randomUUID(),
        preview_token: previewToken,
      })
      return {
        advancedTaskIds: new Set([first.taskId, second.taskId]),
        createdTaskIds: new Set([first.taskId, second.taskId]),
        taskIds: [first.taskId, second.taskId],
        trashedTaskIds: new Set([first.taskId, second.taskId]),
        verdict: commit.body.result ? 'ok' : 'failed',
      }
    },
  },
  {
    id: 'commit_stale_preview',
    expectedErrorMember: 'preview_stale',
    expectedFinalState: 'a commit after the previewed target drifted refuses as preview_stale with zero writes',
    name: 'commit a preview whose target drifted since it was minted',
    async run(ctx) {
      const target = await captureTask(ctx, 'scenario preview-drift target')
      const preview = await dispatch(ctx, 'bulk', 'keepling.preview_bulk_change', {
        command: 'trash_task',
        mutation_id: randomUUID(),
        targets: [{ expected_revision: 1, task_id: target.taskId }],
      })
      if (preview.body.error) throw new Error(`preview setup failed: ${JSON.stringify(preview.body.error)}`)
      const previewToken = preview.body.result.structuredContent.preview_token
      // Drift the target between preview and commit -- a genuine edit
      // through the real write tool, not a synthetic database write.
      await dispatch(ctx, 'write', 'keepling.update_task', {
        expected_revision: 1,
        mutation_id: randomUUID(),
        task_id: target.taskId,
        title: 'drifted before commit',
        version: 1,
      })
      const commit = await dispatch(ctx, 'bulk', 'keepling.commit_bulk_change', {
        mutation_id: randomUUID(),
        preview_token: previewToken,
      })
      assertKnownError(commit, 'preview_stale', ctx.errorVectors)
      return {
        advancedTaskIds: new Set([target.taskId]),
        createdTaskIds: new Set([target.taskId]),
        errorObserved: 'preview_stale',
        taskIds: [target.taskId],
        verdict: 'refused',
      }
    },
  },
  {
    id: 'call_without_required_scope',
    expectedErrorMember: 'insufficient_scope',
    expectedFinalState: 'a write attempted with a read-only grant is refused with insufficient_scope and zero mutation',
    name: 'call a tool without the scope it needs',
    async run(ctx) {
      const mutationId = randomUUID()
      const taskId = randomUUID()
      const response = await toolsCall(ctx.origin, ctx.grants.read.accessToken, 'keepling.capture_task', {
        mutation_id: mutationId,
        task_id: taskId,
        title: 'should never be created',
        version: 1,
      })
      assertKnownError(response, 'insufficient_scope', ctx.errorVectors)
      return {
        createdTaskIds: new Set(),
        errorObserved: 'insufficient_scope',
        taskIds: [taskId],
        verdict: 'refused',
      }
    },
  },
  {
    id: 'replay_mutation_identity',
    expectedErrorMember: null,
    expectedFinalState: 'replaying the same mutation_id returns the original stored result and creates no second task',
    name: 'replay a mutation identity',
    async run(ctx) {
      const mutationId = randomUUID()
      const taskId = randomUUID()
      const title = 'scenario replay target'
      const first = await dispatch(ctx, 'write', 'keepling.capture_task', {
        mutation_id: mutationId,
        task_id: taskId,
        title,
        version: 1,
      })
      const replay = await dispatch(ctx, 'write', 'keepling.capture_task', {
        mutation_id: mutationId,
        task_id: taskId,
        title,
        version: 1,
      })
      const identical = JSON.stringify(first.body.result) === JSON.stringify(replay.body.result)
      if (!identical) throw new Error('replaying mutation_id did not return the original stored result')
      return {
        createdTaskIds: new Set([taskId]),
        taskIds: [taskId],
        verdict: first.body.result && replay.body.result ? 'ok' : 'failed',
      }
    },
  },
]

if (SCENARIOS.length < 9) {
  throw new Error(`scenarios.mjs declares only ${SCENARIOS.length} scenarios; the plan requires at least 9`)
}
