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
type WireResolveTaskConflictCommand = components['schemas']['ResolveTaskConflictCommand']
type WireReturnToInboxCommand = components['schemas']['ReturnToInboxCommand']
type WireRestoreAcknowledgement = components['schemas']['RestoreAcknowledgement']
type WireTaskLifecycleCommand = components['schemas']['TaskLifecycleCommand']
type WireTaskViewItem = components['schemas']['TaskViewItem']
type WireTaskViewPage = components['schemas']['TaskViewPage']
type WireTodayMoveRequest = components['schemas']['TodayMoveRequest']
type WireTodayMoveResponse = components['schemas']['TodayMoveResponse']
type WireTrashResponse = components['schemas']['TrashResponse']
type WireUndoAvailability = components['schemas']['UndoAvailability']
type WireUndoNoChange = components['schemas']['UndoNoChange']
type WireUndoResult = components['schemas']['UndoResult']
type WireUndoTaskCommand = components['schemas']['UndoTaskCommand']
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
type DeviceGrantSummary = components['schemas']['DeviceGrantSummary']
type DeviceGrantRevocationResponse = components['schemas']['DeviceGrantRevocationResponse']

// The wire `DeviceGrantSummary` schema (packages/contracts/openapi/keepling.yaml)
// closes `client_kind` to `electron | iphone` (`NativeClientIdentity`) and does
// not yet publish `scope`, `last_used_at`, or `authorized_at` -- even though the
// server's own `device_grants.client_kind` CHECK constraint has admitted `mcp`
// since 05-01, and `GET /api/v1/account/device-grants` (KeeplingWeb.DeviceGrantController)
// genuinely returns `client_kind: "mcp"` rows at runtime. The generated TS type
// is stale relative to the runtime contract; `client_kind` is widened to `string`
// here (rather than trusting the closed union) so a real "mcp" value type-checks,
// and `scope`/`last_used_at`/`authorized_at` are read DEFENSIVELY (optional,
// absent from every response today) rather than fabricated. The UI is correct
// today (renders "no scopes" / no timestamp) and picks up real values
// automatically once a follow-up server-side plan closes both gaps in
// `packages/contracts/openapi/keepling.yaml` and
// `KeeplingWeb.DeviceGrantController.grant_response/1`. See 05-09-SUMMARY.md.
type WireAgentGrantSummary = Omit<DeviceGrantSummary, 'client_kind'> & {
  authorized_at?: string
  client_kind: string
  last_used_at?: string | null
  scope?: readonly string[]
}

type WireAgentGrantsResponse = {
  device_grants: readonly WireAgentGrantSummary[]
}

