import { createHash } from 'node:crypto'

import { describe, expect, it } from 'vitest'

import { KeeplingSyncAdapter, settleRefusal, SyncRefusedError } from '../../main/adapters/sync.ts'
import { classifyServerRefusal } from '../../main/adapters/server-refusal.ts'
import { isSyncAuthenticationRequired, isSyncUnreachable } from '../../main/application/sync-reachability.ts'

/**
 * O-38, at the layer that actually knows.
 *
 * The problem bodies below are copied from the SERVER's own constructors
 * (`Keepling.Adapters.Postgres.CommandStore#semantic_rejection`,
 * `#persist_command_conflict`, `KeeplingWeb.Auth#authentication_problem`),
 * not invented. The real-stack lane proves the same thing end to end
 * against real Phoenix; this proves the classification exhaustively, which
 * a single end-to-end case cannot.
 */

const editConflict = {
  affected_fields: ['title'],
  code: 'task_edit_conflict',
  conflict: {
    fields: [{ base: 'Book the ferry', current: 'Book the ferry from Oban', field: 'title', mine: 'Book the ferry to Mull' }],
    id: '7f7a4f7e-0000-4000-8000-000000000001',
    latest_revision: 4,
  },
  current_revision: 4,
  detail: 'Review the affected fields before saving again.',
  recovery_action: 'review_task_conflict',
  retryable: false,
  status: 409,
  title: 'Task changed elsewhere',
  type: '/problems/task_edit_conflict',
}

const lifecycleConflict = {
  affected_fields: ['completed_at'],
  code: 'task_lifecycle_conflict',
  conflict: {
    fields: [{ base: null, current: '2026-09-04T09:00:00Z', field: 'completed_at', mine: '2026-09-04T10:00:00Z' }],
    id: '7f7a4f7e-0000-4000-8000-000000000002',
    latest_revision: 9,
  },
  current_revision: 9,
  recovery_action: 'refresh_task',
  retryable: false,
  status: 409,
  type: '/problems/task_lifecycle_conflict',
}

const authenticationRequired = {
  code: 'device_authentication_required',
  recovery_action: 'reauthorize_device',
  retryable: false,
  status: 401,
  title: 'Device authentication required',
  type: '/problems/device_authentication_required',
}

describe('classifying what the server answered (O-38)', () => {
  it('recognises every 409 conflict code the server emits', () => {
    for (const code of [
      'task_assignment_conflict',
      'task_edit_conflict',
      'task_lifecycle_conflict',
      'task_trash_conflict',
    ]) {
      expect(classifyServerRefusal(409, { code })?.kind).toBe('conflict')
    }
  })

  it('carries the SERVER’s own conflict values and nothing derived', () => {
    const refusal = classifyServerRefusal(409, editConflict)
    expect(refusal).toEqual({
      affectedFields: ['title'],
      conflictId: '7f7a4f7e-0000-4000-8000-000000000001',
      currentTitle: 'Book the ferry from Oban',
      kind: 'conflict',
      latestRevision: 4,
    })
  })

  it('reports no current title for a conflict the server did not name a title in', () => {
    const refusal = classifyServerRefusal(409, lifecycleConflict)
    expect(refusal).toMatchObject({ affectedFields: ['completed_at'], currentTitle: null, kind: 'conflict' })
  })

  it('treats a 422 semantic refusal as a terminal rejection', () => {
    for (const code of ['title_required', 'notes_too_long', 'no_fields_touched', 'invalid_task_details']) {
      expect(classifyServerRefusal(422, { code, retryable: false })).toEqual({ code, kind: 'rejected' })
    }
  })

  it('treats an unknown command and an unknown task as terminal rejections', () => {
    expect(classifyServerRefusal(400, { code: 'invalid_command' })?.kind).toBe('rejected')
    expect(classifyServerRefusal(404, { code: 'task_not_found' })?.kind).toBe('rejected')
  })

  it('NEVER collapses an authentication problem into a per-mutation rejection', () => {
    // Every authentication problem carries `retryable: false`, so a rule
    // keyed on that field alone would discard a whole outbox as "the server
    // didn't accept these changes" when the truth is "sign in again".
    expect(classifyServerRefusal(401, authenticationRequired)).toEqual({
      code: 'device_authentication_required',
      kind: 'authentication_required',
    })
  })

  it('leaves everything it does not recognise to keep throwing', () => {
    expect(classifyServerRefusal(403, { code: 'origin_not_allowed' })).toBeNull()
    expect(classifyServerRefusal(500, { code: 'infrastructure_failure' })).toBeNull()
    expect(classifyServerRefusal(503, { code: 'infrastructure_failure' })).toBeNull()
    expect(classifyServerRefusal(409, { code: 'conflict_already_resolved' })).toBeNull()
    expect(classifyServerRefusal(409, {})).toBeNull()
  })
})

