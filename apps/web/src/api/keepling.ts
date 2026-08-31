import type { components } from '../../../../packages/contracts/generated/keepling'

type WireCaptureTaskCommand = components['schemas']['CaptureTaskCommand']
type WireCommandAcknowledgement = components['schemas']['CommandAcknowledgement']
type InboxResponse = components['schemas']['InboxResponse']
type Problem = components['schemas']['Problem']
type AuthTransitionResponse = components['schemas']['AuthTransitionResponse']
type LoginRequest = components['schemas']['LoginRequest']
type RecoveryRequest = components['schemas']['RecoveryRequest']
type ReauthenticationRequest = components['schemas']['ReauthenticationRequest']
type SessionResponse = components['schemas']['SessionResponse']
type SessionsResponse = components['schemas']['SessionsResponse']
type SessionMutationResponse = components['schemas']['SessionMutationResponse']
type SessionUpdateRequest = components['schemas']['SessionUpdateRequest']
type SetupRequest = components['schemas']['SetupRequest']
type SetupResponse = components['schemas']['SetupResponse']
type TrackedSession = components['schemas']['TrackedSession']
type VersionedAuthRequest = components['schemas']['VersionedAuthRequest']

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

type CaptureWarning = {
  code: string
  message: string
}

type CaptureAcknowledgement = {
  mutationId: string
  outcome: 'accepted' | 'already_satisfied'
  revision: number
  snapshot: BrowserTask
  taskId: string
  warnings: readonly CaptureWarning[]
}

type AuthenticationTransition = {
  csrfToken: string
  status: AuthTransitionResponse['status']
}

type BrowserSession = {
  clientKind: TrackedSession['client_kind']
  coarseActivity: TrackedSession['coarse_activity']
  createdAt: string
  current: boolean
  id: string
  label: string
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

const jsonRequest = async <RequestBody, ResponseBody>(
  path: string,
  method: 'DELETE' | 'PATCH' | 'POST',
  body: RequestBody | undefined,
  csrfToken?: string,
): Promise<ResponseBody> => {
  const headers: Record<string, string> = {
    accept: 'application/json',
  }

  if (body !== undefined) headers['content-type'] = 'application/json'
  if (csrfToken !== undefined) headers['x-csrf-token'] = csrfToken

  return readJson<ResponseBody>(
    await fetch(path, {
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'same-origin',
      headers,
      method,
    }),
  )
}

const getSession = async (): Promise<SessionResponse> =>
  readJson<SessionResponse>(
    await fetch('/api/v1/session', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

const mapAuthentication = (response: AuthTransitionResponse): AuthenticationTransition => ({
  csrfToken: response.csrf_token,
  status: response.status,
})

const completeSetup = async (
  token: string,
  password: string,
  timezone: string,
): Promise<SetupResponse> => {
  const request: SetupRequest = { password, timezone, token, version: 1 }
  return jsonRequest<SetupRequest, SetupResponse>('/api/v1/setup', 'POST', request)
}

const login = async (password: string, label: string): Promise<AuthenticationTransition> => {
  const request: LoginRequest = { client_kind: 'web', label, password, version: 1 }
  return mapAuthentication(
    await jsonRequest<LoginRequest, AuthTransitionResponse>('/api/v1/login', 'POST', request),
  )
}

const recoverAccount = async (
  token: string,
  password: string,
  label: string,
): Promise<AuthenticationTransition> => {
  const request: RecoveryRequest = {
    client_kind: 'web',
    label,
    password,
    token,
    version: 1,
  }
  return mapAuthentication(
    await jsonRequest<RecoveryRequest, AuthTransitionResponse>(
      '/api/v1/recovery',
      'POST',
      request,
    ),
  )
}

const reauthenticate = async (
  password: string,
  csrfToken: string,
): Promise<AuthenticationTransition> => {
  const request: ReauthenticationRequest = { password, version: 1 }
  return mapAuthentication(
    await jsonRequest<ReauthenticationRequest, AuthTransitionResponse>(
      '/api/v1/reauthenticate',
      'POST',
      request,
      csrfToken,
    ),
  )
}

const logout = async (csrfToken: string): Promise<SessionMutationResponse> => {
  const request: VersionedAuthRequest = { version: 1 }
  return jsonRequest<VersionedAuthRequest, SessionMutationResponse>(
    '/api/v1/logout',
    'POST',
    request,
    csrfToken,
  )
}

const mapSession = (session: TrackedSession): BrowserSession => ({
  clientKind: session.client_kind,
  coarseActivity: session.coarse_activity,
  createdAt: session.created_at,
  current: session.current,
  id: session.id,
  label: session.label,
})

const listSessions = async (): Promise<readonly BrowserSession[]> => {
  const response = await readJson<SessionsResponse>(
    await fetch('/api/v1/sessions', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )
  return response.sessions.map(mapSession)
}

const updateSession = async (
  sessionId: string,
  label: string,
  csrfToken: string,
): Promise<SessionMutationResponse> => {
  const request: SessionUpdateRequest = { label, version: 1 }
  return jsonRequest<SessionUpdateRequest, SessionMutationResponse>(
    `/api/v1/sessions/${encodeURIComponent(sessionId)}`,
    'PATCH',
    request,
    csrfToken,
  )
}

const revokeSession = async (
  sessionId: string,
  csrfToken: string,
): Promise<SessionMutationResponse> =>
  jsonRequest<undefined, SessionMutationResponse>(
    `/api/v1/sessions/${encodeURIComponent(sessionId)}`,
    'DELETE',
    undefined,
    csrfToken,
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
  warnings: acknowledgement.warnings.map((warning) => ({ ...warning })),
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
  completeSetup,
  getInbox,
  getMutation,
  getSession,
  listSessions,
  login,
  logout,
  reauthenticate,
  recoverAccount,
  revokeSession,
  updateSession,
  type AuthenticationTransition,
  type BrowserSession,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type CaptureWarning,
  type Problem,
}
