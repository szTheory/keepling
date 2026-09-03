import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
  type KeyboardEvent,
} from 'react'

import type { ClientFacade, WorkspaceTaskView } from '../ClientFacade'

/**
 * Task detail editor (D-12/D-13/D-14, UI-SPEC). Edits title/notes through the
 * named `editTask` semantic operation, and exposes complete/reopen and
 * Trash/restore as named actions outside the editable controls. Dirty-work
 * safety (Save Changes / Discard Changes / Keep Editing) is owned by the
 * parent Workspace, which drives this component through the imperative
 * handle so navigation away from a dirty draft always goes through the same
 * dialog regardless of what triggered the navigation attempt.
 */
type TaskEditorHandle = {
  discard: () => void
  /** O-11 gap closure (D-06): the current in-progress edit, or `null` when not dirty. Used only for semantic-restoration persistence -- never a durability signal (D-03). */
  getDraft: () => { notes: string; title: string } | null
  save: () => Promise<boolean>
}

type TaskEditorProps = {
  facade: ClientFacade
  /**
   * O-11 gap closure (D-06): a restored recoverable draft for THIS task,
   * applied only once, at mount (never re-applied on a later re-render or
   * task switch -- ordinary edits and the existing `task.id` reset effect
   * own everything after that). Absent/undefined means "start from the
   * task's own canonical title/notes", the pre-existing behavior.
   */
  initialDraft?: { notes: string; title: string }
  onDirtyChange: (dirty: boolean) => void
  task: WorkspaceTaskView
}

const syncStatusLabel = (status: WorkspaceTaskView['syncStatus']): string => {
  if (status === 'synced') return 'Synced'
  if (status === 'saved_on_this_mac') return 'Saved on this Mac'
  return 'Draft'
}

const TaskEditor = forwardRef<TaskEditorHandle, TaskEditorProps>(function TaskEditor(
  { facade, initialDraft, onDirtyChange, task },
  ref,
) {
  const [title, setTitle] = useState(() => initialDraft?.title ?? task.title)
  const [notes, setNotes] = useState(() => initialDraft?.notes ?? task.notes)
  const [saving, setSaving] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [lifecycleBusy, setLifecycleBusy] = useState(false)
  const titleRef = useRef<HTMLInputElement>(null)
  // O-11 gap closure: skip the very first run of the reset-to-canonical
  // effect below so a restored `initialDraft` (applied only via the lazy
  // useState initializers above, at true mount) is never immediately wiped
  // out by this effect on that same mount. Every SUBSEQUENT task switch or
  // remote task field change still resets normally.
  const skippedFirstResetRef = useRef(false)

  useEffect(() => {
    if (!skippedFirstResetRef.current) {
      skippedFirstResetRef.current = true
      setProblem(null)
      return
    }
    setTitle(task.title)
    setNotes(task.notes)
    setProblem(null)
  }, [task.id, task.notes, task.title])

  const dirty = title !== task.title || notes !== task.notes

  useEffect(() => {
    onDirtyChange(dirty)
  }, [dirty, onDirtyChange])

  const save = async (): Promise<boolean> => {
    if (!dirty || saving) return true
    setSaving(true)
    const outcome = await facade.editTask(task.id, { notes, title: title.trim() })
    setSaving(false)
    if (outcome.kind === 'accepted') {
      setProblem(null)
      return true
    }
    setProblem(outcome.message)
    return false
  }

  const discard = () => {
    setTitle(task.title)
    setNotes(task.notes)
    setProblem(null)
  }

  useImperativeHandle(ref, () => ({ discard, getDraft: () => (dirty ? { notes, title } : null), save }))

  const handleKeyDown = (event: KeyboardEvent<HTMLElement>) => {
    if ((event.metaKey || event.ctrlKey) && (event.key === 's' || event.key === 'Enter')) {
      event.preventDefault()
      void save()
    }
  }

  const runLifecycle = async (
    operation: () => Promise<{ kind: 'accepted' } | { kind: 'rejected'; message: string }>,
  ) => {
    if (lifecycleBusy) return
    setLifecycleBusy(true)
    const outcome = await operation()
    setLifecycleBusy(false)
    if (outcome.kind === 'rejected') setProblem(outcome.message)
  }

  const trashed = task.trashedAt !== null
  const completed = task.completedAt !== null

  return (
    <article aria-labelledby="workspace-detail-title" onKeyDown={handleKeyDown}>
      <label htmlFor="task-editor-title">Title</label>
      <input
        id="task-editor-title"
        maxLength={512}
        onChange={(event) => setTitle(event.target.value)}
        readOnly={trashed}
        ref={titleRef}
        value={title}
      />
      <label htmlFor="task-editor-notes">Notes</label>
      <textarea
        id="task-editor-notes"
        maxLength={50_000}
        onChange={(event) => setNotes(event.target.value)}
        readOnly={trashed}
        value={notes}
      />
      <p data-workspace-sync-status={task.syncStatus}>{syncStatusLabel(task.syncStatus)}</p>
      {dirty ? <p data-workspace-dirty="true">Unsaved changes</p> : null}
      {problem ? <p role="alert">{problem}</p> : null}

      <div data-workspace-lifecycle-actions="true">
        {trashed ? (
          <button
            disabled={lifecycleBusy}
            onClick={() => void runLifecycle(() => facade.restoreTask(task.id))}
            type="button"
          >
            Restore
          </button>
        ) : (
          <>
            <button
              disabled={lifecycleBusy}
              onClick={() =>
                void runLifecycle(() =>
                  completed ? facade.reopenTask(task.id) : facade.completeTask(task.id),
                )
              }
              type="button"
            >
              {completed ? 'Reopen' : 'Complete'}
            </button>
            <button
              disabled={lifecycleBusy}
              onClick={() => void runLifecycle(() => facade.trashTask(task.id))}
              type="button"
            >
              Move to Trash
            </button>
            <button
              disabled={lifecycleBusy}
              onClick={() => void runLifecycle(() => facade.moveToday(task.id, !task.planned))}
              type="button"
            >
              {task.planned ? 'Remove from Today' : 'Add to Today'}
            </button>
          </>
        )}
      </div>

      <div data-workspace-save-actions="true">
        <button disabled={!dirty || saving} onClick={() => void save()} type="button">
          {saving ? 'Saving…' : 'Save Changes'}
        </button>
      </div>
    </article>
  )
})

export default TaskEditor
export type { TaskEditorHandle }
