import { BrowserWindow } from 'electron'

import {
  MAIN_WINDOW_DEFAULT_HEIGHT,
  MAIN_WINDOW_DEFAULT_WIDTH,
  MAIN_WINDOW_MIN_HEIGHT,
  MAIN_WINDOW_MIN_WIDTH,
  titleForDestination,
} from './mainWindowState.ts'

/**
 * Creates the one native, resizable, restorable primary window (D-04/D-06/
 * D-07). This module intentionally owns ONLY window creation -- validated
 * bounds/state restoration is Plan 03-11's "DesktopLifecycle" concern
 * (`key_links: lifecycle.ts -> windows/main-window.ts`), and IPC/protocol
 * hardening is Plan 03-10's concern for this wave. Extracting creation here
 * now means neither later plan touches window-construction logic inline in
 * `main/index.ts`.
 */
type MainWindowOptions = {
  bounds?: { height: number; width: number; x?: number; y?: number }
  preloadPath: string
}

const createMainWindow = (options: MainWindowOptions): BrowserWindow => {
  const window = new BrowserWindow({
    height: options.bounds?.height ?? MAIN_WINDOW_DEFAULT_HEIGHT,
    minHeight: MAIN_WINDOW_MIN_HEIGHT,
    minWidth: MAIN_WINDOW_MIN_WIDTH,
    show: false,
    title: titleForDestination('inbox'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: options.preloadPath,
      sandbox: true,
    },
    width: options.bounds?.width ?? MAIN_WINDOW_DEFAULT_WIDTH,
    x: options.bounds?.x,
    y: options.bounds?.y,
  })
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  window.webContents.on('will-navigate', (event) => event.preventDefault())
  return window
}

export { createMainWindow }
export type { MainWindowOptions }
