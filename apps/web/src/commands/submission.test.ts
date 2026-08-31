import { describe, expect, it, vi } from 'vitest'

import { createExactSubmission } from '@/commands/submission'

describe('exact submission recovery', () => {
  it('keeps the original request bytes and identity until an exact acknowledgement', async () => {
    const request = {
      body: '{"version":1,"mutation_id":"mutation-1","task_id":"task-1"}',
      mutationId: 'mutation-1',
      taskId: 'task-1',
    }
    const send = vi.fn().mockResolvedValue({ mutationId: 'mutation-1', taskId: 'task-1' })
    const submission = createExactSubmission({
      classifyError: () => ({ kind: 'unknown' as const }),
      lookup: vi.fn(),
      matchesAcknowledgement: (acknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send,
    })

    expect(submission.snapshot.kind).toBe('not_submitted')

    await submission.submit('csrf-one')

    expect(send).toHaveBeenCalledWith(request, 'csrf-one')
    expect(submission.snapshot).toMatchObject({
      acknowledgement: { mutationId: 'mutation-1', taskId: 'task-1' },
      kind: 'acknowledged',
      request,
    })
  })
})
