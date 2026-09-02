/**
 * Pure main-window sizing/title logic (D-06/D-07), deliberately free of any
 * 'electron' import so it is unit-testable under plain Node/vitest without
 * an Electron runtime (importing 'electron' outside Electron resolves to a
 * path string, not the API surface).
 */
type Destination = 'inbox' | 'settings' | 'sync-recovery' | 'today' | 'trash'

const MAIN_WINDOW_DEFAULT_WIDTH = 1180
const MAIN_WINDOW_DEFAULT_HEIGHT = 780
const MAIN_WINDOW_MIN_WIDTH = 680
const MAIN_WINDOW_MIN_HEIGHT = 520

const destinationLabel = (destination: Destination): string => {
  switch (destination) {
    case 'today':
      return 'Today'
    case 'trash':
      return 'Trash'
    case 'settings':
      return 'Settings'
    case 'sync-recovery':
      return 'Sync & Recovery'
    case 'inbox':
      return 'Inbox'
  }
}

/**
 * D-07: the window title is exactly `Keepling — <coarse destination>` and
 * never a task title, note, project/tag value, account identifier, server
 * URL, or conflict text.
 */
const titleForDestination = (destination: Destination): string => `Keepling — ${destinationLabel(destination)}`

/** D-06: clamp a candidate restored bound into the given visible work area. */
const clampBoundsToWorkArea = (
  bounds: { height: number; width: number; x: number; y: number },
  workArea: { height: number; width: number; x: number; y: number },
): { height: number; width: number; x: number; y: number } => {
  const width = Math.min(Math.max(bounds.width, MAIN_WINDOW_MIN_WIDTH), workArea.width)
  const height = Math.min(Math.max(bounds.height, MAIN_WINDOW_MIN_HEIGHT), workArea.height)
  const x = Math.min(Math.max(bounds.x, workArea.x), workArea.x + workArea.width - width)
  const y = Math.min(Math.max(bounds.y, workArea.y), workArea.y + workArea.height - height)
  return { height, width, x, y }
}

export {
  MAIN_WINDOW_DEFAULT_HEIGHT,
  MAIN_WINDOW_DEFAULT_WIDTH,
  MAIN_WINDOW_MIN_HEIGHT,
  MAIN_WINDOW_MIN_WIDTH,
  clampBoundsToWorkArea,
  destinationLabel,
  titleForDestination,
}
export type { Destination }
