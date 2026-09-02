import { useEffect, useRef, useState } from 'react'

/**
 * Quick Entry (D-09/D-11, UI-SPEC "Quick Entry Contract"). Title-first,
 * `Destination: Inbox` plus optional `Add to Today`, `Add Task` commits.
 * The draft is durable (survives Escape/Command-W hide and window
 * recreation) via `window.keeplingUtility.saveDraft/getDraft`, and is
 * removed only by an explicit `Discard Draft…` with safe `Keep Draft`
 * initial focus. Commit success hides the window; focus return to the
 * prior app is handled main-side by `QuickEntryWindowController.hide()`.
 */
type Status = { kind: 'idle' } | { kind: 'submitting' } | { kind: 'rejected'; message: string }

const DRAFT_SAVE_DEBOUNCE_MS = 250

function QuickEntry() {
  const [title, setTitle] = useState('')
  const [addToToday, setAddToToday] = useState(false)
  const [status, setStatus] = useState<Status>({ kind: 'idle' })
  const [confirmingDiscard, setConfirmingDiscard] = useState(false)
  const titleFieldRef = useRef<HTMLInputElement>(null)
  const keepDraftButtonRef = useRef<HTMLButtonElement>(null)
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    let cancelled = false
    void window.keeplingUtility.getDraft().then((draft) => {
      if (cancelled || draft === null) return
      setTitle(draft.title)
      setAddToToday(draft.addToToday)
    })
    titleFieldRef.current?.focus()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => window.keeplingUtility.onFocusTitle(() => titleFieldRef.current?.focus()), [])

  useEffect(() => {
    if (confirmingDiscard) keepDraftButtonRef.current?.focus()
  }, [confirmingDiscard])

  // Persist the draft as the person types (D-11 "durable draft"), debounced
  // so every keystroke doesn't reach the main-owned store individually.
  useEffect(() => {
    if (saveTimerRef.current !== null) clearTimeout(saveTimerRef.current)
    if (title.trim() === '') return
    saveTimerRef.current = setTimeout(() => {
      void window.keeplingUtility.saveDraft({ addToToday, title })
    }, DRAFT_SAVE_DEBOUNCE_MS)
    return () => {
      if (saveTimerRef.current !== null) clearTimeout(saveTimerRef.current)
    }
  }, [title, addToToday])

  const submit = async () => {
    if (title.trim() === '' || status.kind === 'submitting') return
    setStatus({ kind: 'submitting' })
    try {
      await window.keeplingUtility.capture({ addToToday, title })
      setTitle('')
      setAddToToday(false)
      setStatus({ kind: 'idle' })
    } catch (error) {
      setStatus({
        kind: 'rejected',
        message: error instanceof Error ? error.message : 'Couldn’t add this task. Nothing was changed.',
      })
    }
  }

  const requestHide = () => {
    if (title.trim() === '') {
      window.keeplingUtility.hide()
      return
    }
    // Nonempty draft: hide, never discard, on Escape/Command-W (D-11).
    window.keeplingUtility.hide()
  }

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.nativeEvent.isComposing) return
    if (event.key === 'Escape') {
      event.preventDefault()
      requestHide()
      return
    }
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault()
      void submit()
    }
  }

  const confirmDiscard = () => {
    window.keeplingUtility.requestDiscard()
    setTitle('')
    setAddToToday(false)
    setConfirmingDiscard(false)
  }

  return (
    <div onKeyDown={handleKeyDown}>
      <form
        aria-label="Quick Entry"
        onSubmit={(event) => {
          event.preventDefault()
          void submit()
        }}
      >
        <label htmlFor="quick-entry-title">What do you want to keep?</label>
        <input
          id="quick-entry-title"
          maxLength={512}
          onChange={(event) => setTitle(event.target.value)}
          ref={titleFieldRef}
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
        {title.trim() !== '' ? (
          <button onClick={() => setConfirmingDiscard(true)} type="button">
            Discard Draft…
          </button>
        ) : null}
        {status.kind === 'rejected' ? <p role="alert">{status.message}</p> : null}
      </form>

      {confirmingDiscard ? (
        <div aria-label="Discard Quick Entry Draft?" data-quick-entry-discard-dialog="true" role="alertdialog">
          <h2>Discard Quick Entry Draft?</h2>
          <p>This draft is saved on this Mac but hasn’t been added as a task.</p>
          <button onClick={confirmDiscard} type="button">
            Discard Draft
          </button>
          <button onClick={() => setConfirmingDiscard(false)} ref={keepDraftButtonRef} type="button">
            Keep Draft
          </button>
        </div>
      ) : null}
    </div>
  )
}

export default QuickEntry
