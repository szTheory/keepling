import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from 'react'

import {
  KeeplingApiError,
  clarifyTask,
  editTask,
  editTaskDates,
  getInbox,
  getMutation,
  getTaskActivity,
  type BrowserTask,
  type CommandAcknowledgement,
  type EditTaskSubmission,
  type EditTaskDatesSubmission,
  type TaskDateValues,
  type TaskDetailValues,
} from '@/api/keepling'
import { Button } from '@/components/ui/button'
import type { InterruptedIntent } from '@/features/auth/Reauthenticate'

type TaskEditorProps = {
  csrfToken: string
  onAcknowledged?: (acknowledgement: CommandAcknowledgement) => void
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onNavigate?: (pathname: string) => void
  taskId: string
}

type Draft = Pick<BrowserTask, 'notes' | 'title'> & {
  deadlineOn: string
  plannedOn: string
}
type LoadState =
  | { kind: 'error' }
  | { kind: 'loading' }
  | { accountTimezone: string; kind: 'ready'; task: BrowserTask }

type Submission = {
  action: 'clarify' | 'edit'
  command: EditTaskSubmission | EditTaskDatesSubmission
  commandKind: 'dates' | 'details'
  datesAfter?: Pick<EditTaskDatesSubmission, 'baseValues' | 'fields'>
  navigateAfter?: string
}

type CommandState =
  | { kind: 'authentication-required' }
  | { kind: 'conflict'; message: string }
  | { kind: 'idle' }
  | { kind: 'problem'; message: string }
  | { kind: 'saved'; message: string }
  | { kind: 'submitting' }
  | { kind: 'unknown' }

type FieldErrors = Partial<Record<keyof Draft, string>>

const defaultNavigate = (pathname: string) => {
  window.history.pushState({}, '', pathname)
  window.dispatchEvent(new PopStateEvent('popstate'))
}

