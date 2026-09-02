/**
 * Desktop-only keyboard/menu semantic-command routing (D-12/D-13/D-14).
 *
 * This module is deliberately pure (no Electron, no DOM globals beyond the
 * standard KeyboardEvent/Element shapes) so it is exercised by ordinary
 * jsdom unit tests. It is the ONE shared guard consulted by both:
 *  - real physical keydown events dispatched by the renderer's own listener, and
 *  - synthetic keydown events the native menu (apps/desktop/main/menu.ts)
 *    injects into this same window via `webContents.sendInputEvent` so a
 *    menu click and the equivalent keystroke are indistinguishable to the
 *    renderer and therefore obey the identical guard.
 *
 * `Command-S`/`Command-Return` (save) and list Up/Down/Return already have a
 * working renderer-level implementation from Plan 03-03 (TaskEditor/TaskList)
 * and are intentionally NOT duplicated here.
 */

type SemanticCommand =
  | 'go-inbox'
  | 'go-today'
  | 'new-task'
  | 'sync-recovery'
  | 'toggle-complete-reopen'
  | 'toggle-sidebar'
  | 'toggle-trash-restore'
  | 'undo'

/**
 * Commands the UI-SPEC Menu/Keyboard Contract marks "outside editable
 * controls" (D-12/D-14): they must never fire while an editable control
 * owns focus, during IME composition, or on OS key repeat. This is exactly
 * why the corresponding native menu items are built WITHOUT a registered
 * Electron `accelerator` (see menu.ts) -- an Electron-level global
 * accelerator cannot see DOM focus/composition/repeat state, so the only
 * place this guard can be enforced correctly is here, in the renderer.
 */
const GUARDED_COMMANDS = new Set<SemanticCommand>([
  'toggle-complete-reopen',
  'toggle-trash-restore',
  'undo',
])

type KeyboardCommandEvent = {
  altKey: boolean
  ctrlKey: boolean
  isComposing: boolean
  key: string
  metaKey: boolean
  repeat: boolean
  shiftKey: boolean
}

const isEditableElement = (target: EventTarget | null): boolean => {
  if (!(target instanceof HTMLElement)) return false
  const tag = target.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true
  return Boolean(target.isContentEditable)
}

/**
 * Maps a keydown event to a semantic command per the UI-SPEC Menu and
 * Keyboard Contract table. Returns null for anything unrecognized so the
 * caller can let the browser/native default proceed untouched.
 */
const matchSemanticCommand = (event: KeyboardCommandEvent): SemanticCommand | null => {
  if (!event.metaKey) return null
  const key = event.key.toLowerCase()

  if (!event.shiftKey && !event.altKey && !event.ctrlKey) {
    if (key === 'n') return 'new-task'
    if (key === '1') return 'go-inbox'
    if (key === '2') return 'go-today'
  }

  if (event.shiftKey && !event.altKey && !event.ctrlKey) {
    if (key === 'k') return 'toggle-complete-reopen'
    if (key === 'delete' || key === 'backspace') return 'toggle-trash-restore'
    if (key === 'r') return 'sync-recovery'
  }

  if (!event.shiftKey && !event.altKey && (key === 'delete' || key === 'backspace')) {
    return 'toggle-trash-restore'
  }

  if (!event.shiftKey && !event.altKey && key === 'z') return 'undo'

  if (event.ctrlKey && !event.shiftKey && !event.altKey && key === 's') return 'toggle-sidebar'

  return null
}

/**
 * Applies the D-12/D-14 guard: destructive/"outside editable controls"
 * commands never dispatch while an editable control owns focus, during IME
 * composition, or on key repeat. Non-guarded commands (navigation, new
 * task, sidebar toggle, sync recovery) only skip during composition --
 * they carry no destructive risk and Cmd-held combinations do not collide
 * with ordinary typing.
 */
const shouldDispatchCommand = (
  command: SemanticCommand,
  context: { activeElement: EventTarget | null; isComposing: boolean; repeat: boolean },
): boolean => {
  if (context.isComposing) return false
  if (!GUARDED_COMMANDS.has(command)) return true
  if (context.repeat) return false
  if (isEditableElement(context.activeElement)) return false
  return true
}

export { isEditableElement, matchSemanticCommand, shouldDispatchCommand }
export type { KeyboardCommandEvent, SemanticCommand }
