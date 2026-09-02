import { describe, expect, it } from 'vitest'

import {
  isEditableElement,
  matchSemanticCommand,
  shouldDispatchCommand,
  type KeyboardCommandEvent,
} from '../../renderer/keyboardCommands.ts'

const event = (overrides: Partial<KeyboardCommandEvent>): KeyboardCommandEvent => ({
  altKey: false,
  ctrlKey: false,
  isComposing: false,
  key: '',
  metaKey: false,
  repeat: false,
  shiftKey: false,
  ...overrides,
})

describe('matchSemanticCommand', () => {
  it('maps Command-N to new-task', () => {
    expect(matchSemanticCommand(event({ key: 'n', metaKey: true }))).toBe('new-task')
  })

  it('maps Command-1 and Command-2 to Inbox/Today navigation', () => {
    expect(matchSemanticCommand(event({ key: '1', metaKey: true }))).toBe('go-inbox')
    expect(matchSemanticCommand(event({ key: '2', metaKey: true }))).toBe('go-today')
  })

  it('maps Command-Shift-K to toggle-complete-reopen', () => {
    expect(matchSemanticCommand(event({ key: 'k', metaKey: true, shiftKey: true }))).toBe('toggle-complete-reopen')
  })

  it('maps Command-Delete to toggle-trash-restore', () => {
    expect(matchSemanticCommand(event({ key: 'Delete', metaKey: true }))).toBe('toggle-trash-restore')
  })

  it('maps Command-Shift-Delete to toggle-trash-restore as well (restore direction decided by route/state)', () => {
    expect(matchSemanticCommand(event({ key: 'Delete', metaKey: true, shiftKey: true }))).toBe('toggle-trash-restore')
  })

  it('maps Command-Z (no shift) to undo', () => {
    expect(matchSemanticCommand(event({ key: 'z', metaKey: true }))).toBe('undo')
  })

  it('maps Command-Control-S to toggle-sidebar', () => {
    expect(matchSemanticCommand(event({ key: 's', metaKey: true, ctrlKey: true }))).toBe('toggle-sidebar')
  })

  it('maps Command-Shift-R to sync-recovery', () => {
    expect(matchSemanticCommand(event({ key: 'r', metaKey: true, shiftKey: true }))).toBe('sync-recovery')
  })

  it('returns null without the Command modifier', () => {
    expect(matchSemanticCommand(event({ key: 'n' }))).toBeNull()
  })

  it('returns null for an unrecognized combination', () => {
    expect(matchSemanticCommand(event({ key: 'q', metaKey: true }))).toBeNull()
  })

  it('does not confuse plain Command-S (save, already owned by TaskEditor) with the sidebar toggle', () => {
    expect(matchSemanticCommand(event({ key: 's', metaKey: true }))).toBeNull()
  })
})

describe('isEditableElement', () => {
  it('treats input, textarea, select, and contentEditable as editable', () => {
    expect(isEditableElement(document.createElement('input'))).toBe(true)
    expect(isEditableElement(document.createElement('textarea'))).toBe(true)
    expect(isEditableElement(document.createElement('select'))).toBe(true)
    const editable = document.createElement('div')
    Object.defineProperty(editable, 'isContentEditable', { value: true })
    expect(isEditableElement(editable)).toBe(true)
  })

  it('treats a button and null as not editable', () => {
    expect(isEditableElement(document.createElement('button'))).toBe(false)
    expect(isEditableElement(null)).toBe(false)
  })
})

describe('shouldDispatchCommand', () => {
  const input = document.createElement('input')
  const button = document.createElement('button')

  it('blocks guarded commands (toggle-complete-reopen, toggle-trash-restore, undo) while an editable control owns focus', () => {
    expect(
      shouldDispatchCommand('toggle-complete-reopen', { activeElement: input, isComposing: false, repeat: false }),
    ).toBe(false)
    expect(
      shouldDispatchCommand('toggle-trash-restore', { activeElement: input, isComposing: false, repeat: false }),
    ).toBe(false)
    expect(shouldDispatchCommand('undo', { activeElement: input, isComposing: false, repeat: false })).toBe(false)
  })

  it('blocks guarded commands during IME composition regardless of focus', () => {
    expect(
      shouldDispatchCommand('toggle-complete-reopen', { activeElement: button, isComposing: true, repeat: false }),
    ).toBe(false)
  })

  it('blocks guarded commands on OS key repeat', () => {
    expect(shouldDispatchCommand('undo', { activeElement: button, isComposing: false, repeat: true })).toBe(false)
  })

  it('allows guarded commands outside an editable control, without composition or repeat', () => {
    expect(shouldDispatchCommand('toggle-complete-reopen', { activeElement: button, isComposing: false, repeat: false })).toBe(
      true,
    )
  })

  it('allows non-guarded navigation/new-task/sidebar/sync-recovery commands even while editable, provided no composition', () => {
    expect(shouldDispatchCommand('go-inbox', { activeElement: input, isComposing: false, repeat: false })).toBe(true)
    expect(shouldDispatchCommand('new-task', { activeElement: input, isComposing: false, repeat: true })).toBe(true)
  })

  it('blocks every command during IME composition, guarded or not', () => {
    expect(shouldDispatchCommand('go-inbox', { activeElement: button, isComposing: true, repeat: false })).toBe(false)
  })
})
