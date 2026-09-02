import { useRef, type KeyboardEvent } from 'react'

import type { WorkspaceTaskView } from '../ClientFacade'

/**
 * Stable-identity task list. List focus is independent from selection (D-05):
 * Up/Down moves a roving row focus, Return selects the focused task by ID
 * through the named `onSelect` navigation operation, never by DOM position.
 */
type TaskListProps = {
  onSelect: (taskId: string) => void
  selectedTaskId: string | null
  tasks: readonly WorkspaceTaskView[]
}

const syncStatusLabel = (status: WorkspaceTaskView['syncStatus']): string => {
  if (status === 'synced') return 'Synced'
  if (status === 'saved_on_this_mac') return 'Saved on this Mac'
  return 'Draft'
}

function TaskList({ onSelect, selectedTaskId, tasks }: TaskListProps) {
  const rowRefs = useRef(new Map<string, HTMLLIElement>())

  const focusRowAt = (index: number) => {
    const task = tasks[index]
    if (task === undefined) return
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
          tabIndex={index === 0 ? 0 : -1}
        >
          <span>{task.title}</span>
          <small data-task-sync-status={task.syncStatus}>{syncStatusLabel(task.syncStatus)}</small>
        </li>
      ))}
    </ul>
  )
}

export default TaskList
