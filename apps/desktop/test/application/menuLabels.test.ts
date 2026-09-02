import { describe, expect, it } from 'vitest'

import { deriveMenuLabels } from '../../main/menuLabels.ts'

describe('deriveMenuLabels', () => {
  it('defaults to Complete / Move to Trash with no selection', () => {
    expect(deriveMenuLabels({ hasSelection: false, selectedCompleted: false, selectedTrashed: false })).toEqual({
      completeReopen: 'Complete',
      trashRestore: 'Move to Trash',
    })
  })

  it('shows Complete / Move to Trash for a selected, active, non-trashed task', () => {
    expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: false, selectedTrashed: false })).toEqual({
      completeReopen: 'Complete',
      trashRestore: 'Move to Trash',
    })
  })

  it('swaps to Reopen for a selected, completed task', () => {
    expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: true, selectedTrashed: false })).toEqual({
      completeReopen: 'Reopen',
      trashRestore: 'Move to Trash',
    })
  })

  it('swaps to Restore for a selected, trashed task', () => {
    expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: false, selectedTrashed: true })).toEqual({
      completeReopen: 'Complete',
      trashRestore: 'Restore',
    })
  })

  it('swaps both independently for a selected, completed, trashed task', () => {
    expect(deriveMenuLabels({ hasSelection: true, selectedCompleted: true, selectedTrashed: true })).toEqual({
      completeReopen: 'Reopen',
      trashRestore: 'Restore',
    })
  })
})
