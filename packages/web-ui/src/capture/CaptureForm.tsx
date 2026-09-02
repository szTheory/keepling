import { useState, type FormEvent } from 'react'

import type { CaptureOutcome, ClientFacade } from '../ClientFacade'

/**
 * Presentation-only capture form. It never talks to fetch, IPC, or storage
 * directly -- every commit runs through the named `captureTask` semantic
 * operation on the platform-supplied ClientFacade (D-26/D-27).
 */
type CaptureFormProps = {
  facade: ClientFacade
}

type Status =
  | { kind: 'idle' }
  | { kind: 'submitting' }
  | { kind: 'rejected'; message: string }

function CaptureForm({ facade }: CaptureFormProps) {
  const fieldId = 'workspace-capture-title'
  const [title, setTitle] = useState('')
  const [addToToday, setAddToToday] = useState(false)
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  const submit = async () => {
    if (title.trim() === '' || status.kind === 'submitting') return
    setStatus({ kind: 'submitting' })
    const outcome: CaptureOutcome = await facade.captureTask({ addToToday, title })
    if (outcome.kind === 'accepted') {
      setTitle('')
      setAddToToday(false)
      setStatus({ kind: 'idle' })
    } else {
      setStatus({ kind: 'rejected', message: outcome.message })
    }
  }

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    void submit()
  }

  return (
    <form aria-label="Add task" onSubmit={handleSubmit}>
      <label htmlFor={fieldId}>What do you want to keep?</label>
      <input
        id={fieldId}
        maxLength={512}
        onChange={(event) => setTitle(event.target.value)}
        value={title}
      />
      <p>Destination: Inbox</p>
      <label>
        <input
          checked={addToToday}
          onChange={(event) => setAddToToday(event.target.checked)}
          type="checkbox"
        />
        Add to Today
      </label>
      <button disabled={title.trim() === '' || status.kind === 'submitting'} type="submit">
        Add Task
      </button>
      {status.kind === 'rejected' ? <p role="alert">{status.message}</p> : null}
    </form>
  )
}

export default CaptureForm
