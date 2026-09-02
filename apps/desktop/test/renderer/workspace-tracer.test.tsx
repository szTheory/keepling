import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import Workspace from '../../../../packages/web-ui/src/workspace/Workspace.tsx'
import { createDesktopClientFacade } from '../fixtures/desktopClientFacade.ts'

/**
 * Proves the shared `packages/web-ui` Inbox capture/list/detail presentation
 * renders and behaves correctly against a deterministic desktop-facade
 * fixture that carries no fetch, IPC, or platform dependency -- only the
 * named `ClientFacade` operations (D-04/D-05, D-26/D-27).
 */

const setInputValue = (input: HTMLInputElement, value: string) => {
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
  setter?.call(input, value)
  input.dispatchEvent(new Event('input', { bubbles: true }))
}

describe('workspace-tracer: shared Inbox capture/list/detail slice', () => {
  let container: HTMLDivElement
  let root: Root

  beforeEach(() => {
    container = document.createElement('div')
    document.body.append(container)
    root = createRoot(container)
  })

  afterEach(() => {
    act(() => root.unmount())
    container.remove()
  })

  it('captures a task through the facade and lists it with the D-03 local trust label', async () => {
    const facade = createDesktopClientFacade()

    act(() => {
      root.render(<Workspace facade={facade} />)
    })

    const titleField = container.querySelector<HTMLInputElement>('#workspace-capture-title')
    expect(titleField).not.toBeNull()

    await act(async () => {
      setInputValue(titleField!, 'Call dentist')
    })

    const form = container.querySelector('form')
    expect(form).not.toBeNull()

    await act(async () => {
      form!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
      await Promise.resolve()
    })

    const row = container.querySelector('[data-task-id]')
    expect(row?.textContent).toContain('Call dentist')
    expect(
      container.querySelector('[data-task-sync-status="saved_on_this_mac"]')?.textContent,
    ).toBe('Saved on this Mac')
    expect(titleField!.value).toBe('')
  })

  it('moves stable list focus independently from selection and opens by stable task identity', async () => {
    const facade = createDesktopClientFacade({
      seedTasks: [
        { id: 'task-1', notes: '', syncStatus: 'synced', title: 'Buy milk' },
        { id: 'task-2', notes: 'Bring floor plans', syncStatus: 'synced', title: 'Call landlord' },
      ],
    })

    act(() => {
      root.render(<Workspace facade={facade} />)
    })

    const rows = Array.from(container.querySelectorAll<HTMLLIElement>('[data-task-id]'))
    expect(rows).toHaveLength(2)
    expect(rows[0]?.getAttribute('tabindex')).toBe('0')
    expect(rows[1]?.getAttribute('tabindex')).toBe('-1')

    // List focus moves without changing selection (D-05).
    act(() => {
      rows[0]?.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'ArrowDown' }))
    })
    expect(document.activeElement).toBe(rows[1])
    expect(container.querySelector('#workspace-detail-title')).toBeNull()

    // Return opens the focused task by stable identity.
    act(() => {
      rows[1]?.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter' }))
    })
    expect(container.querySelector('#workspace-detail-title')?.textContent).toBe('Call landlord')
    expect(container.querySelector('[data-task-id="task-2"]')?.getAttribute('aria-current')).toBe(
      'true',
    )
  })

  it('renders byte-identical markup from two independent facade instances (web/desktop parity)', () => {
    const seedTasks = [{ id: 'task-1', notes: '', syncStatus: 'synced' as const, title: 'Water plants' }]

    act(() => {
      root.render(<Workspace facade={createDesktopClientFacade({ seedTasks })} />)
    })
    const first = container.innerHTML

    act(() => {
      root.render(<Workspace facade={createDesktopClientFacade({ seedTasks })} />)
    })
    const second = container.innerHTML

    expect(second).toBe(first)
  })

  it('shows the authoritative empty state copy when Inbox has no tasks', () => {
    act(() => {
      root.render(<Workspace facade={createDesktopClientFacade()} />)
    })

    expect(container.querySelector('[data-workspace-empty="inbox"]')?.textContent).toContain(
      'Inbox Is Clear',
    )
  })
})
