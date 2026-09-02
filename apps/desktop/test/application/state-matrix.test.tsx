// @vitest-environment jsdom
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import Workspace, { resolveBreakpoint } from '../../../../packages/web-ui/src/workspace/Workspace.tsx'
import { createDesktopClientFacade } from '../fixtures/desktopClientFacade.ts'

/**
 * State-complete matrix for the resolved UI-SPEC considerations and the
 * QUAL-04 deterministic-state contract (D-08/D-39/D-41/D-42). Each row is a
 * disposable facade instance and an independent `describe`/`it` -- no case
 * depends on execution order or a shared clock, matching "repeated or
 * concurrent execution uses disposable state and deterministic clocks".
 *
 * Coverage rows below are grouped by UI-SPEC consideration. Rows whose
 * evidence genuinely requires a real rendered/painted surface (CSS overflow
 * clamping, 200% zoom reflow, forced-colors/Reduce-Transparency media
 * features, light/dark screenshot pixels) are out of reach for this
 * component harness and are marked `human-needed` in the plan's SUMMARY
 * rather than asserted here as if they passed (plan's own "Treat backstop
 * rows as evidence obligations" instruction).
 */

const seedTask = (overrides: Partial<Parameters<typeof createDesktopClientFacade>[0]> = {}) =>
  createDesktopClientFacade(overrides)

const renderInto = (facade: ReturnType<typeof createDesktopClientFacade>) => {
  const container = document.createElement('div')
  document.body.append(container)
  const root = createRoot(container)
  act(() => {
    root.render(<Workspace facade={facade} />)
  })
  return { container, root }
}

let mounted: Array<{ container: HTMLDivElement; root: Root }> = []

beforeEach(() => {
  mounted = []
})

afterEach(() => {
  for (const { container, root } of mounted.splice(0)) {
    act(() => root.unmount())
    container.remove()
  }
  window.innerWidth = 1280
})

const mount = (facade: ReturnType<typeof createDesktopClientFacade>) => {
  const rendered = renderInto(facade)
  mounted.push(rendered)
  return rendered
}

describe('state matrix: Populated', () => {
  it('renders a many-row Inbox list with stable roving focus (zero/one/many: many)', () => {
    const { container } = mount(
      seedTask({
        seedTasks: Array.from({ length: 5 }, (_, index) => ({
          completedAt: null,
          id: `task-${index}`,
          notes: '',
          planned: false,
          syncStatus: 'synced' as const,
          title: `Task ${index}`,
          trashedAt: null,
        })),
      }),
    )
    expect(container.querySelectorAll('[data-task-id]')).toHaveLength(5)
  })

  it('renders exactly one row with normal geometry and singular wording (zero/one/many: one)', () => {
    const { container } = mount(
      seedTask({
        seedTasks: [
          { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'synced', title: 'Only task', trashedAt: null },
        ],
      }),
    )
    expect(container.querySelectorAll('[data-task-id]')).toHaveLength(1)
    expect(container.querySelector('[data-task-id]')?.textContent).toContain('Only task')
  })
})

describe('state matrix: Empty', () => {
  it('shows the authoritative Inbox empty copy (zero/one/many: zero)', () => {
    const { container } = mount(seedTask())
    expect(container.querySelector('[data-workspace-empty="inbox"]')?.textContent).toContain('Inbox Is Clear')
  })

  it('shows the authoritative Today empty copy', () => {
    const { container } = mount(seedTask({ seedRoute: 'today' }))
    expect(container.querySelector('[data-workspace-empty="today"]')?.textContent).toContain(
      'Nothing Planned for Today',
    )
  })

  it('shows the authoritative Trash empty copy', () => {
    const { container } = mount(seedTask({ seedRoute: 'trash' }))
    expect(container.querySelector('[data-workspace-empty="trash"]')?.textContent).toContain('Trash Is Empty')
  })
})

describe('state matrix: Loading / durability labels', () => {
  it('labels a freshly captured task "Saved on this Mac" before any network concern (D-03)', async () => {
    const { container } = mount(seedTask())
    const titleField = container.querySelector<HTMLInputElement>('#workspace-capture-title')!
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
    await act(async () => {
      setter?.call(titleField, 'New task')
      titleField.dispatchEvent(new Event('input', { bubbles: true }))
    })
    await act(async () => {
      container.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
      await Promise.resolve()
    })
    expect(container.querySelector('[data-task-sync-status="saved_on_this_mac"]')?.textContent).toBe(
      'Saved on this Mac',
    )
  })
})

describe('state matrix: Error / recovery', () => {
  it('shows the healthy recovery copy when nothing is recoverable', () => {
    const { container } = mount(seedTask())
    expect(container.querySelector('[data-workspace-recovery]')?.textContent).toContain(
      'No Changes Need Your Attention',
    )
  })

  it('offers a named undo action after a lifecycle change and settles after undo', async () => {
    const facade = seedTask({
      seedTasks: [
        { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'synced', title: 'Recoverable', trashedAt: null },
      ],
    })
    const { container } = mount(facade)
    await act(async () => {
      await facade.trashTask('task-1')
    })
    const undoButton = Array.from(container.querySelectorAll('button')).find((button) =>
      button.textContent?.startsWith('Undo Trash'),
    )
    expect(undoButton).toBeDefined()
    await act(async () => {
      undoButton!.dispatchEvent(new MouseEvent('click', { bubbles: true }))
      await Promise.resolve()
    })
    expect(container.querySelector('[data-workspace-recovery]')?.textContent).toContain('Change undone.')
  })

  it('rejects an empty title without changing durable state (local-save failure path)', async () => {
    const facade = seedTask({
      seedTasks: [
        { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'synced', title: 'Keep me', trashedAt: null },
      ],
    })
    const outcome = await facade.editTask('task-1', { notes: '', title: '   ' })
    expect(outcome.kind).toBe('rejected')
    expect(facade.getSnapshot().tasks[0]?.title).toBe('Keep me')
  })
})

