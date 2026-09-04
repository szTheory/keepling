import { useEffect, useState } from 'react'

/**
 * O-31(a): the MAC-04 synchronization row, in the utility windows.
 *
 * 03-19 closed O-31 for the MAIN window only. Quick Entry and Settings load
 * a different, deliberately narrow preload bundle
 * (`preload/utility-preload.ts`, exposing `window.keeplingUtility`), so
 * `window.keepling` and `subscribePresentation` did not exist in their JS
 * context at all -- a person capturing through Quick Entry while offline
 * still got no indication whatsoever. That is precisely the surface where
 * it matters most: Quick Entry is what someone uses when they are not
 * looking at the main window.
 *
 * Copy only, verbatim, and no recovery actions. This is not a smaller
 * version of the main row that lost its buttons -- the remedies act on the
 * main window's Sync & Recovery region, which does not exist here, and
 * carrying them across this bridge would widen it for a surface that could
 * not use them. A `null` copy renders nothing, so a healthy app and a pass
 * inside the anti-flicker grace period stay quiet.
 *
 * Not a live region, for the same reason the main row is not: this window
 * is a two-second capture surface, and interrupting someone mid-title with
 * a background synchronization change is the opposite of what it is for.
 */
type PresentationSummary = {
  copy: string | null
  kind: string
}

function UtilitySyncStatusRow() {
  const [summary, setSummary] = useState<PresentationSummary | null>(null)

  useEffect(
    () =>
      window.keeplingUtility.subscribePresentation((presentation) => {
        setSummary(presentation.summary)
      }),
    [],
  )

  if (summary === null || summary.copy === null) return null

  return (
    <aside
      aria-label="Synchronization status"
      data-sync-status={summary.kind}
      id="utility-sync-status-row"
    >
      <p>{summary.copy}</p>
    </aside>
  )
}

export default UtilitySyncStatusRow
