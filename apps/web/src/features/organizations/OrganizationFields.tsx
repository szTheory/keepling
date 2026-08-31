import { useEffect, useState, type FormEvent } from 'react'

import {
  KeeplingApiError,
  archiveOrganization,
  assignTaskOrganizations,
  createOrganization,
  getTask,
  getOrganizations,
  renameOrganization,
  unarchiveOrganization,
  type AssignTaskOrganizationsSubmission,
  type BrowserOrganization,
  type BrowserTask,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'

type OrganizationFieldsProps = {
  csrfToken: string
  taskId: string
}

type OrganizationManagerProps = {
  csrfToken: string
  kind: BrowserOrganization['kind']
}

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
  | { kind: 'unknown' }

const taskAssignment = (task: BrowserTask): AssignmentDraft => ({
  projectId: task.project?.id ?? null,
  tagIds: task.tags.map((tag) => tag.id).toSorted(),
})

function OrganizationFields({ csrfToken, taskId }: OrganizationFieldsProps) {
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' })
  const [draft, setDraft] = useState<AssignmentDraft>({ projectId: null, tagIds: [] })
  const [assignmentState, setAssignmentState] = useState<AssignmentState>({ kind: 'idle' })
  const [pendingSubmission, setPendingSubmission] =
    useState<AssignTaskOrganizationsSubmission | null>(null)

  useEffect(() => {
    let active = true

    void Promise.all([getTask(taskId), getOrganizations()])
      .then(([task, organizations]) => {
        if (!active) return
        setLoadState({ kind: 'ready', organizations, task })
        setDraft(taskAssignment(task))
      })
      .catch(() => {
        if (active) setLoadState({ kind: 'error' })
      })

    return () => {
      active = false
    }
  }, [taskId])

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

  const deliver = async (submission: AssignTaskOrganizationsSubmission) => {
    setPendingSubmission(submission)
    setAssignmentState({ kind: 'submitting' })

    try {
      const acknowledgement = await assignTaskOrganizations(submission, csrfToken)
      if (acknowledgement.mutationId !== submission.mutationId) {
        setAssignmentState({ kind: 'unknown' })
        return
      }

      setPendingSubmission(null)
      setLoadState((current) =>
        current.kind === 'ready'
          ? { ...current, task: acknowledgement.snapshot }
          : current,
      )
      setDraft(taskAssignment(acknowledgement.snapshot))
      setAssignmentState({ kind: 'saved' })
    } catch (error) {
      if (error instanceof KeeplingApiError && error.problem.code === 'task_assignment_conflict') {
        setPendingSubmission(null)
        setAssignmentState({ kind: 'conflict', message: error.message })
      } else if (error instanceof KeeplingApiError) {
        setPendingSubmission(null)
        setAssignmentState({ kind: 'problem', message: error.message })
      } else {
        setAssignmentState({ kind: 'unknown' })
      }
    }
  }

  const save = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!acceptedTask || assignmentState.kind === 'submitting') return

    const submission =
      pendingSubmission ??
      ({
        baseValues: taskAssignment(acceptedTask),
        expectedRevision: acceptedTask.revision,
        fields: { projectId: draft.projectId, tagIds: draft.tagIds.toSorted() },
        mutationId: crypto.randomUUID(),
        taskId: acceptedTask.id,
      } satisfies AssignTaskOrganizationsSubmission)

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
              disabled={assignmentState.kind === 'submitting'}
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
                      disabled={assignmentState.kind === 'submitting'}
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
          {assignmentState.kind === 'unknown' ? (
            <div className="rounded-lg border p-4" role="status">
              <p>Checking whether your change was saved…</p>
              <Button className="mt-3 min-h-11" onClick={() => pendingSubmission && void deliver(pendingSubmission)} type="button" variant="outline">
                Check again
              </Button>
            </div>
          ) : null}
          {assignmentState.kind === 'saved' ? <p role="status">Task assignments saved.</p> : null}

          <Button className="min-h-11" disabled={assignmentState.kind === 'submitting'} type="submit">
            {assignmentState.kind === 'submitting' ? 'Saving…' : 'Save assignments'}
          </Button>
        </form>
      </div>
    </main>
  )
}

