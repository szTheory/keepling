import type { components } from '../../../../packages/contracts/generated/keepling'

type WireCaptureTaskCommand = components['schemas']['CaptureTaskCommand']
type WireAssignTaskOrganizationsCommand = components['schemas']['AssignTaskOrganizationsCommand']
type WireActivityItem = components['schemas']['ActivityItem']
type WireActivityPage = components['schemas']['ActivityPage']
type WireClarifyTaskCommand = components['schemas']['ClarifyTaskCommand']
type WireCommandAcknowledgement = components['schemas']['CommandAcknowledgement']
type WireCreateOrganizationCommand = components['schemas']['CreateOrganizationCommand']
type WireEditTaskCommand = components['schemas']['EditTaskCommand']
type WireEditTaskDatesRequest = components['schemas']['EditTaskDatesRequest']
type WirePlanForTodayRequest = components['schemas']['PlanForTodayRequest']
type WireOrganizationAcknowledgement = components['schemas']['OrganizationAcknowledgement']
type WireOrganizationLifecycleCommand = components['schemas']['OrganizationLifecycleCommand']
type WireOrganizationsResponse = components['schemas']['OrganizationsResponse']
type WireRenameOrganizationCommand = components['schemas']['RenameOrganizationCommand']
type WireReturnToInboxCommand = components['schemas']['ReturnToInboxCommand']
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
  deadlineOn: string | null
  id: string
  inboxState: 'clarified' | 'inbox'
  notes: string
  plannedOn: string | null
  project: TaskOrganizationReference | null
  revision: number
  tags: readonly TaskOrganizationReference[]
  title: string
}

type TaskOrganizationReference = {
  archived: boolean
  id: string
  name: string
}

type BrowserOrganization = {
  archived: boolean
  assignable: boolean
  id: string
  kind: 'project' | 'tag'
  name: string
  revision: number
}

type ActivityChange =
  | {
      field: 'deadline_on' | 'planned_on'
      kind: 'date'
      new: string | null
      old: string | null
    }
  | {
      field: 'completed_at' | 'trashed_at'
      kind: 'instant'
      new: string | null
      old: string | null
    }
  | {
      field: 'project'
      kind: 'organization'
      new: TaskOrganizationReference | null
      old: TaskOrganizationReference | null
    }
  | {
      field: 'tags'
      kind: 'organizations'
      new: readonly TaskOrganizationReference[]
      old: readonly TaskOrganizationReference[]
    }
  | {
      field: 'inbox_state'
      kind: 'state'
      new: string | null
      old: string | null
    }
  | {
      field: 'notes' | 'title'
      kind: 'text'
      new: string | null
      old: string | null
    }

type TaskActivity = {
  acceptedAt: string
  activityId: number
  actor: {
    label: string
    principal: 'account_owner' | 'authorized_grant'
    type: 'agent' | 'user'
  }
  changes: readonly ActivityChange[]
  clientKind: 'electron' | 'iphone' | 'mcp' | 'web'
  fromRevision: number | null
  mutationId: string
  outcome: 'accepted'
  recoveryState: 'available' | 'expired' | 'not_available' | 'stale' | 'undone'
  toRevision: number
  type: WireActivityItem['type']
  undoneActivityId: number | null
  version: 1
}

type TaskActivityPage = {
  accountTimezone: string
  items: readonly TaskActivity[]
  nextCursor: string | null
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

type CommandAcknowledgement = {
  mutationId: string
  outcome: 'accepted' | 'already_satisfied'
  revision: number
  snapshot: BrowserTask
  taskId: string
  warnings: readonly CaptureWarning[]
}

type CaptureAcknowledgement = CommandAcknowledgement

type TaskDetailValues = {
  notes?: string
  title?: string
}

type EditTaskSubmission = {
  baseValues: TaskDetailValues
  expectedRevision: number
  fields: TaskDetailValues
  mutationId: string
  taskId: string
}

type TaskDateValues = {
  deadlineOn?: string | null
  plannedOn?: string | null
}

type EditTaskDatesSubmission = {
  baseValues: TaskDateValues
  expectedRevision: number
  fields: TaskDateValues
  mutationId: string
  taskId: string
}

type PlanningSubmission = {
  basePlannedOn: string | null
  expectedRevision: number
  mutationId: string
  taskId: string
}

type ReturnToInboxSubmission = {
  expectedRevision: number
  mutationId: string
  taskId: string
}

type OrganizationAssignmentValues = {
  projectId: string | null
  tagIds: readonly string[]
}

type AssignTaskOrganizationsSubmission = {
  baseValues: OrganizationAssignmentValues
  expectedRevision: number
  fields: OrganizationAssignmentValues
  mutationId: string
  taskId: string
}

type CreateOrganizationSubmission = {
  kind: BrowserOrganization['kind']
  mutationId: string
  name: string
  organizationId: string
}

type RenameOrganizationSubmission = {
  expectedRevision: number
  mutationId: string
  name: string
  organizationId: string
}

type OrganizationLifecycleSubmission = {
  expectedRevision: number
  mutationId: string
  organizationId: string
}

type OrganizationAcknowledgement = {
  mutationId: string
  organizationId: string
  outcome: 'accepted' | 'already_satisfied'
  revision: number
  snapshot: BrowserOrganization
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
  deadlineOn: task.deadline_on,
  id: task.id,
  inboxState: task.inbox_state,
  notes: task.notes,
  plannedOn: task.planned_on,
  project: task.project == null ? null : { ...task.project },
  revision: task.revision,
  tags: task.tags?.map((tag) => ({ ...tag })) ?? [],
  title: task.title,
})

