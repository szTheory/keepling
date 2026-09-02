import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'

import type { ClientFacade } from '../../../../packages/web-ui/src/ClientFacade.ts'
import WorkspaceShell from './WorkspaceShell'

const stubFacade: ClientFacade = {
  captureTask: async () => ({
    kind: 'accepted',
    task: { completedAt: null, id: 't', notes: '', planned: false, syncStatus: 'synced', title: 't', trashedAt: null },
  }),
  completeTask: async () => ({ kind: 'accepted' }),
  editTask: async () => ({ kind: 'accepted' }),
  getRecoveryAvailability: () => null,
  getSnapshot: () => ({ conflict: null, route: 'inbox', selectedTaskId: null, tasks: [] }),
  moveToday: async () => ({ kind: 'accepted' }),
  reopenTask: async () => ({ kind: 'accepted' }),
  resolveConflict: async () => ({ kind: 'accepted' }),
  restoreTask: async () => ({ kind: 'accepted' }),
  selectTask: () => undefined,
  setRoute: () => undefined,
  subscribe: () => () => undefined,
  subscribeRecovery: () => () => undefined,
  trashTask: async () => ({ kind: 'accepted' }),
  undoLastChange: async () => ({ kind: 'accepted' }),
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
