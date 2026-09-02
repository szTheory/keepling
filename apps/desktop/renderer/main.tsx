import { createRoot } from 'react-dom/client'

import DesktopShell from './DesktopShell.tsx'
import QuickEntry from './quick-entry.tsx'
import Settings from './settings.tsx'
import { createDesktopClientFacade } from './desktopClientFacade.ts'
import './desktop.css'

/**
 * The Electron renderer composes the shared `packages/web-ui` Workspace
 * presentation through the real desktop `ClientFacade` adapter -- the same
 * presentation the browser adapter and the deterministic test fixture also
 * drive (D-04/D-05/D-26/D-27). This is the load-bearing wiring: Plan 03-09
 * proved the extraction boundary; Plan 03-03 made it the shipped Mac
 * renderer for the main window.
 *
 * Plan 03-04 adds two additional resident utility-window views (Quick
 * Entry, Settings) selected by a `?view=` query parameter set by
 * `QuickEntryWindowController`/the settings-window opener when they call
 * `loadURL` against this same built `index.html`. The main window's URL
 * carries no `view` parameter and renders the full `DesktopShell`/
 * `Workspace` as before.
 */
const root = document.getElementById('root')
if (root === null) throw new Error('renderer root is missing')

const view = new URLSearchParams(window.location.search).get('view')

if (view === 'quick-entry') {
  createRoot(root).render(<QuickEntry />)
} else if (view === 'settings') {
  createRoot(root).render(<Settings />)
} else {
  const facade = createDesktopClientFacade()
  createRoot(root).render(<DesktopShell facade={facade} />)
}