function OrganizationManager({ csrfToken, kind }: OrganizationManagerProps) {
  const [organizations, setOrganizations] = useState<readonly BrowserOrganization[]>([])
  const [loading, setLoading] = useState(true)
  const [name, setName] = useState('')
  const [renames, setRenames] = useState<Record<string, string>>({})
  const [confirmArchiveId, setConfirmArchiveId] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [message, setMessage] = useState<{ kind: 'alert' | 'status'; text: string } | null>(null)

  useEffect(() => {
    let active = true
    void getOrganizations()
      .then((loaded) => {
        if (!active) return
        const relevant = loaded.filter((organization) => organization.kind === kind)
        setOrganizations(relevant)
        setRenames(Object.fromEntries(relevant.map((organization) => [organization.id, organization.name])))
        setLoading(false)
      })
      .catch(() => {
        if (!active) return
        setLoading(false)
        setMessage({ kind: 'alert', text: `Couldn’t load ${kind}s. Nothing was changed.` })
      })
    return () => {
      active = false
    }
  }, [kind])

  const replaceOrganization = (organization: BrowserOrganization) => {
    setOrganizations((current) =>
      current.some((candidate) => candidate.id === organization.id)
        ? current.map((candidate) => candidate.id === organization.id ? organization : candidate)
        : [...current, organization],
    )
    setRenames((current) => ({ ...current, [organization.id]: organization.name }))
  }

  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (name.trim() === '') return
    setBusyId('create')
    setMessage(null)
    try {
      const acknowledgement = await createOrganization(
        {
          kind,
          mutationId: crypto.randomUUID(),
          name,
          organizationId: crypto.randomUUID(),
        },
        csrfToken,
      )
      replaceOrganization(acknowledgement.snapshot)
      setName('')
      setMessage({ kind: 'status', text: `${kind === 'project' ? 'Project' : 'Tag'} created.` })
    } catch (error) {
      setMessage({
        kind: 'alert',
        text: error instanceof Error ? error.message : `Couldn’t create ${kind}. Nothing was changed.`,
      })
    } finally {
      setBusyId(null)
    }
  }

  const rename = async (organization: BrowserOrganization) => {
    setBusyId(organization.id)
    setMessage(null)
    try {
      const acknowledgement = await renameOrganization(
        {
          expectedRevision: organization.revision,
          mutationId: crypto.randomUUID(),
          name: renames[organization.id] ?? organization.name,
          organizationId: organization.id,
        },
        csrfToken,
      )
      replaceOrganization(acknowledgement.snapshot)
      setMessage({ kind: 'status', text: `${organization.name} renamed.` })
    } catch (error) {
      setMessage({ kind: 'alert', text: error instanceof Error ? error.message : 'Nothing changed.' })
    } finally {
      setBusyId(null)
    }
  }

  const archive = async (organization: BrowserOrganization) => {
    setBusyId(organization.id)
    setMessage(null)
    try {
      const acknowledgement = await archiveOrganization(
        {
          expectedRevision: organization.revision,
          mutationId: crypto.randomUUID(),
          organizationId: organization.id,
        },
        csrfToken,
      )
      replaceOrganization(acknowledgement.snapshot)
      setConfirmArchiveId(null)
      setMessage({ kind: 'status', text: `${organization.name} archived.` })
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'project_archive_blocked'
      ) {
        const count = error.problem.active_unfinished_task_count ?? 0
        setMessage({
          kind: 'alert',
          text: `${organization.name} still has ${String(count)} active unfinished ${count === 1 ? 'task' : 'tasks'}. Nothing changed.`,
        })
      } else {
        setMessage({ kind: 'alert', text: error instanceof Error ? error.message : 'Nothing changed.' })
      }
    } finally {
      setBusyId(null)
    }
  }

  const unarchive = async (organization: BrowserOrganization) => {
    setBusyId(organization.id)
    setMessage(null)
    try {
      const acknowledgement = await unarchiveOrganization(
        {
          expectedRevision: organization.revision,
          mutationId: crypto.randomUUID(),
          organizationId: organization.id,
        },
        csrfToken,
      )
      replaceOrganization(acknowledgement.snapshot)
      setMessage({ kind: 'status', text: `${organization.name} unarchived.` })
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'active_organization_name_collision'
      ) {
        setMessage({
          kind: 'alert',
          text: `${organization.name} remains archived because an active ${kind} already uses that name.`,
        })
      } else {
        setMessage({ kind: 'alert', text: error instanceof Error ? error.message : 'Nothing changed.' })
      }
    } finally {
      setBusyId(null)
    }
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
              id={`new-${label}-name`}
              maxLength={200}
              onChange={(event) => setName(event.target.value)}
              value={name}
            />
          </div>
          <Button className="min-h-11" disabled={busyId !== null || name.trim() === ''} type="submit">
            Create {label}
          </Button>
        </form>

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
                    disabled={busyId !== null}
                    onClick={() => void rename(organization)}
                    type="button"
                    variant="outline"
                  >
                    Save name
                  </Button>
                  {organization.archived ? (
                    <Button
                      className="min-h-11"
                      disabled={busyId !== null}
                      onClick={() => void unarchive(organization)}
                      type="button"
                      variant="outline"
                    >
                      Unarchive {organization.name}
                    </Button>
                  ) : (
                    <Button
                      className="min-h-11"
                      disabled={busyId !== null}
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
                        disabled={busyId !== null}
                        onClick={() => void archive(organization)}
                        type="button"
                        variant="destructive"
                      >
                        Confirm archive {organization.name}
                      </Button>
                      <Button className="min-h-11" onClick={() => setConfirmArchiveId(null)} type="button" variant="outline">
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
