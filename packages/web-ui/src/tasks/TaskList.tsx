import { useEffect, useRef, useState, type KeyboardEvent } from 'react'

import type { WorkspaceTaskView } from '../ClientFacade'

/**
 * Stable-identity task list. List focus is independent from selection (D-05):
 * Up/Down moves a roving row focus, Return selects the focused task by ID
 * through the named `onSelect` navigation operation, never by DOM position.
 *
 * `focusTaskId` lets the parent restore focus by stable identity after a row
 * is removed (complete/trash/remote change/window recreation) instead of
 * falling back to a DOM index, which would land on whatever task happens to
 * occupy that position now.
 */
type TaskListProps = {
  focusTaskId?: string | null
  onSelect: (taskId: string) => void
  selectedTaskId: string | null
  tasks: readonly WorkspaceTaskView[]
}

const syncStatusLabel = (status: WorkspaceTaskView['syncStatus']): string => {
  if (status === 'synced') return 'Synced'
  if (status === 'saved_on_this_mac') return 'Saved on this Mac'
  return 'Draft'
}

function TaskList({ focusTaskId, onSelect, selectedTaskId, tasks }: TaskListProps) {
  const rowRefs = useRef(new Map<string, HTMLLIElement>())
  const [rovingId, setRovingId] = useState<string | null>(tasks[0]?.id ?? null)

  useEffect(() => {
    if (tasks.some((task) => task.id === rovingId)) return
    setRovingId(tasks[0]?.id ?? null)
  }, [rovingId, tasks])

  useEffect(() => {
    if (focusTaskId === undefined || focusTaskId === null) return
    setRovingId(focusTaskId)
    rowRefs.current.get(focusTaskId)?.focus()
  }, [focusTaskId])

  const focusRowAt = (index: number) => {
    const task = tasks[index]
    if (task === undefined) return
    setRovingId(task.id)
    rowRefs.current.get(task.id)?.focus()
  }

  const handleKeyDown = (event: KeyboardEvent<HTMLLIElement>, index: number) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      focusRowAt(index + 1)
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      focusRowAt(index - 1)
    } else if (event.key === 'Enter') {
      event.preventDefault()
      const task = tasks[index]
      if (task) onSelect(task.id)
    }
  }

  const activeId = rovingId ?? tasks[0]?.id

  return (
    <ul aria-label="Tasks">
      {tasks.map((task, index) => (
        <li
          aria-current={task.id === selectedTaskId ? 'true' : undefined}
          data-task-id={task.id}
          key={task.id}
          onClick={() => onSelect(task.id)}
          onKeyDown={(event) => handleKeyDown(event, index)}
          ref={(node) => {
            if (node) rowRefs.current.set(task.id, node)
            else rowRefs.current.delete(task.id)
          }}
          tabIndex={task.id === activeId ? 0 : -1}
        >
          <span>{task.title}</span>
          <small data-task-sync-status={task.syncStatus}>{syncStatusLabel(task.syncStatus)}</small>
        </li>
      ))}
    </ul>
  )
}

export default TaskList