type BrowserTask = {
  capturedAt: string
  completedAt: string | null
  deadlineOn: string | null
  id: string
  inboxState: 'clarified' | 'inbox'
  notes: string
  plannedOn: string | null
  project: TaskOrganizationReference | null
  revision: number
  tags: readonly TaskOrganizationReference[]
  title: string
  trashedAt: string | null
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

type TaskViewName = 'completed' | 'inbox' | 'today' | 'upcoming'

type TaskViewItem = {
  capturedAt: string
  completedAt?: string
  completedOn?: string
  deadlineOn: string | null
  groupOn?: string
  id: string
  plannedOn: string | null
  reasons: readonly NonNullable<WireTaskViewItem['reasons']>[number][]
  revision: number
  section?: NonNullable<WireTaskViewItem['section']>
  title: string
  upcomingReason?: NonNullable<WireTaskViewItem['upcoming_reason']>
}

type TaskViewPage = {
  accountDay: string
  accountTimezone: string
  items: readonly TaskViewItem[]
  nextCursor: string | null
  orderRevision: number | null
  view: TaskViewName
}

type TodayMoveSubmission = {
  direction: 'earlier' | 'later'
  expectedOrderRevision: number
  mutationId: string
  taskId: string
}

type PreparedTodayMove = Readonly<{
  body: string
  direction: TodayMoveSubmission['direction']
  expectedOrderRevision: number
  mutationId: string
  path: string
  taskId: string
}>

type TodayMoveAcknowledgement = {
  mutationId: string
  orderRevision: number
  taskId: string
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
  resolvedConflictId: string | null
  snapshot: BrowserTask
  taskId: string
  undo: UndoAvailability | null
  warnings: readonly CaptureWarning[]
}

type UndoAvailability = {
  expiresAt: string
  handle: string
  label: string
}

type UndoNoChange = {
  code: WireUndoNoChange['code']
  mutationId: string
  outcome: WireUndoNoChange['outcome']
  recoveryAction: WireUndoNoChange['recovery_action']
  retryable: boolean
  title: string
}

type UndoSubmission = {
  availability: UndoAvailability
  mutationId: string
}

type UndoResult =
  | { acknowledgement: CommandAcknowledgement; kind: 'acknowledged' }
  | { kind: 'no-change'; result: UndoNoChange }

type RestoreAcknowledgement = CommandAcknowledgement & {
  destinations: readonly WireRestoreAcknowledgement['destinations'][number][]
}

type CaptureAcknowledgement = CommandAcknowledgement

type TaskDetailValues = {
  notes?: string
  title?: string
}

type TaskConflictField = {
  base: string | null
  current: string | null
  field: 'notes' | 'title'
  mine: string | null
}

type TaskConflict = {
  fields: readonly TaskConflictField[]
  id: string
  latestRevision: number
}

type ConflictResolutionSubmission = {
  conflictId: string
  latestRevision: number
  mutationId: string
  selections: Partial<Record<TaskConflictField['field'], 'current' | 'mine'>>
  taskId: string
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

type LifecycleSubmission = ReturnToInboxSubmission

type PreparedTaskCommand = {
  readonly body: string
  readonly mutationId: string
  readonly path: string
  readonly taskId: string
}

type PreparedRestoreTask = PreparedTaskCommand

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

type AgentGrant = {
  authorizedAt: string | null
  clientKind: 'mcp'
  id: string
  installationId: string
  label: string
  lastUsedAt: string | null
  revoked: boolean
  // `null` means the server did not report a scope list for this grant, which
  // is a DIFFERENT claim from `[]` ("this grant holds no scopes"). On a consent
  // screen those are opposite statements, so the absence is preserved here
  // rather than collapsed, exactly as `authorizedAt`/`lastUsedAt` preserve it.
  scope: readonly string[] | null
}

class KeeplingApiError extends Error {
  readonly problem: Problem
  readonly conflict: TaskConflict | null

  constructor(problem: Problem) {
    super(problem.detail ?? problem.title)
    this.name = 'KeeplingApiError'
    this.problem = problem
    this.conflict = mapTaskConflict(problem.conflict)
  }
}

const mapTaskConflict = (conflict: Problem['conflict']): TaskConflict | null => {
  if (
    conflict === undefined ||
    !conflict.fields.every((field) => field.field === 'notes' || field.field === 'title')
  ) {
    return null
  }

  return {
    fields: conflict.fields.map((field) => ({
      base: field.base,
      current: field.current,
      field: field.field as TaskConflictField['field'],
      mine: field.mine,
    })),
    id: conflict.id,
    latestRevision: conflict.latest_revision,
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

const mapAgentGrant = (grant: WireAgentGrantSummary): AgentGrant => ({
  authorizedAt: grant.authorized_at ?? null,
  clientKind: 'mcp',
  id: grant.id,
  installationId: grant.installation_id,
  label: grant.label,
  lastUsedAt: grant.last_used_at ?? null,
  revoked: grant.revoked,
  scope: grant.scope ?? null,
})

const listDeviceGrants = async (): Promise<readonly AgentGrant[]> => {
  const response = await readJson<WireAgentGrantsResponse>(
    await fetch('/api/v1/account/device-grants', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

  return response.device_grants
    .filter((grant) => grant.client_kind === 'mcp')
    .map(mapAgentGrant)
}

const revokeDeviceGrant = async (
  installationId: string,
  csrfToken: string,
): Promise<DeviceGrantRevocationResponse> =>
  jsonRequest<undefined, DeviceGrantRevocationResponse>(
    `/api/v1/account/device-grants/${encodeURIComponent(installationId)}`,
    'DELETE',
    undefined,
    csrfToken,
  )

const mapTask = (task: components['schemas']['TaskSnapshot']): BrowserTask => ({
  capturedAt: task.captured_at,
  completedAt: task.completed_at,
  deadlineOn: task.deadline_on,
  id: task.id,
  inboxState: task.inbox_state,
  notes: task.notes,
  plannedOn: task.planned_on,
  project: task.project == null ? null : { ...task.project },
  revision: task.revision,
  tags: task.tags?.map((tag) => ({ ...tag })) ?? [],
  title: task.title,
  trashedAt: task.trashed_at,
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

const mapTaskViewItem = (task: WireTaskViewItem): TaskViewItem => ({
  capturedAt: task.captured_at,
  ...(task.completed_at === undefined ? {} : { completedAt: task.completed_at }),
  ...(task.completed_on === undefined ? {} : { completedOn: task.completed_on }),
  deadlineOn: task.deadline_on,
  ...(task.group_on === undefined ? {} : { groupOn: task.group_on }),
  id: task.id,
  plannedOn: task.planned_on,
  reasons: task.reasons ?? [],
  revision: task.revision,
  ...(task.section === undefined ? {} : { section: task.section }),
  title: task.title,
  ...(task.upcoming_reason === undefined ? {} : { upcomingReason: task.upcoming_reason }),
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

const mapUndoAvailability = (undo: WireUndoAvailability): UndoAvailability => ({
  expiresAt: undo.expires_at,
  handle: undo.handle,
  label: undo.label,
})

const mapAcknowledgement = (acknowledgement: WireCommandAcknowledgement): CommandAcknowledgement => {
  const undo = acknowledgement.undo ? mapUndoAvailability(acknowledgement.undo) : null

  if (undo) {
    window.dispatchEvent(new CustomEvent<UndoAvailability>('keepling:undo-available', { detail: undo }))
  }

  return {
    mutationId: acknowledgement.mutation_id,
    outcome: acknowledgement.outcome,
    revision: acknowledgement.revision,
    resolvedConflictId: acknowledgement.resolved_conflict_id ?? null,
    snapshot: mapTask(acknowledgement.snapshot),
    taskId: acknowledgement.task_id,
    undo,
    warnings: acknowledgement.warnings.map((warning) => ({ ...warning })),
  }
}

const mapUndoNoChange = (result: WireUndoNoChange): UndoNoChange => ({
  code: result.code,
  mutationId: result.mutation_id,
  outcome: result.outcome,
  recoveryAction: result.recovery_action,
  retryable: result.retryable,
  title: result.title,
})

const mapUndoResult = (result: WireUndoResult): UndoResult =>
  'snapshot' in result
    ? { acknowledgement: mapAcknowledgement(result), kind: 'acknowledged' }
    : { kind: 'no-change', result: mapUndoNoChange(result) }

const mapRestoreAcknowledgement = (
  acknowledgement: WireRestoreAcknowledgement,
): RestoreAcknowledgement => ({
  ...mapAcknowledgement(acknowledgement),
  destinations: [...acknowledgement.destinations],
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

const getTask = async (taskId: string): Promise<BrowserTask> =>
  mapTask(
    await readJson<components['schemas']['TaskSnapshot']>(
      await fetch(`/api/v1/tasks/${encodeURIComponent(taskId)}`, {
        credentials: 'same-origin',
        headers: { accept: 'application/json' },
      }),
    ),
  )

const getTrash = async (): Promise<readonly BrowserTask[]> => {
  const response = await readJson<WireTrashResponse>(
    await fetch('/api/v1/trash', {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

  return response.tasks.map(mapTask)
}

const getTaskView = async (view: TaskViewName, cursor?: string): Promise<TaskViewPage> => {
  const query = new URLSearchParams({ limit: '20' })
  if (cursor !== undefined) query.set('cursor', cursor)
  const path = view === 'inbox' ? '/api/v1/views/inbox' : `/api/v1/${view}`
  const response = await readJson<WireTaskViewPage>(
    await fetch(`${path}?${query.toString()}`, {
      credentials: 'same-origin',
      headers: { accept: 'application/json' },
    }),
  )

  return {
    accountDay: response.account_day,
    accountTimezone: response.account_timezone,
    items: response.items.map(mapTaskViewItem),
    nextCursor: response.next_cursor,
    orderRevision: response.order_revision,
    view: response.view,
  }
}

const todayMoveRequest = (submission: TodayMoveSubmission): WireTodayMoveRequest => ({
    direction: submission.direction,
    expected_order_revision: submission.expectedOrderRevision,
    mutation_id: submission.mutationId,
    task_id: submission.taskId,
    version: 1,
  })

const prepareTodayMove = (submission: TodayMoveSubmission): PreparedTodayMove =>
  Object.freeze({
    body: JSON.stringify(todayMoveRequest(submission)),
    direction: submission.direction,
    expectedOrderRevision: submission.expectedOrderRevision,
    mutationId: submission.mutationId,
    path: '/api/v1/commands/move-today-task',
    taskId: submission.taskId,
  })

const mapTodayMoveAcknowledgement = (
  response: WireTodayMoveResponse,
): TodayMoveAcknowledgement => ({
  mutationId: response.mutation_id,
  orderRevision: response.order_revision,
  taskId: response.task_id,
})

const submitPreparedTodayMove = async (
  request: PreparedTodayMove,
  csrfToken: string,
): Promise<TodayMoveAcknowledgement> =>
  mapTodayMoveAcknowledgement(
    await readJson<WireTodayMoveResponse>(
      await fetch(request.path, {
        body: request.body,
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

const getTodayMoveMutation = async (
  mutationId: string,
): Promise<TodayMoveAcknowledgement> =>
  mapTodayMoveAcknowledgement(
    await readJson<WireTodayMoveResponse>(
      await fetch(`/api/v1/today/mutations/${encodeURIComponent(mutationId)}`, {
        credentials: 'same-origin',
        headers: { accept: 'application/json' },
      }),
    ),
  )

const moveTodayTask = async (
  submission: TodayMoveSubmission,
  csrfToken: string,
): Promise<TodayMoveAcknowledgement> =>
  submitPreparedTodayMove(prepareTodayMove(submission), csrfToken)

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

const prepareCaptureTask = (submission: CaptureTaskSubmission): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/capture-task',
    {
      mutation_id: submission.mutationId,
      task_id: submission.taskId,
      title: submission.title,
      version: 1,
    } satisfies WireCaptureTaskCommand,
    submission.mutationId,
    submission.taskId,
  )

const taskEditCommand = (submission: EditTaskSubmission): WireEditTaskCommand => ({
  base_values: submission.baseValues,
  expected_revision: submission.expectedRevision,
  fields: submission.fields,
  mutation_id: submission.mutationId,
  task_id: submission.taskId,
  version: 1,
})

const prepareTaskCommand = <RequestBody>(
  path: string,
  command: RequestBody,
  mutationId: string,
  taskId: string,
): PreparedTaskCommand =>
  Object.freeze({
    body: JSON.stringify(command),
    mutationId,
    path,
    taskId,
  })

const submitPreparedTaskCommand = async (
  request: PreparedTaskCommand,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  mapAcknowledgement(
    await readJson<WireCommandAcknowledgement>(
      await fetch(request.path, {
        body: request.body,
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
  submitPreparedTaskCommand(
    prepareTaskCommand(
      '/api/v1/commands/edit-task',
      taskEditCommand(submission),
      submission.mutationId,
      submission.taskId,
    ),
    csrfToken,
  )

const prepareEditTask = (submission: EditTaskSubmission): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/edit-task',
    taskEditCommand(submission),
    submission.mutationId,
    submission.taskId,
  )

const resolveTaskConflict = async (
  submission: ConflictResolutionSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> => {
  const command: WireResolveTaskConflictCommand = {
    conflict_id: submission.conflictId,
    latest_revision: submission.latestRevision,
    mutation_id: submission.mutationId,
    selections: submission.selections,
    task_id: submission.taskId,
    version: 1,
  }

  return submitTaskCommand(
    '/api/v1/commands/resolve-task-conflict',
    command,
    csrfToken,
  )
}

const prepareResolveTaskConflict = (
  submission: ConflictResolutionSubmission,
): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/resolve-task-conflict',
    {
      conflict_id: submission.conflictId,
      latest_revision: submission.latestRevision,
      mutation_id: submission.mutationId,
      selections: submission.selections,
      task_id: submission.taskId,
      version: 1,
    } satisfies WireResolveTaskConflictCommand,
    submission.mutationId,
    submission.taskId,
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

const prepareEditTaskDates = (submission: EditTaskDatesSubmission): PreparedTaskCommand => {
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

  return prepareTaskCommand(
    '/api/v1/commands/edit-task-dates',
    command,
    submission.mutationId,
    submission.taskId,
  )
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

const preparePlanForToday = (submission: PlanningSubmission): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/plan-for-today',
    planningCommand(submission),
    submission.mutationId,
    submission.taskId,
  )

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

const prepareClarifyTask = (submission: EditTaskSubmission): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/clarify-task',
    taskEditCommand(submission),
    submission.mutationId,
    submission.taskId,
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

const lifecycleCommand = (submission: LifecycleSubmission): WireTaskLifecycleCommand => ({
  expected_revision: submission.expectedRevision,
  mutation_id: submission.mutationId,
  task_id: submission.taskId,
  version: 1,
})

const prepareLifecycleTask = (
  action: 'complete' | 'reopen',
  submission: LifecycleSubmission,
): PreparedTaskCommand =>
  prepareTaskCommand(
    `/api/v1/commands/${action}-task`,
    lifecycleCommand(submission),
    submission.mutationId,
    submission.taskId,
  )

const completeTask = async (
  submission: LifecycleSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand('/api/v1/commands/complete-task', lifecycleCommand(submission), csrfToken)

const reopenTask = async (
  submission: LifecycleSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand('/api/v1/commands/reopen-task', lifecycleCommand(submission), csrfToken)

const trashTask = async (
  submission: LifecycleSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitTaskCommand('/api/v1/commands/trash-task', lifecycleCommand(submission), csrfToken)

const restoreTask = async (
  submission: LifecycleSubmission,
  csrfToken: string,
): Promise<RestoreAcknowledgement> =>
  mapRestoreAcknowledgement(
    await jsonRequest<WireTaskLifecycleCommand, WireRestoreAcknowledgement>(
      '/api/v1/commands/restore-task',
      'POST',
      lifecycleCommand(submission),
      csrfToken,
    ),
  )

const prepareRestoreTask = (submission: LifecycleSubmission): PreparedRestoreTask =>
  prepareTaskCommand(
    '/api/v1/commands/restore-task',
    lifecycleCommand(submission),
    submission.mutationId,
    submission.taskId,
  )

const submitPreparedRestoreTask = async (
  request: PreparedRestoreTask,
  csrfToken: string,
): Promise<RestoreAcknowledgement> =>
  mapRestoreAcknowledgement(
    await readJson<WireRestoreAcknowledgement>(
      await fetch(request.path, {
        body: request.body,
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

const undoTask = async (
  submission: UndoSubmission,
  csrfToken: string,
): Promise<UndoResult> => {
  const command: WireUndoTaskCommand = {
    handle: submission.availability.handle,
    mutation_id: submission.mutationId,
    version: 1,
  }

  const response = await fetch('/api/v1/commands/undo-task', {
    body: JSON.stringify(command),
    credentials: 'same-origin',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      'x-csrf-token': csrfToken,
    },
    method: 'POST',
  })
  const body = (await response.json()) as WireUndoResult | Problem

  if (!response.ok && !(response.status === 404 && 'outcome' in body)) {
    throw new KeeplingApiError(body as Problem)
  }

  return mapUndoResult(body as WireUndoResult)
}

const assignmentCommand = (
  submission: AssignTaskOrganizationsSubmission,
): WireAssignTaskOrganizationsCommand => ({
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
  })

const prepareAssignTaskOrganizations = (
  submission: AssignTaskOrganizationsSubmission,
): PreparedTaskCommand =>
  prepareTaskCommand(
    '/api/v1/commands/assign-task-organizations',
    assignmentCommand(submission),
    submission.mutationId,
    submission.taskId,
  )

const assignTaskOrganizations = async (
  submission: AssignTaskOrganizationsSubmission,
  csrfToken: string,
): Promise<CommandAcknowledgement> =>
  submitPreparedTaskCommand(prepareAssignTaskOrganizations(submission), csrfToken)

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

const getRestoreMutation = async (mutationId: string): Promise<RestoreAcknowledgement> =>
  mapRestoreAcknowledgement(
    await readJson<WireRestoreAcknowledgement>(
      await fetch(`/api/v1/mutations/${encodeURIComponent(mutationId)}`, {
        credentials: 'same-origin',
        headers: { accept: 'application/json' },
      }),
    ),
  )

const getOrganizationMutation = async (
  mutationId: string,
): Promise<OrganizationAcknowledgement> =>
  mapOrganizationAcknowledgement(
    await readJson<WireOrganizationAcknowledgement>(
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
  completeTask,
  completeSetup,
  createOrganization,
  editTaskDates,
  getInbox,
  getMutation,
  getRestoreMutation,
  getOrganizationMutation,
  getOrganizations,
  getSession,
  getTrash,
  getTaskActivity,
  getTask,
  getTaskView,
  getTodayMoveMutation,
  editTask,
  listDeviceGrants,
  listSessions,
  login,
  logout,
  reauthenticate,
  recoverAccount,
  resolveTaskConflict,
  renameOrganization,
  reopenTask,
  restoreTask,
  returnToInbox,
  revokeDeviceGrant,
  revokeSession,
  updateSession,
  unarchiveOrganization,
  unplanTask,
  trashTask,
  undoTask,
  planForToday,
  prepareClarifyTask,
  prepareCaptureTask,
  prepareAssignTaskOrganizations,
  prepareEditTask,
  prepareEditTaskDates,
  prepareLifecycleTask,
  preparePlanForToday,
  prepareResolveTaskConflict,
  prepareRestoreTask,
  prepareTodayMove,
  moveTodayTask,
  submitPreparedTodayMove,
  submitPreparedTaskCommand,
  submitPreparedRestoreTask,
  type AssignTaskOrganizationsSubmission,
  type ActivityChange,
  type AgentGrant,
  type AuthenticationTransition,
  type BrowserOrganization,
  type BrowserSession,
  type BrowserTask,
  type CaptureAcknowledgement,
  type CaptureTaskSubmission,
  type CaptureWarning,
  type CommandAcknowledgement,
  type ConflictResolutionSubmission,
  type CreateOrganizationSubmission,
  type EditTaskSubmission,
  type EditTaskDatesSubmission,
  type LifecycleSubmission,
  type PlanningSubmission,
  type PreparedTaskCommand,
  type PreparedRestoreTask,
  type Problem,
  type OrganizationAcknowledgement,
  type OrganizationAssignmentValues,
  type OrganizationLifecycleSubmission,
  type RenameOrganizationSubmission,
  type RestoreAcknowledgement,
  type ReturnToInboxSubmission,
  type TaskDetailValues,
  type TaskConflict,
  type TaskConflictField,
  type TaskDateValues,
  type TaskActivity,
  type TaskActivityPage,
  type TaskViewItem,
  type TaskViewName,
  type TaskViewPage,
  type UndoAvailability,
  type UndoNoChange,
  type UndoResult,
  type UndoSubmission,
  type TodayMoveSubmission,
  type TodayMoveAcknowledgement,
  type PreparedTodayMove,
  type TaskOrganizationReference,
}
