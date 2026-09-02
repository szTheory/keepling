import { describe, expect, it } from 'vitest'

import {
  MAIN_WINDOW_MIN_HEIGHT,
  MAIN_WINDOW_MIN_WIDTH,
  clampBoundsToWorkArea,
  titleForDestination,
} from '../../main/windows/mainWindowState.ts'

describe('titleForDestination', () => {
  it('produces the exact D-07 title pattern for every coarse destination', () => {
    expect(titleForDestination('inbox')).toBe('Keepling — Inbox')
    expect(titleForDestination('today')).toBe('Keepling — Today')
    expect(titleForDestination('trash')).toBe('Keepling — Trash')
    expect(titleForDestination('settings')).toBe('Keepling — Settings')
    expect(titleForDestination('sync-recovery')).toBe('Keepling — Sync & Recovery')
  })
})

describe('clampBoundsToWorkArea', () => {
  const workArea = { height: 900, width: 1600, x: 0, y: 0 }

  it('leaves already-valid bounds untouched', () => {
    expect(clampBoundsToWorkArea({ height: 780, width: 1180, x: 100, y: 60 }, workArea)).toEqual({
      height: 780,
      width: 1180,
      x: 100,
      y: 60,
    })
  })

  it('enforces the D-06/UI-SPEC 680x520 minimum bounds', () => {
    expect(clampBoundsToWorkArea({ height: 100, width: 100, x: 0, y: 0 }, workArea)).toEqual({
      height: MAIN_WINDOW_MIN_HEIGHT,
      width: MAIN_WINDOW_MIN_WIDTH,
      x: 0,
      y: 0,
    })
  })

  it('clamps an off-screen origin back into the visible work area, keeping the titlebar reachable', () => {
    expect(clampBoundsToWorkArea({ height: 780, width: 1180, x: 5000, y: -400 }, workArea)).toEqual({
      height: 780,
      width: 1180,
      x: workArea.width - 1180,
      y: 0,
    })
  })

  it('never exceeds the work area even for an oversized restored window', () => {
    const result = clampBoundsToWorkArea({ height: 2000, width: 3000, x: 0, y: 0 }, workArea)
    expect(result.width).toBeLessThanOrEqual(workArea.width)
    expect(result.height).toBeLessThanOrEqual(workArea.height)
  })
})
