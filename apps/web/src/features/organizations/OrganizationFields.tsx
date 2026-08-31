import { useEffect, useRef, useState, type FormEvent } from 'react'

import {
  KeeplingApiError,
  archiveOrganization,
  createOrganization,
  getOrganizationMutation,
  getTask,
  getOrganizations,
  renameOrganization,
  prepareAssignTaskOrganizations,
  unarchiveOrganization,
  type AssignTaskOrganizationsSubmission,
  type BrowserOrganization,
  type BrowserTask,
  type CreateOrganizationSubmission,
  type OrganizationAcknowledgement,
  type OrganizationLifecycleSubmission,
  type RenameOrganizationSubmission,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import {
  classifyKeeplingError,
  createExactSubmission,
  createTaskSubmission,
  type ExactSubmission,
  type ExactSubmissionState,
  type TaskSubmissionState,
} from '@/commands/submission'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'
import MutationRecoveryPanel from '@/features/recovery/MutationRecoveryPanel'

type OrganizationFieldsProps = {
  csrfToken: string
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  taskId: string
}

type OrganizationManagerProps = {
  csrfToken: string
  kind: BrowserOrganization['kind']
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
}

type OrganizationAction =
  | {
      displayName: string
      kind: BrowserOrganization['kind']
      submission: CreateOrganizationSubmission
      type: 'create'
    }
  | {
      displayName: string
      kind: BrowserOrganization['kind']
      submission: RenameOrganizationSubmission
      type: 'rename'
    }
  | {
      displayName: string
      kind: BrowserOrganization['kind']
      submission: OrganizationLifecycleSubmission
      type: 'archive' | 'unarchive'
    }

type OrganizationSubmissionState = ExactSubmissionState<
  OrganizationAction,
  OrganizationAcknowledgement,
  KeeplingApiError
>

type OrganizationExactSubmission = ExactSubmission<
  OrganizationAction,
  OrganizationAcknowledgement,
  KeeplingApiError
>

type AssignmentDraft = {
  projectId: string | null
  tagIds: readonly string[]
}

type LoadState =
  | { kind: 'error' }
  | { kind: 'loading' }
  | { kind: 'ready'; organizations: readonly BrowserOrganization[]; task: BrowserTask }

type AssignmentState =
  | { kind: 'conflict'; message: string }
  | { kind: 'idle' }
  | { kind: 'problem'; message: string }
  | { kind: 'saved' }
  | { kind: 'submitting' }
  | { kind: 'recovering' }

const authenticationFor = (error: unknown) => {
  if (!(error instanceof KeeplingApiError)) return null
  if (error.problem.code === 'authentication_required') return 'sign_in' as const
  if (error.problem.code === 'recent_authentication_required') return 'reauthenticate' as const
  return null
}

const taskAssignment = (task: BrowserTask): AssignmentDraft => ({
  projectId: task.project?.id ?? null,
  tagIds: task.tags.map((tag) => tag.id).toSorted(),
})

const actionIdentity = (action: OrganizationAction) => ({
  mutationId: action.submission.mutationId,
  organizationId: action.submission.organizationId,
})

const submitOrganizationAction = (
  action: OrganizationAction,
  csrfToken: string,
): Promise<OrganizationAcknowledgement> => {
  switch (action.type) {
    case 'create':
      return createOrganization(action.submission, csrfToken)
    case 'rename':
      return renameOrganization(action.submission, csrfToken)
    case 'archive':
      return archiveOrganization(action.submission, csrfToken)
    case 'unarchive':
      return unarchiveOrganization(action.submission, csrfToken)
  }
}

function OrganizationFields({
  csrfToken,
  onAuthenticationRequired,
  taskId,
}: OrganizationFieldsProps) {
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' })
  const [draft, setDraft] = useState<AssignmentDraft>({ projectId: null, tagIds: [] })
  const [assignmentState, setAssignmentState] = useState<AssignmentState>({ kind: 'idle' })
  const [recoveryState, setRecoveryState] = useState<TaskSubmissionState | null>(null)
  const exactSubmission = useRef<ReturnType<typeof createTaskSubmission> | null>(null)

  useEffect(() => {
    let active = true

    const load = async (allowAuthenticationRecovery: boolean) => {
      try {
        const [task, organizations] = await Promise.all([getTask(taskId), getOrganizations()])
        if (!active) return
        setLoadState({ kind: 'ready', organizations, task })
        setDraft(taskAssignment(task))
      } catch (error) {
        if (!active) return
        const authentication = authenticationFor(error)
        if (allowAuthenticationRecovery && authentication && onAuthenticationRequired) {
          onAuthenticationRequired(
            {
              authentication,
              kind: 'read',
              mutationId: `read:task-organizations:${taskId}`,
            },
            async () => {
              await load(false)
            },
          )
          return
        }
        setLoadState({ kind: 'error' })
        if (!allowAuthenticationRecovery) throw error
      }
    }

    void load(true)

    return () => {
      active = false
    }
  }, [onAuthenticationRequired, taskId])

  const acceptedTask = loadState.kind === 'ready' ? loadState.task : null
  const organizations = loadState.kind === 'ready' ? loadState.organizations : []
  const projects = organizations.filter(
    (organization) =>
      organization.kind === 'project' &&
      (organization.assignable || organization.id === acceptedTask?.project?.id),
  )
  const tags = organizations.filter(
    (organization) =>
      organization.kind === 'tag' &&
      (organization.assignable || acceptedTask?.tags.some((tag) => tag.id === organization.id)),
  )

  const settle = async (exact: ReturnType<typeof createTaskSubmission>) => {
    const state = exact.snapshot

    if (state.kind === 'acknowledged') {
      exactSubmission.current = null
      setRecoveryState(null)
      setLoadState((current) =>
        current.kind === 'ready'
          ? { ...current, task: state.acknowledgement.snapshot }
          : current,
      )
      setDraft(taskAssignment(state.acknowledgement.snapshot))
      setAssignmentState({ kind: 'saved' })
      return
    }

    if (state.kind === 'unknown' || state.kind === 'authentication_required') {
      setAssignmentState({ kind: 'recovering' })
      return
    }

    if (state.kind !== 'conflict' && state.kind !== 'rejected') return
    exactSubmission.current = null
    setRecoveryState(null)
    setAssignmentState(
      state.rejection.problem.code === 'task_assignment_conflict'
        ? { kind: 'conflict', message: state.rejection.message }
        : { kind: 'problem', message: state.rejection.message },
    )
  }

  const deliver = async (
    submission: AssignTaskOrganizationsSubmission,
    activeCsrfToken = csrfToken,
  ) => {
    const exact = createTaskSubmission(
      prepareAssignTaskOrganizations(submission),
      setRecoveryState,
    )
    exactSubmission.current = exact
    setAssignmentState({ kind: 'submitting' })
    await exact.submit(activeCsrfToken)
    await settle(exact)
  }

  const checkPending = async () => {
    const exact = exactSubmission.current
    if (!exact) return
    setAssignmentState({ kind: 'submitting' })
    await exact.check(csrfToken)
    await settle(exact)
  }

  const requestAuthentication = () => {
    const exact = exactSubmission.current
    if (
      !exact ||
      exact.snapshot.kind !== 'authentication_required' ||
      !onAuthenticationRequired
    ) {
      return
    }
    const { authentication, operation, request } = exact.snapshot
    onAuthenticationRequired(
      {
        authentication,
        kind: operation === 'lookup' ? 'submitted-unknown' : 'not-submitted',
        mutationId: request.mutationId,
      },
      async (nextCsrfToken) => {
        setAssignmentState({ kind: 'submitting' })
        await exact.resumeAfterAuthentication(nextCsrfToken)
        await settle(exact)
      },
    )
  }

  const save = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!acceptedTask || exactSubmission.current || assignmentState.kind === 'submitting') return

    const submission = {
        baseValues: taskAssignment(acceptedTask),
        expectedRevision: acceptedTask.revision,
        fields: { projectId: draft.projectId, tagIds: draft.tagIds.toSorted() },
        mutationId: crypto.randomUUID(),
        taskId: acceptedTask.id,
      } satisfies AssignTaskOrganizationsSubmission

    void deliver(submission)
  }

  const toggleTag = (tagId: string, selected: boolean) => {
    setDraft((current) => ({
      ...current,
      tagIds: selected
        ? [...current.tagIds, tagId].toSorted()
        : current.tagIds.filter((candidate) => candidate !== tagId),
    }))
  }

  if (loadState.kind === 'loading') {
    return (
      <main className="p-6" id="main-content">
        <p role="status">Loading project and tags…</p>
      </main>
    )
  }

  if (loadState.kind === 'error') {
    return (
      <main className="p-6" id="main-content">
        <p role="alert">Couldn’t load project and tags. Your task wasn’t changed.</p>
      </main>
    )
  }

  return (
    <main className="min-h-screen bg-card px-4 py-8 sm:px-6" id="main-content">
      <div className="mx-auto max-w-3xl">
        <a className="font-semibold text-primary underline" href={`/tasks/${encodeURIComponent(taskId)}`}>
          Back to task
        </a>
        <h1 className="mt-4 text-[1.75rem] font-semibold">Project and tags</h1>
        <p className="mt-2 text-muted-foreground">
          Assign one project and any number of flat tags. Archived assignments stay named.
        </p>

        <form className="mt-8 space-y-8" onSubmit={save}>
          <div className="space-y-2">
            <label className="block text-sm font-semibold" htmlFor="task-project">
              Project
            </label>
            <select
              className="min-h-11 w-full rounded-lg border border-input bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              disabled={assignmentState.kind === 'submitting' || assignmentState.kind === 'recovering'}
              id="task-project"
              onChange={(event) =>
                setDraft((current) => ({ ...current, projectId: event.target.value || null }))
              }
              value={draft.projectId ?? ''}
            >
              <option value="">No project</option>
              {projects.map((project) => (
                <option key={project.id} value={project.id}>
                  {project.name}{project.archived ? ' — Archived' : ''}
                </option>
              ))}
            </select>
          </div>

          <fieldset className="space-y-3">
            <legend className="text-sm font-semibold">Tags</legend>
            {tags.length === 0 ? (
              <p className="text-muted-foreground">No tags are available.</p>
            ) : (
              tags.map((tag) => {
                const selected = draft.tagIds.includes(tag.id)
                return (
                  <label className="flex min-h-11 items-center gap-3" key={tag.id}>
                    <input
                      aria-label={`${tag.name}${tag.archived ? ' — Archived' : ''}`}
                      checked={selected}
                      className="size-5 accent-primary focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                      disabled={assignmentState.kind === 'submitting' || assignmentState.kind === 'recovering'}
                      onChange={(event) => toggleTag(tag.id, event.target.checked)}
                      type="checkbox"
                    />
                    <span>{tag.name}</span>
                    {tag.archived ? (
                      <span className="text-sm font-semibold text-muted-foreground" data-organization-status>
                        Archived
                      </span>
                    ) : null}
                  </label>
                )
              })
            )}
          </fieldset>

          {assignmentState.kind === 'conflict' || assignmentState.kind === 'problem' ? (
            <p className="rounded-lg border border-destructive p-4" role="alert">
              {assignmentState.message}
            </p>
          ) : null}
          <MutationRecoveryPanel
            onCheck={() => void checkPending()}
            onSignIn={requestAuthentication}
            state={recoveryState}
          />
          {assignmentState.kind === 'saved' ? <p role="status">Task assignments saved.</p> : null}

          <Button className="min-h-11" disabled={assignmentState.kind === 'submitting' || assignmentState.kind === 'recovering'} type="submit">
            {assignmentState.kind === 'submitting' ? 'Saving…' : 'Save assignments'}
          </Button>
        </form>
      </div>
    </main>
  )
}

