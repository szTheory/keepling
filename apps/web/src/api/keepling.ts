import type { components } from '../../../../packages/contracts/generated/keepling'

type WireCaptureTaskCommand = components['schemas']['CaptureTaskCommand']
type WireCommandAcknowledgement = components['schemas']['CommandAcknowledgement']
type InboxResponse = components['schemas']['InboxResponse']
type Problem = components['schemas']['Problem']
type SessionResponse = components['schemas']['SessionResponse']

type BrowserTask = {
  capturedAt: string
  id: string
  inboxState: 'inbox'
  revision: number
  title: string
}

type CaptureTaskSubmission = {
  mutationId: string
  taskId: string
  title: string
}

type CaptureAcknowledgement = {
  mutationId: string
  outcome: 'accepted' | 'already_satisfied'
  revision: number
  snapshot: BrowserTask
  taskId: string
}

class KeeplingApiError extends Error {
  readonly problem: Problem

  constructor(problem: Problem) {
    super(problem.detail ?? problem.title)
    this.name = 'KeeplingApiError'
    this.problem = problem
  }
}

const readJson = async <ResponseBody>(response: Response): Promise<ResponseBody> => {
  const body = (await response.json()) as ResponseBody | Problem

  if (!response.ok) {
    throw new KeeplingApiError(body as Problem)
  }

  return body as ResponseBody
}

const getSession = async (): Promise<SessionResponse> =>
  readJson<SessionResponse>(
    await fetch('/api/v1/session', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

const mapTask = (task: components['schemas']['TaskSnapshot']): BrowserTask => ({
  capturedAt: task.captured_at,
  id: task.id,
  inboxState: task.inbox_state,
  revision: task.revision,
  title: task.title,
})

const mapAcknowledgement = (
  acknowledgement: WireCommandAcknowledgement,
): CaptureAcknowledgement => ({
  mutationId: acknowledgement.mutation_id,
  outcome: acknowledgement.outcome,
  revision: acknowledgement.revision,
  snapshot: mapTask(acknowledgement.snapshot),
  taskId: acknowledgement.task_id,
})

const getInbox = async (): Promise<readonly BrowserTask[]> => {
  const response = await readJson<InboxResponse>(
    await fetch('/api/v1/inbox', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

  return response.tasks.map(mapTask)
}

const captureTask = async (
  submission: CaptureTaskSubmission,
  csrfToken: string,
): Promise<CaptureAcknowledgement> => {
  const command: WireCaptureTaskCommand = {
    mutation_id: submission.mutationId,
    task_id: submission.taskId,
    title: submission.title,
    version: 1,
  }

  return mapAcknowledgement(
    await readJson<WireCommandAcknowledgement>(
    await fetch('/api/v1/commands/capture-task', {
      body: JSON.stringify(command),
      credentials: 'same-origin',
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        'x-csrf-token': csrfToken,
      },
      method: 'POST',
    }),
    ),
  )
}

const getMutation = async (mutationId: string): Promise<CaptureAcknowledgement> =>
  mapAcknowledgement(
    await readJson<WireCommandAcknowledgement>(
    await fetch(`/api/v1/mutations/${encodeURIComponent(mutationId)}`, {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
    ),
  )

export {
  KeeplingApiError,
  captureTask,
  getInbox,
  getMutation,
  getSession,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type Problem,
}
