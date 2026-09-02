import { useEffect, useState, type FormEvent } from 'react'
import { createRoot } from 'react-dom/client'

type Snapshot = Awaited<ReturnType<typeof window.keepling.snapshot>>

const App = () => {
  const [draft, setDraft] = useState('')
  const [snapshot, setSnapshot] = useState<Snapshot>({ tasks: [] })
  const [message, setMessage] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    void window.keepling.snapshot().then(setSnapshot)
  }, [])

  const save = async (event: FormEvent) => {
    event.preventDefault()
    if (saving || draft.trim() === '') return
    setSaving(true)
    try {
      const acceptance = await window.keepling.capture({ title: draft })
      setSnapshot(acceptance.snapshot)
      setDraft('')
      setMessage('Saved on this Mac')
    } finally {
      setSaving(false)
    }
  }

  return (
    <main>
      <header>
        <p className="eyebrow">Keepling</p>
        <h1>Inbox</h1>
      </header>
      <form onSubmit={(event) => void save(event)}>
        <label htmlFor="task-title">Task title</label>
        <div className="capture-row">
          <input
            autoFocus
            id="task-title"
            maxLength={512}
            onChange={(event) => setDraft(event.target.value)}
            placeholder="What do you want to keep?"
            value={draft}
          />
          <button disabled={saving || draft.trim() === ''} type="submit">
            {saving ? 'Saving…' : 'Save task'}
          </button>
        </div>
      </form>
      {message ? <p className="status" role="status">{message}</p> : null}
      <ul aria-label="Inbox tasks">
        {snapshot.tasks.map((task) => (
          <li key={task.id}>
            <span>{task.title}</span>
            <small>{task.syncStatus === 'synced' ? 'Synced' : 'Saved on this Mac'}</small>
          </li>
        ))}
      </ul>
    </main>
  )
}

const style = document.createElement('style')
style.textContent = `
  :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
  body { margin: 0; background: Canvas; color: CanvasText; }
  main { max-width: 720px; margin: 0 auto; padding: 48px; }
  header { margin-bottom: 32px; }
  .eyebrow { margin: 0 0 6px; color: color-mix(in srgb, CanvasText 58%, transparent); font-size: 13px; font-weight: 650; letter-spacing: .08em; text-transform: uppercase; }
  h1 { margin: 0; font-size: 32px; letter-spacing: -.03em; }
  label { display: block; margin-bottom: 8px; font-size: 14px; font-weight: 600; }
  .capture-row { display: flex; gap: 10px; }
  input { flex: 1; min-width: 0; border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 10px; background: Canvas; color: CanvasText; padding: 12px 14px; font: inherit; }
  button { border: 0; border-radius: 10px; padding: 0 18px; background: AccentColor; color: AccentColorText; font: inherit; font-weight: 650; }
  button:disabled { opacity: .5; }
  :focus-visible { outline: 3px solid AccentColor; outline-offset: 2px; }
  .status { margin: 12px 0 0; color: color-mix(in srgb, CanvasText 66%, transparent); font-size: 14px; }
  ul { list-style: none; margin: 30px 0 0; padding: 0; border-top: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
  li { display: flex; justify-content: space-between; gap: 24px; padding: 16px 2px; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
  small { color: color-mix(in srgb, CanvasText 58%, transparent); white-space: nowrap; }
  @media (prefers-reduced-motion: no-preference) { button { transition: opacity 120ms ease; } }
`
document.head.append(style)

const root = document.getElementById('root')
if (root === null) throw new Error('renderer root is missing')
createRoot(root).render(<App />)
