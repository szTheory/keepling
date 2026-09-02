import { useEffect, useState } from 'react'

/**
 * Settings (D-10, D-14 `Command-,`). Surfaces the configurable Quick Entry
 * global shortcut and, when registration failed (a collision with another
 * application), the persistent `Quick Entry shortcut isn’t available.`
 * notice with a direct `Change Shortcut…` action -- never a silent
 * fallback to a different shortcut.
 */
type ShortcutStatus = { accelerator: string; registered: boolean }

function Settings() {
  const [status, setStatus] = useState<ShortcutStatus | null>(null)
  const [rebinding, setRebinding] = useState(false)
  const [candidate, setCandidate] = useState('')

  useEffect(() => {
    void window.keeplingUtility.getShortcutStatus().then(setStatus)
    return window.keeplingUtility.onShortcutStatus(setStatus)
  }, [])

  const submitRebind = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (candidate.trim() === '') return
    const next = await window.keeplingUtility.setShortcut(candidate.trim())
    setStatus(next)
    if (next.registered) {
      setRebinding(false)
      setCandidate('')
    }
  }

  return (
    <section aria-label="Settings">
      <h1>Settings</h1>
      <h2>Quick Entry Shortcut</h2>
      {status === null ? null : status.registered ? (
        <p>Current shortcut: {status.accelerator}</p>
      ) : (
        <p role="alert">Quick Entry shortcut isn’t available.</p>
      )}
      {rebinding ? (
        <form onSubmit={(event) => void submitRebind(event)}>
          <label htmlFor="settings-shortcut-candidate">New shortcut</label>
          <input
            id="settings-shortcut-candidate"
            onChange={(event) => setCandidate(event.target.value)}
            placeholder="Control+Alt+Space"
            value={candidate}
          />
          <button type="submit">Save Shortcut</button>
          <button onClick={() => setRebinding(false)} type="button">
            Cancel
          </button>
        </form>
      ) : (
        <button onClick={() => setRebinding(true)} type="button">
          Change Shortcut…
        </button>
      )}
    </section>
  )
}

export default Settings