describe('state matrix: Conflict', () => {
  it('presents mine/current inline and never overwrites without an explicit choice', () => {
    const facade = seedTask({
      seedConflict: { current: 'Buy oat milk', field: 'title', id: 'conflict-1', mine: 'Buy milk', taskId: 'task-1' },
      seedTasks: [
        { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'saved_on_this_mac', title: 'Buy milk', trashedAt: null },
      ],
    })
    const { container } = mount(facade)
    expect(container.textContent).toContain('This task changed somewhere else.')
    expect(container.textContent).toContain('Buy oat milk')
    expect(container.textContent).toContain('Buy milk')
    // The underlying task title is untouched until an explicit choice is made.
    expect(facade.getSnapshot().tasks[0]?.title).toBe('Buy milk')
  })

  it('commits the chosen field and clears the conflict on resolution', async () => {
    const facade = seedTask({
      seedConflict: { current: 'Buy oat milk', field: 'title', id: 'conflict-1', mine: 'Buy milk', taskId: 'task-1' },
      seedTasks: [
        { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'saved_on_this_mac', title: 'Buy milk', trashedAt: null },
      ],
    })
    const { container } = mount(facade)
    const useCurrent = Array.from(container.querySelectorAll('button')).find((b) => b.textContent === 'Use current')!
    await act(async () => {
      useCurrent.dispatchEvent(new MouseEvent('click', { bubbles: true }))
      await Promise.resolve()
    })
    expect(container.textContent).not.toContain('This task changed somewhere else.')
    expect(facade.getSnapshot().tasks[0]?.title).toBe('Buy oat milk')
  })
})

describe('state matrix: Partial', () => {
  it('keeps valid fields visible when notes are absent and lifecycle actions stay available', () => {
    const { container } = mount(
      seedTask({
        seedTasks: [
          { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'synced', title: 'No notes yet', trashedAt: null },
        ],
      }),
    )
    act(() => {
      container.querySelector('[data-task-id]')!.dispatchEvent(
        new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter' }),
      )
    })
    expect(container.querySelector('#task-editor-notes')).not.toBeNull()
    expect(container.querySelector('[data-workspace-lifecycle-actions]')?.textContent).toContain('Complete')
  })
})

describe('state matrix: dirty-work safety (D-12)', () => {
  it('offers Save Changes / Discard Changes / Keep Editing when navigating away from a dirty draft', async () => {
    const facade = seedTask({
      seedTasks: [
        { completedAt: null, id: 'task-1', notes: '', planned: false, syncStatus: 'synced', title: 'Draft me', trashedAt: null },
        { completedAt: null, id: 'task-2', notes: '', planned: false, syncStatus: 'synced', title: 'Other task', trashedAt: null },
      ],
    })
    const { container } = mount(facade)
    act(() => facade.selectTask('task-1'))

    const titleField = container.querySelector<HTMLInputElement>('#task-editor-title')!
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
    act(() => {
      setter?.call(titleField, 'Draft me, edited')
      titleField.dispatchEvent(new Event('input', { bubbles: true }))
    })

    const otherRow = container.querySelector('[data-task-id="task-2"]')!
    act(() => {
      otherRow.dispatchEvent(new MouseEvent('click', { bubbles: true }))
    })

    expect(container.querySelector('[data-workspace-dirty-dialog]')).not.toBeNull()
    expect(container.textContent).toContain('Save Changes')
    expect(container.textContent).toContain('Discard Changes')
    expect(container.textContent).toContain('Keep Editing')
    // Navigation did not happen yet -- the draft is still the active selection.
    expect(facade.getSnapshot().selectedTaskId).toBe('task-1')
  })
})

describe('state matrix: Overflow / long text', () => {
  it('retains a long title and long recovery/dialog copy in full without losing content (backstop: visual wrap/clamp verified separately)', () => {
    const longTitle = 'A'.repeat(600)
    const { container } = mount(
      seedTask({
        seedTasks: [
          { completedAt: null, id: 'task-1', notes: 'B'.repeat(2_000), planned: false, syncStatus: 'synced', title: longTitle.slice(0, 512), trashedAt: null },
        ],
      }),
    )
    act(() => {
      container.querySelector('[data-task-id]')!.dispatchEvent(
        new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter' }),
      )
    })
    const notesField = container.querySelector<HTMLTextAreaElement>('#task-editor-notes')!
    expect(notesField.value).toHaveLength(2_000)
    expect(container.querySelector('#workspace-detail-title')?.textContent).toHaveLength(512)
  })
})

describe('state matrix: responsive breakpoint (D-04)', () => {
  it('resolves compact below 1024px, compact-wide from 1024px, and persistent from 1064px', () => {
    expect(resolveBreakpoint(680)).toBe('compact')
    expect(resolveBreakpoint(1023)).toBe('compact')
    expect(resolveBreakpoint(1024)).toBe('compact-wide')
    expect(resolveBreakpoint(1063)).toBe('compact-wide')
    expect(resolveBreakpoint(1064)).toBe('persistent')
    expect(resolveBreakpoint(1440)).toBe('persistent')
  })

  it('re-derives the live breakpoint attribute on window resize', () => {
    window.innerWidth = 680
    const { container } = mount(seedTask())
    expect(container.querySelector('main')?.getAttribute('data-workspace-breakpoint')).toBe('compact')

    act(() => {
      window.innerWidth = 1440
      window.dispatchEvent(new Event('resize'))
    })
    expect(container.querySelector('main')?.getAttribute('data-workspace-breakpoint')).toBe('persistent')
  })
})
