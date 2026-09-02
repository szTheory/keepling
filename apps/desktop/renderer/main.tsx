import { createRoot } from 'react-dom/client'

import Workspace from '../../../packages/web-ui/src/workspace/Workspace.tsx'
import { createDesktopClientFacade } from './desktopClientFacade.ts'
import './desktop.css'

/**
 * The Electron renderer composes the shared `packages/web-ui` Workspace
 * presentation through the real desktop `ClientFacade` adapter -- the same
 * presentation the browser adapter and the deterministic test fixture also
 * drive (D-04/D-05/D-26/D-27). This is the load-bearing wiring: Plan 03-09
 * proved the extraction boundary; this plan (03-03) makes it the shipped
 * Mac renderer.
 */
const facade = createDesktopClientFacade()

const root = document.getElementById('root')
if (root === null) throw new Error('renderer root is missing')
createRoot(root).render(<Workspace facade={facade} />)