const mapOrganization = (
  organization: components['schemas']['OrganizationSnapshot'],
): BrowserOrganization => ({
  archived: organization.archived,
  assignable: organization.assignable,
  id: organization.id,
  kind: organization.kind,
  name: organization.name,
  revision: organization.revision,
})

const mapActivityChange = (change: WireActivityItem['changes'][number]): ActivityChange => {
  if (change.kind === 'organization') {
    return {
      ...change,
      new: change.new == null ? null : { ...change.new },
      old: change.old == null ? null : { ...change.old },
    }
  }
  if (change.kind === 'organizations') {
    return {
      ...change,
      new: change.new.map((organization) => ({ ...organization })),
      old: change.old.map((organization) => ({ ...organization })),
    }
  }
  return { ...change }
}

const mapActivity = (activity: WireActivityItem): TaskActivity => ({
  acceptedAt: activity.accepted_at,
  activityId: activity.activity_id,
  actor: { ...activity.actor },
  changes: activity.changes.map(mapActivityChange),
  clientKind: activity.client_kind,
  fromRevision: activity.from_revision,
  mutationId: activity.mutation_id,
  outcome: activity.outcome,
  recoveryState: activity.recovery_state,
  toRevision: activity.to_revision,
  type: activity.type,
  undoneActivityId: activity.undone_activity_id,
  version: activity.version,
})

const mapOrganizationAcknowledgement = (
  acknowledgement: WireOrganizationAcknowledgement,
): OrganizationAcknowledgement => ({
  mutationId: acknowledgement.mutation_id,
  organizationId: acknowledgement.organization_id,
  outcome: acknowledgement.outcome,
  revision: acknowledgement.revision,
  snapshot: mapOrganization(acknowledgement.snapshot),
})