function OrganizationManager({
  csrfToken,
  kind,
  onAuthenticationRequired,
}: OrganizationManagerProps) {
  const [organizations, setOrganizations] = useState<readonly BrowserOrganization[]>([])
  const [loading, setLoading] = useState(true)
  const [name, setName] = useState('')
  const [renames, setRenames] = useState<Record<string, string>>({})
  const [confirmArchiveId, setConfirmArchiveId] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [message, setMessage] = useState<{ kind: 'alert' | 'status'; text: string } | null>(null)
  const [pendingAction, setPendingAction] = useState<OrganizationAction | null>(null)
  const [submissionState, setSubmissionState] =
    useState<OrganizationSubmissionState | null>(null)
  const exactSubmission = useRef<OrganizationExactSubmission | null>(null)

  useEffect(() => {
    let active = true

    const load = async (allowAuthenticationRecovery: boolean) => {
      try {
        const loaded = await getOrganizations()
        if (!active) return
        const relevant = loaded.filter((organization) => organization.kind === kind)
        setOrganizations(relevant)
        setRenames(Object.fromEntries(relevant.map((organization) => [organization.id, organization.name])))
        setLoading(false)
      } catch (error) {
        if (!active) return
        const authentication = authenticationFor(error)
        if (allowAuthenticationRecovery && authentication && onAuthenticationRequired) {
          onAuthenticationRequired(
            {
              authentication,
              kind: 'read',
              mutationId: `read:organizations:${kind}`,
            },
            async () => {
              await load(false)
            },
          )
          return
        }
        setLoading(false)
        setMessage({ kind: 'alert', text: `Couldn’t load ${kind}s. Nothing was changed.` })
        if (!allowAuthenticationRecovery) throw error
      }
    }

    void load(true)
    return () => {
      active = false
    }
  }, [kind, onAuthenticationRequired])

  const replaceOrganization = (organization: BrowserOrganization) => {
    setOrganizations((current) =>
      current.some((candidate) => candidate.id === organization.id)
        ? current.map((candidate) => candidate.id === organization.id ? organization : candidate)
        : [...current, organization],
    )
    setRenames((current) => ({ ...current, [organization.id]: organization.name }))
  }

  const clearPending = () => {
    exactSubmission.current = null
    setPendingAction(null)
    setSubmissionState(null)
    setBusyId(null)
  }

  const settle = async (action: OrganizationAction, exact: OrganizationExactSubmission) => {
    const state = exact.snapshot

    if (state.kind === 'acknowledged') {
      replaceOrganization(state.acknowledgement.snapshot)
      if (action.type === 'create') setName('')
      if (action.type === 'archive') setConfirmArchiveId(null)

      const actionCopy =
        action.type === 'create'
          ? `${action.kind === 'project' ? 'Project' : 'Tag'} created.`
          : `${action.displayName} ${action.type === 'rename' ? 'renamed' : `${action.type}d`}.`

      clearPending()
      setMessage({ kind: 'status', text: actionCopy })
      return
    }

    if (state.kind === 'authentication_required') {
      setBusyId(null)
      if (onAuthenticationRequired) {
        onAuthenticationRequired(
          {
            authentication: state.authentication,
            kind: state.operation === 'lookup' ? 'submitted-unknown' : 'not-submitted',
            mutationId: action.submission.mutationId,
          },
          async (nextCsrfToken) => {
            setBusyId(action.type === 'create' ? 'create' : action.submission.organizationId)
            await exact.resumeAfterAuthentication(nextCsrfToken)
            await settle(action, exact)
          },
        )
      }
      return
    }

    if (state.kind === 'unknown') {
      setBusyId(null)
      return
    }

    if (state.kind !== 'rejected' && state.kind !== 'conflict') return

    const error = state.rejection
    clearPending()

    if (action.type === 'archive' && error.problem.code === 'project_archive_blocked') {
      const count = error.problem.active_unfinished_task_count ?? 0
      setMessage({
        kind: 'alert',
        text: `${action.displayName} still has ${String(count)} active unfinished ${count === 1 ? 'task' : 'tasks'}. Nothing changed.`,
      })
    } else if (
      action.type === 'unarchive' &&
      error.problem.code === 'active_organization_name_collision'
    ) {
      setMessage({
        kind: 'alert',
        text: `${action.displayName} remains archived because an active ${action.kind} already uses that name.`,
      })
    } else {
      setMessage({ kind: 'alert', text: error.message })
    }
  }

  const begin = async (action: OrganizationAction) => {
    const identity = actionIdentity(action)
    setPendingAction(action)
    setBusyId(action.type === 'create' ? 'create' : identity.organizationId)
    setMessage(null)

    const exact = createExactSubmission<
      OrganizationAction,
      OrganizationAcknowledgement,
      KeeplingApiError
    >({
      classifyError: classifyKeeplingError,
      lookup: (original) => getOrganizationMutation(original.submission.mutationId),
      matchesAcknowledgement: (acknowledgement) =>
        acknowledgement.mutationId === identity.mutationId &&
        acknowledgement.organizationId === identity.organizationId,
      onStateChange: setSubmissionState,
      request: action,
      send: submitOrganizationAction,
    })

    exactSubmission.current = exact
    await exact.submit(csrfToken)
    await settle(action, exact)
  }

  const checkPending = async () => {
    const exact = exactSubmission.current
    if (!exact || !pendingAction) return

    setBusyId(
      pendingAction.type === 'create' ? 'create' : pendingAction.submission.organizationId,
    )
    await exact.check(csrfToken)
    await settle(pendingAction, exact)
  }

  const create = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (name.trim() === '' || pendingAction) return

    void begin({
      displayName: name,
      kind,
      submission: {
        kind,
        mutationId: crypto.randomUUID(),
        name,
        organizationId: crypto.randomUUID(),
      },
      type: 'create',
    })
  }

  const rename = (organization: BrowserOrganization) => {
    if (pendingAction) return
    void begin({
      displayName: organization.name,
      kind: organization.kind,
      submission: {
        expectedRevision: organization.revision,
        mutationId: crypto.randomUUID(),
        name: renames[organization.id] ?? organization.name,
        organizationId: organization.id,
      },
      type: 'rename',
    })
  }

  const archive = (organization: BrowserOrganization) => {
    if (pendingAction) return
    void begin({
      displayName: organization.name,
      kind: organization.kind,
      submission: {
        expectedRevision: organization.revision,
        mutationId: crypto.randomUUID(),
        organizationId: organization.id,
      },
      type: 'archive',
    })
  }

  const unarchive = (organization: BrowserOrganization) => {
    if (pendingAction) return
    void begin({
      displayName: organization.name,
      kind: organization.kind,
      submission: {
        expectedRevision: organization.revision,
        mutationId: crypto.randomUUID(),
        organizationId: organization.id,
      },
      type: 'unarchive',
    })
  }

  const label = kind === 'project' ? 'project' : 'tag'
  const title = kind === 'project' ? 'Projects' : 'Tags'

  return (
    <main className="min-h-screen bg-background px-4 py-8 sm:px-6" id="main-content">
      <div className="mx-auto max-w-3xl">
        <h1 className="text-[1.75rem] font-semibold">{title}</h1>
        <p className="mt-2 text-muted-foreground">
          Names are labels. Keepling keeps assignments attached to stable identities.
        </p>

        <form className="mt-8 flex flex-wrap items-end gap-3" onSubmit={create}>
          <div className="min-w-64 flex-1 space-y-2">
            <label className="block text-sm font-semibold" htmlFor={`new-${label}-name`}>
              New {label} name
            </label>
            <input
              className="min-h-11 w-full rounded-lg border border-input bg-card px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              disabled={pendingAction !== null}
              id={`new-${label}-name`}
              maxLength={200}
              onChange={(event) => setName(event.target.value)}
              value={name}
            />
          </div>
          <Button
            className="min-h-11"
            disabled={pendingAction !== null || busyId !== null || name.trim() === ''}
            type="submit"
          >
            Create {label}
          </Button>
        </form>

        {submissionState?.kind === 'unknown' ? (
          <div className="mt-6 rounded-lg border p-4" role="status">
            <p>Checking whether the organization change was saved…</p>
            <Button
              className="mt-3 min-h-11"
              onClick={() => void checkPending()}
              type="button"
              variant="outline"
            >
              Check again
            </Button>
          </div>
        ) : null}

        {submissionState?.kind === 'authentication_required' ? (
          <p className="mt-6 rounded-lg border p-4" role="status">
            Sign in again. Keepling will check whether the organization change was saved.
          </p>
        ) : null}

        {message ? (
          <p className="mt-6 rounded-lg border p-4" role={message.kind}>
            {message.text}
          </p>
        ) : null}

        {loading ? <p className="mt-8" role="status">Loading {label}s…</p> : null}
        {!loading ? (
          <ul className="mt-8 divide-y divide-border">
            {organizations.map((organization) => (
              <li className="py-5" key={organization.id}>
                <div className="flex flex-wrap items-center gap-3">
                  <label className="sr-only" htmlFor={`rename-${organization.id}`}>
                    Rename {organization.name}
                  </label>
                  <input
                    className="min-h-11 min-w-56 flex-1 rounded-lg border border-input bg-card px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                    disabled={pendingAction !== null}
                    id={`rename-${organization.id}`}
                    maxLength={200}
                    onChange={(event) =>
                      setRenames((current) => ({
                        ...current,
                        [organization.id]: event.target.value,
                      }))
                    }
                    value={renames[organization.id] ?? organization.name}
                  />
                  {organization.archived ? (
                    <span className="text-sm font-semibold text-muted-foreground">Archived</span>
                  ) : null}
                  <Button
                    className="min-h-11"
                    disabled={pendingAction !== null || busyId !== null}
                    onClick={() => void rename(organization)}
                    type="button"
                    variant="outline"
                  >
                    Save name
                  </Button>
                  {organization.archived ? (
                    <Button
                      className="min-h-11"
                      disabled={pendingAction !== null || busyId !== null}
                      onClick={() => void unarchive(organization)}
                      type="button"
                      variant="outline"
                    >
                      Unarchive {organization.name}
                    </Button>
                  ) : (
                    <Button
                      className="min-h-11"
                      disabled={pendingAction !== null || busyId !== null}
                      onClick={() => setConfirmArchiveId(organization.id)}
                      type="button"
                      variant="outline"
                    >
                      Archive {organization.name}
                    </Button>
                  )}
                </div>

                {confirmArchiveId === organization.id ? (
                  <div className="mt-4 rounded-lg border p-4">
                    <p>Archive {organization.name}? It won’t appear in new assignments.</p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Existing assignments remain visible.
                    </p>
                    <div className="mt-3 flex flex-wrap gap-3">
                      <Button
                        className="min-h-11"
                        disabled={pendingAction !== null || busyId !== null}
                        onClick={() => void archive(organization)}
                        type="button"
                        variant="destructive"
                      >
                        Confirm archive {organization.name}
                      </Button>
                      <Button
                        className="min-h-11"
                        disabled={pendingAction !== null}
                        onClick={() => setConfirmArchiveId(null)}
                        type="button"
                        variant="outline"
                      >
                        Keep active
                      </Button>
                    </div>
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        ) : null}
      </div>
    </main>
  )
}

export { OrganizationManager }
export default OrganizationFields
