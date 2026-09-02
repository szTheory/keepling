/**
 * Pure native-menu label/validation logic (D-14), free of any 'electron'
 * import so it is unit-testable under plain Node/vitest.
 */
type MenuState = {
  hasSelection: boolean
  selectedCompleted: boolean
  selectedTrashed: boolean
}

type MenuLabels = {
  completeReopen: string
  trashRestore: string
}

/**
 * "Native menu validation changes Complete to Reopen and Move to Trash to
 * Restore as appropriate" (UI-SPEC Menu and Keyboard Contract). With no
 * selected task the label stays in its default (non-destructive) sense.
 */
const deriveMenuLabels = (state: MenuState): MenuLabels => ({
  completeReopen: state.hasSelection && state.selectedCompleted ? 'Reopen' : 'Complete',
  trashRestore: state.hasSelection && state.selectedTrashed ? 'Restore' : 'Move to Trash',
})

export { deriveMenuLabels }
export type { MenuLabels, MenuState }
