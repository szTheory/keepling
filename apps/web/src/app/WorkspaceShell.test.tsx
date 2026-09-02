import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'

import type { ClientFacade } from '../../../../packages/web-ui/src/ClientFacade.ts'
import WorkspaceShell from './WorkspaceShell'

const stubFacade: ClientFacade = {
  captureTask: async () => ({ kind: 'accepted', task: { id: 't', notes: '', syncStatus: 'synced', title: 't' } }),
  getRecoveryAvailability: () => null,
  getSnapshot: () => ({ selectedTaskId: null, tasks: [] }),
  selectTask: () => undefined,
  subscribe: () => () => undefined,
  subscribeRecovery: () => () => undefined,
}

describe('WorkspaceShell shared-workspace opt-in', () => {
  it('renders children unchanged when useSharedWorkspace is not set (default, unaffected)', () => {
    render(
      <WorkspaceShell clientFacade={stubFacade} pathname="/">
        <main id="main-content">Existing routed content</main>
      </WorkspaceShell>,
    )

    expect(screen.getByText('Existing routed content')).toBeInTheDocument()
  })

  it('renders the shared packages/web-ui Workspace only when explicitly opted in', () => {
    render(
      <WorkspaceShell clientFacade={stubFacade} pathname="/" useSharedWorkspace>
        <main id="main-content">Existing routed content</main>
      </WorkspaceShell>,
    )

    expect(screen.queryByText('Existing routed content')).not.toBeInTheDocument()
    expect(screen.getByText('Inbox Is Clear')).toBeInTheDocument()
  })
})
