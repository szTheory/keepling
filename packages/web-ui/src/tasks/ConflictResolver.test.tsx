import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import type { ClientFacade, TaskOutcome, WorkspaceConflictView } from '../ClientFacade'
import ConflictResolver from './ConflictResolver'

const makeFacade = (resolveConflict: ClientFacade['resolveConflict']): ClientFacade =>
  ({
    resolveConflict,
  }) as unknown as ClientFacade

const oneFieldConflict: WorkspaceConflictView = {
  fields: [{ current: 'Current title', field: 'title', mine: 'My title' }],
  id: 'conflict-1',
  taskId: 'task-1',
}

const sixFieldConflict: WorkspaceConflictView = {
  fields: [
    { current: 'Current title', field: 'title', mine: 'My title' },
    { current: 'Current notes', field: 'notes', mine: 'My notes' },
    { current: '2026-09-10', field: 'plannedDate', mine: '2026-09-11' },
    { current: '2026-09-20', field: 'deadline', mine: '2026-09-21' },
    { current: 'Work', field: 'project', mine: 'Personal' },
    { current: 'a, b', field: 'tags', mine: 'a, c' },
  ],
  id: 'conflict-6',
  taskId: 'task-1',
}

const lifecycleConflict: WorkspaceConflictView = {
  fields: [{ current: 'Active', field: 'completion', mine: 'Completed' }],
  id: 'conflict-lifecycle',
  taskId: 'task-1',
}

describe('ConflictResolver', () => {
  it('renders exactly one labelled group for a one-field conflict', () => {
    render(<ConflictResolver conflict={oneFieldConflict} facade={makeFacade(vi.fn())} />)

    const groups = screen.getAllByRole('group')
    expect(groups).toHaveLength(1)
    expect(within(groups[0]!).getByText('Title')).toBeVisible()
    expect(screen.getByText('My title', { exact: false })).toBeVisible()
    expect(screen.getByText('Current title', { exact: false })).toBeVisible()
  })

  it('renders one labelled group per field, same geometry, for a six-field conflict', () => {
    render(<ConflictResolver conflict={sixFieldConflict} facade={makeFacade(vi.fn())} />)

    const groups = screen.getAllByRole('group')
    expect(groups).toHaveLength(6)
    for (const label of ['Title', 'Notes', 'Planned date', 'Deadline', 'Project', 'Tags']) {
      expect(screen.getByText(label)).toBeVisible()
    }
  })

  it('renders no row for a field absent from the conflict payload', () => {
    render(<ConflictResolver conflict={oneFieldConflict} facade={makeFacade(vi.fn())} />)

    expect(screen.queryByText('Notes')).not.toBeInTheDocument()
    expect(screen.queryByText('Deadline')).not.toBeInTheDocument()
    expect(screen.getAllByRole('group')).toHaveLength(1)
  })

  it('renders a lifecycle divergence as its own row in plain lifecycle words', () => {
    render(<ConflictResolver conflict={lifecycleConflict} facade={makeFacade(vi.fn())} />)

    expect(screen.getByText('Completion')).toBeVisible()
    expect(screen.getByText('Completed', { exact: false })).toBeVisible()
    expect(screen.getByText('Active', { exact: false })).toBeVisible()
  })

  it('stages per-row choices and mutates nothing until the single submission point', async () => {
    const resolveConflict = vi.fn<ClientFacade['resolveConflict']>(async () => ({ kind: 'accepted' }))
    const user = userEvent.setup()
    render(<ConflictResolver conflict={oneFieldConflict} facade={makeFacade(resolveConflict)} />)

    const useMine = screen.getByRole('radio', { name: 'Use mine' })
    await user.click(useMine)
    expect(resolveConflict).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Save resolution' }))
    expect(resolveConflict).toHaveBeenCalledTimes(1)
    expect(resolveConflict).toHaveBeenCalledWith({ title: 'mine' })
  })

  it('submits only the fields the conflict named, preserving nonconflicting fields untouched', async () => {
    const resolveConflict = vi.fn<ClientFacade['resolveConflict']>(async () => ({ kind: 'accepted' }))
    const user = userEvent.setup()
    render(<ConflictResolver conflict={sixFieldConflict} facade={makeFacade(resolveConflict)} />)

    for (const group of screen.getAllByRole('group')) {
      await user.click(within(group).getByRole('radio', { name: 'Use current' }))
    }
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))

    expect(resolveConflict).toHaveBeenCalledWith({
      deadline: 'current',
      notes: 'current',
      plannedDate: 'current',
      project: 'current',
      tags: 'current',
      title: 'current',
    })
  })

  it('surfaces the existing rejected copy on a rejected submission', async () => {
    const outcome: TaskOutcome = { kind: 'rejected', message: 'Nothing was changed.' }
    const resolveConflict = vi.fn<ClientFacade['resolveConflict']>(async () => outcome)
    const user = userEvent.setup()
    render(<ConflictResolver conflict={oneFieldConflict} facade={makeFacade(resolveConflict)} />)

    await user.click(screen.getByRole('radio', { name: 'Use mine' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Nothing was changed.')
  })

  it('surfaces the existing uncertain-result copy without introducing new error language', async () => {
    const outcome: TaskOutcome = { kind: 'rejected', message: 'Checking whether your change was saved…' }
    const resolveConflict = vi.fn<ClientFacade['resolveConflict']>(async () => outcome)
    const user = userEvent.setup()
    render(<ConflictResolver conflict={oneFieldConflict} facade={makeFacade(resolveConflict)} />)

    await user.click(screen.getByRole('radio', { name: 'Use current' }))
    await user.click(screen.getByRole('button', { name: 'Save resolution' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Checking whether your change was saved…')
  })

  it('applies the six-line collapse-with-disclosure pattern per row for notes, project, and tag values', async () => {
    const longText = Array.from({ length: 8 }, (_, index) => `Line ${index + 1}`).join('\n')
    const conflict: WorkspaceConflictView = {
      fields: [
        { current: longText, field: 'notes', mine: longText },
        { current: longText, field: 'project', mine: longText },
        { current: longText, field: 'tags', mine: longText },
      ],
      id: 'conflict-long',
      taskId: 'task-1',
    }
    render(<ConflictResolver conflict={conflict} facade={makeFacade(vi.fn())} />)

    const disclosures = screen.getAllByRole('button', { name: 'Show full value' })
    // Two values (mine + current) per row, three rows.
    expect(disclosures).toHaveLength(6)
    expect(disclosures[0]).toHaveAttribute('aria-expanded', 'false')

    const user = userEvent.setup()
    await user.click(disclosures[0]!)
    expect(disclosures[0]).toHaveAttribute('aria-expanded', 'true')
    expect(disclosures[0]).toHaveTextContent('Show less')
  })
})
