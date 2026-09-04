import { useEffect, useRef, useState } from 'react'

import UtilitySyncStatusRow from './UtilitySyncStatusRow.tsx'

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
  const discardTriggerRef = useRef<HTMLButtonElement>(null)
  // Only restore focus for a dialog that was actually open, so the very
  // first render (dialog closed) never steals focus from the title field.
  const dialogWasOpenRef = useRef(false)
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

  // O-36 (1/2). A dialog that returns focus to NOWHERE is a
  // keyboard-navigation defect in its own right, and it is what D-06/MAC-02
  // mean by focus restoration. Measured before this fix: dismissing the
  // confirmation with `Keep Draft` left AX focus on `AXWebArea "Keepling"`
  // -- the document -- rather than on any control.
  //
  // Focus returns to the control that OPENED the dialog when that control
  // still exists (`Keep Draft`), and falls back to the title field when it
  // does not (`Discard Draft` removes the draft, so `Discard Draft…`
  // unmounts with it). The fallback is not cosmetic: it is the path taken
  // on the confirm branch.
  useEffect(() => {
    if (confirmingDiscard) {
      keepDraftButtonRef.current?.focus()
      return
    }
    if (!dialogWasOpenRef.current) return
    dialogWasOpenRef.current = false
    const invoker = discardTriggerRef.current
    if (invoker !== null && invoker.isConnected) invoker.focus()
    else titleFieldRef.current?.focus()
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

  /**
   * O-36 (2/2). THE WINDOW, not a subtree.
   *
   * This was `<div onKeyDown={handleKeyDown}>`, and React's synthetic
   * keydown only fires for keys delivered INTO that subtree. Whenever focus
   * sat on the document instead of a control -- measured after the discard
   * confirmation closed, but reachable from any future focus-to-body path --
   * Escape reached the body, never descended into the div, and silently did
   * nothing. Tabbing back into the field made the very same key work.
   *
   * Binding on `window` makes the guarantee STRUCTURAL rather than
   * incidental: there is no focus position inside this window from which
   * Escape can fail. It is deliberately NOT a main-process global
   * accelerator -- Escape is a window-local key, and a global one would
   * swallow Escape from every other application on this Mac.
   *
   * The live handler is held in a ref so the listener is registered exactly
   * once, yet always sees the current draft and submission state.
   */
  const keyDownRef = useRef<(event: KeyboardEvent) => void>(() => undefined)
  useEffect(() => {
    keyDownRef.current = (event: KeyboardEvent) => {
      if (event.isComposing) return
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
  })
  useEffect(() => {
    const listener = (event: KeyboardEvent) => keyDownRef.current(event)
    window.addEventListener('keydown', listener)
    return () => window.removeEventListener('keydown', listener)
  }, [])

  const confirmDiscard = () => {
    window.keeplingUtility.requestDiscard()
    setTitle('')
    setAddToToday(false)
    setConfirmingDiscard(false)
  }

  return (
    <div>
      {/*
        O-31(a): the main-owned synchronization row. Rendered ABOVE the form
        so someone capturing while offline reads it before they commit,
        rather than discovering afterwards that nothing left this Mac.
      */}
      <UtilitySyncStatusRow />
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
          <button
            onClick={() => {
              dialogWasOpenRef.current = true
              setConfirmingDiscard(true)
            }}
            ref={discardTriggerRef}
            type="button"
          >
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
