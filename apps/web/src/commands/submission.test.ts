import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import { createExactSubmission } from '@/commands/submission'
import MutationRecoveryPanel from '@/features/recovery/MutationRecoveryPanel'

type TestAcknowledgement = { mutationId: string; taskId: string }

describe('exact submission recovery', () => {
  const request = {
    body: '{"version":1,"mutation_id":"mutation-1","task_id":"task-1"}',
    mutationId: 'mutation-1',
    taskId: 'task-1',
  }

  it('keeps the original request bytes and identity until an exact acknowledgement', async () => {
    const send = vi.fn().mockResolvedValue({ mutationId: 'mutation-1', taskId: 'task-1' })
    const submission = createExactSubmission({
      classifyError: () => ({ kind: 'unknown' as const }),
      lookup: vi.fn(),
      matchesAcknowledgement: (acknowledgement: TestAcknowledgement) =>
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

  it('ignores duplicate activation while the original delivery is in flight', async () => {
    const request = {
      body: '{"mutation_id":"mutation-2"}',
      mutationId: 'mutation-2',
      taskId: 'task-2',
    }
    let acknowledge: ((value: { mutationId: string; taskId: string }) => void) | undefined
    const send = vi.fn(
      () =>
        new Promise<{ mutationId: string; taskId: string }>((resolve) => {
          acknowledge = resolve
        }),
    )
    const submission = createExactSubmission({
      classifyError: () => ({ kind: 'unknown' as const }),
      lookup: vi.fn(),
      matchesAcknowledgement: (result) => result.mutationId === request.mutationId,
      request,
      send,
    })

    const first = submission.submit('csrf-one')
    const duplicate = submission.submit('csrf-one')

    expect(send).toHaveBeenCalledTimes(1)
    acknowledge?.({ mutationId: 'mutation-2', taskId: 'task-2' })
    await Promise.all([first, duplicate])
    expect(submission.snapshot.kind).toBe('acknowledged')
  })

  it('checks an unknown result then retries the exact request when no receipt exists', async () => {
    const disconnected = new Error('connection lost')
    const notFound = new Error('receipt not found')
    const send = vi
      .fn()
      .mockRejectedValueOnce(disconnected)
      .mockResolvedValueOnce({ mutationId: 'mutation-1', taskId: 'task-1' })
    const lookup = vi.fn().mockRejectedValue(notFound)
    const submission = createExactSubmission({
      classifyError: (error) => ({
        kind: error === notFound ? ('not_found' as const) : ('unknown' as const),
      }),
      lookup,
      matchesAcknowledgement: (acknowledgement: TestAcknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send,
    })

    await submission.submit('csrf-one')
    expect(submission.snapshot.kind).toBe('unknown')

    await submission.check('csrf-two')

    expect(lookup).toHaveBeenCalledWith(request)
    expect(send).toHaveBeenNthCalledWith(2, request, 'csrf-two')
    expect(submission.snapshot.kind).toBe('acknowledged')
  })

  it('supports a direct same-identity retry for lifecycle recovery', async () => {
    const disconnected = new Error('connection lost')
    const send = vi
      .fn()
      .mockRejectedValueOnce(disconnected)
      .mockResolvedValueOnce({ mutationId: 'mutation-1', taskId: 'task-1' })
    const submission = createExactSubmission({
      classifyError: () => ({ kind: 'unknown' as const }),
      lookup: vi.fn(),
      matchesAcknowledgement: (acknowledgement: TestAcknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send,
    })

    await submission.submit('csrf-one')
    await submission.retry('csrf-two')

    expect(send).toHaveBeenNthCalledWith(2, request, 'csrf-two')
    expect(submission.snapshot.kind).toBe('acknowledged')
  })

  it('reauthenticates an unknown lookup before recovering the stored result', async () => {
    const disconnected = new Error('connection lost')
    const authenticationRequired = new Error('authentication required')
    const send = vi.fn().mockRejectedValue(disconnected)
    const lookup = vi
      .fn()
      .mockRejectedValueOnce(authenticationRequired)
      .mockResolvedValueOnce({ mutationId: 'mutation-1', taskId: 'task-1' })
    const submission = createExactSubmission({
      classifyError: (error) =>
        error === authenticationRequired
          ? ({ authentication: 'sign_in', kind: 'authentication_required' } as const)
          : ({ kind: 'unknown' } as const),
      lookup,
      matchesAcknowledgement: (acknowledgement: TestAcknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send,
    })

    await submission.submit('csrf-expired')
    await submission.check('csrf-expired')
    expect(submission.snapshot).toMatchObject({
      authentication: 'sign_in',
      kind: 'authentication_required',
      operation: 'lookup',
      request,
    })

    await submission.resumeAfterAuthentication('csrf-rotated')

    expect(send).toHaveBeenCalledTimes(1)
    expect(lookup).toHaveBeenCalledTimes(2)
    expect(submission.snapshot.kind).toBe('acknowledged')
  })

  it('reauthenticates a not-submitted request then sends the unchanged bytes', async () => {
    const authenticationRequired = new Error('authentication required')
    const send = vi
      .fn()
      .mockRejectedValueOnce(authenticationRequired)
      .mockResolvedValueOnce({ mutationId: 'mutation-1', taskId: 'task-1' })
    const submission = createExactSubmission({
      classifyError: (error) =>
        error === authenticationRequired
          ? ({ authentication: 'reauthenticate', kind: 'authentication_required' } as const)
          : ({ kind: 'unknown' } as const),
      lookup: vi.fn(),
      matchesAcknowledgement: (acknowledgement: TestAcknowledgement) =>
        acknowledgement.mutationId === request.mutationId &&
        acknowledgement.taskId === request.taskId,
      request,
      send,
    })

    await submission.submit('csrf-expired')
    expect(submission.snapshot).toMatchObject({
      authentication: 'reauthenticate',
      kind: 'authentication_required',
      operation: 'send',
      request,
    })

    await submission.resumeAfterAuthentication('csrf-rotated')

    expect(send).toHaveBeenNthCalledWith(2, request, 'csrf-rotated')
    expect(submission.snapshot.kind).toBe('acknowledged')
  })

  it('renders persistent exact recovery copy and actions', async () => {
    const user = userEvent.setup()
    const onCheck = vi.fn()
    const onSignIn = vi.fn()
    const taskRequest = { ...request, path: '/api/v1/commands/edit-task' }
    const { rerender } = render(
      MutationRecoveryPanel({
        onCheck,
        onSignIn,
        state: { kind: 'unknown', request: taskRequest },
      }),
    )

    expect(screen.getByText('Checking whether your change was saved…')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Check again' }))
    expect(onCheck).toHaveBeenCalledOnce()

    rerender(
      MutationRecoveryPanel({
        onCheck,
        onSignIn,
        state: {
          authentication: 'sign_in',
          kind: 'authentication_required',
          operation: 'lookup',
          request: taskRequest,
        },
      }),
    )
    expect(
      screen.getByText('Sign in again to finish saving. Your changes are still here.'),
    ).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Sign in and continue' }))
    expect(onSignIn).toHaveBeenCalledOnce()
  })

  it.each(['conflict', 'rejected'] as const)(
    'keeps the exact request with a terminal %s result',
    async (kind) => {
      const terminal = new Error(kind)
      const submission = createExactSubmission({
        classifyError: () => ({ kind, rejection: terminal }),
        lookup: vi.fn(),
        matchesAcknowledgement: () => false,
        request,
        send: vi.fn().mockRejectedValue(terminal),
      })

      await submission.submit('csrf-one')

      expect(submission.snapshot).toMatchObject({ kind, rejection: terminal, request })
    },
  )

  it('fences a late acknowledgement after account-scoped state is cleared', async () => {
    let acknowledge: ((value: { mutationId: string; taskId: string }) => void) | undefined
    const submission = createExactSubmission({
      classifyError: () => ({ kind: 'unknown' as const }),
      lookup: vi.fn(),
      matchesAcknowledgement: () => true,
      request,
      send: vi.fn(
        () =>
          new Promise<{ mutationId: string; taskId: string }>((resolve) => {
            acknowledge = resolve
          }),
      ),
    })

    const pending = submission.submit('csrf-one')
    submission.fence()
    acknowledge?.({ mutationId: 'mutation-1', taskId: 'task-1' })
    await pending

    expect(submission.snapshot).toMatchObject({ kind: 'not_submitted', request })
  })
})