function TaskEditor({
  csrfToken,
  onAcknowledged = () => undefined,
  onAuthenticationRequired,
  onNavigate = defaultNavigate,
  taskId,
}: TaskEditorProps) {
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' })
  const [draft, setDraft] = useState<Draft>({
    deadlineOn: '',
    notes: '',
    plannedOn: '',
    title: '',
  })
  const [commandState, setCommandState] = useState<CommandState>({ kind: 'idle' })
  const [submission, setSubmission] = useState<Submission | null>(null)
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({})
  const [pendingNavigation, setPendingNavigation] = useState<string | null>(null)
  const titleRef = useRef<HTMLInputElement>(null)
  const notesRef = useRef<HTMLTextAreaElement>(null)
  const plannedOnRef = useRef<HTMLInputElement>(null)
  const deadlineOnRef = useRef<HTMLInputElement>(null)
  const stayRef = useRef<HTMLButtonElement>(null)
  const currentPath = useRef(`${window.location.pathname}${window.location.search}`)
  const allowNavigation = useRef(false)

  useEffect(() => {
    let active = true

    void Promise.all([getInbox(), getTaskActivity(taskId)])
      .then(([tasks, activity]) => {
        if (!active) return
        const task = tasks.find((candidate) => candidate.id === taskId)
        if (!task) {
          setLoadState({ kind: 'error' })
          return
        }
        setLoadState({ accountTimezone: activity.accountTimezone, kind: 'ready', task })
        setDraft({
          deadlineOn: task.deadlineOn ?? '',
          notes: task.notes,
          plannedOn: task.plannedOn ?? '',
          title: task.title,
        })
      })
      .catch(() => {
        if (active) setLoadState({ kind: 'error' })
      })

    return () => {
      active = false
    }
  }, [taskId])

  const acceptedTask = loadState.kind === 'ready' ? loadState.task : null
  const dirty =
    acceptedTask !== null &&
    (draft.deadlineOn !== (acceptedTask.deadlineOn ?? '') ||
      draft.notes !== acceptedTask.notes ||
      draft.plannedOn !== (acceptedTask.plannedOn ?? '') ||
      draft.title !== acceptedTask.title)
  const locked = submission !== null

  useEffect(() => {
    if (!dirty) return

    const guard = (event: BeforeUnloadEvent) => {
      event.preventDefault()
      event.returnValue = ''
    }

    window.addEventListener('beforeunload', guard)
    return () => window.removeEventListener('beforeunload', guard)
  }, [dirty])

  useEffect(() => {
    if (!dirty) return

    const guardBack = () => {
      if (allowNavigation.current) {
        allowNavigation.current = false
        return
      }
      const destination = `${window.location.pathname}${window.location.search}`
      window.history.pushState({}, '', currentPath.current)
      setPendingNavigation(destination)
    }

    window.addEventListener('popstate', guardBack)
    return () => window.removeEventListener('popstate', guardBack)
  }, [dirty])

  useEffect(() => {
    if (!dirty) return

    const guardLink = (event: MouseEvent) => {
      const target = event.target
      if (!(target instanceof Element)) return
      const anchor = target.closest('a[href]')
      if (!(anchor instanceof HTMLAnchorElement)) return
      const destination = new URL(anchor.href, window.location.href)
      if (destination.origin !== window.location.origin) return
      event.preventDefault()
      setPendingNavigation(`${destination.pathname}${destination.search}`)
    }

    document.addEventListener('click', guardLink, true)
    return () => document.removeEventListener('click', guardLink, true)
  }, [dirty])

  useEffect(() => {
    if (!pendingNavigation) return
    stayRef.current?.focus()
  }, [pendingNavigation])

  const changedValues = useMemo(() => {
    if (!acceptedTask) return { baseValues: {}, fields: {} }
    const baseValues: TaskDetailValues = {}
    const fields: TaskDetailValues = {}

    if (draft.title !== acceptedTask.title) {
      baseValues.title = acceptedTask.title
      fields.title = draft.title
    }
    if (draft.notes !== acceptedTask.notes) {
      baseValues.notes = acceptedTask.notes
      fields.notes = draft.notes
    }

    return { baseValues, fields }
  }, [acceptedTask, draft])

  const changedDateValues = useMemo(() => {
    if (!acceptedTask) return { baseValues: {}, fields: {} }
    const baseValues: TaskDateValues = {}
    const fields: TaskDateValues = {}

    if (draft.plannedOn !== (acceptedTask.plannedOn ?? '')) {
      baseValues.plannedOn = acceptedTask.plannedOn
      fields.plannedOn = draft.plannedOn === '' ? null : draft.plannedOn
    }
    if (draft.deadlineOn !== (acceptedTask.deadlineOn ?? '')) {
      baseValues.deadlineOn = acceptedTask.deadlineOn
      fields.deadlineOn = draft.deadlineOn === '' ? null : draft.deadlineOn
    }

    return { baseValues, fields }
  }, [acceptedTask, draft.deadlineOn, draft.plannedOn])

  const validCivilDate = (value: string) => {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
    if (!match) return false
    const year = Number(match[1])
    const month = Number(match[2])
    const day = Number(match[3])
    const date = new Date(Date.UTC(year, month - 1, day))
    return (
      date.getUTCFullYear() === year &&
      date.getUTCMonth() === month - 1 &&
      date.getUTCDate() === day
    )
  }

  const validate = () => {
    const errors: FieldErrors = {}
    const titleLength = [...draft.title.trim()].length
    const notesLength = [...draft.notes].length

    if (titleLength === 0) errors.title = 'Enter a task title.'
    else if (titleLength > 512) errors.title = 'Shorten the title to 512 characters or fewer.'
    if (notesLength > 50_000) errors.notes = 'Shorten the notes to 50000 characters or fewer.'
    if (draft.plannedOn !== '' && !validCivilDate(draft.plannedOn)) {
      errors.plannedOn = 'Enter a valid planned date in YYYY-MM-DD format.'
    }
    if (draft.deadlineOn !== '' && !validCivilDate(draft.deadlineOn)) {
      errors.deadlineOn = 'Enter a valid deadline in YYYY-MM-DD format.'
    }

    setFieldErrors(errors)
    const first = errors.title
      ? titleRef.current
      : errors.notes
        ? notesRef.current
        : errors.plannedOn
          ? plannedOnRef.current
          : errors.deadlineOn
            ? deadlineOnRef.current
            : null
    first?.focus()
    return Object.keys(errors).length === 0
  }

  const reconcile = async (
    acknowledgement: CommandAcknowledgement,
    current: Submission,
    activeCsrfToken: string,
  ) => {
    if (acknowledgement.mutationId !== current.command.mutationId) {
      setCommandState({ kind: 'unknown' })
      return
    }

    if (current.commandKind === 'details' && current.datesAfter) {
      setLoadState((state) => ({
        accountTimezone: state.kind === 'ready' ? state.accountTimezone : 'UTC',
        kind: 'ready',
        task: acknowledgement.snapshot,
      }))
      const next: Submission = {
        action: current.action,
        command: {
          ...current.datesAfter,
          expectedRevision: acknowledgement.revision,
          mutationId: crypto.randomUUID(),
          taskId: acknowledgement.taskId,
        },
        commandKind: 'dates',
        navigateAfter: current.navigateAfter,
      }
      await deliver(next, activeCsrfToken)
      return
    }

    setSubmission(null)
    setFieldErrors({})
    setLoadState((state) => ({
      accountTimezone: state.kind === 'ready' ? state.accountTimezone : 'UTC',
      kind: 'ready',
      task: acknowledgement.snapshot,
    }))
    setDraft({
      deadlineOn: acknowledgement.snapshot.deadlineOn ?? '',
      notes: acknowledgement.snapshot.notes,
      plannedOn: acknowledgement.snapshot.plannedOn ?? '',
      title: acknowledgement.snapshot.title,
    })
    onAcknowledged(acknowledgement)
    setCommandState({
      kind: 'saved',
      message: current.action === 'clarify' ? 'Task moved out of Inbox.' : 'Task saved.',
    })
    if (current.navigateAfter) {
      allowNavigation.current = true
      onNavigate(current.navigateAfter)
    }
  }

  const deliver = async (current: Submission, activeCsrfToken = csrfToken) => {
    setSubmission(current)
    setCommandState({ kind: 'submitting' })

    try {
      let acknowledgement: CommandAcknowledgement
      if (current.commandKind === 'dates') {
        acknowledgement = await editTaskDates(
          current.command as EditTaskDatesSubmission,
          activeCsrfToken,
        )
      } else {
        acknowledgement =
          current.action === 'clarify'
            ? await clarifyTask(current.command as EditTaskSubmission, activeCsrfToken)
            : await editTask(current.command as EditTaskSubmission, activeCsrfToken)
      }
      await reconcile(acknowledgement, current, activeCsrfToken)
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        setCommandState({ kind: 'authentication-required' })
        onAuthenticationRequired(
          { kind: 'not-submitted', mutationId: current.command.mutationId },
          (nextCsrfToken) => deliver(current, nextCsrfToken),
        )
      } else if (error instanceof KeeplingApiError && error.problem.code === 'task_edit_conflict') {
        setSubmission(null)
        setCommandState({ kind: 'conflict', message: error.message })
      } else if (error instanceof KeeplingApiError) {
        setSubmission(null)
        const errors: FieldErrors = {}
        if (error.problem.code === 'title_required' || error.problem.code === 'title_too_long') {
          errors.title = error.message
        }
        if (error.problem.code === 'notes_too_long') errors.notes = error.message
        setFieldErrors(errors)
        if (errors.title) titleRef.current?.focus()
        else if (errors.notes) notesRef.current?.focus()
        setCommandState({ kind: 'problem', message: error.message })
      } else {
        setCommandState({ kind: 'unknown' })
      }
    }
  }

  const checkSubmission = async (current: Submission, _activeCsrfToken = csrfToken) => {
    setCommandState({ kind: 'submitting' })

    try {
      await reconcile(
        await getMutation(current.command.mutationId),
        current,
        _activeCsrfToken,
      )
    } catch (error) {
      if (
        error instanceof KeeplingApiError &&
        error.problem.code === 'authentication_required' &&
        onAuthenticationRequired
      ) {
        setCommandState({ kind: 'authentication-required' })
        onAuthenticationRequired(
          { kind: 'submitted-unknown', mutationId: current.command.mutationId },
          (nextCsrfToken) => checkSubmission(current, nextCsrfToken),
        )
      } else if (error instanceof KeeplingApiError && error.problem.code !== 'mutation_not_found') {
        setSubmission(null)
        setCommandState({ kind: 'problem', message: error.message })
      } else {
        setCommandState({ kind: 'unknown' })
      }
    }
  }

  const submit = async (action: Submission['action'], navigateAfter?: string) => {
    if (!acceptedTask || commandState.kind === 'submitting' || !validate()) return
    const hasDetails = Object.keys(changedValues.fields).length > 0
    const hasDates = Object.keys(changedDateValues.fields).length > 0
    if (action === 'edit' && !hasDetails && !hasDates) {
      if (navigateAfter) onNavigate(navigateAfter)
      return
    }

    const current =
      submission ??
      (action === 'edit' && !hasDetails
        ? ({
            action,
            command: {
              baseValues: changedDateValues.baseValues,
              expectedRevision: acceptedTask.revision,
              fields: changedDateValues.fields,
              mutationId: crypto.randomUUID(),
              taskId: acceptedTask.id,
            },
            commandKind: 'dates',
            navigateAfter,
          } satisfies Submission)
        : ({
            action,
            command: {
              baseValues: changedValues.baseValues,
              expectedRevision: acceptedTask.revision,
              fields: changedValues.fields,
              mutationId: crypto.randomUUID(),
              taskId: acceptedTask.id,
            },
            commandKind: 'details',
            datesAfter: hasDates ? changedDateValues : undefined,
            navigateAfter,
          } satisfies Submission))

    setPendingNavigation(null)
    await deliver(current)
  }

  const requestNavigation = (pathname: string) => {
    if (dirty) setPendingNavigation(pathname)
    else onNavigate(pathname)
  }

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    void submit('edit')
  }

  const handleKeyDown = (event: KeyboardEvent<HTMLFormElement>) => {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      void submit('edit')
    } else if (event.key === 'Escape') {
      event.preventDefault()
      requestNavigation('/')
    }
  }

  if (loadState.kind === 'loading') {
    return (
      <main className="p-6" id="main-content">
        <p role="status">Loading task…</p>
      </main>
    )
  }

  if (loadState.kind === 'error') {
    return (
      <main className="p-6" id="main-content">
        <div role="alert">
          <p>Couldn’t load this task. Your tasks weren’t changed.</p>
          <Button className="mt-3" onClick={() => onNavigate('/')} variant="outline">
            Return to Inbox
          </Button>
        </div>
      </main>
    )
  }

  const firstError =
    fieldErrors.title ??
    fieldErrors.notes ??
    fieldErrors.plannedOn ??
    fieldErrors.deadlineOn
  const dateWarning =
    draft.plannedOn !== '' &&
    draft.deadlineOn !== '' &&
    validCivilDate(draft.plannedOn) &&
    validCivilDate(draft.deadlineOn) &&
    draft.plannedOn > draft.deadlineOn

  return (
    <main
      className="min-h-screen bg-card px-4 py-8 sm:px-6 lg:fixed lg:inset-y-0 lg:right-0 lg:z-20 lg:w-[calc(100%-41.5rem)] lg:min-w-[30rem] lg:overflow-y-auto lg:border-l lg:border-border lg:px-8"
      id="main-content"
    >
      <div
        aria-hidden={pendingNavigation ? true : undefined}
        className="mx-auto max-w-3xl"
        inert={pendingNavigation ? true : undefined}
      >
        <p className="text-sm font-semibold text-muted-foreground">Inbox</p>
        <h1 className="mt-2 text-[1.75rem] font-semibold leading-[1.2]">Edit task</h1>

        <form className="mt-8 space-y-6" onKeyDown={handleKeyDown} onSubmit={handleSubmit}>
          {firstError ? (
            <div className="rounded-lg border border-destructive p-4" role="alert">
              <p className="font-semibold">Review the highlighted fields.</p>
              <ul className="mt-2 list-disc pl-5">
                {fieldErrors.title ? (
                  <li>
                    <a className="underline" href="#task-editor-title">
                      {fieldErrors.title}
                    </a>
                  </li>
                ) : null}
                {fieldErrors.notes ? (
                  <li>
                    <a className="underline" href="#task-editor-notes">
                      {fieldErrors.notes}
                    </a>
                  </li>
                ) : null}
                {fieldErrors.plannedOn ? (
                  <li>
                    <a className="underline" href="#task-editor-planned-on">
                      {fieldErrors.plannedOn}
                    </a>
                  </li>
                ) : null}
                {fieldErrors.deadlineOn ? (
                  <li>
                    <a className="underline" href="#task-editor-deadline-on">
                      {fieldErrors.deadlineOn}
                    </a>
                  </li>
                ) : null}
              </ul>
            </div>
          ) : null}

          <div className="space-y-2">
            <label className="block text-sm font-semibold" htmlFor="task-editor-title">
              Title
            </label>
            <input
              aria-describedby={fieldErrors.title ? 'task-editor-title-error' : undefined}
              aria-invalid={fieldErrors.title ? true : undefined}
              className="min-h-11 w-full rounded-lg border border-input bg-background px-3 py-2 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="task-editor-title"
              maxLength={512}
              onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))}
              readOnly={locked}
              ref={titleRef}
              value={draft.title}
            />
            {fieldErrors.title ? (
              <p className="text-sm text-destructive" id="task-editor-title-error">
                {fieldErrors.title}
              </p>
            ) : null}
          </div>

          <div className="space-y-2">
            <label className="block text-sm font-semibold" htmlFor="task-editor-notes">
              Notes
            </label>
            <textarea
              aria-describedby={fieldErrors.notes ? 'task-editor-notes-error' : undefined}
              aria-invalid={fieldErrors.notes ? true : undefined}
              className="min-h-40 w-full resize-y rounded-lg border border-input bg-background px-3 py-2 text-base leading-6 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              id="task-editor-notes"
              maxLength={50_000}
              onChange={(event) => setDraft((current) => ({ ...current, notes: event.target.value }))}
              readOnly={locked}
              ref={notesRef}
              value={draft.notes}
            />
            {fieldErrors.notes ? (
              <p className="text-sm text-destructive" id="task-editor-notes-error">
                {fieldErrors.notes}
              </p>
            ) : null}
          </div>

          <fieldset className="space-y-4">
            <legend className="text-sm font-semibold">Dates</legend>
            <p className="text-sm text-muted-foreground">
              Dates use {loadState.accountTimezone}
            </p>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <label className="block text-sm font-semibold" htmlFor="task-editor-planned-on">
                  Planned date
                </label>
                <input
                  aria-describedby={
                    fieldErrors.plannedOn ? 'task-editor-planned-on-error' : undefined
                  }
                  aria-invalid={fieldErrors.plannedOn ? true : undefined}
                  className="min-h-11 w-full rounded-lg border border-input bg-background px-3 py-2 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  id="task-editor-planned-on"
                  inputMode="numeric"
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, plannedOn: event.target.value }))
                  }
                  placeholder="YYYY-MM-DD"
                  readOnly={locked}
                  ref={plannedOnRef}
                  value={draft.plannedOn}
                />
                {fieldErrors.plannedOn ? (
                  <p className="text-sm text-destructive" id="task-editor-planned-on-error">
                    {fieldErrors.plannedOn}
                  </p>
                ) : null}
              </div>
              <div className="space-y-2">
                <label className="block text-sm font-semibold" htmlFor="task-editor-deadline-on">
                  Deadline
                </label>
                <input
                  aria-describedby={
                    fieldErrors.deadlineOn ? 'task-editor-deadline-on-error' : undefined
                  }
                  aria-invalid={fieldErrors.deadlineOn ? true : undefined}
                  className="min-h-11 w-full rounded-lg border border-input bg-background px-3 py-2 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  id="task-editor-deadline-on"
                  inputMode="numeric"
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, deadlineOn: event.target.value }))
                  }
                  placeholder="YYYY-MM-DD"
                  readOnly={locked}
                  ref={deadlineOnRef}
                  value={draft.deadlineOn}
                />
                {fieldErrors.deadlineOn ? (
                  <p className="text-sm text-destructive" id="task-editor-deadline-on-error">
                    {fieldErrors.deadlineOn}
                  </p>
                ) : null}
              </div>
            </div>
            {dateWarning ? (
              <p className="rounded-lg border border-border bg-muted p-3 text-sm" role="status">
                Planned date is after the deadline. Both dates will be saved.
              </p>
            ) : null}
          </fieldset>

          {dirty ? <p className="text-sm font-semibold text-muted-foreground">Unsaved changes</p> : null}

          <div className="flex flex-wrap gap-3">
            <Button disabled={!dirty || locked} type="submit">
              {commandState.kind === 'submitting' ? 'Saving…' : 'Save changes'}
            </Button>
            {loadState.task.inboxState === 'inbox' ? (
              <Button
                disabled={locked}
                onClick={() => void submit('clarify', '/')}
                type="button"
                variant="outline"
              >
                Save &amp; move out of Inbox
              </Button>
            ) : null}
            <Button disabled={locked} onClick={() => requestNavigation('/')} type="button" variant="ghost">
              Cancel editing
            </Button>
          </div>
        </form>

        {commandState.kind === 'saved' ? (
          <p className="mt-6" role="status">
            {commandState.message}
          </p>
        ) : null}
        {commandState.kind === 'unknown' ? (
          <div className="mt-6 rounded-lg border border-border p-4" role="status">
            <p>Checking whether your change was saved…</p>
            <Button className="mt-3" onClick={() => submission && void checkSubmission(submission)} variant="outline">
              Check again
            </Button>
          </div>
        ) : null}
        {commandState.kind === 'authentication-required' ? (
          <div className="mt-6 rounded-lg border border-border p-4" role="status">
            Sign in again to finish saving. Your changes are still here.
          </div>
        ) : null}
        {commandState.kind === 'conflict' ? (
          <div className="mt-6 rounded-lg border border-border p-4" role="alert">
            <h2 className="text-xl font-semibold">This task changed somewhere else.</h2>
            <p className="mt-2">Review the affected fields before saving again.</p>
          </div>
        ) : null}
        {commandState.kind === 'problem' && !firstError ? (
          <div className="mt-6 rounded-lg border border-border p-4" role="alert">
            {commandState.message}
          </div>
        ) : null}
      </div>

      {pendingNavigation ? (
        <div
          aria-labelledby="dirty-navigation-title"
          aria-modal="true"
          className="fixed inset-0 z-50 grid place-items-center bg-foreground/30 p-4"
          role="alertdialog"
        >
          <div className="w-full max-w-md rounded-xl border border-border bg-background p-6 shadow-lg">
            <h2 className="text-xl font-semibold" id="dirty-navigation-title">
              You have unsaved changes.
            </h2>
            <p className="mt-2 text-muted-foreground">Save them before leaving this task?</p>
            <div className="mt-6 flex flex-wrap gap-3">
              <Button ref={stayRef} onClick={() => setPendingNavigation(null)} variant="outline">
                Stay here
              </Button>
              <Button onClick={() => void submit('edit', pendingNavigation)}>Save changes</Button>
              <Button
                onClick={() => {
                  allowNavigation.current = true
                  onNavigate(pendingNavigation)
                }}
                variant="destructive"
              >
                Discard changes
              </Button>
            </div>
          </div>
        </div>
      ) : null}
    </main>
  )
}

export default TaskEditor
