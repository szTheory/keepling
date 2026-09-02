import { Menu, type BrowserWindow, type MenuItemConstructorOptions } from 'electron'

import { deriveMenuLabels, type MenuState } from './menuLabels.ts'

/**
 * Native App/File/Edit/View/Window/Help menus (D-07/D-14).
 *
 * Dispatch design (documented rationale, not incidental): every command
 * that needs the MAIN WINDOW's renderer to act (New Task, Inbox/Today,
 * Save, Complete/Reopen, Move to Trash/Restore, Undo, Toggle Sidebar,
 * Sync & Recovery) is delivered by synthesizing the EXACT SAME keyboard
 * event a person would type, via `webContents.sendInputEvent`, into the
 * main window. The renderer (`apps/desktop/renderer/DesktopShell.tsx` +
 * `keyboardCommands.ts`) therefore applies ONE shared editable/composition/
 * repeat guard to both a real keypress and a menu click -- exactly the
 * "focused-editable/composition/repeat guard shared by menu equivalents
 * and renderer accelerators" this plan's Task 1 requires.
 *
 * This also means these menu items are built WITHOUT a registered Electron
 * `accelerator`: Electron's menu accelerators intercept the OS-level
 * keystroke ahead of the renderer (this is how `role: 'undo'`/`'paste'`/etc.
 * work), so registering `CmdOrCtrl+S` or `CmdOrCtrl+Z` here would silently
 * break the native text-field undo and TaskEditor's own already-working
 * Command-S handling. The physical keyboard shortcut for these commands is
 * therefore handled ENTIRELY by the renderer; the menu item exists for
 * discoverability (mouse click) and shows the shortcut as label text.
 * Quick Entry and Settings are the exception: they are main-owned windows
 * with no native-text-editing collision risk, so they DO carry a live
 * Electron accelerator.
 *
 * Known integration gap (see this plan's SUMMARY "Known Gaps"): the menu
 * cannot yet reflect the renderer's live route/selection state (dynamic
 * Complete<->Reopen / Move to Trash<->Restore labels) without a new
 * renderer->main IPC channel, which would require editing
 * `apps/desktop/preload/index.ts` -- explicitly out of this plan's scope
 * for this wave (Plan 03-10 owns that file). `deriveMenuLabels` is built
 * and unit-tested and ready to wire once that channel exists.
 */
type SemanticKeyEvent = { keyCode: string; modifiers: ('alt' | 'cmd' | 'ctrl' | 'shift')[] }

const SEMANTIC_KEY_EVENTS: Record<
  'complete-reopen' | 'go-inbox' | 'go-today' | 'new-task' | 'save' | 'sync-recovery' | 'toggle-sidebar' | 'trash-restore' | 'undo',
  SemanticKeyEvent
> = {
  'complete-reopen': { keyCode: 'K', modifiers: ['cmd', 'shift'] },
  'go-inbox': { keyCode: '1', modifiers: ['cmd'] },
  'go-today': { keyCode: '2', modifiers: ['cmd'] },
  'new-task': { keyCode: 'N', modifiers: ['cmd'] },
  save: { keyCode: 'S', modifiers: ['cmd'] },
  'sync-recovery': { keyCode: 'R', modifiers: ['cmd', 'shift'] },
  'toggle-sidebar': { keyCode: 'S', modifiers: ['cmd', 'ctrl'] },
  'trash-restore': { keyCode: 'Delete', modifiers: ['cmd'] },
  undo: { keyCode: 'Z', modifiers: ['cmd'] },
}

const sendSemanticKey = (window: BrowserWindow | null, event: SemanticKeyEvent): void => {
  if (window === null || window.isDestroyed()) return
  window.webContents.sendInputEvent({ keyCode: event.keyCode, modifiers: event.modifiers, type: 'keyDown' })
  window.webContents.sendInputEvent({ keyCode: event.keyCode, modifiers: event.modifiers, type: 'keyUp' })
}

type MenuDeps = {
  getMainWindow: () => BrowserWindow | null
  getMenuState: () => MenuState
  openQuickEntry: () => void
  openSettings: () => void
  quickEntryAccelerator: string
}

const buildApplicationMenu = (deps: MenuDeps): Menu => {
  const mainWindow = () => deps.getMainWindow()
  const labels = deriveMenuLabels(deps.getMenuState())

  const template: MenuItemConstructorOptions[] = [
    {
      label: 'Keepling',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { accelerator: 'CmdOrCtrl+,', click: () => deps.openSettings(), label: 'Settings…' },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'File',
      submenu: [
        { accelerator: 'CmdOrCtrl+N', click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['new-task']), label: 'New Task' },
        // No Electron `accelerator` here: the actual shortcut is a GLOBAL
        // OS-wide binding owned by `globalShortcut` (D-09/D-10), which must
        // fire even while Keepling isn't the focused app -- a Menu
        // accelerator only fires while focused, and registering both would
        // race the same key combination against two different registries.
        { click: () => deps.openQuickEntry(), label: `Quick Entry (${deps.quickEntryAccelerator})` },
        { type: 'separator' },
        { click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS.save), label: 'Save' },
        { type: 'separator' },
        { role: 'close' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS.undo), label: 'Undo Last Supported Action' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { accelerator: 'CmdOrCtrl+1', click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['go-inbox']), label: 'Inbox' },
        { accelerator: 'CmdOrCtrl+2', click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['go-today']), label: 'Today' },
        { type: 'separator' },
        {
          accelerator: 'Cmd+Ctrl+S',
          click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['toggle-sidebar']),
          label: 'Toggle Sidebar',
        },
        {
          click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['complete-reopen']),
          label: labels.completeReopen,
        },
        {
          click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['trash-restore']),
          label: labels.trashRestore,
        },
        {
          accelerator: 'CmdOrCtrl+Shift+R',
          click: () => sendSemanticKey(mainWindow(), SEMANTIC_KEY_EVENTS['sync-recovery']),
          label: 'Sync & Recovery',
        },
      ],
    },
    { label: 'Window', role: 'windowMenu' },
    { label: 'Help', role: 'help', submenu: [] },
  ]

  return Menu.buildFromTemplate(template)
}

export { SEMANTIC_KEY_EVENTS, buildApplicationMenu, sendSemanticKey }
export type { MenuDeps }