const mapAcknowledgement = (acknowledgement: WireCommandAcknowledgement): CommandAcknowledgement => ({
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

const getOrganizations = async (): Promise<readonly BrowserOrganization[]> => {
  const response = await readJson<WireOrganizationsResponse>(
    await fetch('/api/v1/organizations', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

  return response.organizations.map(mapOrganization)
}

const getTaskActivity = async (
  taskId: string,
  cursor?: string,
): Promise<TaskActivityPage> => {
  const query = new URLSearchParams({ limit: '20' })
  if (cursor !== undefined) query.set('cursor', cursor)

  const response = await readJson<WireActivityPage>(
    await fetch(
      `/api/v1/tasks/${encodeURIComponent(taskId)}/activity?${query.toString()}`,
      {
        credentials: 'same-origin',
        headers: { accept: 'application/json' },
      },
    ),
  )

  return {
    accountTimezone: response.account_timezone,
    items: response.items.map(mapActivity),
    nextCursor: response.next_cursor,
  }
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

const taskEditCommand = (submission: EditTaskSubmission): WireEditTaskCommand => ({
  base_values: submission.baseValues,
  expected_revision: submission.expectedRevision,
  fields: submission.fields,
  mutation_id: submission.mutationId,
  task_id: submission.taskId,
  version: 1,
})

const submitTaskCommand = async <RequestBody>(
  path: string,
  command: RequestBody,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  mapAcknowledgement(
    await jsonRequest<RequestBody, WireCommandAcknowledgement>(path, 'POST', command, csrfToken),
  )

const editTask = async (
  submission: EditTaskSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand<WireEditTaskCommand>(
    '/api/v1/commands/edit-task',
    taskEditCommand(submission),
    csrfToken,
  )

const editTaskDates = async (
  submission: EditTaskDatesSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> => {
  const command: WireEditTaskDatesRequest = {
    base_values: {
      ...(submission.baseValues.deadlineOn !== undefined
        ? { deadline_on: submission.baseValues.deadlineOn }
        : {}),
      ...(submission.baseValues.plannedOn !== undefined
        ? { planned_on: submission.baseValues.plannedOn }
        : {}),
    },
    expected_revision: submission.expectedRevision,
    fields: {
      ...(submission.fields.deadlineOn !== undefined
        ? { deadline_on: submission.fields.deadlineOn }
        : {}),
      ...(submission.fields.plannedOn !== undefined
        ? { planned_on: submission.fields.plannedOn }
        : {}),
    },
    mutation_id: submission.mutationId,
    task_id: submission.taskId,
    version: 1,
  }

  return submitTaskCommand('/api/v1/commands/edit-task-dates', command, csrfToken)
}

const planningCommand = (submission: PlanningSubmission): WirePlanForTodayRequest => ({
  base_planned_on: submission.basePlannedOn,
  expected_revision: submission.expectedRevision,
  mutation_id: submission.mutationId,
  task_id: submission.taskId,
  version: 1,
})

const planForToday = async (
  submission: PlanningSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand('/api/v1/commands/plan-for-today', planningCommand(submission), csrfToken)

const unplanTask = async (
  submission: PlanningSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand('/api/v1/commands/unplan-task', planningCommand(submission), csrfToken)

const clarifyTask = async (
  submission: EditTaskSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand<WireClarifyTaskCommand>(
    '/api/v1/commands/clarify-task',
    taskEditCommand(submission),
    csrfToken,
  )

const returnToInbox = async (
  submission: ReturnToInboxSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> => {
  const command: WireReturnToInboxCommand = {
    expected_revision: submission.expectedRevision,
    mutation_id: submission.mutationId,
    task_id: submission.taskId,
    version: 1,
  }

  return submitTaskCommand('/api/v1/commands/return-to-inbox', command, csrfToken)
}

const assignTaskOrganizations = async (
  submission: AssignTaskOrganizationsSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> => {
  const command: WireAssignTaskOrganizationsCommand = {
    base_values: {
      project_id: submission.baseValues.projectId,
      tag_ids: submission.baseValues.tagIds,
    },
    expected_revision: submission.expectedRevision,
    fields: {
      project_id: submission.fields.projectId,
      tag_ids: submission.fields.tagIds,
    },
    mutation_id: submission.mutationId,
    task_id: submission.taskId,
    version: 1,
  }

  return submitTaskCommand('/api/v1/commands/assign-task-organizations', command, csrfToken)
}

const createOrganization = async (
  submission: CreateOrganizationSubmission,
  csrfToken: string,
): Promise<OrganizationAcknowledgement> => {
  const command: WireCreateOrganizationCommand = {
    kind: submission.kind,
    mutation_id: submission.mutationId,
    name: submission.name,
    organization_id: submission.organizationId,
    version: 1,
  }

  return mapOrganizationAcknowledgement(
    await jsonRequest<WireCreateOrganizationCommand, WireOrganizationAcknowledgement>(
      '/api/v1/commands/create-organization',
      'POST',
      command,
      csrfToken,
    ),
  )
}

const renameOrganization = async (
  submission: RenameOrganizationSubmission,
  csrfToken: string,
): Promise<OrganizationAcknowledgement> => {
  const command: WireRenameOrganizationCommand = {
    expected_revision: submission.expectedRevision,
    mutation_id: submission.mutationId,
    name: submission.name,
    organization_id: submission.organizationId,
    version: 1,
  }

  return mapOrganizationAcknowledgement(
    await jsonRequest<WireRenameOrganizationCommand, WireOrganizationAcknowledgement>(
      '/api/v1/commands/rename-organization',
      'POST',
      command,
      csrfToken,
    ),
  )
}

const organizationLifecycle = async (
  action: 'archive' | 'unarchive',
  submission: OrganizationLifecycleSubmission,
  csrfToken: string,
): Promise<OrganizationAcknowledgement> => {
  const command: WireOrganizationLifecycleCommand = {
    expected_revision: submission.expectedRevision,
    mutation_id: submission.mutationId,
    organization_id: submission.organizationId,
    version: 1,
  }

  return mapOrganizationAcknowledgement(
    await jsonRequest<WireOrganizationLifecycleCommand, WireOrganizationAcknowledgement>(
      `/api/v1/commands/${action}-organization`,
      'POST',
      command,
      csrfToken,
    ),
  )
}

const archiveOrganization = (
  submission: OrganizationLifecycleSubmission,
  csrfToken: string,
) => organizationLifecycle('archive', submission, csrfToken)

const unarchiveOrganization = (
  submission: OrganizationLifecycleSubmission,
  csrfToken: string,
) => organizationLifecycle('unarchive', submission, csrfToken)

const getMutation = async (mutationId: string): Promise<CommandAcknowledgement> =>
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
  archiveOrganization,
  assignTaskOrganizations,
  captureTask,
  clarifyTask,
  completeSetup,
  createOrganization,
  editTaskDates,
  getInbox,
  getMutation,
  getOrganizations,
  getSession,
  getTaskActivity,
  editTask,
  listSessions,
  login,
  logout,
  reauthenticate,
  recoverAccount,
  renameOrganization,
  returnToInbox,
  revokeSession,
  updateSession,
  unarchiveOrganization,
  unplanTask,
  planForToday,
  type AssignTaskOrganizationsSubmission,
  type ActivityChange,
  type AuthenticationTransition,
  type BrowserOrganization,
  type BrowserSession,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type CaptureWarning,
  type CommandAcknowledgement,
  type CreateOrganizationSubmission,
  type EditTaskSubmission,
  type EditTaskDatesSubmission,
  type PlanningSubmission,
  type Problem,
  type OrganizationAcknowledgement,
  type OrganizationAssignmentValues,
  type OrganizationLifecycleSubmission,
  type RenameOrganizationSubmission,
  type ReturnToInboxSubmission,
  type TaskDetailValues,
  type TaskDateValues,
  type TaskActivity,
  type TaskActivityPage,
  type TaskOrganizationReference,
}
