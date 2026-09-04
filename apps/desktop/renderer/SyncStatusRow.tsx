import { useEffect, useState } from 'react'

/**
 * The MAC-04 status row (O-30, Rule 2 addition).
 *
 * `DesktopApplication` has published a closed, main-owned presentation row
 * for every synchronization and recovery state since Plan 03-05, and the
 * preload bridge has delivered it with a sequence contract since 03-08 --
 * but nothing ever RENDERED it. `desktopClientFacade` subscribed only to
 * trigger a snapshot refetch, so every row's authored copy was published to
 * a renderer that displayed none of it, and MAC-04's "inspect the state
 * without reading logs" was not achievable at any of them. This component
 * is that missing surface for the main window.
 *
 * Three properties it deliberately keeps:
 *
 *  - It renders main's copy VERBATIM and infers nothing. The renderer never
 *    derives a state, never re-words a row, and never invents a count;
 *    `summary.copy` is authored in `main/application/presentation.ts` and
 *    is the single source of what a person reads (D-26/D-27).
 *  - A `null` copy renders NOTHING. `healthy` and a pass inside the
 *    anti-flicker grace period are quiet states by design, so the row must
 *    disappear rather than say "everything is fine" -- a persistent
 *    reassurance is exactly the claim this app must not make.
 *  - It is NOT a live region. The workspace already owns exactly one
 *    announcer (`packages/web-ui/src/recovery/SyncRecovery.tsx`), and
 *    `test/e2e/accessibility.spec.ts` pins that count at one on purpose --
 *    a second announcer would turn every background synchronization change
 *    into an interruption of whatever someone is typing. This row is a
 *    labeled, always-inspectable complementary landmark instead, which is
 *    precisely what MAC-04 asks for: a state a person can INSPECT without
 *    reading logs.
 */
type PresentationSummary = {
  copy: string | null
  count: number | null
  kind: string
}

function SyncStatusRow() {
  const [summary, setSummary] = useState<PresentationSummary | null>(null)

  useEffect(
    () =>
      window.keepling.subscribePresentation((presentation) => {
        setSummary(presentation.summary)
      }),
    [],
  )

  if (summary === null || summary.copy === null) return null

  return (
    <aside
      aria-label="Synchronization status"
      data-sync-status={summary.kind}
      id="sync-status-row"
    >
      <p>{summary.copy}</p>
    </aside>
  )
}

export default SyncStatusRow