describe('settling a refusal into an acknowledgement (O-38)', () => {
  const identity = { fingerprint: 'f'.repeat(64), mutationId: 'm-1', taskId: 't-1' }

  it('settles a conflict with the server’s current title and revision', () => {
    const settled = settleRefusal(new SyncRefusedError('task_edit_conflict', 409, editConflict), identity)
    expect(settled).toEqual({
      fingerprint: identity.fingerprint,
      mutationId: 'm-1',
      outcome: 'conflict',
      snapshot: {
        affected_fields: ['title'],
        conflict_id: '7f7a4f7e-0000-4000-8000-000000000001',
        id: 't-1',
        revision: 4,
        title: 'Book the ferry from Oban',
      },
    })
  })

  it('settles a 422 as a rejection carrying the server’s code', () => {
    const settled = settleRefusal(new SyncRefusedError('title_required', 422, { code: 'title_required' }), identity)
    expect(settled).toMatchObject({ outcome: 'rejected', snapshot: { id: 't-1', rejection_code: 'title_required' } })
  })

  it('refuses to settle an authentication problem or an unrecognised failure', () => {
    expect(settleRefusal(new SyncRefusedError('authentication_required', 401, authenticationRequired), identity)).toBeNull()
    expect(settleRefusal(new SyncRefusedError('infrastructure_failure', 503, { code: 'x' }), identity)).toBeNull()
    expect(settleRefusal(new Error('anything else'), identity)).toBeNull()
  })
})

/**
 * The adapter itself, driven with an injected `fetch`. This is a UNIT lane,
 * so a stub transport is the right tool here -- the real-stack lane
 * (`tooling/verify-real-stack-desktop.mjs`) refuses a stubbed fetch and
 * proves the same behaviour against real Phoenix.
 */
const adapterWith = (respond: (url: string, init?: RequestInit) => Response) =>
  new KeeplingSyncAdapter({
    accessToken: () => 'token',
    baseUrl: 'http://127.0.0.1:4102',
    fetch: async (url, init) => respond(String(url), init),
  })

const bytes = JSON.stringify({
  base_values: { notes: '', title: 'Book the ferry' },
  expected_revision: 3,
  fields: { notes: '', title: 'Book the ferry to Mull' },
  mutation_id: 'm-1',
  task_id: 't-1',
  type: 'edit_task',
  version: 1,
})

const problemResponse = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { headers: { 'content-type': 'application/problem+json' }, status })

describe('KeeplingSyncAdapter.push against what the server answers (O-38)', () => {
  it('returns a conflict acknowledgement instead of throwing on a real 409', async () => {
    const adapter = adapterWith((url) => {
      expect(url).toContain('/api/v1/commands/edit-task')
      return problemResponse(409, editConflict)
    })
    const acknowledgement = await adapter.push(bytes)
    expect(acknowledgement).toMatchObject({
      fingerprint: createHash('sha256').update(bytes).digest('hex'),
      mutationId: 'm-1',
      outcome: 'conflict',
    })
  })

  it('returns a rejected acknowledgement on a real 422', async () => {
    const adapter = adapterWith(() => problemResponse(422, { code: 'no_fields_touched', retryable: false }))
    await expect(adapter.push(bytes)).resolves.toMatchObject({ outcome: 'rejected' })
  })

  it('still throws, tagged, on a 401 so the sign-in row can be published', async () => {
    const adapter = adapterWith(() => problemResponse(401, authenticationRequired))
    await expect(adapter.push(bytes)).rejects.toSatisfy((error: unknown) => isSyncAuthenticationRequired(error))
  })

  it('still throws loudly on a 5xx -- an unheard answer is never a settled one', async () => {
    const adapter = adapterWith(() => problemResponse(503, { code: 'infrastructure_failure' }))
    await expect(adapter.push(bytes)).rejects.toThrow('infrastructure_failure')
  })

  it('still reports an unreachable server as unreachable, not as a rejection', async () => {
    const adapter = adapterWith(() => {
      throw new Error('ECONNREFUSED')
    })
    await expect(adapter.push(bytes)).rejects.toSatisfy((error: unknown) => isSyncUnreachable(error))
  })

  it('still refuses a 200 body that claims an outcome the contract does not publish', async () => {
    // `CommandAcknowledgement.outcome` publishes only accepted /
    // already_satisfied. Widening THAT would be the silent-failure trade
    // this plan forbids; a conflict arrives as a 409, not as a 200.
    const adapter = adapterWith(() =>
      new Response(JSON.stringify({ mutation_id: 'm-1', outcome: 'conflict', snapshot: { id: 't-1' } }), {
        headers: { 'content-type': 'application/json' },
        status: 200,
      }),
    )
    await expect(adapter.push(bytes)).rejects.toThrow('server acknowledgement is invalid')
  })
})
